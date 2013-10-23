//Implements a cryptographically secure random number generator
module vibe.crypto.cryptorand;


private import std.conv : text;

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

//System cryptography secure random generator
//Used "CryptGenRandom" function for Windows and "/dev/urandom" for Posix
final class SystemRand
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
		
		//reference to the file stream
		private File file;
	}
	else
	{
		static assert(0, "OS is not supported");
	}
	
	//Creates new random generator
	this()
	{
		version(Windows)
		{
			//init cryptographic service provider
			if(0 == CryptAcquireContext(&this.hCryptProv, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT))
			{
				throw new CryptoException(text("Cannot init SystemRand: Error id is ", GetLastError()));
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
				throw new CryptoException(text("Cannot init SystemRand: Error id is ", e.errno, `, Error message is: "`, e.msg, `"`));
			}
			catch(Exception e)
			{
				throw new CryptoException(text("Cannot init SystemRand: ", e.msg));
			}
		}
	}
	
	//Fills the buffer new random numbers
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
	
	auto systemRand = new SystemRand();
	
	//holds the random number
	ubyte[] rand = new ubyte[bufferSize];
	
	//holds the previous random number after the creation of the next one
	ubyte[] prevRadn = new ubyte[bufferSize];
	
	//create the next random number
	systemRand.read(prevRadn);
	
	assert(!equal(prevRadn, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");
	
	//take "iterationCount" arrays with random bytes
	foreach(i; 0..iterationCount)
	{
		//create the next random number
		systemRand.read(rand);
		
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
	
	auto systemRand = new SystemRand();
	
	//holds the random number
	ubyte[bufferSize] rand;
	
	//holds the previous random number after the creation of the next one
	ubyte[bufferSize] prevRadn;
	
	//create the next random number
	systemRand.read(prevRadn);
	
	assert(prevRadn != zeroArray, "it's almost unbelievable - all random bytes is zero");
	
	//take "iterationCount" arrays with random bytes
	foreach(i; 0..iterationCount)
	{
		//create the next random number
		systemRand.read(rand);
		
		assert(prevRadn != zeroArray, "it's almost unbelievable - all random bytes is zero");
		
		assert(rand != prevRadn, "it's almost unbelievable - current and previous random bytes are equal");
		
		//copy current random bytes for next iteration
		prevRadn[] = rand[];
	}
}
