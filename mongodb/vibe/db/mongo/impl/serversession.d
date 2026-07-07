/**
	Logical sessions: id generation, the server-session pool, and the
	client-session handle that drives multi-document transactions.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.serversession;

import vibe.data.bson;
import vibe.db.mongo.impl.transaction : Transaction, TransactionState, withTransactionRetry, applyTransaction, commitTransactionCommand, abortTransactionCommand;
import core.time : MonoTime, Duration, minutes;
import std.algorithm : map;
import std.algorithm.mutation : remove, SwapStrategy;
import std.array : array;
import std.typecons : Nullable;

@safe:

/// MongoDB's default deadline for the whole transaction-with-retry loop (120 seconds).
enum defaultTransactionTimeout = 2.minutes;

/// MongoDB's safety margin: treat a session as about to expire one minute before its timeout.
enum sessionSafetyMargin = 1.minutes;

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
	private bool m_dirty;

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

	/// True when the session is within MongoDB's safety margin of `timeout`.
	bool isAboutToExpire(MonoTime now, Duration timeout) @safe const
	{
		return now - m_lastUse >= timeout - sessionSafetyMargin;
	}

	/// Marks the session dirty: a network error occurred while using it, so its
	/// server-side state is unknown and it must NOT be returned to the pool.
	void markDirty() @safe { m_dirty = true; }

	/// Whether the session has been marked dirty (must be discarded, not pooled).
	bool isDirty() @safe const { return m_dirty; }
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

/// At the safety-margin boundary the session is about to expire; just under it, it is still fresh.
unittest
{
	import core.time : MonoTime, minutes, seconds;

	auto session = ServerSession.create();
	auto t0 = MonoTime.currTime;
	session.touch(t0);

	assert(session.isAboutToExpire(t0 + (30.minutes - sessionSafetyMargin), 30.minutes),
		"a session idle for timeout minus the safety margin is about to expire");
	assert(!session.isAboutToExpire(t0 + (30.minutes - sessionSafetyMargin) - 1.seconds, 30.minutes),
		"just under the safety-margin boundary the session is still fresh");
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

/// a session is not dirty until marked, and markDirty makes it dirty
unittest
{
	auto session = ServerSession.create();
	assert(!session.isDirty(), "a fresh server session is not dirty");
	session.markDirty();
	assert(session.isDirty(), "markDirty marks the session dirty (its server-side state is unknown)");
}

/// Hands out server sessions, reusing released ones.
struct ServerSessionPool
{
	private ServerSession[] m_available;
	/// Idle-session timeout, seeded from MongoDB's 30-minute default and refreshed
	/// via `updateTimeout` from the topology-advertised logicalSessionTimeoutMinutes.
	private Duration m_timeout = 30.minutes;

	/// Returns a session ready for use, reusing a released one when available.
	ServerSession acquire(MonoTime now = MonoTime.currTime) @safe
	{
		while (m_available.length)
		{
			auto reused = m_available[$ - 1];
			m_available = m_available[0 .. $ - 1];
			if (!reused.isAboutToExpire(now, m_timeout))
			{
				// Last-use is the time the session is handed out for a command, not the
				// time it is later released (the spec defines last-use as command time).
				reused.touch(now);
				return reused;
			}
		}

		auto fresh = ServerSession.create();
		fresh.touch(now);
		return fresh;
	}

	/// Returns a session to the pool for later reuse, preserving its last-use (command) time.
	void release(ServerSession session, MonoTime now = MonoTime.currTime) @safe
	{
		m_available = m_available.remove!(s => s.isAboutToExpire(now, m_timeout), SwapStrategy.unstable);
		// A dirty session was tainted by a network error: its server-side state is
		// unknown, so discard it rather than recycling its lsid.
		if (session.isDirty())
			return;
		m_available ~= session;
	}

	/// Updates the idle-session timeout from the topology-advertised logical session
	/// timeout; a null value (none advertised) leaves the current timeout unchanged.
	void updateTimeout(Nullable!Duration timeout) @safe
	{
		if (!timeout.isNull)
			m_timeout = timeout.get;
	}

	/// Empties the pool, returning the lsids of every pooled session so they can
	/// be ended on the server (the `endSessions` command on client shutdown).
	Bson[] takeAllLsids() @safe
	{
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

/// Last-use is the acquire/command time, not the release time: a session held idle past the
/// timeout before release is not pooled as fresh.
unittest
{
	import core.time : MonoTime, minutes;

	ServerSessionPool pool;
	auto t0 = MonoTime.currTime;
	auto first = pool.acquire(t0);              // last use ≈ command time = t0
	pool.release(first, t0 + 40.minutes);       // the app held it idle 40m before releasing
	auto later = pool.acquire(t0 + 41.minutes); // the server expired the lsid ~t0+30m

	assert(later.lsid != first.lsid,
		"a session idle since its last use is discarded, not refreshed to the release time");
}

/// updateTimeout shortens the idle window so a once-reusable session expires.
unittest
{
	import core.time : MonoTime, minutes;
	import std.typecons : Nullable;

	ServerSessionPool pool;
	pool.updateTimeout(Nullable!Duration(10.minutes));
	auto t0 = MonoTime.currTime;
	auto first = pool.acquire(t0);
	pool.release(first, t0);
	auto later = pool.acquire(t0 + 15.minutes);

	assert(later.lsid != first.lsid,
		"after updateTimeout(10m) a session idle 15m is discarded, not reused");
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

/// release discards a dirty session instead of returning it to the pool
unittest
{
	ServerSessionPool pool;
	auto clean = pool.acquire();
	auto dirty = pool.acquire();
	dirty.markDirty();

	pool.release(clean);
	pool.release(dirty);

	auto lsids = pool.takeAllLsids();
	assert(lsids.length == 1, "a dirty session is not returned to the pool");
	assert(lsids[0] == clean.lsid, "only the clean session remains poolable");
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
	private long m_txnNumber;
	private Bson delegate(Bson) @safe m_runCommand;

	@disable this(this);

	/// Wraps a checked-out server session with the delegate that returns it to its pool.
	this(ServerSession session, void delegate(ServerSession) @safe release, Bson delegate(Bson command) @safe runCommand = null) @safe
	{
		m_session = session;
		m_release = release;
		m_runCommand = runCommand;
	}

	/// Best-effort cleanup when `endSession` was not called: returns the underlying server
	/// session to its pool so its lsid is ended on client shutdown rather than leaking. Only
	/// the pool return is done here (no network I/O), so it is safe even from the GC finalizer;
	/// aborting an in-progress transaction still requires an explicit `endSession()`.
	~this() @safe
	{
		if (m_release !is null)
		{
			m_release(m_session);
			m_release = null;
		}
	}

	/// The logical session id document for this session.
	Bson lsid() @safe const { return m_session.lsid; }

	/// Aborts any in-progress transaction, then returns the underlying server session to its pool.
	void endSession() @safe
	{
		if (m_transaction.isActive())
			abortTransaction();

		if (m_release !is null)
		{
			m_release(m_session);
			m_release = null;
		}
	}

	/// Begins a multi-document transaction on this session.
	void startTransaction() @safe
	{
		m_transaction.start();
		m_txnNumber = m_session.nextTransactionNumber();
	}

	/// Decorates an operation command with this session's transaction context.
	private Bson prepareCommand(Bson command) @safe
	{
		const firstCommand = m_transaction.isFirstCommand();
		m_transaction.markInProgress();
		return applyTransaction(applySession(command, lsid), m_txnNumber, firstCommand);
	}

	/// Decorates an outgoing operation command for this session.
	Bson applyToCommand(Bson command) @safe
	{
		if (m_transaction.isActive())
			return prepareCommand(command);
		return applySession(command, lsid);
	}

	/// The continuation fields a follow-up command (e.g. a getMore) must carry to stay
	/// inside this session's active transaction: `{lsid, txnNumber, autocommit: false}`,
	/// never `startTransaction` since a continuation is never the transaction's first command.
	/// Returns an empty object when no transaction is active.
	Bson transactionContext() @safe const
	{
		if (!m_transaction.isActive())
			return Bson.emptyObject;
		return applyTransaction(applySession(Bson.emptyObject, lsid), m_txnNumber, false);
	}

	/// Commits the active transaction on this session.
	void commitTransaction() @safe
	{
		dispatchTransactionControl(commitTransactionCommand(m_txnNumber));
		m_transaction.commit();
	}

	/// Aborts the active transaction on this session.
	void abortTransaction() @safe
	{
		// abortTransaction is best-effort per the transactions spec: a failure to tell
		// the server (rejected, network error during cleanup) must not raise to the caller.
		try
			dispatchTransactionControl(abortTransactionCommand(m_txnNumber));
		catch (Exception)
		{
		}
		m_transaction.abort();
	}

	/// Sends a transaction-control command (commit/abort) to the server when the
	/// transaction has reached it and a runner is wired up.
	private void dispatchTransactionControl(Bson controlCommand) @safe
	{
		if (!shouldDispatchControl())
			return;
		auto command = applySession(controlCommand, lsid);
		command["$db"] = Bson("admin");
		m_runCommand(command);
	}

	/// True when a transaction-control command must reach the server: the transaction has
	/// dispatched a command (so the server knows about it) and a server-command runner is wired up.
	private bool shouldDispatchControl() @safe const
	{
		return m_transaction.isInProgress() && m_runCommand !is null;
	}

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

	/// The transaction number allocated for the active transaction on this session.
	long transactionNumber() @safe const { return m_txnNumber; }
}

/// True when the pointer refers to a session currently inside an active transaction.
bool inActiveTransaction(scope const(MongoClientSession)* session) @safe
{
	return session !is null && session.inTransaction;
}

/// A null session pointer is never in an active transaction.
unittest
{
	assert(!inActiveTransaction(null),
		"a null session pointer is not in an active transaction");
}

/// A fresh session with no transaction started is not in an active transaction.
unittest
{
	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {});

	assert(!(() @trusted => inActiveTransaction(&session))(),
		"a session with no transaction started is not in an active transaction");
}

/// A session reports an active transaction once one is started.
unittest
{
	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {});

	session.startTransaction();

	assert((() @trusted => inActiveTransaction(&session))(),
		"a session is in an active transaction after startTransaction");
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

/// Dropping a session without endSession still returns it to the pool (the destructor cleans up).
unittest
{
	bool released;

	{
		auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe { released = true; });
		// intentionally never call endSession()
	} // ~this runs here

	assert(released,
		"a session dropped without endSession is returned to its pool by the destructor, not leaked");
}

/// A destructor on an explicitly-ended session does not release the server session a second time.
unittest
{
	int releases = 0;

	{
		auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe { releases++; });
		session.endSession();
	} // ~this runs here; m_release is already null

	assert(releases == 1,
		"the destructor must not double-release a session that was already ended");
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

/// The first transaction started on a fresh session has transaction number 1.
unittest
{
	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {});

	session.startTransaction();

	assert(session.transactionNumber() == 1,
		"the first transaction on a fresh session must have transaction number 1");
}

/// The first command prepared inside a transaction carries lsid, txnNumber, autocommit and startTransaction.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	session.startTransaction();
	auto cmd = Bson.emptyObject;
	cmd["insert"] = Bson("people");
	auto decorated = session.prepareCommand(cmd);

	assert(decorated["insert"] == Bson("people"),
		"prepareCommand preserves the original command");
	assert(decorated["lsid"] == server.lsid,
		"the first command carries the session's logical session id");
	assert(decorated["txnNumber"].get!long == session.transactionNumber(),
		"the first command carries the allocated transaction number");
	assert(decorated["autocommit"].get!bool == false,
		"a command inside a transaction sets autocommit false");
	assert(decorated["startTransaction"].get!bool == true,
		"the first command of a transaction starts it");
}

/// applyToCommand decorates a command with the full transaction context while a transaction is active.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	session.startTransaction();
	auto cmd = Bson.emptyObject;
	cmd["insert"] = Bson("people");
	auto decorated = session.applyToCommand(cmd);

	assert(decorated["insert"] == Bson("people"),
		"applyToCommand preserves the original command");
	assert(decorated["lsid"] == server.lsid,
		"applyToCommand carries the session's logical session id inside a transaction");
	assert(decorated["txnNumber"].get!long == session.transactionNumber(),
		"applyToCommand carries the allocated transaction number inside a transaction");
	assert(decorated["autocommit"].get!bool == false,
		"applyToCommand sets autocommit false inside a transaction");
	assert(decorated["startTransaction"].get!bool == true,
		"applyToCommand starts the transaction on the first command");
}

/// transactionContext yields the getMore continuation fields inside a transaction: lsid, txnNumber and autocommit false, never startTransaction.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	session.startTransaction();
	auto context = session.transactionContext();

	assert(context["lsid"] == server.lsid,
		"transactionContext carries the session's logical session id");
	assert(context["txnNumber"].get!long == session.transactionNumber(),
		"transactionContext carries the active transaction number");
	assert(context["autocommit"].get!bool == false,
		"transactionContext sets autocommit false");
	assert(context["startTransaction"].type == Bson.Type.null_,
		"transactionContext never starts the transaction: a continuation is not the first command");
}

/// Outside a transaction transactionContext yields an empty object, attaching nothing to a continuation.
unittest
{
	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {});

	assert(session.transactionContext() == Bson.emptyObject,
		"transactionContext is empty when no transaction is active");
}

/// transactionContext does not consume the first-command flag: a later prepared command still carries startTransaction.
unittest
{
	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {});

	session.startTransaction();
	session.transactionContext();
	auto first = session.prepareCommand(Bson(["insert": Bson("people")]));

	assert(first["startTransaction"].get!bool == true,
		"transactionContext must not mark the transaction in-progress, so the first command still starts it");
}

/// Outside a transaction applyToCommand attaches only the lsid, never the transaction fields.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	auto cmd = Bson.emptyObject;
	cmd["find"] = Bson("people");
	auto decorated = session.applyToCommand(cmd);

	assert(decorated["lsid"] == server.lsid,
		"a session command carries the lsid");
	assert(decorated["find"] == Bson("people"),
		"applyToCommand preserves the original command outside a transaction");
	assert(decorated["txnNumber"].type == Bson.Type.null_,
		"no txnNumber outside a transaction");
	assert(decorated["autocommit"].type == Bson.Type.null_,
		"no autocommit outside a transaction");
	assert(decorated["startTransaction"].type == Bson.Type.null_,
		"no startTransaction outside a transaction");
}

/// The second command prepared inside a transaction omits startTransaction but keeps the transaction context.
unittest
{
	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {});

	session.startTransaction();
	auto first = session.prepareCommand(Bson(["insert": Bson("people")]));
	auto second = session.prepareCommand(Bson(["update": Bson("people")]));

	assert(second["startTransaction"].type == Bson.Type.null_,
		"only the first command of a transaction carries startTransaction");
	assert(second["txnNumber"].get!long == session.transactionNumber(),
		"a subsequent command still carries the transaction number");
	assert(second["autocommit"].get!bool == false,
		"a subsequent command stays inside the transaction with autocommit false");
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

/// Committing an in-progress transaction dispatches a command through the injected runner.
unittest
{
	int runnerCalls;
	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { runnerCalls++; return Bson.emptyObject; };

	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {}, runner);

	session.startTransaction();
	session.prepareCommand(Bson(["insert": Bson("people")]));
	session.commitTransaction();

	assert(runnerCalls == 1,
		"committing an in-progress transaction sends a command to the server");
}

/// The dispatched commit command carries the session's lsid so the server can find the transaction.
unittest
{
	Bson captured;
	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { captured = cmd; return Bson.emptyObject; };

	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {}, runner);

	session.startTransaction();
	session.prepareCommand(Bson(["insert": Bson("people")]));
	session.commitTransaction();

	assert(captured["lsid"] == server.lsid,
		"the commit command identifies the session via lsid");
	assert(captured["commitTransaction"].get!int == 1,
		"the commit command names the operation");
	assert(captured["txnNumber"].get!long == session.transactionNumber(),
		"the commit command carries the transaction number");
}

/// The dispatched commit command targets the admin database via $db, as the spec requires.
unittest
{
	Bson captured;
	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { captured = cmd; return Bson.emptyObject; };

	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {}, runner);

	session.startTransaction();
	session.prepareCommand(Bson(["insert": Bson("people")]));
	session.commitTransaction();

	assert(captured["$db"] == Bson("admin"),
		"transaction-control commands run against the admin database");
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

/// Aborting an in-progress transaction dispatches an abortTransaction command identifying the session.
unittest
{
	Bson captured;
	bool called;
	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { called = true; captured = cmd; return Bson.emptyObject; };

	auto server = ServerSession.create();
	auto session = MongoClientSession(server, (ServerSession s) @safe {}, runner);

	session.startTransaction();
	session.prepareCommand(Bson(["insert": Bson("people")]));
	session.abortTransaction();

	assert(called, "aborting an in-progress transaction sends an abortTransaction command");
	assert(captured["abortTransaction"].get!int == 1,
		"aborting an in-progress transaction sends an abortTransaction command");
	assert(captured["lsid"] == server.lsid,
		"the abort command identifies the session");
}

/// Committing or aborting a never-ran transaction is a client-side no-op that never contacts the server.
unittest
{
	int runnerCalls;
	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { runnerCalls++; return Bson.emptyObject; };

	{
		auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {}, runner);
		session.startTransaction();
		session.commitTransaction();

		assert(runnerCalls == 0,
			"committing a never-ran transaction does not contact the server");
	}

	runnerCalls = 0;

	{
		auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {}, runner);
		session.startTransaction();
		session.abortTransaction();

		assert(runnerCalls == 0,
			"aborting a never-ran transaction does not contact the server");
	}
}

/// Aborting an in-progress transaction swallows a runner error and still reaches the aborted state, as abort is best-effort.
unittest
{
	import std.exception : assertNotThrown;

	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { throw new Exception("server rejected abort"); };

	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {}, runner);

	session.startTransaction();
	session.prepareCommand(Bson(["insert": Bson("people")]));

	assertNotThrown(session.abortTransaction(),
		"abortTransaction must swallow runner errors (best-effort per spec)");
	assert(session.transactionState() == TransactionState.aborted,
		"the transaction still reaches the aborted state after a swallowed runner error");
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

/// Ending a session with a genuinely in-progress transaction dispatches abortTransaction to the server.
unittest
{
	Bson captured;
	bool aborted;
	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { aborted = true; captured = cmd; return Bson.emptyObject; };

	bool released;
	auto release = (ServerSession s) @safe { released = true; };
	auto session = MongoClientSession(ServerSession.create(), release, runner);

	session.startTransaction();
	session.prepareCommand(Bson(["insert": Bson("people")]));
	session.endSession();

	assert(aborted, "ending a session with an in-progress transaction aborts it on the server");
	assert(captured["abortTransaction"].get!int == 1,
		"ending a session with an in-progress transaction sends an abortTransaction command");
	assert(released == true,
		"endSession still releases the server session");
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

/// withTransaction threads the runner end-to-end: a body that runs an operation commits on the server.
unittest
{
	Bson captured;
	bool committed;
	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { committed = true; captured = cmd; return Bson.emptyObject; };

	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {}, runner);

	auto t0 = MonoTime.currTime;
	auto clock = () @safe => t0;
	auto result = session.withTransaction!int(() @safe {
		session.prepareCommand(Bson(["insert": Bson("people")]));
		return 99;
	}, 1.minutes, clock);

	assert(result == 99,
		"withTransaction returns the body result");
	assert(committed && captured["commitTransaction"].get!int == 1,
		"a transaction with operations is committed on the server");
	assert(session.transactionState() == TransactionState.committed,
		"withTransaction commits the transaction");
}

/// The transaction number advances across successive transactions on the same session.
unittest
{
	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {});

	session.startTransaction();
	assert(session.transactionNumber() == 1,
		"the first transaction is number 1");

	session.commitTransaction();

	session.startTransaction();
	assert(session.transactionNumber() == 2,
		"a second transaction gets the next number");
}

/// commitTransaction propagates a runner error, unlike best-effort abort which swallows it.
unittest
{
	import std.exception : assertThrown;

	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { throw new Exception("commit failed on server"); };

	auto session = MongoClientSession(ServerSession.create(), (ServerSession s) @safe {}, runner);

	session.startTransaction();
	session.prepareCommand(Bson(["insert": Bson("c")]));

	assertThrown!Exception(session.commitTransaction(),
		"commitTransaction must propagate a runner error (unlike best-effort abort)");
}

/// endSession releases the server session even when the abort runner throws, as abort is best-effort.
unittest
{
	import std.exception : assertNotThrown;

	Bson delegate(Bson) @safe runner = (Bson cmd) @safe { throw new Exception("abort rejected"); };

	bool released;
	auto release = (ServerSession s) @safe { released = true; };
	auto session = MongoClientSession(ServerSession.create(), release, runner);

	session.startTransaction();
	session.prepareCommand(Bson(["insert": Bson("c")]));

	assertNotThrown(session.endSession(),
		"endSession must not propagate the abort runner error (abort is best-effort)");
	assert(released,
		"endSession releases the server session even when the abort runner throws");
}
