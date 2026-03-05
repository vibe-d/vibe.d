import vibe.db.mongo.mongo;
import vibe.db.mongo.client;
import vibe.db.mongo.settings;
import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import core.time;
import std.algorithm;
import std.conv;
import std.exception;

int main(string[] args)
{
	bool expectFail;
	string replicaSet;
	MongoHost[] hosts;

	setLogLevel(LogLevel.diagnostic);

	if (args.length < 2)
	{
		logError("Usage: %s <port1,port2,...> [--replicaSet <name>] [--expectFail]", args[0]);
		return 1;
	}

	runTask({ sleepUninterruptible(30.seconds); assert(false, "Timeout exceeded"); });

	foreach (portStr; args[1].splitter(','))
	{
		hosts ~= MongoHost("127.0.0.1", portStr.to!ushort);
	}

	foreach (i, arg; args[2 .. $])
	{
		if (arg == "--replicaSet" && i + 1 < args[2 .. $].length)
			replicaSet = args[2 .. $][i + 1];
		else if (arg == "--expectFail")
			expectFail = true;
	}

	auto settings = new MongoClientSettings;
	settings.hosts = hosts;
	settings.replicaSet = replicaSet;
	settings.connectTimeoutMS = 5_000;
	settings.socketTimeoutMS = 5_000;
	settings.appName = "VibeReplicaSetTest";

	MongoClient client;

	try
	{
		logInfo("Connecting to %(%s, %) replicaSet=%s", hosts.map!(h => h.name ~ ":" ~ h.port.to!string), replicaSet);
		client = connectMongoDB(settings);
	}
	catch (Exception e)
	{
		if (expectFail)
		{
			logInfo("Got expected connection failure: %s", e.msg);
			return 0;
		}
		throw e;
	}

	if (expectFail)
	{
		logError("Expected connection failure, but connection succeeded");
		return 1;
	}

	assert(client !is null);

	logInfo("Connection established, running CRUD smoke test");

	auto coll = client.getCollection("rstest.smoke");
	auto objID = BsonObjectID.generate;

	coll.insertOne(Bson(["_id": Bson(objID), "hello": Bson("replicaset")]));

	auto doc = coll.findOne(["_id": objID]);
	assert(!doc.isNull, "Inserted document not found");
	assert(doc["hello"].get!string == "replicaset", "Document content mismatch");

	coll.drop();

	logInfo("All replica set tests passed");
	return 0;
}
