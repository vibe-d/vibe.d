/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.algorithm : equal, map, sort;
import std.array : array;
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

	testCursorEdgeCases(client);

	coll.deleteAll();
}

void testCursorEdgeCases(MongoClient client)
{
	import vibe.db.mongo.impl.crud : FindOptions;

	auto coll = client.getCollection("test.cursor_edge");
	coll.deleteAll();

	foreach (i; 0 .. 100)
		coll.insertOne(["idx": i]);

	// Empty result set: find with non-matching filter
	auto emptyCursor = coll.find(["idx": Bson(-999)]);
	assert(emptyCursor.empty);

	// skip past all documents results in empty cursor
	auto skipped = coll.find(Bson.emptyObject).skip(200).array;
	assert(skipped.length == 0);

	// sort + skip + limit combination
	auto sorted = coll.find(Bson.emptyObject).sort(["idx": -1]).skip(10).limit(5).array;
	assert(sorted.length == 5);
	// Descending: 99, 98, 97, ... skip 10 -> 89, 88, 87, 86, 85
	assert(sorted[0]["idx"].get!int == 89);
	assert(sorted[4]["idx"].get!int == 85);

	// limit(1) returns exactly one document
	auto single = coll.find(Bson.emptyObject).limit(1).array;
	assert(single.length == 1);

	// Projection via FindOptions: only return specific fields
	FindOptions projOpts;
	projOpts.projection = Bson(["idx": Bson(1), "_id": Bson(0)]);
	auto projected = coll.find(Bson.emptyObject, projOpts).limit(3).array;
	assert(projected.length == 3);
	foreach (doc; projected) {
		auto keys = doc.get!(Bson[string]).byKey.array;
		assert(keys.sort!"a<b".array == ["idx"]);
	}

	// Large skip with limit: skip(95) + limit(10) -> only 5 docs remain
	auto tail = coll.find(Bson.emptyObject).sort(["idx": 1]).skip(95).limit(10).array;
	assert(tail.length == 5);
	assert(tail[0]["idx"].get!int == 95);
	assert(tail[4]["idx"].get!int == 99);

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
