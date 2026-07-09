/// Requires a mongo service running on localhost; port via args[1].
/// Verifies multi-document transactions end-to-end, adapting to the deployment:
///   * Against a REPLICA SET (or sharded cluster) it runs real transactions: an
///     insert performed inside a transaction via an explicit session is durably
///     persisted on commit and rolled back on abort, observed by a plain
///     non-session read.
///   * Against a STANDALONE server (the default CI harness) transactions are not
///     supported, so it confirms the driver transmits the transaction context by
///     forcing the server to reject a transactional write with its
///     "Transaction numbers are only allowed on a replica set member or mongos"
///     error — proving the command reached the server carrying lsid/txnNumber.

module app;

import vibe.data.bson;
import vibe.db.mongo.mongo;
import vibe.db.mongo.collection : InsertOneOptions, InsertManyOptions, UpdateOptions, DeleteOptions, FindOptions;
import vibe.db.mongo.connection : MongoException;

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

	if (isTransactionCapable(client))
		runReplicaSetTest(client);
	else
		runStandaloneTest(client);
}

/// Transactions need a replica set member or a mongos; a hello reply advertises
/// `setName` for a replica set and `msg == "isdbgrid"` for a sharded cluster.
bool isTransactionCapable(MongoClient client)
{
	auto hello = client.getDatabase("admin").runCommandChecked(Bson(["hello": Bson(1)]));
	return hello["setName"].type != Bson.Type.null_
		|| hello["msg"].opt!string == "isdbgrid";
}

/// A committed transactional insert is durable; an aborted one is rolled back.
void runReplicaSetTest(MongoClient client)
{
	auto coll = client.getDatabase("txn_it")["commit_persists"];
	coll.drop(); // MongoCollection.drop tolerates NamespaceNotFound (code 26)

	auto session = client.startSession();
	session.startTransaction();
	coll.insertOne(Bson(["_id": Bson("c1"), "v": Bson("committed")]), InsertOneOptions.init, &session);
	session.commitTransaction();
	session.endSession();

	auto found = coll.findOne(Bson(["_id": Bson("c1")]));
	assert(found.type != Bson.Type.null_, "a committed transactional insert is visible after commit");
	assert(found["v"].get!string == "committed", "the committed document carries the written value");

	auto acoll = client.getDatabase("txn_it")["abort_rolls_back"];
	acoll.drop();
	auto asession = client.startSession();
	asession.startTransaction();
	acoll.insertOne(Bson(["_id": Bson("a1"), "v": Bson("rolled-back")]), InsertOneOptions.init, &asession);
	asession.abortTransaction();
	asession.endSession();

	auto gone = acoll.findOne(Bson(["_id": Bson("a1")]));
	assert(gone.type == Bson.Type.null_, "an aborted transactional insert is NOT visible after abort");

	runWriteOpsTest(client);
	runFindAndModifyTest(client);
	runReadYourWritesTest(client);
	runMultiBatchReadTest(client);
	runPartialReadAbortTest(client);
}

/// A multi-batch transaction cursor read only partway, then aborted, must clean
/// up safely: the cursor destructor's killCursors may hit the server after the
/// transaction already killed the cursor, but no uncaught exception may escape
/// and the client/connection must stay usable for later operations.
void runPartialReadAbortTest(MongoClient client)
{
	auto coll = client.getDatabase("txn_it")["partial_read"];
	coll.drop();
	foreach (i; 0 .. 6)
		coll.insertOne(Bson(["_id": Bson(i)]));

	auto session = client.startSession();
	session.startTransaction();
	{
		FindOptions fo;
		fo.batchSize = 2; // multi-batch: leaves the cursor alive after a partial read
		int seen;
		foreach (doc; coll.find(Bson.emptyObject, fo, &session))
		{
			seen++;
			if (seen == 1)
				break; // stop after the FIRST doc: cursor still alive server-side, inside the txn
		}
		// the cursor temporary is destroyed here (end of scope) -> its destructor runs killCursors
	}
	session.abortTransaction();
	session.endSession();

	// the client must still be fully usable after the partial-read + abort cleanup
	auto fresh = client.startSession();
	fresh.startTransaction();
	coll.insertOne(Bson(["_id": Bson("after")]), InsertOneOptions.init, &fresh);
	fresh.commitTransaction();
	fresh.endSession();
	assert(coll.findOne(Bson(["_id": Bson("after")])).type != Bson.Type.null_,
		"the client works normally after a partial-read transaction cursor was aborted");
}

/// A find inside a transaction whose result spans multiple batches must return
/// every matching document — the getMore continuations have to carry the session.
void runMultiBatchReadTest(MongoClient client)
{
	auto coll = client.getDatabase("txn_it")["multi_batch"];
	coll.drop();
	// seed 5 docs OUTSIDE any transaction (committed) so the in-txn read must page through them
	foreach (i; 0 .. 5)
		coll.insertOne(Bson(["_id": Bson(i), "v": Bson(i)]));

	auto session = client.startSession();
	session.startTransaction();
	FindOptions fo;
	fo.batchSize = 2; // forces getMore continuations (batches of 2 over 5 docs)
	int count;
	foreach (doc; coll.find(Bson.emptyObject, fo, &session))
		count++;
	session.commitTransaction();
	session.endSession();

	assert(count == 5,
		"a multi-batch find inside a transaction returns all documents across getMore continuations");
}

/// A findOne performed inside a transaction (with the session) sees the
/// transaction's own uncommitted insert; after abort it is invisible again.
void runReadYourWritesTest(MongoClient client)
{
	auto coll = client.getDatabase("txn_it")["read_your_writes"];
	coll.drop();

	auto session = client.startSession();
	session.startTransaction();
	coll.insertOne(Bson(["_id": Bson("ryw"), "n": Bson(1)]), InsertOneOptions.init, &session);

	// read INSIDE the same transaction (passing the session) — must see the uncommitted insert
	auto seen = coll.findOne(Bson(["_id": Bson("ryw")]), FindOptions.init, &session);
	assert(seen.type != Bson.Type.null_,
		"a findOne inside the transaction sees the transaction's own uncommitted write");
	assert(seen["n"].get!int == 1, "the in-transaction read returns the written value");

	session.abortTransaction(); // roll back so nothing persists
	session.endSession();

	// a plain non-session read must NOT see it (it was rolled back)
	assert(coll.findOne(Bson(["_id": Bson("ryw")])).type == Bson.Type.null_,
		"the rolled-back read-your-writes document is not visible after abort");
}

/// An atomic read-modify-write via findAndModify participates in a transaction
/// and persists on commit.
void runFindAndModifyTest(MongoClient client)
{
	auto coll = client.getDatabase("txn_it")["find_and_modify"];
	coll.drop();
	coll.insertOne(Bson(["_id": Bson("fam"), "n": Bson(0)]));

	auto session = client.startSession();
	session.startTransaction();
	coll.findAndModify(Bson(["_id": Bson("fam")]), Bson(["$set": Bson(["n": Bson(5)])]), null, &session);
	session.commitTransaction();
	session.endSession();

	assert(coll.findOne(Bson(["_id": Bson("fam")]))["n"].get!int == 5,
		"findAndModify inside a transaction persists on commit");
}

/// Every mutating op (insertMany/updateOne/deleteOne) participates in one
/// transaction and its net effect is durable on commit.
void runWriteOpsTest(MongoClient client)
{
	auto coll = client.getDatabase("txn_it")["write_ops"];
	coll.drop();
	coll.insertOne(Bson(["_id": Bson("keep"), "n": Bson(0)]));
	coll.insertOne(Bson(["_id": Bson("doomed"), "n": Bson(0)]));

	auto session = client.startSession();
	session.startTransaction();
	coll.insertMany([Bson(["_id": Bson("m1")]), Bson(["_id": Bson("m2")])], InsertManyOptions.init, &session);
	coll.updateOne(Bson(["_id": Bson("keep")]), Bson(["$set": Bson(["n": Bson(1)])]), UpdateOptions.init, &session);
	coll.deleteOne(Bson(["_id": Bson("doomed")]), DeleteOptions.init, &session);
	session.commitTransaction();
	session.endSession();

	assert(coll.findOne(Bson(["_id": Bson("m1")])).type != Bson.Type.null_, "insertMany in a txn persists on commit");
	assert(coll.findOne(Bson(["_id": Bson("keep")]))["n"].get!int == 1, "updateOne in a txn persists on commit");
	assert(coll.findOne(Bson(["_id": Bson("doomed")])).type == Bson.Type.null_, "deleteOne in a txn persists on commit");
}

/// On a standalone the server rejects a transactional write, which proves the
/// driver transmitted the transaction context (lsid/txnNumber/startTransaction).
void runStandaloneTest(MongoClient client)
{
	auto coll = client.getDatabase("txn_it")["standalone_reject"];
	coll.drop();

	auto session = client.startSession();
	session.startTransaction();

	bool rejected;
	try
		coll.insertOne(Bson(["_id": Bson("s1")]), InsertOneOptions.init, &session);
	catch (MongoException e)
		rejected = canFind(e.msg, "Transaction numbers are only allowed");

	assert(rejected,
		"a standalone must reject a transactional insert, proving the transaction context reached the server");

	session.endSession();
}
