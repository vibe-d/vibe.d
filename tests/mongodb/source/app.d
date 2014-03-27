/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.vibe;

void runTest()
{
	MongoClient client;
	try client = connectMongoDB("localhost");
	catch (Exception e) {
		logInfo("Failed to connect to local MongoDB server. Skipping test.");
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
	assert(data.key2.get!string() == "1337");
	coll.database.fsync();
	auto logBson = client.getDatabase("admin").getLog("global");
	assert(!logBson.isNull());

	// testing cursor range interface
	coll.remove();
	coll.insert(["key1" : "value1"]);
	coll.insert(["key1" : "value2"]);
	coll.insert(["key1" : "value2"]);
	auto data1 = coll.find(["key1" : "value1"]);
	auto data2 = coll.find(["key1" : "value2"]);

	import std.range;
	auto converted = zip(data1, data2).map!( a => a[0].key1.get!string() ~ a[1].key1.get!string() )();
	assert(!converted.empty);
	assert(converted.front == "value1value2");
}

int main()
{
	int ret = 0;
	runTask({
		try runTest();
		catch (Throwable th) {
			logError("Test failed: %s", th.msg);
			ret = 1;
		} finally exitEventLoop(true);
	});
	runEventLoop();
	return ret;
}
