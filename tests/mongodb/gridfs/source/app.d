/// Exercises GridFSBucket's buffer round-trip against a real mongod.
/// A multi-chunk buffer uploaded via uploadFromBuffer must come back byte-identical
/// through downloadToBuffer.

module app;

import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.conv : to;
import std.exception : assertThrown;

void runTest(ushort port)
{
	auto client = connectMongoDB("mongodb://127.0.0.1:" ~ port.to!string ~ "/");
	scope (exit) client.cleanupConnections();
	auto db = client.getDatabase("gridfs_test");

	// Force multiple chunks out of a small buffer: 250 bytes / 100 = 3 chunks.
	GridFSBucketOptions options;
	options.chunkSizeBytes = 100;
	auto bucket = GridFSBucket(db, options);

	// Clear any prior files/chunks state so reruns stay idempotent.
	try db["fs.files"].drop; catch (Exception) {}
	try db["fs.chunks"].drop; catch (Exception) {}

	ubyte[] data;
	foreach (i; 0 .. 250)
		data ~= cast(ubyte)(i % 256);

	auto id = bucket.uploadFromBuffer("hello.bin", data);
	logInfo("uploaded %s bytes as %s", data.length, id.to!string);

	auto got = bucket.downloadToBuffer(id);
	assert(got == data, "downloaded buffer did not match the uploaded bytes");
	logInfo("buffer round-trip OK: %s bytes across multiple chunks", got.length);

	auto missingId = BsonObjectID.generate();
	assertThrown(bucket.downloadToBuffer(missingId));
	logInfo("missing-id download rejected as required");

	logInfo("gridfs harness passed");
}

void main(string[] args)
{
	setLogLevel(LogLevel.info);
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
	runTest(port);
}
