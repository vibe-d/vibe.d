/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.algorithm : all, canFind, equal, map, sort;
import std.conv : to;
import std.encoding : sanitize;
import std.exception : assertThrown;


void runTest(ushort port)
{
	MongoClient client = connectMongoDB("127.0.0.1", port);

	auto coll = client.getCollection("test.drop_test");

	// Insert a document to ensure the collection exists
	coll.insertOne(["key": Bson("value")]);

	// Drop an existing collection
	coll.drop;

	// Drop a non-existent collection (must not throw on any MongoDB version)
	coll.drop;
}

void main(string[] args)
{
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
    runTest(port);
}
