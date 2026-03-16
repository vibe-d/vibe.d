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
import std.uni;
import std.utf;
import vibe.crypto.cryptorand;

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

/**
 * SASLprep profile (RFC 4013) for password normalization.
 *
 * Applies the following steps:
 * 1. Map: non-ASCII spaces to U+0020, "commonly mapped to nothing" removed
 * 2. Normalize: NFKC
 * 3. Prohibit: check for prohibited characters
 * 4. Check bidi: ensure no mixed LTR/RTL without proper framing
 *
 * For ASCII-only input, returns the string unchanged (fast path).
 */
package string saslPrep(string input)
@safe {
	if (isAscii(input))
	{
		foreach (char c; input)
		{
			enforce(c >= 0x20 && c != 0x7F, "SASLprep prohibited character U+" ~ format("%04X", cast(uint)c));
		}
		return input;
	}

	dchar[] mapped;
	mapped.reserve(input.length);

	foreach (dchar ch; input)
	{
		if (isNonAsciiSpace(ch)) {
			mapped ~= ' ';
		} else if (!isCommonlyMappedToNothing(ch)) {
			mapped ~= ch;
		}
	}

	auto normalized = normalize!NFKC(mapped);
	string result = normalized.to!string;

	foreach (dchar ch; result)
	{
		enforce(!isProhibited(ch), "SASLprep prohibited character U+" ~ format("%04X", cast(uint)ch));
	}

	enforceBidi(result);

	return result;
}

private bool isAscii(string s) @safe @nogc pure nothrow
{
	foreach (char c; s)
	{
		if (c > 0x7E)
			return false;
	}
	return true;
}

/// RFC 3454 C.1.2 - Non-ASCII space characters mapped to U+0020
private bool isNonAsciiSpace(dchar ch) @safe @nogc pure nothrow
{
	switch (ch)
	{
		case 0x00A0: // NO-BREAK SPACE
		case 0x1680: // OGHAM SPACE MARK
		case 0x2000: // EN QUAD
		case 0x2001: // EM QUAD
		case 0x2002: // EN SPACE
		case 0x2003: // EM SPACE
		case 0x2004: // THREE-PER-EM SPACE
		case 0x2005: // FOUR-PER-EM SPACE
		case 0x2006: // SIX-PER-EM SPACE
		case 0x2007: // FIGURE SPACE
		case 0x2008: // PUNCTUATION SPACE
		case 0x2009: // THIN SPACE
		case 0x200A: // HAIR SPACE
		case 0x202F: // NARROW NO-BREAK SPACE
		case 0x205F: // MEDIUM MATHEMATICAL SPACE
		case 0x3000: // IDEOGRAPHIC SPACE
			return true;
		default:
			return false;
	}
}

/// RFC 3454 B.1 - Commonly mapped to nothing
private bool isCommonlyMappedToNothing(dchar ch) @safe @nogc pure nothrow
{
	switch (ch)
	{
		case 0x00AD: // SOFT HYPHEN
		case 0x034F: // COMBINING GRAPHEME JOINER
		case 0x1806: // MONGOLIAN TODO SOFT HYPHEN
		case 0x180B: // MONGOLIAN FREE VARIATION SELECTOR ONE
		case 0x180C: // MONGOLIAN FREE VARIATION SELECTOR TWO
		case 0x180D: // MONGOLIAN FREE VARIATION SELECTOR THREE
		case 0x200B: // ZERO WIDTH SPACE
		case 0x200C: // ZERO WIDTH NON-JOINER
		case 0x200D: // ZERO WIDTH JOINER
		case 0xFE00: // VARIATION SELECTOR-1
		case 0xFE01: // VARIATION SELECTOR-2
		case 0xFE02: // VARIATION SELECTOR-3
		case 0xFE03: // VARIATION SELECTOR-4
		case 0xFE04: // VARIATION SELECTOR-5
		case 0xFE05: // VARIATION SELECTOR-6
		case 0xFE06: // VARIATION SELECTOR-7
		case 0xFE07: // VARIATION SELECTOR-8
		case 0xFE08: // VARIATION SELECTOR-9
		case 0xFE09: // VARIATION SELECTOR-10
		case 0xFE0A: // VARIATION SELECTOR-11
		case 0xFE0B: // VARIATION SELECTOR-12
		case 0xFE0C: // VARIATION SELECTOR-13
		case 0xFE0D: // VARIATION SELECTOR-14
		case 0xFE0E: // VARIATION SELECTOR-15
		case 0xFE0F: // VARIATION SELECTOR-16
		case 0xFEFF: // ZERO WIDTH NO-BREAK SPACE
			return true;
		default:
			return false;
	}
}

/// RFC 3454 C.2.1, C.2.2, C.3-C.9 - Prohibited characters
private bool isProhibited(dchar ch) @safe @nogc pure nothrow
{
	// C.2.1 ASCII control characters
	if (ch <= 0x001F || ch == 0x007F)
		return true;

	// C.2.2 Non-ASCII control characters
	if ((ch >= 0x0080 && ch <= 0x009F) ||
		ch == 0x06DD || ch == 0x070F ||
		ch == 0x180E ||
		(ch >= 0x200C && ch <= 0x200D) ||
		(ch >= 0x2028 && ch <= 0x2029) ||
		(ch >= 0x2060 && ch <= 0x2063) ||
		(ch >= 0x206A && ch <= 0x206F) ||
		ch == 0xFEFF ||
		(ch >= 0xFFF9 && ch <= 0xFFFC) ||
		(ch >= 0x1D173 && ch <= 0x1D17A))
		return true;

	// C.3 Private use
	if ((ch >= 0xE000 && ch <= 0xF8FF) ||
		(ch >= 0xF0000 && ch <= 0xFFFFD) ||
		(ch >= 0x100000 && ch <= 0x10FFFD))
		return true;

	// C.4 Non-character code points
	if ((ch >= 0xFDD0 && ch <= 0xFDEF) ||
		(ch & 0xFFFF) == 0xFFFE || (ch & 0xFFFF) == 0xFFFF)
		return true;

	// C.5 Surrogate codes (shouldn't appear in valid UTF, but check anyway)
	if (ch >= 0xD800 && ch <= 0xDFFF)
		return true;

	// C.7 Inappropriate for canonical representation
	if (ch >= 0x2FF0 && ch <= 0x2FFB)
		return true;

	// C.8 Change display properties or are deprecated
	if (ch == 0x0340 || ch == 0x0341 || ch == 0x200E || ch == 0x200F ||
		ch == 0x202A || ch == 0x202B || ch == 0x202C || ch == 0x202D ||
		ch == 0x202E || ch == 0x206A || ch == 0x206B || ch == 0x206C ||
		ch == 0x206D || ch == 0x206E || ch == 0x206F)
		return true;

	// C.9 Tagging characters
	if (ch == 0xE0001 || (ch >= 0xE0020 && ch <= 0xE007F))
		return true;

	return false;
}

/// RFC 3454 D.1/D.2 - Bidirectional check
private void enforceBidi(string s) @safe
{
	bool hasRandALCat = false;
	bool hasLCat = false;
	dchar first = dchar.init;
	dchar last = dchar.init;

	foreach (dchar ch; s)
	{
		if (first == dchar.init)
			first = ch;
		last = ch;

		if (isRandALCat(ch))
			hasRandALCat = true;
		if (isLCat(ch))
			hasLCat = true;
	}

	if (hasRandALCat)
	{
		enforce(!hasLCat, "SASLprep bidirectional check failed: mixed R/AL and L characters");
		enforce(isRandALCat(first) && isRandALCat(last),
			"SASLprep bidirectional check failed: string with R/AL must start and end with R/AL");
	}
}

/// RFC 3454 D.1 - Characters with bidirectional property "R" or "AL"
private bool isRandALCat(dchar ch) @safe @nogc pure nothrow
{
	if (ch >= 0x0590 && ch <= 0x05FF) return true; // Hebrew
	if (ch >= 0x0600 && ch <= 0x06FF) return true; // Arabic
	if (ch >= 0x0700 && ch <= 0x074F) return true; // Syriac
	if (ch >= 0x0780 && ch <= 0x07BF) return true; // Thaana
	if (ch >= 0xFB1D && ch <= 0xFB4F) return true; // Hebrew Presentation Forms
	if (ch >= 0xFB50 && ch <= 0xFDFF) return true; // Arabic Presentation Forms-A
	if (ch >= 0xFE70 && ch <= 0xFEFF) return true; // Arabic Presentation Forms-B
	return false;
}

/// RFC 3454 D.2 - Characters with bidirectional property "L"
private bool isLCat(dchar ch) @safe @nogc pure nothrow
{
	if (ch >= 0x0041 && ch <= 0x005A) return true; // A-Z
	if (ch >= 0x0061 && ch <= 0x007A) return true; // a-z
	if (ch >= 0x00C0 && ch <= 0x00D6) return true; // Latin Extended
	if (ch >= 0x00D8 && ch <= 0x00F6) return true;
	if (ch >= 0x00F8 && ch <= 0x0220) return true;
	if (ch >= 0x0222 && ch <= 0x0233) return true;
	if (ch >= 0x0250 && ch <= 0x02AD) return true; // IPA Extensions
	if (ch >= 0x0388 && ch <= 0x03CE) return true; // Greek
	if (ch >= 0x03D0 && ch <= 0x03F6) return true;
	if (ch >= 0x0400 && ch <= 0x0482) return true; // Cyrillic
	if (ch >= 0x048A && ch <= 0x04CE) return true;
	if (ch >= 0x04D0 && ch <= 0x04F9) return true;
	return false;
}

/// saslPrep returns ASCII strings unchanged
unittest
{
	assert(saslPrep("pencil") == "pencil");
	assert(saslPrep("pencil") is "pencil");
}

/// saslPrep normalizes non-ASCII space U+00A0 to regular space
unittest
{
	assert(saslPrep("p\u00A0s") == "p s");
}

/// saslPrep removes soft hyphen (commonly mapped to nothing)
unittest
{
	assert(saslPrep("p\u00ADs") == "ps");
}

/// saslPrep applies NFKC normalization
unittest
{
	// U+2126 OHM SIGN normalizes to U+03A9 GREEK CAPITAL LETTER OMEGA under NFKC
	assert(saslPrep("\u2126") == "\u03A9");
}

/// saslPrep rejects ASCII control characters
unittest
{
	assertThrown!Exception(saslPrep("bad\x00char"));
	assertThrown!Exception(saslPrep("bad\x07char"));
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
