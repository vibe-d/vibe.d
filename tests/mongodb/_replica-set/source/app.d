import vibe.db.mongo.mongo;
import vibe.db.mongo.client;
import vibe.db.mongo.settings;
import vibe.core.core;
import vibe.core.log;
import vibe.data.bson;
import core.time;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;

int main(string[] args)
{
	bool expectFail;
	bool expectSecondary;
	bool expectWriteToPrimary;
	bool expectReadFromSecondary;
	string replicaSet;
	string readPrefStr;
	MongoHost[] hosts;

	setLogLevel(LogLevel.diagnostic);

	if (args.length < 2)
	{
		logError("Usage: %s <port1,port2,...> [--replicaSet <name>] [--readPreference <pref>] [--expectFail] [--expectSecondary] [--expectWriteToPrimary] [--expectReadFromSecondary]", args[0]);
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
		else if (arg == "--readPreference" && i + 1 < args[2 .. $].length)
			readPrefStr = args[2 .. $][i + 1];
		else if (arg == "--expectFail")
			expectFail = true;
		else if (arg == "--expectSecondary")
			expectSecondary = true;
		else if (arg == "--expectWriteToPrimary")
			expectWriteToPrimary = true;
		else if (arg == "--expectReadFromSecondary")
			expectReadFromSecondary = true;
	}

	auto settings = new MongoClientSettings;
	settings.hosts = hosts;
	settings.replicaSet = replicaSet;
	settings.connectTimeoutMS = 5_000;
	settings.socketTimeoutMS = 5_000;
	settings.appName = "VibeReplicaSetTest";

	if (readPrefStr.length)
	{
		switch (readPrefStr)
		{
			case "primary": settings.readPreference = ReadPreference.primary; break;
			case "primaryPreferred": settings.readPreference = ReadPreference.primaryPreferred; break;
			case "secondary": settings.readPreference = ReadPreference.secondary; break;
			case "secondaryPreferred": settings.readPreference = ReadPreference.secondaryPreferred; break;
			case "nearest": settings.readPreference = ReadPreference.nearest; break;
			default: logError("Unknown readPreference: %s", readPrefStr); return 1;
		}
	}

	MongoClient client;

	try
	{
		logInfo("Connecting to %(%s, %) replicaSet=%s readPreference=%s",
			hosts.map!(h => h.name ~ ":" ~ h.port.to!string), replicaSet, readPrefStr);
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

	if (expectSecondary)
	{
		auto status = client.getDatabase("admin").runCommand(Bson(["hello": Bson(1)]));
		auto isSecondary = status["secondary"].get!bool;
		auto me = status["me"].get!string;
		logInfo("Connected to %s (secondary=%s)", me, isSecondary);
		enforce(isSecondary, "Expected to be connected to a secondary, but connected to: " ~ me);
		logInfo("Correctly connected to secondary %s", me);
		return 0;
	}

	if (expectWriteToPrimary)
	{
		// The client is configured with readPreference=secondary, so reads land on a
		// secondary. Each write below must still be routed to the primary; before the
		// fix they were sent to the read-preference target and rejected by the server
		// with NotWritablePrimary. Success here is the regression guard for #2847.
		auto coll = client.getCollection("rstest.writeprimary");
		auto objID = BsonObjectID.generate;

		coll.insertOne(Bson(["_id": Bson(objID), "n": Bson(1)]));
		coll.updateOne(["_id": objID], Bson(["$set": Bson(["n": Bson(2)])]));

		// Confirm the writes reached the primary by reading from it directly. The
		// primary is read-your-write consistent, so there is no replication lag to
		// wait on.
		auto verifier = connectMongoDB(primarySettings(hosts, replicaSet));
		auto onPrimary = verifier.getCollection("rstest.writeprimary");

		auto stored = onPrimary.findOne(["_id": objID]);
		enforce(!stored.isNull, "Insert was not routed to the primary");
		enforce(stored["n"].get!int == 2, "Update was not routed to the primary");

		coll.deleteOne(["_id": objID]);
		enforce(onPrimary.findOne(["_id": objID]).isNull, "Delete was not routed to the primary");

		coll.drop();
		logInfo("Writes correctly routed to primary under readPreference=secondary");
		return 0;
	}

	if (expectReadFromSecondary)
	{
		// The client default is primary. A per-query readPreference=secondary must both
		// route the read to a secondary AND inject $readPreference so the secondary
		// actually serves it. Before the fix the secondary rejects the read
		// (NotPrimaryNoSecondaryOk) or the override is ignored and the read silently runs
		// on the primary. This is the regression guard for #2848.
		auto coll = client.getCollection("rstest.readsecondary");
		try coll.drop(); catch (Exception) {}

		enum int total = 500;
		Bson[] docs;
		foreach (i; 0 .. total)
			docs ~= Bson(["_id": Bson(i), "v": Bson(i)]);

		InsertManyOptions writeOpts;
		WriteConcern majority;
		majority.w = Bson("majority");
		writeOpts.writeConcern = majority;
		coll.insertMany(docs, writeOpts);

		// 1) per-query override routes a command to a secondary (server selection)
		auto hello = client.getDatabase("admin").runCommand(Bson(["hello": Bson(1)]), ReadPreference.secondary);
		enforce(hello["secondary"].get!bool,
			"runCommand with readPreference=secondary did not reach a secondary: " ~ hello["me"].opt!string);

		// 2) a real multi-batch find is served by a secondary, proving $readPreference is
		//    injected on the find and that getMore stays pinned to the same secondary
		FindOptions findOpts;
		findOpts.readPreference = ReadPreference.secondary;
		findOpts.batchSize = 100;
		auto received = coll.find(Bson.emptyObject, findOpts).array;
		enforce(received.length == total,
			"expected " ~ total.to!string ~ " docs from secondary, got " ~ received.length.to!string);

		coll.drop();
		logInfo("Per-query readPreference=secondary served %s docs from a secondary", total);
		return 0;
	}

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

MongoClientSettings primarySettings(MongoHost[] hosts, string replicaSet)
{
	auto settings = new MongoClientSettings;
	settings.hosts = hosts;
	settings.replicaSet = replicaSet;
	settings.connectTimeoutMS = 5_000;
	settings.socketTimeoutMS = 5_000;
	settings.appName = "VibeReplicaSetWriteVerifier";
	settings.readPreference = ReadPreference.primary;

	return settings;
}
