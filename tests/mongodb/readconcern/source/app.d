/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.data.bson;
import vibe.db.mongo.mongo;
import vibe.db.mongo.settings;

import std.conv : to;

void runTest(ushort port)
{
	testUriParsing();
	testInheritanceChain(port);
	testPerOperationOverride(port);
}

void testUriParsing()
{
	MongoClientSettings cfg;

	assert(parseMongoDBUrl(cfg, "mongodb://localhost/?readConcernLevel=majority"));
	assert(cfg.readConcern.level == "majority");

	MongoClientSettings cfg2;
	assert(parseMongoDBUrl(cfg2, "mongodb://localhost"));
	assert(cfg2.readConcern.level == "");
}

void testInheritanceChain(ushort port)
{
	auto client = connectMongoDB("mongodb://127.0.0.1:" ~ to!string(port) ~ "/?readConcernLevel=majority");
	assert(client.readConcern.level == "majority");

	auto db = client.getDatabase("test");
	assert(db.readConcern.level == "majority");

	auto dbOverridden = db.withReadConcern(ReadConcern("local"));
	assert(dbOverridden.readConcern.level == "local");
	assert(db.readConcern.level == "majority");

	auto coll = dbOverridden["readconcern_test"];
	assert(coll.readConcern.level == "local");

	auto collOverridden = coll.withReadConcern(ReadConcern("available"));
	assert(collOverridden.readConcern.level == "available");
	assert(coll.readConcern.level == "local");
}

void testPerOperationOverride(ushort port)
{
	auto client = connectMongoDB("mongodb://127.0.0.1:" ~ to!string(port) ~ "/?readConcernLevel=majority");

	auto coll = client.getCollection("test.readconcern_test");
	coll.deleteAll();
	coll.insertOne(["key": Bson("value")]);

	auto data = coll.find(Bson.emptyObject).front;
	assert(data["key"].get!string == "value");

	import vibe.db.mongo.impl.crud : FindOptions;
	FindOptions opts;
	opts.readConcern = ReadConcern("local");
	auto data2 = coll.find(Bson.emptyObject, opts).front;
	assert(data2["key"].get!string == "value");

	coll.deleteAll();
}

void main(string[] args)
{
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
	runTest(port);
}
