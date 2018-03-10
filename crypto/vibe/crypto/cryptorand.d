/**
	Implements cryptographically secure random number generators.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Ilya Shipunov
*/
module vibe.crypto.cryptorand;

import std.conv : text;
import std.digest.sha;
import vibe.core.stream;


/** Creates a cryptographically secure random number generator.

	Note that the returned RNG will operate in a non-blocking mode, which means
	that if no sufficient entropy has been generated, new random numbers will be
	generated from previous state.
*/
RandomNumberStream secureRNG()
@safe {
	static SystemRNG m_rng;
	if (!m_rng) m_rng = new SystemRNG;
	return m_rng;
}


/**
	Base interface for all cryptographically secure RNGs.
*/
interface RandomNumberStream : InputStream {
	/**
		Fills the buffer new random numbers.

		Params:
			dst = The buffer that will be filled with random numbers.
				It will contain buffer.length random ubytes.
				Supportes both heap-based and stack-based arrays.

		Throws:
			CryptoException on error.
	*/
	override size_t read(scope ubyte[] dst, IOMode mode) @safe;

	alias read = InputStream.read;
}

version(linux)
	enum bool LinuxMaybeHasGetrandom = __traits(compiles, {import mir.linux._asm.unistd : NR_getrandom;});
else
	enum bool LinuxMaybeHasGetrandom = false;

static if (LinuxMaybeHasGetrandom)
{
	// getrandom was introduced in Linux 3.17
    private enum GET_RANDOM {
        UNINITIALIZED,
        NOT_AVAILABLE,
        AVAILABLE,
    }
	private __gshared GET_RANDOM hasGetRandom = GET_RANDOM.UNINITIALIZED;
	private import core.sys.posix.sys.utsname : utsname;
	// druntime might not be properly annotated
	private extern(C) int uname(scope utsname* __name) @nogc nothrow;
	// checks whether the Linux kernel supports getRandom by looking at the
	// reported version
	private bool initHasGetRandom() @nogc @trusted nothrow
	{
		import core.stdc.string : strtok;
		import core.stdc.stdlib : atoi;

		utsname uts;
		uname(&uts);
		char* p = uts.release.ptr;

		// poor man's version check
		auto token = strtok(p, ".");
		int major = atoi(token);
		if (major > 3) return true;

		if (major == 3)
		{
			token = strtok(p, ".");
			if (atoi(token) >= 17) return true;
		}

		return false;
	}
	private extern(C) int syscall(size_t ident, size_t n, size_t arg1, size_t arg2) @nogc nothrow;
}

version (CRuntime_Bionic)
    version = secure_arc4random;//ChaCha20
version (OSX)
    version = secure_arc4random;//AES
version (OpenBSD)
    version = secure_arc4random;//ChaCha20
version (NetBSD)
    version = secure_arc4random;//ChaCha20
version (secure_arc4random)
extern(C) @nogc nothrow private @system
{
	void arc4random_buf(scope void* buf, size_t nbytes);
}

/**
	Operating system specific cryptography secure random number generator.

	It uses the "CryptGenRandom" function for Windows; the "arc4random_buf"
	function (not based on RC4 but on a modern and cryptographically secure
	cipher) for macOS/OpenBSD/NetBSD; the "getrandom" syscall for Linux 3.17
	and later; and "/dev/urandom" for other Posix platforms.
	It's recommended to combine the output use additional processing generated random numbers
	via provided functions for systems where security matters.

	Remarks:
		Windows "CryptGenRandom" RNG has known security vulnerabilities on
		Windows 2000 and Windows XP (assuming the attacker has control of the
		machine). Fixed for Windows XP Service Pack 3 and Windows Vista.

	See_Also: $(LINK http://en.wikipedia.org/wiki/CryptGenRandom)
*/
final class SystemRNG : RandomNumberStream {
@safe:
	import std.exception;

	version(Windows)
	{
		//cryptographic service provider
		private HCRYPTPROV hCryptProv;
	}
	else version(secure_arc4random)
	{
		//Using arc4random does not involve any extra fields.
	}
	else version(Posix)
	{
		import core.stdc.errno : errno, EINTR;
		import core.stdc.stdio : FILE, _IONBF, fopen, fclose, fread, setvbuf;

		//cryptographic file stream
		private FILE* m_file;
	}
	else
	{
		static assert(0, "OS is not supported");
	}

	/**
		Creates new system random generator
	*/
	this()
	@trusted {
		version(Windows)
		{
			//init cryptographic service provider
			enforce!CryptoException(CryptAcquireContext(&this.hCryptProv, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT) != 0,
				text("Cannot init SystemRNG: Error id is ", GetLastError()));
		}
		else version(secure_arc4random)
		{
			//arc4random requires no setup or cleanup.
		}
		else version(Posix)
		{
			version (linux) static if (LinuxMaybeHasGetrandom)
			{
				import core.atomic : atomicLoad, atomicStore;
				auto p = atomicLoad(*cast(const shared GET_RANDOM*) &hasGetRandom);
				if (p == GET_RANDOM.UNINITIALIZED)
				{
					p = initHasGetRandom() ? GET_RANDOM.AVAILABLE
						: GET_RANDOM.NOT_AVAILABLE;
					// Benign race condition.
					atomicStore(*cast(shared GET_RANDOM*) &hasGetRandom, p);
				}
				if (p == GET_RANDOM.AVAILABLE)
					return;
			}
			//open file
			m_file = fopen("/dev/urandom", "rb");
			enforce!CryptoException(m_file !is null, "Failed to open /dev/urandom");
			scope (failure) fclose(m_file);
			//do not use buffering stream to avoid possible attacks
			enforce!CryptoException(setvbuf(m_file, null, 0, _IONBF) == 0,
				"Failed to disable buffering for random number file handle");
		}
	}

	~this()
	@trusted {
		version(Windows)
		{
			CryptReleaseContext(this.hCryptProv, 0);
		}
		else version (secure_arc4random)
		{
			//arc4random requires no setup or cleanup.
		}
		else version (Posix)
		{
			version (linux) static if (LinuxMaybeHasGetrandom)
			{
				if (m_file is null) return;
			}
			fclose(m_file);
		}
	}

	@property bool empty() { return false; }
	@property ulong leastSize() { return ulong.max; }
	@property bool dataAvailableForRead() { return true; }
	const(ubyte)[] peek() { return null; }

	size_t read(scope ubyte[] buffer, IOMode mode) @trusted
	in
	{
		assert(buffer.length, "buffer length must be larger than 0");
		assert(buffer.length <= uint.max, "buffer length must be smaller or equal uint.max");
	}
	body
	{
		version (Windows)
		{
			if(0 == CryptGenRandom(this.hCryptProv, cast(DWORD)buffer.length, buffer.ptr))
			{
				throw new CryptoException(text("Cannot get next random number: Error id is ", GetLastError()));
			}
		}
		else version (secure_arc4random)
		{
			arc4random_buf(buffer.ptr, buffer.length);//Cannot fail.
		}
		else version (Posix)
		{
			version (linux) static if (LinuxMaybeHasGetrandom)
			{
				if (hasGetRandom == GET_RANDOM.AVAILABLE)
				{
					/*
						http://man7.org/linux/man-pages/man2/getrandom.2.html
						If the urandom source has been initialized, reads of up to 256 bytes
						will always return as many bytes as requested and will not be
						interrupted by signals.  No such guarantees apply for larger buffer
						sizes.
					*/
					import mir.linux._asm.unistd : NR_getrandom;
					size_t len = buffer.length;
					size_t ptr = cast(size_t) buffer.ptr;
					while (len > 0)
					{
						auto res = syscall(NR_getrandom, ptr, len, 0);
						if (res >= 0)
						{
							len -= res;
							ptr += res;
						}
						else if (errno != EINTR)
						{
							throw new CryptoException(
								text("Failed to read next random number: ", errno));
						}
					}
					return buffer.length;
				}
			}
			enforce!CryptoException(fread(buffer.ptr, buffer.length, 1, m_file) == 1,
				text("Failed to read next random number: ", errno));
		}
		return buffer.length;
	}

	alias read = RandomNumberStream.read;
}

//test heap-based arrays
unittest
{
	import std.algorithm;
	import std.range;

	//number random bytes in the buffer
	enum uint bufferSize = 20;

	//number of iteration counts
	enum iterationCount = 10;

	auto rng = new SystemRNG();

	//holds the random number
	ubyte[] rand = new ubyte[bufferSize];

	//holds the previous random number after the creation of the next one
	ubyte[] prevRadn = new ubyte[bufferSize];

	//create the next random number
	rng.read(prevRadn);

	assert(!equal(prevRadn, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");

	//take "iterationCount" arrays with random bytes
	foreach(i; 0..iterationCount)
	{
		//create the next random number
		rng.read(rand);

		assert(!equal(rand, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");

		assert(!equal(rand, prevRadn), "it's almost unbelievable - current and previous random bytes are equal");

		//copy current random bytes for next iteration
		prevRadn[] = rand[];
	}
}

//test stack-based arrays
unittest
{
	import std.algorithm;
	import std.range;
	import std.array;

	//number random bytes in the buffer
	enum uint bufferSize = 20;

	//number of iteration counts
	enum iterationCount = 10;

	//array that contains only zeros
	ubyte[bufferSize] zeroArray;
	zeroArray[] = take(repeat(cast(ubyte)0), bufferSize).array()[];

	auto rng = new SystemRNG();

	//holds the random number
	ubyte[bufferSize] rand;

	//holds the previous random number after the creation of the next one
	ubyte[bufferSize] prevRadn;

	//create the next random number
	rng.read(prevRadn);

	assert(prevRadn != zeroArray, "it's almost unbelievable - all random bytes is zero");

	//take "iterationCount" arrays with random bytes
	foreach(i; 0..iterationCount)
	{
		//create the next random number
		rng.read(rand);

		assert(prevRadn != zeroArray, "it's almost unbelievable - all random bytes is zero");

		assert(rand != prevRadn, "it's almost unbelievable - current and previous random bytes are equal");

		//copy current random bytes for next iteration
		prevRadn[] = rand[];
	}
}


/**
	Hash-based cryptographically secure random number mixer.

	This RNG uses a hash function to mix a specific amount of random bytes from the input RNG.
	Use only cryptographically secure hash functions like SHA-512, Whirlpool or SHA-256, but not MD5.

	Params:
		Hash: The hash function used, for example SHA1
		factor: Determines how many times the hash digest length of input data
			is used as input to the hash function. Increase factor value if you
			need more security because it increases entropy level or decrease
			the factor value if you need more speed.

*/
final class HashMixerRNG(Hash, uint factor) : RandomNumberStream
	if(isDigest!Hash)
{
	static assert(factor, "factor must be larger than 0");

	//random number generator
	SystemRNG rng;

	/**
		Creates new hash-based mixer random generator.
	*/
	this()
	{
		//create random number generator
		this.rng = new SystemRNG();
	}

	@property bool empty() { return false; }
	@property ulong leastSize() { return ulong.max; }
	@property bool dataAvailableForRead() { return true; }
	const(ubyte)[] peek() { return null; }

	size_t read(scope ubyte[] buffer, IOMode mode)
	in
	{
		assert(buffer.length, "buffer length must be larger than 0");
		assert(buffer.length <= uint.max, "buffer length must be smaller or equal uint.max");
	}
	body
	{
		auto len = buffer.length;

		//use stack to allocate internal buffer
		ubyte[factor * digestLength!Hash] internalBuffer = void;

		//init internal buffer
		this.rng.read(internalBuffer);

		//create new random number on stack
		ubyte[digestLength!Hash] randomNumber = digest!Hash(internalBuffer);

		//allows to fill buffers longer than hash digest length
		while(buffer.length > digestLength!Hash)
		{
			//fill the buffer's beginning
			buffer[0..digestLength!Hash] = randomNumber[0..$];

			//receive the buffer's end
			buffer = buffer[digestLength!Hash..$];

			//re-init internal buffer
			this.rng.read(internalBuffer);

			//create next random number
			randomNumber = digest!Hash(internalBuffer);
		}

		//fill the buffer's end
		buffer[0..$] = randomNumber[0..buffer.length];

		return len;
	}

	alias read = RandomNumberStream.read;
}

/// A SHA-1 based mixing RNG. Alias for HashMixerRNG!(SHA1, 5).
alias SHA1HashMixerRNG = HashMixerRNG!(SHA1, 5);

//test heap-based arrays
unittest
{
	import std.algorithm;
	import std.range;
	import std.typetuple;
	import std.digest.md;

	//number of iteration counts
	enum iterationCount = 10;

	enum uint factor = 5;

	//tested hash functions
	foreach(Hash; TypeTuple!(SHA1, MD5))
	{
		//test for different number random bytes in the buffer from 10 to 80 inclusive
		foreach(bufferSize; iota(10, 81))
		{
			auto rng = new HashMixerRNG!(Hash, factor)();

			//holds the random number
			ubyte[] rand = new ubyte[bufferSize];

			//holds the previous random number after the creation of the next one
			ubyte[] prevRadn = new ubyte[bufferSize];

			//create the next random number
			rng.read(prevRadn);

			assert(!equal(prevRadn, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");

			//take "iterationCount" arrays with random bytes
			foreach(i; 0..iterationCount)
			{
				//create the next random number
				rng.read(rand);

				assert(!equal(rand, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");

				assert(!equal(rand, prevRadn), "it's almost unbelievable - current and previous random bytes are equal");

				//make sure that we have different random bytes in different hash digests
				if(bufferSize > digestLength!Hash)
				{
					//begin and end of random number array
					ubyte[] begin = rand[0..digestLength!Hash];
					ubyte[] end = rand[digestLength!Hash..$];

					//compare all nearby hash digests
					while(end.length >= digestLength!Hash)
					{
						assert(!equal(begin, end[0..digestLength!Hash]), "it's almost unbelievable - random bytes in different hash digests are equal");

						//go to the next hash digests
						begin = end[0..digestLength!Hash];
						end = end[digestLength!Hash..$];
					}
				}

				//copy current random bytes for next iteration
				prevRadn[] = rand[];
			}
		}
	}
}

//test stack-based arrays
unittest
{
	import std.algorithm;
	import std.range;
	import std.array;
	import std.typetuple;
	import std.digest.md;

	//number of iteration counts
	enum iterationCount = 10;

	enum uint factor = 5;

	//tested hash functions
	foreach(Hash; TypeTuple!(SHA1, MD5))
	{
		//test for different number random bytes in the buffer
		foreach(bufferSize; TypeTuple!(10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80))
		{
			//array that contains only zeros
			ubyte[bufferSize] zeroArray;
			zeroArray[] = take(repeat(cast(ubyte)0), bufferSize).array()[];

			auto rng = new HashMixerRNG!(Hash, factor)();

			//holds the random number
			ubyte[bufferSize] rand;

			//holds the previous random number after the creation of the next one
			ubyte[bufferSize] prevRadn;

			//create the next random number
			rng.read(prevRadn);

			assert(prevRadn != zeroArray, "it's almost unbelievable - all random bytes is zero");

			//take "iterationCount" arrays with random bytes
			foreach(i; 0..iterationCount)
			{
				//create the next random number
				rng.read(rand);

				assert(prevRadn != zeroArray, "it's almost unbelievable - all random bytes is zero");

				assert(rand != prevRadn, "it's almost unbelievable - current and previous random bytes are equal");

				//make sure that we have different random bytes in different hash digests
				if(bufferSize > digestLength!Hash)
				{
					//begin and end of random number array
					ubyte[] begin = rand[0..digestLength!Hash];
					ubyte[] end = rand[digestLength!Hash..$];

					//compare all nearby hash digests
					while(end.length >= digestLength!Hash)
					{
						assert(!equal(begin, end[0..digestLength!Hash]), "it's almost unbelievable - random bytes in different hash digests are equal");

						//go to the next hash digests
						begin = end[0..digestLength!Hash];
						end = end[digestLength!Hash..$];
					}
				}

				//copy current random bytes for next iteration
				prevRadn[] = rand[];
			}
		}
	}
}


/**
	Thrown when an error occurs during random number generation.
*/
class CryptoException : Exception
{
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) @safe pure nothrow
	{
		super(msg, file, line, next);
	}
}


version(Windows)
{
	import core.sys.windows.windows;

	private extern(Windows) nothrow
	{
		alias HCRYPTPROV = size_t;

		enum LPCTSTR NULL = cast(LPCTSTR)0;
		enum DWORD PROV_RSA_FULL = 1;
		enum DWORD CRYPT_VERIFYCONTEXT = 0xF0000000;

		BOOL CryptAcquireContextA(HCRYPTPROV *phProv, LPCTSTR pszContainer, LPCTSTR pszProvider, DWORD dwProvType, DWORD dwFlags);
		alias CryptAcquireContext = CryptAcquireContextA;

		BOOL CryptReleaseContext(HCRYPTPROV hProv, DWORD dwFlags);

		BOOL CryptGenRandom(HCRYPTPROV hProv, DWORD dwLen, BYTE *pbBuffer);
	}
}

