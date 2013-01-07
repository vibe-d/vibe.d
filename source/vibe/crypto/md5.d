/**
	MD5 hashing functions.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger
*/
module vibe.crypto.md5;

static if( __traits(compiles, {import std.digest.md;}) ){
	import std.digest.md;

	string md5(in char[] str) 
	{
		MD5 ctx;
		ctx.start();
		ctx.put(cast(ubyte[])str);
		return ctx.finish().toHexString().idup;
	}
} else {
	import std.md5;

	string md5(in char[] str) 
	{
		ubyte[16] digest;
		MD5_CTX ctx;
		ctx.start();
		ctx.update(str);
		ctx.finish(digest);
		return digestToString(digest);
	}
}