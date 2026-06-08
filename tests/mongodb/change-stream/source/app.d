/// Requires a mongo service running on localhost; port via args[1].
/// Verifies MongoDB change stream (watch) support end-to-end.
///
/// Change streams are only available on replica sets and sharded clusters, so
/// the test adapts to the deployment it is pointed at:
///   * Against a STANDALONE server (the default CI harness) it confirms the
///     driver builds and transmits a valid `$changeStream` aggregation: the
///     server must reject it with the topology error ("only supported on replica
///     sets"), proving the command reached the server well-formed rather than
///     failing to parse. Collection-, database- and client-level watch() are all
///     exercised, with and without options/a user pipeline.
///   * Against a REPLICA SET it confirms watch() opens and a real insert is
///     observed as an `insert` change event carrying a resume token.

module app;

import vibe.data.bson;
import vibe.db.mongo.mongo;
import vibe.db.mongo.impl.changestream : ChangeStreamOptions, ChangeStreamFullDocument;

import vibe.core.log;

import std.algorithm : canFind;
import std.conv : to;

int main(string[] args)
{
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
	runTest(port);
	return 0;
}

void runTest(ushort port)
{
	auto client = connectMongoDB("127.0.0.1", port);

	if (isChangeStreamCapable(client))
		runReplicaSetTest(client);
	else
		runStandaloneTest(client);
}

/// Change streams need a replica set member or a mongos; a hello reply advertises
/// `setName` for a replica set and `msg == "isdbgrid"` for a sharded cluster.
bool isChangeStreamCapable(MongoClient client)
{
	auto hello = client.getDatabase("admin").runCommandChecked(Bson(["hello": Bson(1)]));
	return hello["setName"].type != Bson.Type.null_
		|| hello["msg"].opt!string == "isdbgrid";
}

/// On a standalone the server rejects any `$changeStream` aggregation. Opening a
/// watch and forcing the round-trip must raise that specific topology error,
/// which proves the driver transmitted a well-formed change-stream command.
void runStandaloneTest(MongoClient client)
{
	auto coll = client.getCollection("test.changestream");

	assertChangeStreamUnsupported({ cast(void) coll.watch().empty; },
		"collection-level watch");

	ChangeStreamOptions options;
	options.fullDocument = ChangeStreamFullDocument.updateLookup;
	auto userPipeline = [Bson(["$match": Bson(["operationType": Bson("insert")])])];
	assertChangeStreamUnsupported({ cast(void) coll.watch(userPipeline, options).empty; },
		"collection-level watch with options and a user pipeline");

	assertChangeStreamUnsupported({ cast(void) client.getDatabase("test").watch().empty; },
		"database-level watch");

	assertChangeStreamUnsupported({ cast(void) client.watch().empty; },
		"client-level (deployment) watch");

	logInfo("Standalone change-stream test OK: the server rejected every watch() with the replica-set topology error.");
}

/// Runs `body` and asserts it threw the change-stream topology error rather than
/// a malformed-command error (which would indicate the driver built it wrong).
void assertChangeStreamUnsupported(scope void delegate() body, string what)
{
	bool threw = false;
	string message;
	try
		body();
	catch (Exception e) {
		threw = true;
		message = e.msg;
	}

	assert(threw, what ~ " on a standalone must be rejected by the server");
	assert(message.canFind("replica") || message.canFind("changeStream") || message.canFind("$changeStream"),
		what ~ " must fail with the change-stream topology error, got: " ~ message);
}

/// On a replica set, a watch observes a subsequent insert as an `insert` event
/// carrying a resume token.
void runReplicaSetTest(MongoClient client)
{
	auto coll = client.getCollection("test.changestream");
	coll.drop();

	auto stream = coll.watch();
	coll.insertOne(["greeting": "hello change streams"]);

	assert(!stream.empty, "the change stream must observe the inserted document");
	auto event = stream.front;
	assert(event["operationType"].get!string == "insert",
		"the observed change event must be an insert");
	assert(!stream.resumeToken.isNull,
		"consuming an event must cache a resume token");

	stream.popFront();
	coll.drop();
	logInfo("Replica-set change-stream test OK: insert observed with resume token %s.", stream.resumeToken.get);
}
