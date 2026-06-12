/**
	MongoDB wire-protocol primitives: opcodes, the reply/section delegate types,
	message length computation and OP_MSG body parsing.

	These are internal helpers used by the MongoConnection send/receive methods,
	which stay in connection.d because they operate on the connection's stream.

	Copyright: © 2012-2016 Sönke Ludwig, © 2020-2022 Jan Jurzitza
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Jurzitza
*/
module vibe.db.mongo.impl.wire;

import std.conv : to;
import std.exception : enforce;

import vibe.data.bson;
import vibe.db.mongo.connection : MongoDriverException;
import vibe.db.mongo.flags : ReplyFlags;

package(vibe.db.mongo) enum OpCode : int {
	Reply        = 1, // sent only by DB
	Update       = 2001,
	Insert       = 2002,
	Reserved1    = 2003,
	Query        = 2004,
	GetMore      = 2005,
	Delete       = 2006,
	KillCursors  = 2007,

	Compressed   = 2012,
	Msg          = 2013,
}

/// Whether an OP_MSG flagBits field has checksumPresent (bit 0) set — a 4-byte CRC32C
/// trailer follows the sections. Bit 16 is exhaustAllowed, not the checksum bit;
/// confusing the two parses the CRC as a section or truncates real data (review M13).
package(vibe.db.mongo) bool checksumPresent(uint flagBits) @safe
{
	return (flagBits & 1) != 0;
}

package(vibe.db.mongo) alias ReplyDelegate = void delegate(long cursor, ReplyFlags flags, int first_doc, int num_docs) @safe;
package(vibe.db.mongo) template DocDelegate(T) { alias DocDelegate = void delegate(size_t idx, ref T doc) @safe; }

package(vibe.db.mongo) alias MsgReplyDelegate(bool dupBson : true) = void delegate(uint flags, Bson document) @safe;
package(vibe.db.mongo) alias MsgReplyDelegate(bool dupBson : false) = void delegate(uint flags, scope Bson document) @safe;
package(vibe.db.mongo) alias MsgSection1StartDelegate = void delegate(scope const(char)[] identifier, int size) @safe;
package(vibe.db.mongo) alias MsgSection1Delegate(bool dupBson : true) = void delegate(scope const(char)[] identifier, Bson document) @safe;
package(vibe.db.mongo) alias MsgSection1Delegate(bool dupBson : false) = void delegate(scope const(char)[] identifier, scope Bson document) @safe;

package(vibe.db.mongo) int sendLength(ARGS...)(scope ARGS args)
{
	import std.traits;
	static if (ARGS.length == 1) {
		alias T = ARGS[0];
		static if (is(T == string)) return cast(int)args[0].length + 1;
		else static if (is(T == int)) return 4;
		else static if (is(T == long)) return 8;
		else static if (is(T == Bson)) return cast(int)() @trusted { return args[0].data.length; } ();
		else static if (isArray!T) {
			int ret = 0;
			foreach (el; args[0]) ret += sendLength(el);
			return ret;
		} else static assert(false, "Unexpected type: "~T.stringof);
	}
	else if (ARGS.length == 0) return 0;
	else return sendLength(args[0 .. $/2]) + sendLength(args[$/2 .. $]);
}

/// sendLength of a string is its length plus one
unittest
{
	assert(sendLength("test") == 5);
	assert(sendLength("") == 1);
}

/// sendLength of an int is 4 and of a long is 8
unittest
{
	assert(sendLength(42) == 4);
	assert(sendLength(42L) == 8);
}

/// sendLength of a Bson is the length of its raw data
unittest
{
	auto bson = Bson(42);
	assert(sendLength(bson) == cast(int)bson.data.length);
}

/// sendLength of an array sums the lengths of its elements
unittest
{
	assert(sendLength(["ab", "c"]) == 5);
	assert(sendLength(cast(string[])[]) == 0);
}

/// sendLength of multiple arguments sums each argument
unittest
{
	assert(sendLength("test", 42) == 9);
	assert(sendLength() == 0);
}

package(vibe.db.mongo) void parseOpMsgBody(bool dupBson)(
	const(ubyte)[] data,
	scope MsgReplyDelegate!dupBson on_sec0,
	scope MsgSection1StartDelegate on_sec1_start,
	scope MsgSection1Delegate!dupBson on_sec1_doc)
{
	import std.bitmanip : littleEndianToNative;

	size_t pos = 0;

	T readVal(T)() @trusted {
		enum sz = T.sizeof;
		enforce!MongoDriverException(pos + sz <= data.length, "Buffer underflow in decompressed OP_MSG");
		ubyte[sz] buf = (cast(ubyte[]) data[pos .. pos + sz])[0 .. sz];
		pos += sz;
		return littleEndianToNative!(T, sz)(buf);
	}

	uint flagBits = readVal!uint();
	const bool hasCRC = checksumPresent(flagBits);
	const size_t endPos = data.length - (hasCRC ? uint.sizeof : 0);

	bool gotSec0;
	while (pos < endPos) {
		ubyte payloadType = readVal!ubyte();

		switch (payloadType) {
			case 0:
				gotSec0 = true;
				int bsonLen = readVal!int();
				enforce!MongoDriverException(bsonLen >= 5, "Invalid BSON document length in decompressed OP_MSG");
				enforce!MongoDriverException(pos + bsonLen - 4 <= data.length, "BSON overflows decompressed buffer");

				auto bsonData = new ubyte[bsonLen];
				bsonData[0 .. 4] = toBsonData(bsonLen)[];
				bsonData[4 .. bsonLen] = data[pos .. pos + bsonLen - 4];
				pos += bsonLen - 4;

				auto doc = () @trusted { return Bson(Bson.Type.object, cast(immutable) bsonData); }();
				on_sec0(flagBits, doc);
				break;

			case 1:
				if (!gotSec0) {
					throw new MongoDriverException("Got OP_MSG section 1 before section 0 in decompressed message");
				}

				auto sectionStart = pos;
				int size = readVal!int();

				auto identStart = pos;
				while (pos < data.length && data[pos] != 0) {
					pos++;
				}
				auto identifier = cast(const(char)[]) data[identStart .. pos];
				pos++;

				on_sec1_start(identifier, size);

				while (pos - sectionStart < size) {
					int docLen = readVal!int();
					enforce!MongoDriverException(docLen >= 5, "Invalid BSON document length in decompressed OP_MSG section 1");

					auto bsonData = new ubyte[docLen];
					bsonData[0 .. 4] = toBsonData(docLen)[];
					bsonData[4 .. docLen] = data[pos .. pos + docLen - 4];
					pos += docLen - 4;

					auto doc = () @trusted { return Bson(Bson.Type.object, cast(immutable) bsonData); }();
					on_sec1_doc(identifier, doc);
				}
				break;

			default:
				throw new MongoDriverException("Unexpected payload section type in decompressed message: " ~ payloadType.to!string);
		}
	}
}

/// parseOpMsgBody parses section 0 document and flags from raw OP_MSG body
unittest
{
	auto doc = Bson(["ok": Bson(1.0)]);
	auto docBytes = () @trusted { return cast(const(ubyte)[]) doc.data; }();

	ubyte[] body_;
	body_ ~= toBsonData(cast(uint) 0)[];
	body_ ~= cast(ubyte) 0;
	body_ ~= docBytes;

	Bson parsed;
	uint parsedFlags;

	parseOpMsgBody!true(body_,
		(flags, document) { parsedFlags = flags; parsed = document; },
		(scope ident, size) {},
		(scope ident, document) {});

	assert(parsedFlags == 0);
	assert(parsed["ok"].get!double == 1.0);
}

/// parseOpMsgBody treats checksumPresent (flag bit 0) as a CRC trailer, not as a section
unittest
{
	auto doc = Bson(["ok": Bson(1.0)]);
	auto docBytes = () @trusted { return cast(const(ubyte)[]) doc.data; }();

	ubyte[] body_;
	body_ ~= toBsonData(cast(uint) 1)[];
	body_ ~= cast(ubyte) 0;
	body_ ~= docBytes;
	body_ ~= toBsonData(cast(uint) 0xDEADBEEF)[];

	Bson parsed;
	uint parsedFlags;
	bool gotSection0;

	parseOpMsgBody!true(body_,
		(flags, document) { gotSection0 = true; parsedFlags = flags; parsed = document; },
		(scope ident, size) {},
		(scope ident, document) {});

	assert(gotSection0, "section 0 callback did not fire");
	assert(parsedFlags == 1u, "checksumPresent flag bit not preserved");
	assert(parsed["ok"].get!double == 1.0, "section 0 document did not round-trip");
}

/// parseOpMsgBody correctly parses a compressed and decompressed OP_MSG body
unittest
{
	import vibe.db.mongo.impl.compression : compressData, decompressData;
	import vibe.db.mongo.settings : Compressor;

	auto doc = Bson(["ok": Bson(1.0)]);
	auto docBytes = () @trusted { return cast(const(ubyte)[]) doc.data; }();

	ubyte[] body_;
	body_ ~= toBsonData(cast(uint) 0)[];
	body_ ~= cast(ubyte) 0;
	body_ ~= docBytes;

	auto compressed = compressData(Compressor.zlib, body_, 6);
	auto decompressed = decompressData(Compressor.zlib, compressed, cast(int) body_.length);

	Bson parsed;
	parseOpMsgBody!true(decompressed,
		(flags, document) { parsed = document; },
		(scope ident, size) {},
		(scope ident, document) {});

	assert(parsed["ok"].get!double == 1.0);
}
