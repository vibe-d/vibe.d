/**
	Multi-document transaction state machine for logical sessions.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.transaction;

import std.exception : enforce;
import std.typecons : Nullable;
import vibe.data.bson;
import vibe.db.mongo.settings : MongoHost;

@safe:

/// The lifecycle state of a multi-document transaction on a session.
enum TransactionState { none, starting, inProgress, committed, aborted }

/// Tracks the lifecycle of a multi-document transaction.
struct Transaction
{
	private TransactionState m_state;
	private Nullable!MongoHost m_pinnedServer;

	/// The current transaction lifecycle state.
	TransactionState state() @safe const { return m_state; }

	/// The server this transaction is pinned to, if any.
	Nullable!MongoHost pinnedServer() @safe const { return m_pinnedServer; }

	/// Pins the transaction to the server its operations run on.
	void pinServer(MongoHost host) @safe { m_pinnedServer = host; }

	/// Whether a transaction is currently active (started or in progress).
	bool isActive() @safe const
	{
		return m_state == TransactionState.starting || m_state == TransactionState.inProgress;
	}

	/// Begins a transaction, moving it into the starting state.
	void start() @safe
	{
		enforce(!isActive, "a transaction is already in progress");
		m_state = TransactionState.starting;
	}

	/// Ends an active transaction successfully.
	void commit() @safe { finish(TransactionState.committed, "commit"); }

	/// Ends an active transaction by rolling it back.
	void abort() @safe { finish(TransactionState.aborted, "abort"); }

	/// Marks the transaction in progress once its first command has been dispatched.
	void markInProgress() @safe { m_state = TransactionState.inProgress; }

	/// Releases an active transaction into a terminal state and unpins its server.
	private void finish(TransactionState terminal, string action) @safe
	{
		requireActive(action);
		m_state = terminal;
		m_pinnedServer.nullify();
	}

	private void requireActive(string action) @safe const
	{
		enforce(isActive, "no transaction is in progress to " ~ action);
	}
}

/// A fresh transaction has no active transaction.
unittest
{
	Transaction txn;
	assert(txn.state == TransactionState.none, "a fresh transaction has no active transaction");
}

/// start() begins a transaction in the starting state.
unittest
{
	Transaction txn;
	txn.start();
	assert(txn.state == TransactionState.starting, "start() begins a transaction in the starting state");
}

/// commit() ends an active transaction in the committed state.
unittest
{
	Transaction txn;
	txn.start();
	txn.commit();
	assert(txn.state == TransactionState.committed, "commit() ends an active transaction in the committed state");
}

/// abort() rolls back an active transaction to the aborted state.
unittest
{
	Transaction txn;
	txn.start();
	txn.abort();
	assert(txn.state == TransactionState.aborted, "abort() rolls back an active transaction to the aborted state");
}

/// start() throws when a transaction is already active.
unittest
{
	import std.exception : assertThrown;

	Transaction txn;
	txn.start();
	assertThrown(txn.start(), "starting a transaction while one is already active must throw");
}

/// commit() throws when no transaction is active.
unittest
{
	import std.exception : assertThrown;

	Transaction txn;
	assertThrown(txn.commit(), "committing with no active transaction must throw");
}

/// abort() throws when no transaction is active.
unittest
{
	import std.exception : assertThrown;

	Transaction txn;
	assertThrown(txn.abort(), "aborting with no active transaction must throw");
}

/// markInProgress() moves a started transaction into the inProgress state.
unittest
{
	Transaction txn;
	txn.start();
	txn.markInProgress();
	assert(txn.state == TransactionState.inProgress, "the first command marks the transaction in progress");
}

/// pinServer() records the server a transaction runs on.
unittest
{
	import vibe.db.mongo.settings : MongoHost;

	Transaction txn;
	assert(txn.pinnedServer.isNull, "a fresh transaction has no pinned server");
	txn.pinServer(MongoHost("rs0-a", 27017));
	assert(!txn.pinnedServer.isNull && txn.pinnedServer.get == MongoHost("rs0-a", 27017),
		"pinServer records the server the transaction runs on");
}

/// commit() releases the server pin so the session is no longer stuck on it.
unittest
{
	import vibe.db.mongo.settings : MongoHost;

	Transaction txn;
	txn.start();
	txn.pinServer(MongoHost("rs0-a", 27017));
	txn.commit();
	assert(txn.pinnedServer.isNull, "committing a transaction releases its server pin");
}

/// abort() releases the server pin so the session is no longer stuck on it.
unittest
{
	import vibe.db.mongo.settings : MongoHost;

	Transaction txn;
	txn.start();
	txn.pinServer(MongoHost("rs0-a", 27017));
	txn.abort();
	assert(txn.pinnedServer.isNull, "aborting a transaction releases its server pin");
}

/// Builds the `commitTransaction` admin command for the given transaction number.
Bson commitTransactionCommand(long txnNumber) @safe
{
	return transactionControlCommand("commitTransaction", txnNumber);
}

/// commitTransactionCommand() builds the commitTransaction admin command.
unittest
{
	import vibe.data.bson;

	auto cmd = commitTransactionCommand(7);
	assert(cmd["commitTransaction"].get!int == 1, "commit command names the operation");
	assert(cmd["txnNumber"].get!long == 7, "commit command carries the transaction number");
	assert(cmd["autocommit"].get!bool == false, "commit command sets autocommit false");
}

/// Builds the `abortTransaction` admin command for the given transaction number.
Bson abortTransactionCommand(long txnNumber) @safe
{
	return transactionControlCommand("abortTransaction", txnNumber);
}

/// abortTransactionCommand() builds the abortTransaction admin command.
unittest
{
	import vibe.data.bson;

	auto cmd = abortTransactionCommand(3);
	assert(cmd["abortTransaction"].get!int == 1, "abort command names the operation");
	assert(cmd["txnNumber"].get!long == 3, "abort command carries the transaction number");
	assert(cmd["autocommit"].get!bool == false, "abort command sets autocommit false");
}

/// Builds a transaction-control admin command (commit/abort) for the given number.
private Bson transactionControlCommand(string name, long txnNumber) @safe
{
	return Bson([
		name: Bson(1),
		"txnNumber": Bson(txnNumber),
		"autocommit": Bson(false),
	]);
}

/// Attaches transaction fields to a command. The first command of a transaction
/// also carries `startTransaction: true`.
Bson applyTransaction(Bson command, long txnNumber, bool firstCommand) @safe
{
	Bson result = command;
	result["txnNumber"] = Bson(txnNumber);
	result["autocommit"] = Bson(false);
	if (firstCommand)
		result["startTransaction"] = Bson(true);
	return result;
}

/// applyTransaction() decorates the first command with transaction fields.
unittest
{
	import vibe.data.bson;

	Bson cmd = Bson.emptyObject;
	cmd["insert"] = Bson("people");

	auto result = applyTransaction(cmd, 4, true);
	assert(result["insert"] == Bson("people"), "the original command is preserved");
	assert(result["txnNumber"].get!long == 4, "the transaction number is attached");
	assert(result["autocommit"].get!bool == false, "autocommit is false inside a transaction");
	assert(result["startTransaction"].get!bool == true, "the first command starts the transaction");
}

/// applyTransaction() omits startTransaction on subsequent commands.
unittest
{
	import vibe.data.bson;

	Bson cmd = Bson.emptyObject;
	cmd["update"] = Bson("people");

	auto result = applyTransaction(cmd, 4, false);
	assert(result["txnNumber"].get!long == 4, "the transaction number is attached");
	assert(result["autocommit"].get!bool == false, "autocommit is false inside a transaction");
	assert(result["startTransaction"].type == Bson.Type.null_,
		"only the first command carries startTransaction");
}

/// MongoDB error label marking a transaction safe to retry from the start.
enum transientTransactionErrorLabel = "TransientTransactionError";

/// MongoDB error label marking a commit whose outcome is unknown and may be retried.
enum unknownCommitResultLabel = "UnknownTransactionCommitResult";

/// Runs `body` inside a transaction and commits it, returning the body's result.
/// Retries the whole transaction on a transient body failure, and retries the
/// commit on an unknown commit result, until either succeeds or `expired` is true.
T withTransactionRetry(T)(
	scope T delegate() @safe body,
	scope void delegate() @safe start,
	scope void delegate() @safe commit,
	scope void delegate() @safe abort,
	scope bool delegate() @safe expired)
{
	import vibe.db.mongo.connection : MongoException;

	outer: while (true)
	{
		start();
		T result;
		try
			result = body();
		catch (MongoException e)
		{
			abort();
			if (e.hasErrorLabel(transientTransactionErrorLabel) && !expired())
				continue;
			throw e;
		}

		while (true)
		{
			try
			{
				commit();
				return result;
			}
			catch (MongoException e)
			{
				if (e.hasErrorLabel(unknownCommitResultLabel) && !expired())
					continue;
				if (e.hasErrorLabel(transientTransactionErrorLabel) && !expired())
					continue outer;
				throw e;
			}
		}
	}

	assert(0);
}

/// withTransactionRetry() runs the body once and commits when nothing throws.
unittest
{
	int starts;
	int commits;
	int aborts;

	auto result = withTransactionRetry!int(
		() @safe => 42,
		() @safe { starts++; },
		() @safe { commits++; },
		() @safe { aborts++; },
		() @safe => false);

	assert(result == 42, "the body's return value is propagated");
	assert(starts == 1, "the transaction is started exactly once");
	assert(commits == 1, "the transaction is committed exactly once");
	assert(aborts == 0, "a successful transaction is never aborted");
}

/// withTransactionRetry() retries the whole transaction when the body throws TransientTransactionError.
unittest
{
	import vibe.db.mongo.connection : MongoException;

	int starts;
	int commits;
	int aborts;
	int bodyCalls;

	auto result = withTransactionRetry!int(
		() @safe {
			bodyCalls++;
			if (bodyCalls == 1)
			{
				auto e = new MongoException("transient");
				e.errorLabels = ["TransientTransactionError"];
				throw e;
			}
			return 7;
		},
		() @safe { starts++; },
		() @safe { commits++; },
		() @safe { aborts++; },
		() @safe => false);

	assert(result == 7, "the retried body's return value is propagated");
	assert(starts == 2, "a transient failure restarts the whole transaction");
	assert(bodyCalls == 2, "the body runs again after a transient failure");
	assert(aborts == 1, "the failed attempt is aborted before retrying");
	assert(commits == 1, "the successful retry is committed exactly once");
}

/// withTransactionRetry() stops retrying and rethrows once the deadline has expired.
unittest
{
	import vibe.db.mongo.connection : MongoException;
	import std.exception : assertThrown;

	int starts;
	int commits;
	int aborts;
	int bodyCalls;

	assertThrown!MongoException(withTransactionRetry!int(
		delegate int() @safe {
			bodyCalls++;
			if (bodyCalls > 5)
				throw new Exception("retry-cap exceeded");
			auto e = new MongoException("transient");
			e.errorLabels = ["TransientTransactionError"];
			throw e;
		},
		() @safe { starts++; },
		() @safe { commits++; },
		() @safe { aborts++; },
		() @safe => true));

	assert(bodyCalls == 1, "the expired deadline stops the body running a second time");
	assert(starts == 1, "the expired deadline stops the transaction restarting");
	assert(aborts == 1, "the expired attempt is still aborted before rethrowing");
	assert(commits == 0, "an expired transaction is never committed");
}

/// withTransactionRetry() retries the commit on UnknownTransactionCommitResult without re-running the body.
unittest
{
	import vibe.db.mongo.connection : MongoException;

	int starts;
	int commits;
	int aborts;
	int bodyCalls;

	auto result = withTransactionRetry!int(
		() @safe { bodyCalls++; return 9; },
		() @safe { starts++; },
		() @safe {
			commits++;
			if (commits == 1)
			{
				auto e = new MongoException("commit result unknown");
				e.errorLabels = ["UnknownTransactionCommitResult"];
				throw e;
			}
		},
		() @safe { aborts++; },
		() @safe => false);

	assert(result == 9, "the body's return value is propagated after the commit retry");
	assert(starts == 1, "an unknown commit result does not restart the transaction");
	assert(bodyCalls == 1, "an unknown commit result does not re-run the body");
	assert(commits == 2, "the commit is retried after an unknown result");
	assert(aborts == 0, "retrying the commit never aborts");
}

/// withTransactionRetry() restarts the whole transaction when the commit throws TransientTransactionError.
unittest
{
	import vibe.db.mongo.connection : MongoException;

	int starts;
	int commits;
	int aborts;
	int bodyCalls;

	auto result = withTransactionRetry!int(
		() @safe { bodyCalls++; return 5; },
		() @safe { starts++; },
		() @safe {
			commits++;
			if (commits == 1)
			{
				auto e = new MongoException("transient commit");
				e.errorLabels = [transientTransactionErrorLabel];
				throw e;
			}
		},
		() @safe { aborts++; },
		() @safe => false);

	assert(result == 5, "the restarted transaction's body return value is propagated");
	assert(starts == 2, "a transient commit failure restarts the whole transaction");
	assert(bodyCalls == 2, "a transient commit failure re-runs the body");
	assert(commits == 2, "the commit runs again after the restart");
	assert(aborts == 0, "the transient commit path does not abort");
}
