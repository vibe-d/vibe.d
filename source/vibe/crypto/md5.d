/**
	Deprecated; MD5 hashing functions.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger
*/
module vibe.crypto.md5;
pragma(msg, "Module vibe.crypto.md5 is deprecated, please import std.digest.md instead.");

static if( __traits(compiles, {import std.digest.md;}) ){
	import std.digest.md;

	deprecated("Please use std.digest.hexDigest!MD5 instead.")
	string md5(in char[] str) 
	{
		return hexDigest!MD5(str).idup;
	}
} else {
	import std.md5;

	deprecated("Please use std.digest.hexDigest!MD5 instead.")
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