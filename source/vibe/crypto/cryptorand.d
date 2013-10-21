//Implements a cryptographically secure random number generator
module vibe.crypto.cryptorand;

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
//Used "CryptGenRandom" function for Windows and "/dev/urandom" (default) or "/dev/random" for Posix
//Use "/dev/random" only for long-term secure-critical purposes because it works too slow
struct SystemRand
{
	//infinite range - always false
	enum bool empty = false;
	
	@disable this();
	
	version(Windows)
	{
		private import std.conv;
		
		//cryptographic service provider
		private HCRYPTPROV hCryptProv;
		private BYTE[] buffer;
	}
	else version(Posix)
	{
		private import std.stdio;
		
		//reference to the file stream chunks
		private File.ByChunk chunks;
	}
	else
	{
		static assert(0, "OS is not supported");
	}
	
	//Creates new random generator
	//"size" param specify a number of bytes in the buffer with random number
	//"advancedSecurity" param specify to use "/dev/urandom" if "false" (default)
	//or "/dev/random" if "true" for Posix. Do nothing for Windows.
	this(uint size, bool advancedSecurity = false)
	in
	{
		assert(size, "size must be larger than 0");
	}
	body
	{
		version(Windows)
		{
			this.buffer = new BYTE[size];
			
			//init cryptographic service provider
			if(0 == CryptAcquireContext(&this.hCryptProv, NULL, NULL, PROV_RSA_FULL, CRYPT_VERIFYCONTEXT))
			{
				throw new CryptoException(text("Cannot init SystemRand: Error id is ", GetLastError()));
			}
			
			//init buffer
			this.popFront();
		}
		else version(Posix)
		{
			string file = "/dev/urandom";
			
			if(advancedSecurity)
			{
				file = "/dev/random";
			}
			
			try
			{
				//open file
				this.chunks = File(file).byChunk(size);
			}
			catch(Exception e)
			{
				throw new CryptoException("Cannot init SystemRand: " ~ e.msg);
			}
		}
	}
	
	//create a next random number
	void popFront()
	{
		version(Windows)
		{
			if(0 == CryptGenRandom(this.hCryptProv, cast(DWORD)this.buffer.length, this.buffer.ptr))
			{
				throw new CryptoException(text("Cannot get next random number: Error id is ", GetLastError()));
			}
		}
		else version(Posix)
		{
			try
			{
				this.chunks.popFront();
			}
			catch(Exception e)
			{
				throw new CryptoException("Cannot get next random number: " ~ e.msg);
			}
		}
	}
	
	//Return current buffer with random number
	//Current buffer will be overwritten by the next call of popFront()
	//For long-term storage copy array using .dup or.idup methods
	@property ubyte[] front() nothrow
	{
		version(Windows)
		{
			return this.buffer;
		}
		else version(Posix)
		{
			return this.chunks.front;
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

unittest
{
	import std.algorithm;
	import std.range;
	
	//number random bytes in the buffer
	enum uint bufferSize = 20;
	
	//number of iteration counts 
	enum iterationCount = 10;
	
	//check bouth true and false values for advancedSecurity
	foreach(advancedSecurity; [true, false])
	{
		auto systemRand = SystemRand(bufferSize, advancedSecurity);
		
		//must be a input range
		static assert(isInputRange!SystemRand);
		//must return ubyte[]
		static assert(is(typeof(systemRand.front) == ubyte[]));
		
		assert(!equal(systemRand.front, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");
		
		//holds the previous random number after the creation of the next one
		ubyte[] prevRadn = systemRand.front.dup;
		//create the next random number
		systemRand.popFront();
		
		//take "iterationCount" arrays with random bytes
		foreach(i; 0..iterationCount)
		{
			assert(!equal(systemRand.front, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");
			
			assert(!equal(systemRand.front, prevRadn), "it's almost unbelievable - current and previous random bytes are equal");
			
			//copy current random bytes for next iteration
			prevRadn = systemRand.front.dup;
			
			//create the next random number
			systemRand.popFront();
		}
	}
}


import std.digest.sha;

//Hash-based cryptographically secure random number generator
//Use only cryptographically secure hash functions like SHA-512 or SHA1, but not MD5
struct HashRand(Hash)
if(isDigest!Hash)
{
	//infinite range - always false
	enum bool empty = false;
	
	ubyte[] buffer;
	
	//random number generator
	SystemRand rand;
	
	@disable this();
	
	//Creates new random generator
	//"factor" param shows in how many times a random number generator buffer bigger than output buffer
	//Increase "factor" value if you need more security because it increases entropy level
	//Decrease "factor" value if you need more speed
	this(uint factor)
	in
	{
		assert(factor, "factor must be larger than 0");
	}
	body
	{
		//create buffer
		this.buffer = new ubyte[digestLength!Hash];
		
		//create random number generator
		this.rand = SystemRand(factor * cast(uint)digestLength!Hash);
		
		//init buffer
		this.popFront();
	}
	
	//create a next random number
	void popFront()
	{
		this.buffer[] = digest!Hash(this.rand.front);
		this.rand.popFront();
	}
	
	//Return current buffer with random number
	//Current buffer will be overwritten by the next call of popFront()
	//For long-term storage copy array using .dup or.idup methods
	@property ubyte[] front() nothrow
	{
		return this.buffer;
	}
}

alias HashRand!SHA1 SHA1HashRand;


unittest
{
	import std.algorithm;
	import std.range;
	
	//number random bytes in the buffer
	enum uint bufferSize = digestLength!SHA1;
	
	//number of iteration counts 
	enum iterationCount = 10;
	
	auto hashRand = SHA1HashRand(5);
	
	//must be a input range
	static assert(isInputRange!SHA1HashRand);
	//must return ubyte[]
	static assert(is(typeof(hashRand.front) == ubyte[]));
	
	assert(!equal(hashRand.front, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");
	
	//holds the previous random number after the creation of the next one
	ubyte[] prevRadn = hashRand.front.dup;
	//create the next random number
	hashRand.popFront();
	
	//take "iterationCount" arrays with random bytes
	foreach(i; 0..iterationCount)
	{
		assert(!equal(hashRand.front, take(repeat(0), bufferSize)), "it's almost unbelievable - all random bytes is zero");
		
		assert(!equal(hashRand.front, prevRadn), "it's almost unbelievable - current and previous random bytes are equal");
		
		//copy current random bytes for next iteration
		prevRadn = hashRand.front.dup;
		
		//create the next random number
		hashRand.popFront();
	}
}
