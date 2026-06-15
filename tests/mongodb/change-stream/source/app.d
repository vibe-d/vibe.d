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
import vibe.core.core : sleep;

import core.time : MonoTime, seconds, msecs;
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

	// MongoDB 3.6 rejects opening a $changeStream on a non-existent database (newer servers
	// tolerate a missing collection); create the collection explicitly before watching.
	client.getDatabase("test").runCommandChecked(Bson(["create": Bson("changestream")]));

	auto stream = coll.watch();

	// The change stream does not capture the aggregate's start point (postBatchResumeToken
	// is untracked — see L14(B)), so a priming read is required to anchor the watch point
	// before the write; otherwise the cursor effectively starts at the first getMore and
	// never observes an insert that happened before it.
	assert(stream.empty, "a freshly opened change stream has no buffered events yet");

	coll.insertOne(["greeting": "hello change streams"]);

	// A change stream is a non-blocking tailable cursor: `empty` is non-monotonic and
	// a getMore can return an empty batch before the event is visible. Poll until the
	// insert is observed, per the documented usage pattern, rather than checking once.
	auto deadline = MonoTime.currTime + 10.seconds;
	while (stream.empty) {
		assert(MonoTime.currTime < deadline,
			"the change stream must observe the inserted document within the deadline");
		sleep(100.msecs);
	}

	auto event = stream.front;
	assert(event["operationType"].get!string == "insert",
		"the observed change event must be an insert");

	// The resume token is cached from the consumed event, so it is only available
	// after popFront advances past it.
	stream.popFront();
	assert(!stream.resumeToken.isNull,
		"consuming an event must cache a resume token");

	coll.drop();
	logInfo("Replica-set change-stream test OK: insert observed with resume token %s.", stream.resumeToken.get);
}
