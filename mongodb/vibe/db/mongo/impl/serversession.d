/**
	Logical session id generation for retryable writes.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.serversession;

import vibe.data.bson;
import core.time : MonoTime, Duration, minutes;

@safe:

/// Builds a fresh logical session id document `{ id: <UUID binary subtype 0x04, 16 bytes> }`.
Bson logicalSessionId()
{
	import std.uuid : randomUUID;
	auto bytes = randomUUID().data;
	return Bson(["id": Bson(BsonBinData(BsonBinData.Type.uuid, bytes.idup))]);
}

/// Builds the `endSessions` admin command that frees the given logical sessions on the server.
Bson endSessionsCommand(Bson[] lsids) @safe
{
	return Bson(["endSessions": Bson(lsids)]);
}

/// Returns the command with the logical session id attached.
Bson applySession(Bson command, Bson lsid) @safe
{
	Bson result = command;
	result["lsid"] = lsid;
	return result;
}

/// Tracks per-session state such as the monotonic transaction number.
struct ServerSession
{
	private long m_txnNumber;
	private Bson m_lsid;
	private MonoTime m_lastUse;

	/// Returns the next monotonic transaction number, starting at 1.
	// TODO(sessions): transactions and causal consistency build on this session.
	// Add startTransaction/commitTransaction (using this txnNumber) and an
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

/// A client-facing handle to a logical session, holding a checked-out server session.
// TODO(B-sess8): this handle is move-only in intent — `endSession` nulls `m_release`
// to block a double release, but a struct COPY carries a live `m_release` and could
// release across copies. Add `@disable this(this);` to make the contract explicit.
struct MongoClientSession
{
	private ServerSession m_session;
	private void delegate(ServerSession) @safe m_release;

	this(ServerSession session, void delegate(ServerSession) @safe release) @safe
	{
		m_session = session;
		m_release = release;
	}

	/// The logical session id document for this session.
	Bson lsid() @safe const { return m_session.lsid; }

	/// Returns the underlying server session to its pool.
	void endSession() @safe
	{
		if (m_release !is null)
		{
			m_release(m_session);
			m_release = null;
		}
	}
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
