/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.algorithm : all, canFind, equal, map, sort;
import std.array : array;
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
	testUpdateOperations(client);
	testDeleteOperations(client);
	testEmptyCollectionBehavior(client);
	testAggregationPipeline(client);
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

void testUpdateOperations(MongoClient client)
{
	auto coll = client.getCollection("test.update_ops");
	coll.deleteAll();

	coll.insertOne(Bson(["name": Bson("Alice"), "score": Bson(100L)]));
	coll.insertOne(Bson(["name": Bson("Bob"), "score": Bson(200L)]));
	coll.insertOne(Bson(["name": Bson("Charlie"), "score": Bson(150L)]));

	// updateOne with $set
	auto res = coll.updateOne(["name": "Alice"], ["$set": Bson(["score": Bson(110L)])]);
	assert(res.matchedCount == 1);
	assert(res.modifiedCount == 1);
	assert(coll.findOne(["name": "Alice"])["score"].get!long == 110);

	// updateOne with $inc
	coll.updateOne(["name": "Bob"], ["$inc": Bson(["score": Bson(50L)])]);
	assert(coll.findOne(["name": "Bob"])["score"].get!long == 250);

	// updateOne with $unset
	coll.updateOne(["name": "Charlie"], ["$unset": Bson(["score": Bson("")])]);
	auto charlie = coll.findOne(["name": "Charlie"]);
	assert(charlie["score"].type == Bson.Type.null_);

	// updateMany - update all documents
	auto manyRes = coll.updateMany(Bson.emptyObject, ["$set": Bson(["active": Bson(true)])]);
	assert(manyRes.matchedCount == 3);
	assert(manyRes.modifiedCount == 3);

	// updateOne with upsert on non-existing document
	UpdateOptions upsertOpts;
	upsertOpts.upsert = true;
	coll.updateOne(["name": "Dave"], ["$set": Bson(["name": Bson("Dave"), "score": Bson(99L)])], upsertOpts);
	assert(!coll.findOne(["name": "Dave"]).isNull());

	// updateOne matching nothing (no upsert)
	res = coll.updateOne(["name": "NoSuchPerson"], ["$set": Bson(["score": Bson(0L)])]);
	assert(res.matchedCount == 0);
	assert(res.modifiedCount == 0);

	coll.drop();
}

void testDeleteOperations(MongoClient client)
{
	auto coll = client.getCollection("test.delete_ops");
	coll.deleteAll();

	coll.insertOne(["key": "a"]);
	coll.insertOne(["key": "b"]);
	coll.insertOne(["key": "b"]);
	coll.insertOne(["key": "c"]);

	// deleteOne removes exactly one matching document
	auto res = coll.deleteOne(["key": "b"]);
	assert(res.deletedCount == 1);
	assert(coll.countDocuments(["key": "b"]) == 1);

	// deleteMany removes all matching documents
	coll.insertOne(["key": "b"]);
	res = coll.deleteMany(["key": "b"]);
	assert(res.deletedCount == 2);
	assert(coll.countDocuments(["key": "b"]) == 0);

	// deleteOne with no match
	res = coll.deleteOne(["key": "nonexistent"]);
	assert(res.deletedCount == 0);

	// deleteAll empties collection
	assert(coll.countDocuments(Bson.emptyObject) > 0);
	coll.deleteAll();
	assert(coll.countDocuments(Bson.emptyObject) == 0);

	coll.drop();
}

void testEmptyCollectionBehavior(MongoClient client)
{
	auto coll = client.getCollection("test.empty_coll");
	coll.drop();

	// find on empty collection returns empty cursor
	auto cursor = coll.find(Bson.emptyObject);
	assert(cursor.empty);

	// findOne on empty collection returns null Bson
	assert(coll.findOne(Bson.emptyObject).isNull());

	// countDocuments on empty collection returns 0
	assert(coll.countDocuments(Bson.emptyObject) == 0);

	// estimatedDocumentCount on empty collection returns 0
	assert(coll.estimatedDocumentCount() == 0);

	// updateOne on empty collection matches nothing
	auto ures = coll.updateOne(["key": "x"], ["$set": Bson(["key": Bson("y")])]);
	assert(ures.matchedCount == 0);
	assert(ures.modifiedCount == 0);

	// updateMany on empty collection matches nothing
	ures = coll.updateMany(Bson.emptyObject, ["$set": Bson(["key": Bson("y")])]);
	assert(ures.matchedCount == 0);

	// deleteOne on empty collection deletes nothing
	auto dres = coll.deleteOne(["key": "x"]);
	assert(dres.deletedCount == 0);

	// deleteMany on empty collection deletes nothing
	dres = coll.deleteMany(Bson.emptyObject);
	assert(dres.deletedCount == 0);

	coll.drop();
}

void testAggregationPipeline(MongoClient client)
{
	auto coll = client.getCollection("test.agg_pipeline");
	coll.drop();

	coll.insertOne(Bson(["category": Bson("A"), "value": Bson(10L)]));
	coll.insertOne(Bson(["category": Bson("A"), "value": Bson(20L)]));
	coll.insertOne(Bson(["category": Bson("B"), "value": Bson(30L)]));
	coll.insertOne(Bson(["category": Bson("B"), "value": Bson(40L)]));
	coll.insertOne(Bson(["category": Bson("B"), "value": Bson(50L)]));

	// $group stage with $sum accumulator
	auto grouped = coll.aggregate(
		["$group": Bson(["_id": Bson("$category"), "total": Bson(["$sum": Bson("$value")])])]
	).get!(Bson[]);
	assert(grouped.length == 2);

	// Verify group totals by looking up each category
	long totalA, totalB;
	foreach (doc; grouped) {
		if (doc["_id"].get!string == "A") totalA = doc["total"].get!long;
		if (doc["_id"].get!string == "B") totalB = doc["total"].get!long;
	}
	assert(totalA == 30);
	assert(totalB == 120);

	// $project stage
	auto projected = coll.aggregate(
		["$project": Bson(["category": Bson(1), "_id": Bson(0)])]
	).get!(Bson[]);
	assert(projected.length == 5);
	// Verify only category field present (no _id, no value)
	foreach (doc; projected) {
		auto keys = doc.get!(Bson[string]).byKey.array;
		assert(keys.canFind("category"));
		assert(!keys.canFind("_id"));
		assert(!keys.canFind("value"));
	}

	// countDocuments with skip and limit
	CountOptions countOpts;
	countOpts.skip = 1L;
	countOpts.limit = 2L;
	assert(coll.countDocuments(["category": "B"], countOpts) == 2);

	// countDocuments with skip exceeding match count
	CountOptions skipAllOpts;
	skipAllOpts.skip = 100L;
	assert(coll.countDocuments(["category": "B"], skipAllOpts) == 0);

	// Aggregation on empty collection
	auto emptyColl = client.getCollection("test.agg_empty");
	emptyColl.drop();
	auto emptyResult = emptyColl.aggregate(
		["$group": Bson(["_id": Bson("$category"), "total": Bson(["$sum": Bson("$value")])])]
	).get!(Bson[]);
	assert(emptyResult.length == 0);

	coll.drop();
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
