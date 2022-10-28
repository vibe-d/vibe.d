/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.algorithm : canFind, equal, map, sort;
import std.conv : to;
import std.encoding : sanitize;

struct DBTestEntry
{
	string key1, key2;
}

void runTest(ushort port)
{
	MongoClient client = connectMongoDB("127.0.0.1", port);

	MongoCollection coll = client.getCollection("test.indextest.collection");
	coll.deleteAll();
	coll.insertOne(Bson.fromJson(parseJsonString(`{ "_id": 1, "key": "hello", "idioma": "portuguese", "quote": "A sorte protege os audazes" }`)));
	coll.insertOne(Bson.fromJson(parseJsonString(`{ "_id": 2, "key": "foo", "idioma": "spanish", "quote": "Nada hay más surrealista que la realidad." }`)));
	coll.insertOne(Bson.fromJson(parseJsonString(`{ "_id": 3, "key": "bar", "idioma": "english", "quote": "is this a dagger which I see before me" }`)));

	struct CustomIndex
	{
		int key = 1;
	}

	coll.createIndex(CustomIndex.init);
	IndexOptions textOptions;
	textOptions.languageOverride = "idioma";
	auto textIndex = IndexModel()
		.withOptions(textOptions)
		.add("comments", IndexType.text);
	coll.createIndex(textIndex);

	bool gotId, gotKey, gotText;
	foreach (index; coll.listIndexes())
	{
		logInfo("index: %s", index);
		switch (index["name"].get!string)
		{
		case "_id_":
			gotId = true;
			break;
		case "key_1":
			gotKey = true;
			assert(index["key"]["key"].get!int == 1);
			break;
		case "comments_text":
			gotText = true;
			assert(index["language_override"].get!string == "idioma");
			break;
		default:
			assert(false, "unknown index present: " ~ index["name"].get!string);
		}
	}
	assert(gotId);
	assert(gotKey);
	assert(gotText);

	gotId = gotKey = gotText = false;
	coll.dropIndex(textIndex);

	foreach (index; coll.listIndexes())
	{
		logInfo("index: %s", index);
		switch (index["name"].get!string)
		{
		case "_id_":
			gotId = true;
			break;
		case "key_1":
			gotKey = true;
			assert(index["key"]["key"].get!int == 1);
			break;
		case "comments_text":
			assert(false, "still got comments index after deleting");
		default:
			assert(false, "unknown index present: " ~ index["name"].get!string);
		}
	}
	assert(gotId);
	assert(gotKey);

	gotId = gotKey = gotText = false;
	coll.dropIndexes();

	foreach (index; coll.listIndexes())
	{
		logInfo("index: %s", index);
		switch (index["name"].get!string)
		{
		case "_id_":
			gotId = true;
			break;
		case "key_1":
			assert(false, "still got key index after deleting");
		case "comments_text":
			assert(false, "still got comments index after deleting");
		default:
			assert(false, "unknown index present: " ~ index["name"].get!string);
		}
	}
	assert(gotId);

	gotId = gotKey = gotText = false;
	coll.createIndex(textIndex);
	foreach (index; coll.listIndexes())
	{
		logInfo("index: %s", index);
		switch (index["name"].get!string)
		{
		case "_id_":
			gotId = true;
			break;
		case "key_1":
			assert(false, "still got key index after deleting");
		case "comments_text":
			gotText = true;
			assert(index["language_override"].get!string == "idioma");
			break;
		default:
			assert(false, "unknown index present: " ~ index["name"].get!string);
		}
	}
	assert(gotId);
	assert(gotText);

	gotId = gotKey = gotText = false;
	coll.dropIndexes(["comments_text"]);
	foreach (index; coll.listIndexes())
	{
		logInfo("index: %s", index);
		switch (index["name"].get!string)
		{
		case "_id_":
			gotId = true;
			break;
		case "key_1":
			assert(false, "still got key index after deleting");
		case "comments_text":
			assert(false, "still got comments index after deleting");
		default:
			assert(false, "unknown index present: " ~ index["name"].get!string);
		}
	}
}

int main(string[] args)
{
	int ret = 0;
	ushort port = args.length > 1 ? args[1].to!ushort : MongoClientSettings.defaultPort;
	runTask(() nothrow {
		try runTest(port);
		catch (Exception e) assert(false, e.toString());
		finally exitEventLoop(true);
	});
	runEventLoop();
	return ret;
}
