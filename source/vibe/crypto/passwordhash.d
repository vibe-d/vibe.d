/**
	Password hashing routines

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.crypto.passwordhash;

import std.base64;
import std.exception;
import std.md5;
import std.random;


string generateSimplePasswordHash(string password)
{
	ubyte[4] salt;
	foreach( i; 0 .. 4 ) salt[i] = cast(ubyte)uniform(0, 256);
	ubyte[16] hash;
	sum(hash, salt ~ cast(ubyte[])password);
	return Base64.encode(salt ~ hash).idup;
}

bool testSimplePasswordHash(string hashstring, string password)
{
	ubyte[] upass = Base64.decode(hashstring);
	enforce(upass.length == 20);
	auto salt = upass[0 .. 4];
	auto hashcmp = upass[4 .. 20];
	ubyte[16] hash;
	sum(hash, salt, password);
	return hash == hashcmp;
}
