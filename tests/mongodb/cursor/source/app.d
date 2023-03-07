/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.conv : to;


void runTest(ushort port)
{
	MongoClient client = connectMongoDB("127.0.0.1", port);

	auto coll = client.getCollection("test.collection");
	coll.deleteAll();

	foreach (i; 0 .. 100)
		coll.insertOne(["idx": i]);

	FindOptions opts;
	opts.batchSize = 10;
	auto data = coll.find(Bson.emptyObject, opts);
	size_t i = 0;
	foreach (d; data)
		assert(d["idx"].get!int == i++);
	assert(i == 100);

	coll.deleteAll();
}

void main(string[] args)
{
	int ret = 0;
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
	runTest(port);
}
