/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;
import std.algorithm : canFind, map, equal;
import std.encoding : sanitize;

struct DBTestEntry
{
	string key1, key2;
}

void runTest()
{
	MongoClient client;
	try client = connectMongoDB("127.0.0.1");
	catch (Exception e) {
		logInfo("Failed to connect to local MongoDB server. Skipping test.");
		Throwable th = e;
		while (th) {
			logDiagnostic("Error: %s", th.toString().sanitize);
			th = th.next;
		}
		return;
	}

	auto coll = client.getCollection("test.collection");
	assert(coll.database.getLastError().code < 0);
	assert(coll.name == "collection");
	assert(coll.database.name == "test");
	coll.remove();
	coll.insert([ "key1" : "value1", "key2" : "value2"]);
	coll.update(["key1" : "value1"], [ "key1" : "value1", "key2" : "1337"]);
	assert(coll.database.getLastError().n == 1);
	auto data = coll.findOne(["key1" : "value1"]);
	assert(!data.isNull());
	assert(data["key2"].get!string() == "1337");
	coll.database.fsync();
	auto logBson = client.getDatabase("admin").getLog("global");
	assert(!logBson.isNull());

	// testing cursor range interface
	coll.remove();
	coll.insert(["key1" : "value1", "key2": "3"]);
	coll.insert(["key1" : "value2", "key2": "2"]);
	coll.insert(["key1" : "value2", "key2": "1"]);
	auto data1 = coll.find(["key1" : "value1"]);
	auto data2 = coll.find(["key1" : "value2"]);

	import std.range;
	auto converted = zip(data1, data2).map!( a => a[0]["key1"].get!string() ~ a[1]["key1"].get!string() )();
	assert(!converted.empty);
	assert(converted.front == "value1value2");

	auto names = client.getDatabases().map!(dbs => dbs.name).array;
	assert(names.canFind("test"));
	assert(names.canFind("local"));

	import std.stdio;
	AggregateOptions options;
	options.cursor.batchSize = 5;
	assert(coll.aggregate!DBTestEntry(
		[
			["$match": Bson(["key1": Bson("value2")])],
			["$sort": Bson(["key2": Bson(-1)])]
		],
		options
	).equal([DBTestEntry("value2", "2"), DBTestEntry("value2", "1")]));

	assert(coll.aggregate!DBTestEntry(
		[
			["$match": Bson(["key1": Bson("value2")])],
			["$sort": Bson(["key2": Bson(1)])]
		],
		AggregateOptions.init
	).equal([DBTestEntry("value2", "1"), DBTestEntry("value2", "2")]));

	assert(coll.aggregate(
		["$match": Bson(["key1": Bson("value2")])],
		["$sort": Bson(["key2": Bson(1)])]
	).get!(Bson[]).map!(a => a["key2"].get!string).equal(["1", "2"]));

	// test distinct()
	coll.drop();
	coll.insert(["a": "first", "b": "foo"]);
	coll.insert(["a": "first", "b": "bar"]);
	coll.insert(["a": "first", "b": "bar"]);
	coll.insert(["a": "second", "b": "baz"]);
	coll.insert(["a": "second", "b": "bam"]);
	assert(coll.distinct!string("b", ["a": "first"]).equal(["foo", "bar"]));
}

int main()
{
	int ret = 0;
	runTask({
		try runTest();
		finally exitEventLoop(true);
	});
	runEventLoop();
	return ret;
}
