/**
	MongoDB GridFS API definitions.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.gridfs;

import vibe.data.bson;

import std.array : array;
import std.algorithm : map;
import std.range : chunks, enumerate;
import std.datetime.systime : Clock;
import std.exception : enforce;

@safe:

/// configures a GridFS bucket; bucketName mirrors the Node driver option
struct GridFSBucketOptions
{
	string bucketName = "fs";

	/// default chunk size in bytes; mirrors the Node driver's 255 KiB default
	int chunkSizeBytes = 261120;
}

/// name of the files collection for the given bucket
string filesCollectionName(in GridFSBucketOptions options)
{
	return options.bucketName ~ ".files";
}

/// name of the chunks collection for the given bucket
string chunksCollectionName(in GridFSBucketOptions options)
{
	return options.bucketName ~ ".chunks";
}

/// default GridFS bucket options name the collections fs.files and fs.chunks
unittest
{
	GridFSBucketOptions options = GridFSBucketOptions.init;
	assert(filesCollectionName(options) == "fs.files");
	assert(chunksCollectionName(options) == "fs.chunks");
}

/// default GridFS bucket options chunk size is 261120 bytes
unittest
{
	assert(GridFSBucketOptions.init.chunkSizeBytes == 261120);
}

/// builds a single GridFS chunk document for the slice at index n
private Bson gridfsChunkDocument(BsonObjectID filesId, int n, scope const(ubyte)[] slice)
{
	Bson chunk = Bson.emptyObject;
	chunk["_id"] = Bson(BsonObjectID.generate());
	chunk["files_id"] = Bson(filesId);
	chunk["n"] = Bson(n);
	chunk["data"] = Bson(BsonBinData(BsonBinData.Type.generic, slice.idup));
	return chunk;
}

/// splits data into GridFS chunk documents of at most chunkSize bytes each
Bson[] gridfsChunkDocuments(BsonObjectID filesId, scope const(ubyte)[] data, int chunkSize)
{
	enforce(chunkSize > 0, "GridFS chunkSize must be positive");

	return data.chunks(chunkSize)
		.enumerate
		.map!(indexed => gridfsChunkDocument(filesId, cast(int) indexed.index, indexed.value))
		.array;
}

/// chunking with a non-positive chunk size throws
unittest
{
	import std.exception : assertThrown;

	auto filesId = BsonObjectID.generate();

	assertThrown!Exception(gridfsChunkDocuments(filesId, [ubyte(1), ubyte(2), ubyte(3)], 0));
}

/// chunking empty data yields zero chunks (an empty file is a files document with no chunks)
unittest
{
	const(ubyte)[] empty;
	auto chunks = gridfsChunkDocuments(BsonObjectID.generate(), empty, 255);

	assert(chunks.length == 0, "empty data produces no chunk documents");
}

/// chunking bytes shorter than the chunk size yields one chunk at index zero
unittest
{
	auto filesId = BsonObjectID.generate();
	ubyte[] data = [1, 2, 3];

	auto chunks = gridfsChunkDocuments(filesId, data, 255);

	assert(chunks.length == 1);
	assert(chunks[0]["n"].get!int == 0);
	assert(chunks[0]["files_id"].get!BsonObjectID == filesId);
	assert(chunks[0]["data"].get!BsonBinData.rawData == data);
}

/// chunking a buffer longer than the chunk size yields ordered chunks with a short final chunk
unittest
{
	auto filesId = BsonObjectID.generate();
	ubyte[] data = [1, 2, 3, 4, 5];

	auto chunks = gridfsChunkDocuments(filesId, data, 2);

	assert(chunks.length == 3);

	assert(chunks[0]["n"].get!int == 0);
	assert(chunks[1]["n"].get!int == 1);
	assert(chunks[2]["n"].get!int == 2);

	assert(chunks[0]["data"].get!BsonBinData.rawData == cast(ubyte[])[1, 2]);
	assert(chunks[1]["data"].get!BsonBinData.rawData == cast(ubyte[])[3, 4]);
	assert(chunks[2]["data"].get!BsonBinData.rawData == cast(ubyte[])[5]);

	assert(chunks[0]["files_id"].get!BsonObjectID == filesId);
	assert(chunks[1]["files_id"].get!BsonObjectID == filesId);
	assert(chunks[2]["files_id"].get!BsonObjectID == filesId);
}

/// builds the <bucket>.files metadata document for a stored file
Bson gridfsFilesDocument(BsonObjectID filesId, string filename, long length, int chunkSize)
{
	Bson doc = Bson.emptyObject;
	doc["_id"] = Bson(filesId);
	doc["length"] = Bson(length);
	doc["chunkSize"] = Bson(chunkSize);
	doc["filename"] = Bson(filename);
	doc["uploadDate"] = Bson(BsonDate(Clock.currTime));
	return doc;
}

/// the files document carries the file id, length, chunk size, and filename
unittest
{
	auto filesId = BsonObjectID.generate();

	auto doc = gridfsFilesDocument(filesId, "report.pdf", 1048576L, 261120);

	assert(doc["_id"].get!BsonObjectID == filesId);
	assert(doc["length"].get!long == 1048576L);
	assert(doc["chunkSize"].get!int == 261120);
	assert(doc["filename"].get!string == "report.pdf");
}

/// the files document is stamped with an upload date of BSON date type
unittest
{
	auto doc = gridfsFilesDocument(BsonObjectID.generate(), "f.bin", 10L, 4);

	assert(doc["uploadDate"].type == Bson.Type.date);
}

/// concatenates GridFS chunk documents into the original byte buffer
ubyte[] gridfsAssembleChunks(scope Bson[] chunks)
{
	import std.algorithm : sort;
	import std.conv : to;

	auto ordered = chunks.dup;
	ordered.sort!((a, b) => a["n"].get!int < b["n"].get!int);
	ubyte[] data;
	foreach (i, chunk; ordered)
	{
		enforce(chunk["n"].get!int == cast(int) i,
			"GridFS chunk " ~ i.to!string ~ " is missing");
		data ~= chunk["data"].get!BsonBinData.rawData;
	}
	return data;
}

/// concatenates GridFS chunks and validates the total against the files document's `length`,
/// catching missing trailing chunks (the interior-gap check alone would silently truncate).
ubyte[] gridfsAssembleChunks(scope Bson[] chunks, long expectedLength)
{
	import std.conv : to;

	auto data = gridfsAssembleChunks(chunks);
	enforce(cast(long) data.length == expectedLength,
		"GridFS file is truncated: assembled " ~ data.length.to!string
			~ " bytes but the files document declares " ~ expectedLength.to!string);
	return data;
}

/// assembling chunk documents reconstructs the original bytes
unittest
{
	auto filesId = BsonObjectID.generate();
	ubyte[] data = [1, 2, 3, 4, 5];

	auto chunks = gridfsChunkDocuments(filesId, data, 2);
	auto assembled = gridfsAssembleChunks(chunks);

	assert(assembled == data);
}

/// assembling chunks with a missing index throws
unittest
{
	import std.exception : assertThrown;
	import std.algorithm.mutation : remove;

	auto filesId = BsonObjectID.generate();
	ubyte[] data = [1, 2, 3, 4, 5];

	auto chunks = gridfsChunkDocuments(filesId, data, 2);
	chunks = chunks.remove(1);

	assertThrown(gridfsAssembleChunks(chunks));
}

/// assembling chunks supplied out of order reconstructs the original bytes
unittest
{
	import std.algorithm : reverse;

	auto filesId = BsonObjectID.generate();
	ubyte[] data = [1, 2, 3, 4, 5];

	auto chunks = gridfsChunkDocuments(filesId, data, 2);
	chunks.reverse;

	auto assembled = gridfsAssembleChunks(chunks);

	assert(assembled == data);
}

/// assembling all chunks whose total matches the files length returns the bytes
unittest
{
	auto filesId = BsonObjectID.generate();
	ubyte[] data = [1, 2, 3, 4, 5, 6];

	auto chunks = gridfsChunkDocuments(filesId, data, 2);

	assert(gridfsAssembleChunks(chunks, cast(long) data.length) == data);
}

/// assembling chunks shorter than the files length throws (missing trailing chunks, not just interior gaps)
unittest
{
	import std.exception : assertThrown;

	auto filesId = BsonObjectID.generate();
	ubyte[] data = [1, 2, 3, 4, 5, 6];

	auto chunks = gridfsChunkDocuments(filesId, data, 2); // 3 chunks of 2 bytes
	auto missingTrailing = chunks[0 .. 2];                // drop the LAST chunk: 4 bytes, no interior gap

	assertThrown(gridfsAssembleChunks(missingTrailing, cast(long) data.length),
		"a file missing its trailing chunk is rejected, not silently truncated");
}

import vibe.db.mongo.database : MongoDatabase;
import vibe.db.mongo.collection : MongoCollection;

/// Node-driver-style GridFS bucket. Stores and reads files split across <bucket>.files and <bucket>.chunks.
struct GridFSBucket
{
	private GridFSBucketOptions m_options;
	private MongoCollection m_files;
	private MongoCollection m_chunks;

	this(MongoDatabase db, GridFSBucketOptions options = GridFSBucketOptions.init)
	{
		m_options = options;
		m_files = db[filesCollectionName(options)];
		m_chunks = db[chunksCollectionName(options)];
	}

	/// Splits `data` into chunks, stores them, then writes the files metadata doc. Returns the file id.
	BsonObjectID uploadFromBuffer(string filename, scope const(ubyte)[] data)
	{
		auto filesId = BsonObjectID.generate();
		auto chunks = gridfsChunkDocuments(filesId, data, m_options.chunkSizeBytes);

		// If the files document is never written, drop any chunks already inserted so the
		// bucket is not left with invisible orphans.
		scope (failure)
			m_chunks.deleteMany(["files_id": Bson(filesId)]);

		// An empty file is valid (files document with length 0 and zero chunks); insertMany
		// rejects an empty array, so skip the chunk insert entirely.
		if (chunks.length)
			m_chunks.insertMany(chunks);
		m_files.insertOne(gridfsFilesDocument(filesId, filename, cast(long) data.length, m_options.chunkSizeBytes));
		return filesId;
	}

	/// Loads all chunks for `id` and reassembles the original bytes, validating the total
	/// length against the files document so a missing trailing chunk is not silently dropped.
	ubyte[] downloadToBuffer(BsonObjectID id)
	{
		auto fileDoc = m_files.findOne(["_id": Bson(id)]);
		enforce(!fileDoc.isNull, "GridFS file " ~ id.toString ~ " not found");
		auto chunks = m_chunks.find(["files_id": Bson(id)]).array;
		return gridfsAssembleChunks(chunks, fileDoc["length"].get!long);
	}
}
