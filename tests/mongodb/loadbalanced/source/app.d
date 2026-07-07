/// Exercises the driver's loadBalanced mode.
/// The no-serviceId rejection (negative path) runs against any mongod: a server
/// not behind a load balancer returns no serviceId for a loadBalanced hello, so
/// the handshake must throw. The full cursor-pinning path needs a real sharded
/// cluster behind a load balancer (set MONGODB_LB_URI) and is skipped otherwise.

module app;

import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.conv : to;
import std.algorithm : canFind;
import std.process : environment;

void runTest(ushort port)
{
	// (A) Negative path where loadBalanced=true against a non-LB server must be rejected.
	bool rejected = false;
	try
	{
		// constructing the client performs the handshake; with loadBalanced=true against a
		// non-LB server (no serviceId) it must throw.
		auto client = connectMongoDB("mongodb://127.0.0.1:" ~ port.to!string ~ "/?loadBalanced=true");
		// belt-and-suspenders in case the handshake is lazy: force a command.
		client.getDatabase("admin").runCommandChecked(Bson(["ping": Bson(1)]));
	}
	catch (Exception e)
	{
		rejected = true;
		assert(e.msg.canFind("serviceId") || e.msg.canFind("load balancer"),
			"expected a serviceId / load-balancer error, got: " ~ e.msg);
		logInfo("loadBalanced=true against a non-LB server rejected as required: %s", e.msg);
	}
	assert(rejected, "loadBalanced=true against a non-load-balanced server must be rejected");

	// (B) Full load-balanced path, env-gated, needs a real LB cluster.
	auto lbUri = environment.get("MONGODB_LB_URI", "");
	if (lbUri.length)
	{
		auto client = connectMongoDB(lbUri);   // a mongodb:// URI with loadBalanced=true to a real LB endpoint
		scope (exit) client.cleanupConnections();
		auto coll = client.getCollection("test.lb_demo");
		try coll.drop; catch (Exception) {}
		// seed enough docs to span multiple cursor batches
		foreach (i; 0 .. 50)
			coll.insertOne(Bson(["_id": Bson(i), "v": Bson(i)]));
		// a small-batch find forces getMore round-trips; in LB mode the cursor is pinned to
		// the same backend connection via its serviceId, so this must iterate all 50 docs.
		FindOptions options;
		options.batchSize = 10;
		int seen = 0;
		foreach (doc; coll.find(Bson.emptyObject, options))
			seen++;
		assert(seen == 50, "load-balanced cursor did not return all docs, got: " ~ seen.to!string);
		try coll.drop; catch (Exception) {}
		logInfo("load-balanced cursor pinning OK: iterated %s docs across getMore through the LB", seen);
	}
	else
		logInfo("MONGODB_LB_URI not set: skipping the cursor-pinning path (needs a real sharded cluster behind a load balancer)");

	logInfo("load-balancer harness passed");
}

void main(string[] args)
{
	setLogLevel(LogLevel.info);
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
	runTest(port);
}
