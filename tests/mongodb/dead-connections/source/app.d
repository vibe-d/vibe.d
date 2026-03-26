import vibe.db.mongo.mongo;
import vibe.db.mongo.client;
import vibe.db.mongo.settings;
import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import core.time;
import std.conv;
import std.exception;

int main(string[] args)
{
	setLogLevel(LogLevel.diagnostic);

	if (args.length < 2)
	{
		logError("Usage: %s <port>", args[0]);
		return 1;
	}

	runTask({ sleepUninterruptible(30.seconds); assert(false, "Timeout exceeded"); });

	ushort port = args[1].to!ushort;

	auto settings = new MongoClientSettings;
	settings.hosts = [MongoHost("127.0.0.1", port)];
	settings.connectTimeoutMS = 5_000;
	settings.socketTimeoutMS = 2_000;
	settings.appName = "DeadConnTest";

	logInfo("Phase 1: Create client and open multiple connections");

	MongoClient client;
	try
	{
		client = connectMongoDB(settings);
	}
	catch (Exception e)
	{
		logError("Failed to connect: %s", e.msg);
		return 1;
	}

	auto coll = client.getCollection("deadconn_test.items");

	// Insert documents to ensure at least one pooled connection exists
	foreach (i; 0 .. 5)
	{
		auto objID = BsonObjectID.generate;
		coll.insertOne(Bson(["_id": Bson(objID), "idx": Bson(i)]));
	}

	logInfo("Phase 1 passed: 5 inserts completed");

	// Signal that we're ready for the server to be killed
	import std.stdio : File;
	auto f = File("ready", "w");
	f.write("ready");
	f.close();

	logInfo("Phase 2: Waiting for server restart...");

	// Wait for the "restarted" signal file
	foreach (_; 0 .. 60)
	{
		try
		{
			auto rf = File("restarted", "r");
			rf.close();
			break;
		}
		catch (Exception)
		{
			sleepUninterruptible(500.msecs);
		}
	}

	logInfo("Phase 3: Attempting operations after server restart");

	// The pool has connections to the old server. They should be evicted.
	bool success = false;
	try
	{
		auto objID = BsonObjectID.generate;
		coll.insertOne(Bson(["_id": Bson(objID), "value": Bson("after-restart")]));

		auto doc = coll.findOne(["_id": objID]);
		enforce(!doc.isNull, "Inserted document not found after restart");
		enforce(doc["value"].get!string == "after-restart", "Document content mismatch");

		success = true;
	}
	catch (Exception e)
	{
		logError("Post-restart operation failed: %s", e.msg);
	}

	// Cleanup
	try { coll.drop(); } catch (Exception) {}

	if (success)
	{
		logInfo("All dead-connection eviction tests passed");
		return 0;
	}

	logError("Dead connection test failed");
	return 1;
}
