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
import std.digest.hmac;
import std.digest.sha;
import std.exception;
import std.format;
import std.string;
import std.utf;
import vibe.crypto.cryptorand;

@safe:

private SHA1HashMixerRNG g_rng()
{
	static SHA1HashMixerRNG m_rng;
	if (!m_rng) m_rng = new SHA1HashMixerRNG;
	return m_rng;
}

package struct ScramState
{
	@safe:

	private string m_firstMessageBare;
	private string m_nonce;
	private DigestType!SHA1 m_saltedPassword;
	private string m_authMessage;

	string createInitialRequest(string user)
	{
		ubyte[18] randomBytes;
		g_rng.read(randomBytes[]);
		m_nonce = Base64.encode(randomBytes);

		m_firstMessageBare = format("n=%s,r=%s", escapeUsername(user), m_nonce);
		return format("n,,%s", m_firstMessageBare);
	}

	string update(string password, string challenge)
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

		if (serverNonce[0 .. m_nonce.length] != m_nonce)
			throw new Exception("Invalid server nonce received");
		string finalMessage = format("c=biws,r=%s", serverNonce);

		m_saltedPassword = pbkdf2(password.representation, salt, iterations);
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

	unittest
	{
		string user = "user";
		assert(escapeUsername(user) == user);
		assert(escapeUsername(user) is user);
		assert(escapeUsername("user,1") == "user=2C1");
		assert(escapeUsername("user=1") == "user=3D1");
		assert(escapeUsername("u,=ser1") == "u=2C=3Dser1");
		assert(escapeUsername("u=se=r1") == "u=3Dse=3Dr1");
	}

	private static auto getClientProof(DigestType!SHA1 saltedPassword, string authMessage)
	{
		auto clientKey = () @trusted { return hmac!SHA1("Client Key".representation, saltedPassword); } ();
		auto storedKey = sha1Of(clientKey);
		auto clientSignature = () @trusted { return hmac!SHA1(authMessage.representation, storedKey); } ();

		foreach (i; 0 .. clientKey.length)
		{
			clientKey[i] = clientKey[i] ^ clientSignature[i];
		}
		return clientKey;
	}

	private static bool verifyServerSignature(ubyte[] signature, DigestType!SHA1 saltedPassword, string authMessage)
	@trusted {
		auto serverKey = hmac!SHA1("Server Key".representation, saltedPassword);
		auto serverSignature = hmac!SHA1(authMessage.representation, serverKey);
		return serverSignature == signature;
	}
}

private DigestType!SHA1 pbkdf2(const ubyte[] password, const ubyte[] salt, int iterations)
{
	import std.bitmanip;

	ubyte[4] intBytes = [0, 0, 0, 1];
	auto last = () @trusted { return hmac!SHA1(salt, intBytes[], password); } ();
	auto current = last;
	foreach (i; 1 .. iterations)
	{
		last = () @trusted { return hmac!SHA1(last[], password); } ();
		foreach (j; 0 .. current.length)
		{
			current[j] = current[j] ^ last[j];
		}
	}
	return current;
}
