/**
	Implements a cryptographically secure random number generator
	
	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Ilya Shipunov
*/
module vibe.crypto.cryptorand;

private import std.conv : text;
private import std.digest.sha;

/**
	Thrown if we have errors with random number generation.
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
	pragma(lib,"advapi32");
	
	private import std.c.windows.windows;
	
	private extern(Windows) nothrow
	{
		alias ULONG_PTR HCRYPTPROV;
		
		enum LPCTSTR NULL = cast(LPCTSTR)0;
		enum DWORD PROV_RSA_FULL = 1;
		enum DWORD CRYPT_VERIFYCONTEXT = 0xF0000000;
		
		BOOL CryptAcquireContextA(HCRYPTPROV *phProv, LPCTSTR pszContainer, LPCTSTR pszProvider, DWORD dwProvType, DWORD dwFlags);
		alias CryptAcquireContextA CryptAcquireContext;
		
		BOOL CryptReleaseContext(HCRYPTPROV hProv, DWORD dwFlags);
		
		BOOL CryptGenRandom(HCRYPTPROV hProv, DWORD dwLen, BYTE *pbBuffer);
	}
}

/**
	System cryptography secure random number generator
	It use "CryptGenRandom" function for Windows and "/dev/urandom" for Posix
	It's recommended to use additional processing generated random numbers
	via provided functions for systems where security matters.
	
	Remarks:
		Windows "CryptGenRandom" RNG has problems with Windows 2000 and Windows XP
		(assuming the attacker has control of the machine).
		Fixed for Windows XP Service Pack 3 and Windows Vista.
		http://en.wikipedia.org/wiki/CryptGenRandom
*/
final class SystemRNG
{
	version(Windows)
	{
		//cryptographic service provider
		private HCRYPTPROV hCryptProv;
	}
	else version(Posix)
	{
		private import std.stdio;
		private import std.exception;
		
		//cryptographic file stream
		private File file;
	}
	else
	{
		static assert(0, "OS is not supported");
	}
	
	/**
		Creates new system random generator
	*/
	this()
	{
		version(Windows)
		{
			//init cryptographic service provider
			if(0 == CryptAcquireContext(&this.hCryptProv, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT))
			{
				throw new CryptoException(text("Cannot init SystemRNG: Error id is ", GetLastError()));
			}
		}
		else version(Posix)
		{
			try
			{
				//open file
				this.file = File("/dev/urandom");
				//do not use buffering stream to avoid possible attacks
				this.file.setvbuf(null, _IONBF);
			}
			catch(ErrnoException e)
			{
				throw new CryptoException(text("Cannot init SystemRNG: Error id is ", e.errno, `, Error message is: "`, e.msg, `"`));
			}
			catch(Exception e)
			{
				throw new CryptoException(text("Cannot init SystemRNG: ", e.msg));
			}
		}
	}
	
	/**
		Fills the buffer new random number
		
		Params:
			buffer: The buffer that will be filled new random number.
				It will contain buffer.length random ubytes.
				Supported both heap-based and stack-based arrays.
		Throws:
			CryptoException on error.
	*/
	void read(ubyte[] buffer)
	in
	{
		assert(buffer.length, "buffer length must be larger than 0");
		assert(buffer.length <= uint.max, "buffer length must be smaller or equal uint.max");
	}
	body
	{
		version(Windows)
		{
			if(0 == CryptGenRandom(this.hCryptProv, cast(DWORD)buffer.length, buffer.ptr))
			{
				throw new CryptoException(text("Cannot get next random number: Error id is ", GetLastError()));
			}
		}
		else version(Posix)
		{
			try
			{
				this.file.rawRead(buffer);
			}
			catch(ErrnoException e)
			{
				throw new CryptoException(text("Cannot get next random number: Error id is ", e.errno, `, Error message is: "`, e.msg, `"`));
			}
			catch(Exception e)
			{
				throw new CryptoException(text("Cannot get next random number: ", e.msg));
			}
		}
	}
	
	~this()
	{
		version(Windows)
		{
			CryptReleaseContext(this.hCryptProv, 0);
		}
	}
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
	Hash-based cryptographically secure mixer
	It uses hash function to mix random bytes from input RNG
	Use only cryptographically secure hash functions like SHA-512, Whirlpool or SHA-256, but not MD5
	
	Params:
		Hash: hash function like SHA1
		factor: Shows in how many times a input RNG buffer bigger than output buffer
			Increase factor value if you need more security because it increases entropy level
			Decrease factor value if you need more speed
			
*/
final class HashMixerRNG(Hash, uint factor)
if(isDigest!Hash)
{
	static assert(factor, "factor must be larger than 0");
	
	//random number generator
	SystemRNG rng;
	
	/**
		Creates new hash-based mixer random generator
	*/
	this()
	{
		//create random number generator
		this.rng = new SystemRNG();
	}
	
	/**
		Fills the buffer new random number
		
		Params:
			buffer: The buffer that will be filled new random number.
				It will contain buffer.length random ubytes.
				Supported both heap-based and stack-based arrays.
		Throws:
			CryptoException on error.
	*/
	void read(ubyte[] buffer)
	in
	{
		assert(buffer.length, "buffer length must be larger than 0");
		assert(buffer.length <= uint.max, "buffer length must be smaller or equal uint.max");
	}
	body
	{
		//use stack to allocate internal buffer
		ubyte[factor * digestLength!Hash] internalBuffer;
		
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
	}
}

///alias for HashMixerRNG!(SHA1, 5)
alias HashMixerRNG!(SHA1, 5) SHA1HashMixerRNG;

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
