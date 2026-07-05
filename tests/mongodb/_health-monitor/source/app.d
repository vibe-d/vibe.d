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
	setLogLevel(LogLevel.diagnostic);

	if (args.length < 2)
	{
		logError("Usage: %s <port1,port2,...>", args[0]);
		return 1;
	}

	runTask({ sleepUninterruptible(120.seconds); assert(false, "Timeout exceeded"); });

	MongoHost[] hosts;
	foreach (portStr; args[1].splitter(','))
		hosts ~= MongoHost("127.0.0.1", portStr.to!ushort);

	auto settings = new MongoClientSettings;
	settings.hosts = hosts;
	settings.replicaSet = "rs0";
	settings.connectTimeoutMS = 5_000;
	settings.socketTimeoutMS = 5_000;
	settings.heartbeatFrequencyMS = 500;
	settings.minHeartbeatFrequencyMS = 50;
	settings.serverSelectionTimeoutMS = 20_000;
	settings.appName = "VibeHealthMonitorTest";

	auto client = connectMongoDB(settings);
	enforce(client.activeMonitorCount > 0, "no background monitors were started");

	auto coll = client.getCollection("healthtest.failover");
	try coll.drop(); catch (Exception) {}

	coll.insertOne(Bson(["_id": Bson(BsonObjectID.generate), "phase": Bson("before")]));
	logInfo("Initial write landed on the primary");

	stepDownPrimary(client);

	auto recovered = recoverByWriting(coll, 60.seconds);
	enforce(recovered, "the long-lived client never recovered writes after failover");

	auto count = coll.countDocuments(Bson.emptyObject);
	enforce(count == 2, "expected 2 documents after recovery, found " ~ count.to!string);
	logInfo("Same client recovered on the new primary without reconnecting");

	client.stopMonitoring();
	client.cleanupConnections();
	enforce(client.activeMonitorCount == 0, "monitors did not stop after stopMonitoring()");

	logInfo("Health monitor failover test passed");
	return 0;
}

/// Steps down the current primary on the same client; the command drops its connection.
void stepDownPrimary(MongoClient client)
{
	logInfo("Forcing a failover via replSetStepDown");

	// A command's name must be the first field; a Bson AA literal would reorder it.
	auto cmd = Bson.emptyObject;
	cmd["replSetStepDown"] = Bson(30);
	cmd["force"] = Bson(true);

	try
		client.getDatabase("admin").runCommandChecked(cmd);
	catch (Exception e)
		logInfo("replSetStepDown closed the connection as expected: %s", e.msg);
}

/// Retries a write until one lands on the new primary or the deadline passes.
bool recoverByWriting(MongoCollection coll, Duration budget)
{
	auto deadline = MonoTime.currTime + budget;

	while (MonoTime.currTime < deadline)
	{
		try
		{
			coll.insertOne(Bson(["_id": Bson(BsonObjectID.generate), "phase": Bson("after")]));
			return true;
		}
		catch (Exception e)
		{
			logInfo("Write still failing during failover: %s", e.msg);
			sleep(250.msecs);
		}
	}

	return false;
}
