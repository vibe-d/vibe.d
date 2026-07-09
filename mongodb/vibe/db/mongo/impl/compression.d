/**
	MongoDB wire-protocol compression helpers: compressor negotiation and the
	(de)compression of OP_COMPRESSED payloads.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.compression;

import std.conv : to;

import vibe.db.mongo.connection : MongoDriverException;
import vibe.db.mongo.settings : Compressor, compressorName;

/// Whether the driver actually implements (de)compression for this compressor.
/// Keep in sync with compressData/decompressData below — advertising or selecting
/// an unimplemented compressor halts the process when the server uses it.
package(vibe.db.mongo) bool isImplementedCompressor(Compressor compressor) @safe
{
	return compressor == Compressor.noop || compressor == Compressor.zlib;
}

/// The wire names of the compressors the driver will advertise: only the implemented
/// ones, so the server never compresses a reply with a codec the driver can't decompress.
package(vibe.db.mongo) string[] advertisedCompressorNames(const Compressor[] compressors) @safe
{
	import std.algorithm : filter, map;
	import std.array : array;
	return compressors.filter!isImplementedCompressor.map!compressorName.array;
}

/// advertisedCompressorNames lists only the implemented compressors (so the server never compresses a reply we can't decompress)
unittest
{
	assert(advertisedCompressorNames([Compressor.snappy, Compressor.zlib, Compressor.zstd]) == ["zlib"],
		"only implemented compressors (zlib) are advertised; snappy/zstd are dropped");
	assert(advertisedCompressorNames([Compressor.zlib]) == ["zlib"],
		"an all-implemented list is advertised unchanged");
	assert(advertisedCompressorNames([Compressor.snappy]) == [],
		"a list of only unimplemented compressors advertises nothing");
}

package(vibe.db.mongo) Compressor negotiateCompressor(const Compressor[] clientCompressors, const string[] serverCompressors)
@safe {
	foreach (clientComp; clientCompressors) {
		if (!isImplementedCompressor(clientComp))
			continue;
		foreach (serverComp; serverCompressors) {
			if (compressorName(clientComp) == serverComp) {
				return clientComp;
			}
		}
	}

	return Compressor.noop;
}

/// negotiateCompressor picks first client-preferred compressor supported by server
unittest
{
	assert(negotiateCompressor([Compressor.zlib], ["zlib"]) == Compressor.zlib);
	assert(negotiateCompressor([Compressor.zstd, Compressor.zlib], ["zlib", "snappy"]) == Compressor.zlib);
	assert(negotiateCompressor([Compressor.zstd], ["zlib"]) == Compressor.noop);
	assert(negotiateCompressor([], ["zlib"]) == Compressor.noop);
	assert(negotiateCompressor([Compressor.zlib], []) == Compressor.noop);
}

/// negotiateCompressor never selects an unimplemented compressor (only zlib/noop are implemented)
unittest
{
	// both sides support snappy, but the driver can't compress it -> must NOT pick snappy
	assert(negotiateCompressor([Compressor.snappy], ["snappy"]) == Compressor.noop,
		"negotiateCompressor must not select snappy (unimplemented)");
	// snappy is skipped, zlib (implemented, mutually supported) is chosen
	assert(negotiateCompressor([Compressor.snappy, Compressor.zlib], ["snappy", "zlib"]) == Compressor.zlib,
		"negotiateCompressor skips unimplemented snappy and selects implemented zlib");
	// zstd likewise unimplemented
	assert(negotiateCompressor([Compressor.zstd], ["zstd"]) == Compressor.noop,
		"negotiateCompressor must not select zstd (unimplemented)");
}

package(vibe.db.mongo) Compressor compressorFromId(ubyte id)
@safe {
	switch (id) {
		case 0: return Compressor.noop;
		case 1: return Compressor.snappy;
		case 2: return Compressor.zlib;
		case 3: return Compressor.zstd;
		default: throw new MongoDriverException("Unknown compressor ID: " ~ id.to!string);
	}
}

/// compressorFromId maps wire protocol IDs to Compressor enum values
unittest
{
	assert(compressorFromId(0) == Compressor.noop);
	assert(compressorFromId(1) == Compressor.snappy);
	assert(compressorFromId(2) == Compressor.zlib);
	assert(compressorFromId(3) == Compressor.zstd);
}

package(vibe.db.mongo) ubyte[] compressData(Compressor compressor, const(ubyte)[] data, int zlibLevel)
@trusted {
	final switch (compressor) {
		case Compressor.noop:
			return data.dup;
		case Compressor.zlib:
			import std.zlib : compress;
			return cast(ubyte[]) compress(data, zlibLevel == -1 ? 6 : zlibLevel);
		case Compressor.snappy:
			throw new MongoDriverException("snappy compression not yet implemented");
		case Compressor.zstd:
			throw new MongoDriverException("zstd compression not yet implemented");
	}
}

package(vibe.db.mongo) ubyte[] decompressData(Compressor compressor, const(ubyte)[] data, int uncompressedSize)
@trusted {
	final switch (compressor) {
		case Compressor.noop:
			return data.dup;
		case Compressor.zlib:
			import std.zlib : uncompress;
			return cast(ubyte[]) uncompress(data, uncompressedSize);
		case Compressor.snappy:
			throw new MongoDriverException("snappy decompression not yet implemented");
		case Compressor.zstd:
			throw new MongoDriverException("zstd decompression not yet implemented");
	}
}

/// compressData and decompressData round-trip preserves original data
unittest
{
	auto original = cast(const(ubyte)[]) "The robot shall not harm a human, but I really want to.";
	auto compressed = compressData(Compressor.zlib, original, 6);
	auto decompressed = decompressData(Compressor.zlib, compressed, cast(int) original.length);
	assert(decompressed == original);
}

/// compressData throws a recoverable MongoDriverException for an unimplemented compressor (never halts via assert(false))
unittest
{
	import std.exception : assertThrown;
	auto data = cast(const(ubyte)[]) "payload";
	assertThrown!MongoDriverException(compressData(Compressor.snappy, data, 6),
		"compressData(snappy) must throw a recoverable MongoDriverException, not assert(false)");
}

/// MongoDB's default maxMessageSizeBytes (48 MB): the largest single wire message a server sends.
package(vibe.db.mongo) enum int defaultMaxMessageSizeBytes = 48_000_000;

/// Validates OP_COMPRESSED wire-supplied sizes before allocating or decompressing. A negative
/// size would allocate a huge buffer (fatal OutOfMemoryError); an over-large uncompressedSize is
/// a decompression bomb. Both must be in `[0, maxMessageSizeBytes]`.
package(vibe.db.mongo) void enforceCompressedSizes(int compressedSize, int uncompressedSize, int maxMessageSizeBytes) @safe
{
	import std.exception : enforce;
	enforce!MongoDriverException(compressedSize >= 0 && compressedSize <= maxMessageSizeBytes,
		"OP_COMPRESSED compressed size out of range: " ~ compressedSize.to!string);
	enforce!MongoDriverException(uncompressedSize >= 0 && uncompressedSize <= maxMessageSizeBytes,
		"OP_COMPRESSED uncompressed size out of range: " ~ uncompressedSize.to!string);
}

/// Whether a command must never be compressed because it carries credentials or is part of
/// the authentication handshake. Per the OP_COMPRESSED spec these are exempt regardless of
/// the negotiated compressor, not only during the initial connect-time auth window.
package(vibe.db.mongo) bool isCompressionExempt(string commandName) @safe
{
	switch (commandName)
	{
		case "hello", "isMaster", "ismaster",
			"saslStart", "saslContinue", "authenticate", "getnonce",
			"createUser", "updateUser",
			"copydbsaslstart", "copydbgetnonce", "copydb":
			return true;
		default:
			return false;
	}
}

/// isCompressionExempt flags the credential/handshake commands the spec forbids compressing
unittest
{
	assert(isCompressionExempt("saslStart"), "saslStart carries auth data and must not be compressed");
	assert(isCompressionExempt("saslContinue"), "saslContinue carries auth data and must not be compressed");
	assert(isCompressionExempt("createUser"), "createUser carries a password and must not be compressed");
	assert(isCompressionExempt("updateUser"), "updateUser may carry a password and must not be compressed");
	assert(isCompressionExempt("hello"), "the handshake hello is exempt");
	assert(!isCompressionExempt("insert"), "ordinary commands may be compressed");
	assert(!isCompressionExempt("find"), "ordinary commands may be compressed");
}

/// enforceCompressedSizes rejects negative or over-large OP_COMPRESSED wire sizes
unittest
{
	import std.exception : assertThrown, assertNotThrown;
	enum int max = defaultMaxMessageSizeBytes;

	assertNotThrown(enforceCompressedSizes(100, 500, max), "in-range sizes pass");
	assertNotThrown(enforceCompressedSizes(0, 0, max), "zero sizes pass (an empty message)");
	assertThrown!MongoDriverException(enforceCompressedSizes(-1, 500, max), "a negative compressed size is rejected");
	assertThrown!MongoDriverException(enforceCompressedSizes(100, -1, max), "a negative uncompressed size is rejected");
	assertThrown!MongoDriverException(enforceCompressedSizes(max + 1, 500, max), "an over-large compressed size is rejected");
	assertThrown!MongoDriverException(enforceCompressedSizes(100, max + 1, max), "a decompression-bomb uncompressed size is rejected");
}
