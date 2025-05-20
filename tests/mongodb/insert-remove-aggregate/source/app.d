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

struct DBTestEntry
{
	string key1, key2;
}

void runTest(ushort port)
{
	MongoClient client = connectMongoDB("127.0.0.1", port);

	auto coll = client.getCollection("test.collection");
	coll.deleteAll();
	coll.insertOne(["key1": "value1", "key2": "value2"]);
	auto replaceResult = coll.replaceOne(["key1": "value1"], ["key1": "value1", "key2": "1337"]);
	assert(replaceResult.modifiedCount == 1);
	auto data = coll.findOne(["key1": "value1"]);
	assert(!data.isNull());
	assert(data["key2"].get!string() == "1337");
	client.getDatabase("admin").fsync();
	auto logBson = client.getDatabase("admin").getLog("global");
	assert(!logBson.isNull());

	// testing cursor range interface
	coll.deleteAll();
	coll.insertOne(["key1": "value1", "key2": "3"]);
	coll.insertOne(["key1": "value2", "key2": "2"]);
	coll.insertOne(["key1": "value2", "key2": "1"]);
	auto data1 = coll.find(["key1": "value1"]);
	auto data2 = coll.find(["key1": "value2"]);

	import std.range;

	auto converted = zip(data1, data2).map!(
		a => a[0]["key1"].get!string() ~ a[1]["key1"].get!string())();
	assert(!converted.empty);
	assert(converted.front == "value1value2");

	auto projectedData = coll
		.find(Bson.emptyObject, ["key2": 1])
		.sort(["key2": 1])
		.array;
	assert(projectedData[0]["key2"].get!string == "1");
	assert(projectedData[1]["key2"].get!string == "2");
	assert(projectedData[2]["key2"].get!string == "3");

	assert(projectedData.all!(d =>
		d.get!(Bson[string]).byKey.array.sort!"a<b".array
			== ["_id", "key2"]));

	auto names = client.getDatabases().map!(dbs => dbs.name).array;
	assert(names.canFind("test"));
	assert(names.canFind("local"));

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
		).get!(Bson[])
			.map!(a => a["key2"].get!string)
			.equal(["1", "2"]));

	assert(coll.countDocuments(["key1": "value2"]) == 2);

	// test distinct()
	coll.drop();
	coll.insertOne(["a": "first", "b": "foo"]);
	coll.insertOne(["a": "first", "b": "bar"]);
	coll.insertOne(["a": "first", "b": "bar"]);
	coll.insertOne(["a": "second", "b": "baz"]);
	coll.insertOne(["a": "second", "b": "bam"]);
	auto d = coll.distinct!string("b", ["a": "first"]).array;
	d.sort!"a<b";
	assert(d == ["bar", "foo"]);

	testIndexInsert(client);
}

void testIndexInsert(MongoClient client)
{
	MongoCollection coll = client.getCollection("test.indexedinsert");
	coll.deleteAll();
	auto n = coll.insertMany([
		Bson([
			"_id": Bson(1),
			"username": Bson("Bob")
		]),
		Bson([
			"_id": Bson(2),
			"username": Bson("Alice")
		]),
	]);
	assert(n.insertedCount == 2);

	assertThrown(coll.insertOne(Bson([
		"_id": Bson(2), // duplicate _id
		"username": Bson("Tom")
	])));

	IndexOptions indexOptions;
	indexOptions.unique = true;
	coll.createIndex(IndexModel.init
		.withOptions(indexOptions)
		.add("username", 1));

	coll.insertOne(Bson([
		"_id": Bson(3),
		"username": Bson("Charlie")
	]));

	assertThrown(coll.insertOne(Bson([
		"_id": Bson(4),
		"username": Bson("Bob") // duplicate username
	])));

	assert(coll.estimatedDocumentCount == 3);
}

int main(string[] args)
{
	int ret = 0;
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
	runTest(port);
	return ret;
}
