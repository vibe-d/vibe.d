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

package(vibe.db.mongo) Compressor negotiateCompressor(const Compressor[] clientCompressors, const string[] serverCompressors)
@safe {
	foreach (clientComp; clientCompressors) {
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
			assert(false, "snappy compression not yet implemented");
		case Compressor.zstd:
			assert(false, "zstd compression not yet implemented");
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
			assert(false, "snappy decompression not yet implemented");
		case Compressor.zstd:
			assert(false, "zstd decompression not yet implemented");
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
