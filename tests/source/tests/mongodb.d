module tests.mongodb;

import vibe.vibe;

// Requires mongo service running on localhost with default port
// Uses test database

void test_mongodb_general()
{
	auto client = connectMongoDB("localhost");
	auto coll = client.getCollection("test.collection");
	assert(coll.database.getLastError().code < 0);
	assert(coll.name == "collection");
	assert(coll.database.name == "test");
	coll.remove();
	coll.insert([ "key1" : "value1", "key2" : "value2"]);
	coll.update(["key1" : "value1"], [ "key1" : "value1", "key2" : "1337"]);
	assert(coll.database.getLastError().n == 1);
	auto data = coll.find(["key1" : true]);
	foreach (doc; data)
	{
	    assert(doc.length == 1);
	    assert(doc.key2.get!string() == "1337");
	}
	coll.database.fsync();
	auto logBson = client.getDatabase("admin").getLog("global");
	assert(!logBson.isNull());
}