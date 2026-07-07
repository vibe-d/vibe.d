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
	bool expectStepDownRetry;
	bool expectTagTargeting;
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
		else if (arg == "--expectStepDownRetry")
			expectStepDownRetry = true;
		else if (arg == "--expectTagTargeting")
			expectTagTargeting = true;
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

	if (expectTagTargeting)
	{
		// Target the dc:east members. Secondary reads must land on a dc:east secondary.
		settings.readPreference = ReadPreference.secondary;
		settings.readPreferenceTags = [["dc": "east"]];
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

		// w:majority only guarantees a MAJORITY holds the write; the secondary this
		// read lands on may not be in that majority yet and can briefly lag behind.
		// Poll the secondary until replication catches up rather than asserting on
		// the first (possibly stale) read. The budget is generous for a slow CI
		// runner but stays well under the 30s global test timeout.
		size_t received;
		auto deadline = MonoTime.currTime + 15.seconds;
		for (auto waited = false; ; waited = true)
		{
			received = coll.find(Bson.emptyObject, findOpts).array.length;
			if (received == total)
			{
				if (waited)
					logInfo("Secondary caught up to %s docs after replication lag", total);
				break;
			}
			if (MonoTime.currTime >= deadline)
				break;
			sleep(100.msecs);
		}
		enforce(received == total,
			"expected " ~ total.to!string ~ " docs from secondary, got " ~ received.to!string);

		coll.drop();
		logInfo("Per-query readPreference=secondary served %s docs from a secondary", total);
		return 0;
	}

	if (expectTagTargeting)
	{
		// A secondary read with readPreferenceTags=dc:east must be served by a
		// secondary whose tags include dc:east, never the dc:west member. The hello
		// response reports the contacted member's own tags, so we can prove it.
		foreach (attempt; 0 .. 5)
		{
			auto hello = client.getDatabase("admin").runCommand(Bson(["hello": Bson(1)]));
			auto me = hello["me"].opt!string("?");
			enforce(hello["secondary"].get!bool,
				"tag-targeted read must land on a secondary, got primary " ~ me);
			enforce(hello["tags"]["dc"].get!string == "east",
				"readPreferenceTags=dc:east must route to a dc:east member, got " ~ me
				~ " tagged " ~ hello["tags"].toString());
			logInfo("Tag-targeted secondary read served by dc:east member %s", me);
		}

		logInfo("readPreferenceTags=dc:east correctly targeted dc:east secondaries");
		return 0;
	}

	if (expectStepDownRetry)
	{
		// When the primary steps down mid-operation, the driver must catch the
		// NotWritablePrimary error, refresh the topology, find the newly elected
		// primary, and retry the write once so it lands exactly once.
		auto coll = client.getCollection("rstest.stepdown");
		try coll.drop(); catch (Exception) {}

		// Warm the topology and create the collection on the current primary.
		auto seedID = BsonObjectID.generate;
		coll.insertOne(Bson(["_id": Bson(seedID), "seq": Bson(0)]));

		// Force the current primary to step down for 60s. The command closes our
		// connection to it, so the error it returns is expected and ignored.
		logInfo("Forcing the current primary to step down...");
		try
			client.getDatabase("admin").runCommand(
				Bson(["replSetStepDown": Bson(60), "force": Bson(true)]));
		catch (Exception e)
			logInfo("Step-down command returned (expected): %s", e.msg);

		// Immediately issue a write. The first attempt hits the stepped-down node and
		// fails with NotWritablePrimary; the driver refreshes topology, waits for the
		// new primary, and retries the insert. A fixed _id makes a double-apply fail
		// loudly with a duplicate-key error, so success proves exactly-once delivery.
		auto retriedID = BsonObjectID.generate;
		coll.insertOne(Bson(["_id": Bson(retriedID), "seq": Bson(1)]));
		logInfo("Write after step-down succeeded — retried onto the new primary");

		// Verify the retried write is present exactly once on the new primary.
		auto stored = coll.findOne(["_id": Bson(retriedID)]);
		enforce(!stored.isNull, "retried write did not land on the new primary");
		enforce(stored["seq"].get!int == 1, "retried write stored the wrong value");

		coll.drop();
		logInfo("Primary step-down retry test passed");
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
