/**
	SASL authentication functions

	Copyright: © 2012-2016 Nicolas Gurrola
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Nicolas Gurrola
*/
module vibe.db.mongo.sasl;

import std.algorithm;
import std.base64;
import std.conv;
import std.digest;
import std.digest.hmac;
import std.digest.sha;
import std.exception;
import std.format;
import std.string;
import std.traits;
import std.utf;
import vibe.crypto.cryptorand;
import vibe.db.mongo.saslprep;

@safe:

private SHA1HashMixerRNG g_rng()
{
	static SHA1HashMixerRNG m_rng;
	if (!m_rng) m_rng = new SHA1HashMixerRNG;
	return m_rng;
}

package struct ScramState(HashType = SHA1)
{
	@safe:

	private string m_firstMessageBare;
	private string m_nonce;
	private DigestType!HashType m_saltedPassword;
	private string m_authMessage;

	string createInitialRequest(string user)
	{
		ubyte[18] randomBytes;
		g_rng.read(randomBytes[]);
		m_nonce = Base64.encode(randomBytes);

		m_firstMessageBare = format("n=%s,r=%s", escapeUsername(user), m_nonce);
		return format("n,,%s", m_firstMessageBare);
	}

	version (unittest) private string createInitialRequestWithFixedNonce(string user, string nonce)
	{
		m_nonce = nonce;

		m_firstMessageBare = format("n=%s,r=%s", escapeUsername(user), m_nonce);
		return format("n,,%s", m_firstMessageBare);
	}

	// MongoDB drivers require 4096 min iterations https://github.com/mongodb/specifications/blob/59390a7ab2d5c8f9c29b8af1775ff25915c44036/source/auth/auth.rst#scram-sha-1
	string update(string password, string challenge, int minIterations = 4096)
	{
		string serverFirstMessage = challenge;

		string next = challenge.find(',');
		if (challenge.length < 2 || challenge[0 .. 2] != "r=" || next.length < 3 || next[1 .. 3] != "s=")
			throw new Exception("Invalid server challenge format");
		string serverNonce = challenge[2 .. $ - next.length];
		challenge = next[3 .. $];
		next = challenge.find(',');
		ubyte[] salt = Base64.decode(challenge[0 .. $ - next.length]);

		if (next.length < 3 || next[1 .. 3] != "i=")
			throw new Exception("Invalid server challenge format");
		int iterations = next[3 .. $].to!int();

		if (iterations < minIterations)
			throw new Exception("Server must request at least " ~ minIterations.to!string ~ " iterations");

		if (serverNonce[0 .. m_nonce.length] != m_nonce)
			throw new Exception("Invalid server nonce received");
		string finalMessage = format("c=biws,r=%s", serverNonce);

		m_saltedPassword = pbkdf2!HashType(password.representation, salt, iterations);
		m_authMessage = format("%s,%s,%s", m_firstMessageBare, serverFirstMessage, finalMessage);

		auto proof = getClientProof(m_saltedPassword, m_authMessage);
		return format("%s,p=%s", finalMessage, Base64.encode(proof));
	}

	string finalize(string challenge)
	{
		if (challenge.length < 2 || challenge[0 .. 2] != "v=")
		{
			throw new Exception("Invalid server signature format");
		}
		if (!verifyServerSignature(Base64.decode(challenge[2 .. $]), m_saltedPassword, m_authMessage))
		{
			throw new Exception("Invalid server signature");
		}
		return null;
	}

	private static string escapeUsername(string user)
	{
		char[] buffer;
		foreach (i, dchar ch; user)
		{
			if (ch == ',' || ch == '=') {
				if (!buffer) {
					buffer.reserve(user.length + 2);
					buffer ~= user[0 .. i];
				}
				if (ch == ',')
					buffer ~= "=2C";
				else
					buffer ~= "=3D";
			} else if (buffer)
				encode(buffer, ch);
		}
		return buffer ? () @trusted { return assumeUnique(buffer); } () : user;
	}

	/// escapeUsername preserves plain usernames unchanged
	unittest
	{
		string user = "user";
		assert(escapeUsername(user) == user);
		assert(escapeUsername(user) is user);
	}

	/// escapeUsername encodes commas as =2C
	unittest
	{
		assert(escapeUsername("user,1") == "user=2C1");
	}

	/// escapeUsername encodes equals as =3D
	unittest
	{
		assert(escapeUsername("user=1") == "user=3D1");
	}

	/// escapeUsername encodes mixed commas and equals
	unittest
	{
		assert(escapeUsername("u,=ser1") == "u=2C=3Dser1");
		assert(escapeUsername("u=se=r1") == "u=3Dse=3Dr1");
	}

	/// escapeUsername returns empty string for empty input
	unittest
	{
		assert(escapeUsername("") == "");
	}

	/// escapeUsername encodes strings with only commas
	unittest
	{
		assert(escapeUsername(",,") == "=2C=2C");
	}

	/// escapeUsername encodes strings with only equals
	unittest
	{
		assert(escapeUsername("==") == "=3D=3D");
	}

	/// escapeUsername returns identity for plain alphanumeric strings
	unittest
	{
		assert(escapeUsername("plainuser123") == "plainuser123");
		assert(escapeUsername("plainuser123") is "plainuser123");
	}

	private static auto getClientProof(DigestType!HashType saltedPassword, string authMessage)
	{
		auto clientKey = () @trusted { return hmac!HashType("Client Key".representation, saltedPassword); } ();
		auto storedKey = digest!HashType(clientKey);
		auto clientSignature = () @trusted { return hmac!HashType(authMessage.representation, storedKey); } ();

		foreach (i; 0 .. clientKey.length)
		{
			clientKey[i] = clientKey[i] ^ clientSignature[i];
		}
		return clientKey;
	}

	private static bool verifyServerSignature(ubyte[] signature, DigestType!HashType saltedPassword, string authMessage)
	@trusted {
		auto serverKey = hmac!HashType("Server Key".representation, saltedPassword);
		auto serverSignature = hmac!HashType(authMessage.representation, serverKey);
		return constantTimeEquals(serverSignature[], signature);
	}
}

private DigestType!HashType pbkdf2(HashType)(const ubyte[] password, const ubyte[] salt, int iterations)
{
	import std.bitmanip;

	ubyte[4] intBytes = [0, 0, 0, 1];
	auto last = () @trusted { return hmac!HashType(salt, intBytes[], password); } ();
	static assert(isStaticArray!(typeof(last)),
		"Code is written so that the hash array is expected to be placed on the stack");
	auto current = last;
	foreach (i; 1 .. iterations)
	{
		last = () @trusted { return hmac!HashType(last[], password); } ();
		foreach (j; 0 .. current.length)
		{
			current[j] = current[j] ^ last[j];
		}
	}
	return current;
}

/// Constant-time comparison to prevent timing attacks on signature verification.
private bool constantTimeEquals(const ubyte[] a, const ubyte[] b)
@safe @nogc pure nothrow {
	if (a.length != b.length)
		return false;

	ubyte result = 0;
	foreach (i; 0 .. a.length)
	{
		result |= a[i] ^ b[i];
	}
	return result == 0;
}

/// constantTimeEquals returns true for identical arrays
unittest
{
	ubyte[4] a = [1, 2, 3, 4];
	ubyte[4] b = [1, 2, 3, 4];
	assert(constantTimeEquals(a[], b[]));
}

/// constantTimeEquals returns false for different arrays
unittest
{
	ubyte[4] a = [1, 2, 3, 4];
	ubyte[4] b = [1, 2, 3, 5];
	assert(!constantTimeEquals(a[], b[]));
}

/// constantTimeEquals returns false for different lengths
unittest
{
	ubyte[3] a = [1, 2, 3];
	ubyte[4] b = [1, 2, 3, 4];
	assert(!constantTimeEquals(a[], b[]));
}

/// SCRAM-SHA-1 full authentication flow using MongoDB spec test vectors
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings;

	ScramState!SHA1 state;
	assert(state.createInitialRequestWithFixedNonce("user", "fyko+d2lbbFgONRv9qkxdawL")
		== "n,,n=user,r=fyko+d2lbbFgONRv9qkxdawL");
	auto last = state.update(MongoClientSettings.makeDigest("user", "pencil"),
		"r=fyko+d2lbbFgONRv9qkxdawLHo+Vgk7qvUOKUwuWLIWg4l/9SraGMHEE,s=rQ9ZY3MntBeuP3E1TDVC4w==,i=10000");
	assert(last == "c=biws,r=fyko+d2lbbFgONRv9qkxdawLHo+Vgk7qvUOKUwuWLIWg4l/9SraGMHEE,p=MC2T8BvbmWRckDw8oWl5IVghwCY=",
		last);
	last = state.finalize("v=UMWeI25JD1yNYZRMpZ4VHvhZ9e0=");
	assert(last == "", last);
}

/// SCRAM update throws on missing r= prefix in server challenge
unittest
{
	ScramState!SHA1 s;
	s.createInitialRequestWithFixedNonce("user", "testnonce");
	assertThrown!Exception(s.update("digest", "invalid_challenge"));
}

/// SCRAM update throws on missing s= field in server challenge
unittest
{
	ScramState!SHA1 s;
	s.createInitialRequestWithFixedNonce("user", "testnonce");
	assertThrown!Exception(s.update("digest", "r=testnonceServer,x=bad"));
}

/// SCRAM update throws when server nonce doesn't start with client nonce
unittest
{
	ScramState!SHA1 s;
	s.createInitialRequestWithFixedNonce("user", "testnonce");
	assertThrown!Exception(s.update("digest",
		"r=WRONGnonceServer,s=QSXCR+Q6sek8bf92,i=4096"));
}

/// SCRAM update throws when iteration count 4095 is below minimum 4096
unittest
{
	ScramState!SHA1 s;
	s.createInitialRequestWithFixedNonce("user", "testnonce");
	assertThrown!Exception(s.update("digest",
		"r=testnonceServer,s=QSXCR+Q6sek8bf92,i=4095"));
}

/// SCRAM update succeeds when iteration count is exactly minimum 4096
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings;

	ScramState!SHA1 s;
	s.createInitialRequestWithFixedNonce("user", "testnonce");
	auto digest = MongoClientSettings.makeDigest("user", "pencil");
	s.update(digest, "r=testnonceServer,s=QSXCR+Q6sek8bf92,i=4096");
}

// Test vectors from the MongoDB SCRAM-SHA-1 specification:
// https://github.com/mongodb/specifications/blob/59390a7ab2d5c8f9c29b8af1775ff25915c44036/source/auth/auth.rst#id5
// Nonce, salt, iteration count, and server response are all from that spec.
version (unittest)
{
	private enum scramTestNonce = "fyko+d2lbbFgONRv9qkxdawL";
	private enum scramTestChallenge =
		"r=fyko+d2lbbFgONRv9qkxdawLHo+Vgk7qvUOKUwuWLIWg4l/9SraGMHEE,s=rQ9ZY3MntBeuP3E1TDVC4w==,i=10000";

	private ScramState!SHA1 createScramStateForFinalize()
	{
		import vibe.db.mongo.settings : MongoClientSettings;

		ScramState!SHA1 s;
		s.createInitialRequestWithFixedNonce("user", scramTestNonce);
		s.update(MongoClientSettings.makeDigest("user", "pencil"), scramTestChallenge);
		return s;
	}
}

/// SCRAM finalize throws when response doesn't start with "v="
unittest
{
	auto s = createScramStateForFinalize();
	assertThrown!Exception(s.finalize("invalid_format"));
}

/// SCRAM finalize throws on wrong server signature value
unittest
{
	auto s = createScramStateForFinalize();
	assertThrown!Exception(s.finalize("v=AAAAAAAAAAAAAAAAAAAAAAAAAAAA"));
}

/// SCRAM finalize throws when response is too short
unittest
{
	auto s = createScramStateForFinalize();
	assertThrown!Exception(s.finalize("v"));
}

/// SCRAM-SHA-256 full authentication flow using MongoDB spec test vectors
unittest
{
	// Test vectors from the MongoDB SCRAM-SHA-256 specification:
	// https://github.com/mongodb/specifications/blob/master/source/auth/auth.rst#scram-sha-256
	ScramState!SHA256 state;
	assert(state.createInitialRequestWithFixedNonce("user", "rOprNGfwEbeRWgbNEkqO")
		== "n,,n=user,r=rOprNGfwEbeRWgbNEkqO");

	auto last = state.update("pencil",
		"r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096");
	assert(last == "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=",
		last);

	last = state.finalize("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=");
	assert(last == "", last);
}

/// SCRAM-SHA-256 update succeeds with minimum iteration count 4096
unittest
{
	ScramState!SHA256 s;
	s.createInitialRequestWithFixedNonce("user", "testnonce");
	s.update("pencil", "r=testnonceServer,s=QSXCR+Q6sek8bf92,i=4096");
}

/// SCRAM-SHA-256 update throws when iteration count is below minimum 4096
unittest
{
	ScramState!SHA256 s;
	s.createInitialRequestWithFixedNonce("user", "testnonce");
	assertThrown!Exception(s.update("pencil",
		"r=testnonceServer,s=QSXCR+Q6sek8bf92,i=4095"));
}
