/**
	Logical sessions: id generation, the server-session pool, and the
	client-session handle that drives multi-document transactions.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.serversession;

import vibe.data.bson;
import vibe.db.mongo.impl.transaction : Transaction, TransactionState, withTransactionRetry;
import core.time : MonoTime, Duration, minutes;

@safe:

/// MongoDB's default deadline for the whole transaction-with-retry loop (120 seconds).
enum defaultTransactionTimeout = 2.minutes;

/// Builds a fresh logical session id document `{ id: <UUID binary subtype 0x04, 16 bytes> }`.
Bson logicalSessionId()
{
	import std.uuid : randomUUID;
	auto bytes = randomUUID().data;
	return Bson(["id": Bson(BsonBinData(BsonBinData.Type.uuid, bytes.idup))]);
}

/// A fresh logical session id is `{ id: <UUID binary subtype 0x04, 16 bytes> }`.
unittest
{
	auto lsid = logicalSessionId();

	assert(lsid["id"].type == Bson.Type.binData,
		"the lsid id field must be binary data");
	assert(lsid["id"].get!BsonBinData.type == BsonBinData.Type.uuid,
		"the lsid id field must use UUID binary subtype 0x04");
	assert(lsid["id"].get!BsonBinData.rawData.length == 16,
		"the lsid UUID must be 16 bytes");
}

/// Each fresh logical session id is unique.
unittest
{
	auto a = logicalSessionId();
	auto b = logicalSessionId();

	auto ra = a["id"].get!BsonBinData.rawData;
	auto rb = b["id"].get!BsonBinData.rawData;

	assert(ra != rb, "each logical session id must be unique");
}

/// Builds the `endSessions` admin command that frees the given logical sessions on the server.
Bson endSessionsCommand(Bson[] lsids) @safe
{
	return Bson(["endSessions": Bson(lsids)]);
}

/// The endSessions command lists the given lsids under `endSessions`.
unittest
{
	auto a = logicalSessionId();
	auto b = logicalSessionId();

	auto cmd = endSessionsCommand([a, b]);

	assert(cmd["endSessions"] == Bson([a, b]),
		"endSessionsCommand must list the given lsids under endSessions");
}

/// The endSessions command for an empty list yields an empty array.
unittest
{
	auto cmd = endSessionsCommand([]);

	assert(cmd["endSessions"] == Bson(cast(Bson[])[]),
		"endSessionsCommand of an empty list is { endSessions: [] }");
}

/// Returns the command with the logical session id attached.
Bson applySession(Bson command, Bson lsid) @safe
{
	Bson result = command;
	result["lsid"] = lsid;
	return result;
}

/// Applying a session attaches the given lsid to the command.
unittest
{
	Bson cmd = Bson.emptyObject;
	cmd["find"] = Bson("people");
	auto lsid = logicalSessionId();

	auto result = applySession(cmd, lsid);

	assert(result["lsid"] == lsid,
		"applySession must attach the given lsid to the command");
	assert(result["find"] == Bson("people"),
		"applySession must preserve the original command");
	assert(cmd["lsid"].type == Bson.Type.null_,
		"applySession must not mutate the caller's command");
}

/// Tracks per-session state such as the monotonic transaction number.
struct ServerSession
{
	private long m_txnNumber;
	private Bson m_lsid;
	private MonoTime m_lastUse;

	/// Returns the next monotonic transaction number, starting at 1.
	// TODO(sessions): causal consistency builds on this session. Add an
	// operationTime/afterClusterTime accessor for causally-consistent reads.
	long nextTransactionNumber() @safe { return ++m_txnNumber; }

	/// Builds a session carrying its own fresh logical session id.
	static ServerSession create() @safe { ServerSession s; s.m_lsid = logicalSessionId(); return s; }

	/// The logical session id document for this session.
	Bson lsid() @safe const { return m_lsid; }

	/// Records the time the session was last used.
	void touch(MonoTime now) @safe { m_lastUse = now; }

	/// True when the session is within MongoDB's one-minute safety margin of `timeout`.
	bool isAboutToExpire(MonoTime now, Duration timeout) @safe const
	{
		// TODO(B-sess9): lift the 1.minutes safety margin to a named
		// `enum sessionSafetyMargin = 1.minutes;` so the magic constant has one home.
		return now - m_lastUse >= timeout - 1.minutes;
	}
}

/// touch records last-use so the session is fresh just after.
unittest
{
	import core.time : MonoTime, minutes;

	auto session = ServerSession.create();
	auto t0 = MonoTime.currTime;
	session.touch(t0);

	assert(!session.isAboutToExpire(t0 + 5.minutes, 30.minutes),
		"touch records last-use so the session is fresh");
}

/// The first transaction number on a fresh session is 1.
unittest
{
	ServerSession session;

	assert(session.nextTransactionNumber() == 1,
		"the first transaction number must be 1");
}

/// A session built via `create` carries its own logical session id.
unittest
{
	auto session = ServerSession.create();

	assert(session.lsid["id"].type == Bson.Type.binData,
		"server session carries a logical session id");
}

/// Hands out server sessions, reusing released ones.
struct ServerSessionPool
{
	private ServerSession[] m_available;
	// TODO(B-sess2): the 30-minute default is a guess. Wire the server-advertised
	// logicalSessionTimeoutMinutes (parsed in serverdescription.d) into this pool,
	// using the MIN across data-bearing servers, and refresh it on topology changes.
	private Duration m_timeout = 30.minutes;

	/// Returns a session ready for use, reusing a released one when available.
	ServerSession acquire(MonoTime now = MonoTime.currTime) @safe
	{
		while (m_available.length)
		{
			auto reused = m_available[$ - 1];
			m_available = m_available[0 .. $ - 1];
			if (!reused.isAboutToExpire(now, m_timeout))
				return reused;
		}

		return ServerSession.create();
	}

	/// Returns a session to the pool for later reuse.
	void release(ServerSession session, MonoTime now = MonoTime.currTime) @safe
	{
		import std.algorithm : filter;
		import std.array : array;

		// TODO(B-sess7): this reallocates the whole pool on every release. Prune in
		// place, or only when the pool length crosses a threshold, to amortize it.
		m_available = m_available.filter!(s => !s.isAboutToExpire(now, m_timeout)).array;
		session.touch(now);
		m_available ~= session;
	}

	/// Empties the pool, returning the lsids of every pooled session so they can
	/// be ended on the server (the `endSessions` command on client shutdown).
	Bson[] takeAllLsids() @safe
	{
		import std.algorithm : map;
		import std.array : array;

		auto lsids = m_available.map!(s => s.lsid).array;
		m_available = null;
		return lsids;
	}
}

/// A session acquired from the pool carries a valid logical session id.
unittest
{
	ServerSessionPool pool;
	auto session = pool.acquire();

	assert(session.lsid["id"].type == Bson.Type.binData,
		"an acquired session carries a logical session id");
	assert(session.lsid["id"].get!BsonBinData.rawData.length == 16,
		"the acquired session lsid UUID must be 16 bytes");
}

/// Acquiring after releasing returns the same session.
unittest
{
	ServerSessionPool pool;
	auto first = pool.acquire();
	pool.release(first);
	auto second = pool.acquire();

	assert(second.lsid == first.lsid,
		"a released session must be reused on the next acquire");
}

/// Two sessions held at once are distinct.
unittest
{
	ServerSessionPool pool;
	auto first = pool.acquire();
	auto second = pool.acquire();

	assert(second.lsid != first.lsid,
		"the pool must not hand the same live session to two callers");
}

/// A pooled session idle past the timeout is discarded on acquire.
unittest
{
	import core.time : MonoTime, minutes;

	ServerSessionPool pool;
	auto t0 = MonoTime.currTime;
	auto first = pool.acquire(t0);
	pool.release(first, t0);
	auto later = pool.acquire(t0 + 40.minutes);

	assert(later.lsid != first.lsid,
		"an expired pooled session is discarded; a fresh one is returned");
}

/// A pooled session re-acquired within the timeout is still reused.
unittest
{
	import core.time : MonoTime, minutes;

	ServerSessionPool pool;
	auto t0 = MonoTime.currTime;
	auto first = pool.acquire(t0);
	pool.release(first, t0);
	auto soon = pool.acquire(t0 + 5.minutes);

	assert(soon.lsid == first.lsid,
		"a session still within the timeout must be reused, not discarded");
}

/// Releasing a session prunes pooled sessions already expired at that time.
unittest
{
	import core.time : MonoTime, minutes;

	ServerSessionPool pool;
	auto t0 = MonoTime.currTime;
	auto a = pool.acquire();
	auto b = pool.acquire();
	auto c = pool.acquire();
	pool.release(a, t0);
	pool.release(b, t0);
	pool.release(c, t0 + 40.minutes);

	auto lsids = pool.takeAllLsids();

	assert(lsids.length == 1,
		"expired pooled sessions are pruned on release");
	assert(lsids[0] == c.lsid,
		"the freshly released session remains after pruning");
}

/// Releasing within the timeout keeps still-fresh pooled siblings.
unittest
{
	import core.time : MonoTime, minutes;

	ServerSessionPool pool;
	auto t0 = MonoTime.currTime;
	auto a = pool.acquire();
	auto b = pool.acquire();
	auto c = pool.acquire();
	pool.release(a, t0);
	pool.release(b, t0);
	pool.release(c, t0 + 5.minutes);

	assert(pool.takeAllLsids().length == 3,
		"sessions still within the timeout must not be pruned");
}

/// takeAllLsids drains the pool and returns each pooled session's lsid.
unittest
{
	ServerSessionPool pool;
	auto a = pool.acquire();
	auto b = pool.acquire();
	pool.release(a);
	pool.release(b);

	auto lsids = pool.takeAllLsids();

	assert(lsids.length == 2,
		"takeAllLsids returns one lsid per pooled session");
	assert(pool.acquire().lsid != a.lsid,
		"the pool is empty after draining, so acquire mints a fresh session");
}

/// A client-facing handle to a logical session, holding a checked-out server session.
struct MongoClientSession
{
	private ServerSession m_session;
	private void delegate(ServerSession) @safe m_release;
	private Transaction m_transaction;

	@disable this(this);

	/// Wraps a checked-out server session with the delegate that returns it to its pool.
	this(ServerSession session, void delegate(ServerSession) @safe release) @safe
	{
		m_session = session;
		m_release = release;
	}

	/// The logical session id document for this session.
	Bson lsid() @safe const { return m_session.lsid; }

	/// Aborts any in-progress transaction, then returns the underlying server session to its pool.
	void endSession() @safe
	{
		if (m_transaction.isActive())
			m_transaction.abort();

		if (m_release !is null)
		{
			m_release(m_session);
			m_release = null;
		}
	}

	/// Begins a multi-document transaction on this session.
	void startTransaction() @safe { m_transaction.start(); }

	/// Commits the active transaction on this session.
	void commitTransaction() @safe { m_transaction.commit(); }

	/// Aborts the active transaction on this session.
	void abortTransaction() @safe { m_transaction.abort(); }

	/// Runs `body` inside a transaction, retrying transient failures until the default deadline.
	T withTransaction(T)(scope T delegate() @safe body, Duration timeout = defaultTransactionTimeout)
	{
		return withTransaction!T(body, timeout, () @safe => MonoTime.currTime);
	}

	/// Runs `body` inside a transaction, retrying transient failures until `timeout` elapses.
	T withTransaction(T)(scope T delegate() @safe body, Duration timeout, scope MonoTime delegate() @safe clock)
	{
		immutable deadline = clock() + timeout;
		return withTransactionRetry!T(
			body,
			() @safe { this.startTransaction(); },
			() @safe { this.commitTransaction(); },
			() @safe { this.abortTransaction(); },
			() @safe => clock() >= deadline);
	}

	/// The current transaction lifecycle state of this session.
	TransactionState transactionState() @safe const { return m_transaction.state(); }

	/// Whether a transaction is currently active on this session.
	bool inTransaction() @safe const { return m_transaction.isActive(); }
}

/// A client session cannot be copied, preventing double-release of its server session.
unittest
{
	static assert(!__traits(compiles, {
		auto original = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {});
		MongoClientSession copy = original;
	}), "MongoClientSession must not be copyable");
}

/// A client session built from a server session exposes that session's lsid.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	assert(session.lsid == server.lsid,
		"a client session must expose its server session's lsid");
}

/// Ending a client session returns its server session to the pool for reuse.
unittest
{
	ServerSessionPool pool;
	auto server = pool.acquire();
	auto session = MongoClientSession(server, (ServerSession s) @safe { pool.release(s); });

	session.endSession();
	auto reacquired = pool.acquire();

	assert(reacquired.lsid == server.lsid,
		"endSession returns the server session to the pool for reuse");
}

/// Ending a client session twice releases its server session only once.
unittest
{
	ServerSessionPool pool;
	auto server = pool.acquire();
	int releases = 0;
	auto session = MongoClientSession(server, (ServerSession s) @safe { releases++; pool.release(s); });

	session.endSession();
	session.endSession();

	assert(releases == 1,
		"a second endSession must not release the server session again");
}

/// Starting a transaction moves the session into the starting transaction state.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	session.startTransaction();

	assert(session.transactionState() == TransactionState.starting,
		"startTransaction must move the session into the starting state");
}

/// Committing an active transaction moves the session into the committed transaction state.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	session.startTransaction();
	session.commitTransaction();

	assert(session.transactionState() == TransactionState.committed,
		"commitTransaction must move the session into the committed state");
}

/// Aborting an active transaction moves the session into the aborted transaction state.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	session.startTransaction();
	session.abortTransaction();

	assert(session.transactionState() == TransactionState.aborted,
		"abortTransaction must move the session into the aborted state");
}

/// inTransaction reports true while a transaction is active and false once it is committed.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	session.startTransaction();
	assert(session.inTransaction() == true,
		"an active transaction reports in-transaction");

	session.commitTransaction();
	assert(session.inTransaction() == false,
		"a committed transaction is no longer in-transaction");
}

/// endSession aborts an in-progress transaction while still releasing the server session.
unittest
{
	bool released;
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe { released = true; });

	session.startTransaction();
	session.endSession();

	assert(session.transactionState() == TransactionState.aborted,
		"ending a session aborts an in-progress transaction");
	assert(released == true,
		"ending a session still releases the server session");
}

/// withTransaction runs the body, commits, and returns the body result.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	auto t0 = MonoTime.currTime;
	auto clock = () @safe => t0;
	auto result = session.withTransaction!int(() @safe => 42, 1.minutes, clock);

	assert(result == 42,
		"withTransaction returns the body result");
	assert(session.transactionState() == TransactionState.committed,
		"withTransaction commits the transaction");
}

/// withTransaction called with only a body uses the real clock and default timeout.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	auto result = session.withTransaction!int(() @safe => 7);

	assert(result == 7,
		"the convenience overload returns the body result");
	assert(session.transactionState() == TransactionState.committed,
		"the convenience overload commits");
}

/// withTransaction does not retry a transient failure once the deadline has passed: it runs the body once and aborts.
unittest
{
	import vibe.db.mongo.connection : MongoException;
	import std.exception : assertThrown;

	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	int bodyCalls;
	auto base = MonoTime.currTime;
	int clockCalls;
	auto clock = () @safe { clockCalls++; return clockCalls == 1 ? base : base + 2.minutes; };
	auto transientBody = delegate int() @safe {
		bodyCalls++;
		auto e = new MongoException("transient");
		e.errorLabels = ["TransientTransactionError"];
		throw e;
	};

	assertThrown!MongoException(session.withTransaction!int(transientBody, 1.minutes, clock));

	assert(bodyCalls == 1,
		"a past-deadline transient failure is not retried");
	assert(session.transactionState() == TransactionState.aborted,
		"an expired transaction is aborted");
}

/// withTransaction retries a within-deadline transient failure and commits the eventual body result.
unittest
{
	import vibe.db.mongo.connection : MongoException;

	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	auto t0 = MonoTime.currTime;
	auto clock = () @safe => t0;
	int bodyCalls;
	auto flakyBody = delegate int() @safe {
		bodyCalls++;
		if (bodyCalls == 1) {
			auto e = new MongoException("transient");
			e.errorLabels = ["TransientTransactionError"];
			throw e;
		}
		return 11;
	};

	auto result = session.withTransaction!int(flakyBody, 1.minutes, clock);

	assert(result == 11,
		"a within-deadline transient failure is retried then returns the body result");
	assert(bodyCalls == 2,
		"the body is retried exactly once");
	assert(session.transactionState() == TransactionState.committed,
		"the retried transaction commits");
}
