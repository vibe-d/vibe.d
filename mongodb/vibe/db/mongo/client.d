/**
	MongoClient class doing connection management. Usually this is a main entry point
	for client code.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.client;

public import vibe.db.mongo.collection;
public import vibe.db.mongo.database;

import vibe.core.connectionpool;
import vibe.core.log;
import vibe.core.sync : LocalManualEvent, createManualEvent;
import vibe.db.mongo.connection;
import vibe.db.mongo.settings;
import vibe.db.mongo.topology;
import vibe.db.mongo.monitor;
import vibe.db.mongo.impl.crud;
import vibe.db.mongo.impl.wireversion : WireVersion;
import vibe.data.bson;

import core.time : Duration, seconds, msecs, MonoTime;
import std.conv;
import std.exception : enforce;
import std.typecons : Nullable;

/**
	Represents a connection to a MongoDB server.

	Note that this class uses a ConnectionPool internally to create and reuse
	network connections to the server as necessary. It should be reused for all
	fibers in a thread for optimum performance in high concurrency scenarios.
 */
final class MongoClient {
@safe:

	// Concurrency contract (HARD): a MongoClient is single-thread / single-event-loop.
	// It is safe to share across fibers of ONE thread, but it must NOT be shared across
	// OS threads. The connection pools, m_topologyChanged
	// (a LocalManualEvent), and the bool flags below are all thread-local and
	// unsynchronised; only an event loop on the owning thread may touch them. The
	// AtomicTopology wrapper exists solely to give a consistent intra-thread snapshot
	// of the topology across a yield point (publish/load is one atomic swap); it is NOT
	// a license for cross-thread sharing and does not make the rest of this state safe
	// to mutate from another thread. For one client per thread, use a thread-local
	// instance (e.g. scopedMongoDB) rather than passing one client between threads.
	private {
		ConnectionPool!MongoConnection[string] m_connectionPools;
		MongoClientSettings m_settings;
		AtomicTopology m_topology;
		LocalManualEvent m_topologyChanged;
		bool m_discoveryInProgress;

		MonitorRegistry m_monitors;
	}

	package this(string host, ushort port)
	{
		this("mongodb://" ~ host ~ ":" ~ to!string(port) ~ "/?safe=true");
	}

	/**
		Initializes a MongoDB client using a URL.

		The URL must be in the form documented at
		$(LINK http://www.mongodb.org/display/DOCS/Connections) which is:

		mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]

		Throws:
			An exception if the URL cannot be parsed as a valid MongoDB URL.
	*/
	package this(string url)
	{
		MongoClientSettings settings;
		auto goodUrl = parseMongoDBUrl(settings, url);
		if(!goodUrl) throw new Exception("Unable to parse mongodb URL: " ~ url);
		this(settings);
	}

	package this(MongoClientSettings settings)
	{
		m_settings = settings;
		m_topologyChanged = createManualEvent();

		// discoverTopology()/lockConnection() throw on an unreachable or invalid
		// deployment. The throw must propagate, but destroying a live
		// m_topologyChanged (LocalManualEvent) during the unwind segfaults in
		// vibe-core (releaseRef -> disposeGCSafe outside an event-loop context).
		// LocalManualEvent.init's destructor is a no-op (m_waiter is null), so we
		// move it back to .init before rethrowing: the field dtor that then runs
		// during unwind is harmless. The freshly-allocated waiter is leaked, but
		// only on the failure path where the process is throwing out of the ctor.
		try
		{
			// discoverTopology() runs full SDAM discovery.
			discoverTopology();

			// The monitor registry is always constructed so its call sites
			// (handleStaleCommandError / stopMonitoring / activeMonitorCount, and
			// resolveHost's requestAllChecks) operate on a real object, never a null. It
			// is built BEFORE lockConnection() so server selection during that connect
			// cannot dereference a null registry.
			ServerProber prober = (MongoHost host) @safe => probeServer(m_settings, host);
			m_monitors = new MonitorRegistry(prober, &onMonitorResult,
				m_settings.heartbeatFrequencyMS.msecs, m_settings.minHeartbeatFrequencyMS.msecs);

			// force a connection to cause an exception for wrong URLs
			lockConnection();

			// Start the monitors only after the connection succeeds, so a ctor failure
			// does not leak background monitor tasks.
			m_monitors.reconcileWith(m_topology.load().allKnownHosts());
		}
		catch (Exception e)
		{
			import std.algorithm.mutation : moveEmplace;
			// moveEmplace overwrites the live m_topologyChanged with .init WITHOUT
			// running its (crashing) destructor first, so the field dtor that runs
			// during the rethrow unwind sees a null waiter and is a no-op.
			LocalManualEvent harmless;
			() @trusted { moveEmplace(harmless, m_topologyChanged); }();
			throw e;
		}
	}

	/// Returns the read preference configured for this client.
	@property ReadPreference readPreference() const
	{
		return m_settings.readPreference;
	}

	/// Returns the ordered read-preference tag sets configured for this client.
	@property string[string][] readPreferenceTags()
	{
		return m_settings.readPreferenceTags;
	}

	/// Returns the read concern configured for this client.
	ReadConcern readConcern() const
	{
		return m_settings.readConcern;
	}

	/** Disconnects all currently unused connections to the server.
	*/
	void cleanupConnections()
	{
		foreach (pool; m_connectionPools.byValue)
			pool.removeUnused((conn) nothrow @safe {
				try conn.disconnect();
				catch (Exception e) {
					logWarn("Error thrown during MongoDB connection close: %s", e.msg);
					try () @trusted { logDebug("Full error: %s", e.toString()); } ();
					catch (Exception e) {}
				}
			});
	}

	/**
		Accesses a collection using an absolute path.

		The full database.collection path must be specified. To access
		collections using a path relative to their database, use getDatabase in
		conjunction with MongoDatabase.opIndex.

		Returns:
			MongoCollection for the given combined database and collection name (path)

		Examples:
			---
			auto col = client.getCollection("test.collection");
			---
   */
	MongoCollection getCollection(string path)
	{
		return MongoCollection(this, path);
	}

	/**
		Returns an object representing the specified database.

		The returned object allows to access the database entity (which contains
		a set of collections). There are two main use cases:

		1. Accessing collections using a relative path

		2. Performing service commands on the database itself

		Note that there is no performance gain in accessing collections via a
		relative path compared to getCollection and an absolute path.

		Returns:
			MongoDatabase instance representing requested database

		Examples:
			---
			auto db = client.getDatabase("test");
			auto coll = db["collection"];
			---
	*/
	MongoDatabase getDatabase(string dbName)
	{
		return MongoDatabase(this, dbName);
	}

	/**
	 	Return a handle to all databases of the server.

	 	Returns:
	 		An input range of $(D MongoDatabase) objects.

	 	Examples:
	 		---
	 		auto names = client.getDatabaseNames();
	 		writeln("Current databases are: ", names);
	 		---
	 */
	auto getDatabases()()
	{
		MongoDatabase[] ret;
		foreach (info; lockConnection.listDatabases())
			ret ~= MongoDatabase(this, info.name);
		return ret;
	}

	/// Locks a connection to the server chosen by the configured read preference.
	package LockedConnection!MongoConnection lockConnection()
	{
		return lockConnectionResolving(false, m_settings.readPreference);
	}

	/// Locks a connection to the server chosen by an explicit per-query read preference.
	package LockedConnection!MongoConnection lockConnection(ReadPreference pref)
	{
		return lockConnectionResolving(false, pref);
	}

	/// Locks a connection to the primary. Used for write operations, which must
	/// always go to the primary regardless of the configured read preference.
	package LockedConnection!MongoConnection lockConnectionToPrimary()
	{
		return lockConnectionResolving(true, ReadPreference.primary);
	}

	/// Resolves the host a read should target, retrying once after re-discovery.
	package MongoHost resolveHostForRead(ReadPreference pref)
	{
		try {
			return resolveHost(false, pref);
		} catch (Exception e) {
			logWarn("Read host resolution failed: %s — re-discovering topology", e.msg);
		}

		discoverTopology();
		return resolveHost(false, pref);
	}

	private LockedConnection!MongoConnection lockConnectionResolving(bool toPrimary, ReadPreference pref)
	{
		try {
			return lockConnectionToHost(resolveHost(toPrimary, pref));
		} catch (Exception e) {
			logWarn("Connection acquisition failed: %s — re-discovering topology", e.msg);
		}

		discoverTopology();
		return lockConnectionToHost(resolveHost(toPrimary, pref));
	}

	/// Selects a target host, blocking up to `serverSelectionTimeoutMS` for one to appear.
	private MongoHost resolveHost(bool toPrimary, ReadPreference pref)
	{
		auto deadline = MonoTime.currTime + m_settings.serverSelectionTimeoutMS.msecs;

		while (true)
		{
			// Read the counter before the snapshot so a concurrent update is not missed.
			auto topologyVersion = m_topologyChanged.emitCount;

			auto topology = m_topology.load();
			auto selected = selectTarget(topology, toPrimary, pref,
				m_settings.localThresholdMS, m_settings.maxStalenessSeconds,
				m_settings.readPreferenceTags);
			if (!selected.isNull)
				return selected.get;

			m_monitors.requestAllChecks();

			auto remaining = deadline - MonoTime.currTime;
			if (remaining <= Duration.zero)
				break;

			m_topologyChanged.wait(remaining, topologyVersion);
		}

		throw new MongoDriverException(toPrimary
			? "No primary server available for write"
			: "No suitable server found for read preference");
	}

	/// On a stale-topology command error, marks the host failed and re-checks it.
	private void handleStaleCommandError(MongoHost host, MongoServerErrorCode code) @safe nothrow
	{
		if (!isStaleTopologyError(code))
			return;

		try {
			m_topology.publish(applyFailed(m_topology.load(), host));
			m_topologyChanged.emit();
			m_monitors.requestCheck(host);
		} catch (Exception) {}
	}

	/// Locks a pooled connection for a specific host (e.g. a cursor re-locking its pinned host).
	package LockedConnection!MongoConnection lockConnectionToHost(MongoHost host)
	{
		auto pool = poolFor(host);

		foreach (_; 0 .. 100)
		{
			auto conn = pool.lockConnection();

			if (conn.alive)
				return conn;

			pool.remove(conn.__conn);
			logDiagnostic("Evicted dead MongoDB connection from pool");
		}

		throw new MongoDriverException("Failed to acquire a live connection after evicting 100 dead connections");
	}

	/// Drops the connection pools for hosts no longer in `desiredHosts`, disconnecting
	/// their idle connections first. Without this, a host that leaves the replica set
	/// keeps its pool (and idle sockets) forever, and maxConnections becomes a per-host
	/// rather than a global bound. Connections still checked out are closed when the
	/// in-flight operation returns them to the (now unreferenced) pool.
	private void pruneStalePools(MongoHost[] desiredHosts) @safe
	{
		import std.algorithm : map;
		import std.array : array;

		auto desiredKeys = desiredHosts.map!(h => hostKey(h)).array;
		foreach (key; poolKeysToPrune(m_connectionPools.keys, desiredKeys))
		{
			m_connectionPools[key].removeUnused((conn) nothrow @safe {
				try conn.disconnect();
				catch (Exception e) {
					logWarn("Error closing MongoDB connection for pruned host %s: %s", key, e.msg);
					try () @trusted { logDebug("Full error: %s", e.toString()); } ();
					catch (Exception e) {}
				}
			});
			m_connectionPools.remove(key);
		}
	}

	private ConnectionPool!MongoConnection poolFor(MongoHost host)
	{
		auto key = hostKey(host);

		if (auto existing = key in m_connectionPools)
			return *existing;

		auto pool = new ConnectionPool!MongoConnection(
			() @safe => createConnectionToHost(host),
			m_settings.maxConnections
		);
		m_connectionPools[key] = pool;

		return pool;
	}

	private MongoConnection createConnectionToHost(MongoHost host) @safe
	{
		auto ret = new MongoConnection(m_settings);
		ret.onCommandError(&handleStaleCommandError);

		try {
			ret.connectToHost(host);
		} catch (Exception e) {
			() @trusted { destroy(ret); } ();
			throw e;
		}

		return ret;
	}

	private void discoverTopology()
	{
		import std.algorithm : canFind;

		if (m_discoveryInProgress)
			return;

		m_discoveryInProgress = true;
		scope (exit)
			m_discoveryInProgress = false;

		TopologyDescription newTopology;
		newTopology.type = initialTopologyType();
		// Seed the configured replica-set name so update()'s setName guard enforces it on
		// every probe — including the monitor path, which does not call matchesReplicaSet.
		newTopology.setName = m_settings.replicaSet;
		newTopology.seedCount = cast(uint) m_settings.hosts.length;
		// Feed the configured heartbeat into the maxStaleness formula (was hardcoded to 10s).
		newTopology.heartbeatFrequencyMS = m_settings.heartbeatFrequencyMS;
		Exception lastException;

		MongoHost[] attempted = m_settings.hosts.dup;
		foreach (host; m_settings.hosts) {
			probeAndUpdate(newTopology, host, lastException);
		}

		// A newly discovered host may itself report further hosts we don't know
		// about yet, so keep probing until a full pass turns up nothing new.
		for (bool foundNew = true; foundNew; ) {
			foundNew = false;

			foreach (host; newTopology.allKnownHosts()) {
				if (attempted.canFind(host))
					continue;

				attempted ~= host;
				foundNew = true;
				probeAndUpdate(newTopology, host, lastException);
			}
		}

		// Select with the configured readPreferenceTags so discovery's suitability check
		// matches runtime selection (resolveHost). Otherwise a tag set matching no server
		// passes discovery, then fails (or null-derefs) later in lockConnection().
		auto selected = selectServer(newTopology, m_settings.readPreference, m_settings.localThresholdMS,
			m_settings.maxStalenessSeconds, m_settings.readPreferenceTags);

		if (selected.isNull) {
			throw lastException !is null
				? lastException
				: new MongoDriverException("No suitable server found during topology discovery");
		}

		publishTopology(newTopology);
	}

	/// Publishes a new topology snapshot and notifies waiters.
	private void publishTopology(TopologyDescription topology)
	{
		m_topology.publish(topology);
		m_topologyChanged.emit();
	}

	private void probeAndUpdate(ref TopologyDescription topology, MongoHost host, ref Exception lastException)
	{
		try {
			auto desc = probeServer(m_settings, host);

			if (!matchesReplicaSet(m_settings.replicaSet, desc))
				return;

			topology.update(host, desc);
		} catch (Exception ex) {
			lastException = ex;
			logError("Failed to probe %s:%s: %s", host.name, host.port, ex.msg);
			topology.markFailed(host);
		}
	}

	private TopologyType initialTopologyType()
	{
		if (m_settings.replicaSet.length)
			return TopologyType.replicaSetNoPrimary;

		return TopologyType.unknown;
	}

	/// Publishes a monitor's probe result as a new snapshot and reconciles the monitor set.
	private void onMonitorResult(MongoHost host, Nullable!ServerDescription desc, Duration rtt)
	{
		auto current = m_topology.load();

		TopologyDescription next;
		if (desc.isNull)
			next = applyFailed(current, host);
		else
		{
			auto folded = desc.get;
			folded.roundTripTime = cast(float) foldRtt(current, host, rtt);
			next = applyDescription(current, host, folded);
		}
		publishTopology(next);

		auto knownHosts = m_topology.load().allKnownHosts();
		m_monitors.reconcileWith(knownHosts);
		pruneStalePools(knownHosts);
	}

	/// Folds this probe's measured `rtt` into the host's running RTT average (EWMA). The
	/// first sample for a host (no prior probed average) seeds the average with the raw
	/// measurement; later samples decay the old average per the SDAM alpha=0.2 formula.
	private double foldRtt(ref const TopologyDescription current, MongoHost host, Duration rtt) @safe
	{
		auto sample = rtt.total!"usecs" / 1_000_000.0;
		foreach (ref s; current.servers)
		{
			if (s.host == host && s.description.roundTripTime > 0)
				return ewmaRtt(s.description.roundTripTime, sample, false);
		}
		return ewmaRtt(0.0, sample, true);
	}

	/// Stops all background server monitors. Call before discarding the client.
	void stopMonitoring()
	{
		m_monitors.stopAll();
	}

	/// Tears the client all the way down: stops the background monitors, disconnects
	/// the idle pooled connections, and drops every connection pool. Call before
	/// discarding a client to release its background tasks and sockets. cleanupConnections
	/// needs a live pool, so it runs before the pools are dropped. Connections still
	/// checked out by an in-flight operation are closed when that operation returns them.
	void close()
	{
		stopMonitoring();
		cleanupConnections();
		m_connectionPools = null;
	}

	/// Number of background server monitors currently running.
	size_t activeMonitorCount() const @property
	{
		return m_monitors.length;
	}

	/// Number of per-host connection pools the client currently holds.
	size_t connectionPoolCount() const @property
	{
		return m_connectionPools.length;
	}
}

/**
	Owns a MongoClient and closes it when it leaves scope.

	`scopedMongoDB` returns this handle so a client created in a local or thread-local
	scope is cleaned up deterministically: the destructor calls `MongoClient.close`,
	which stops the background monitors (breaking the monitor-task -> client reference
	cycle that would otherwise keep the client reachable for the lifetime of the
	process) and drains the connection pools.

	The handle is move-only and forwards every `MongoClient` member through `alias this`:
	---
	auto client = scopedMongoDB("127.0.0.1");
	auto users = client.getCollection("myapp.users");
	---

	To keep a raw, manually-managed `MongoClient` alive beyond the handle's scope (for
	example to store it in a long-lived object), call `release()` to take ownership; you
	are then responsible for calling `close()` before discarding it.
*/
struct MongoClientHandle {
@safe:
	private MongoClient m_client;
	private void delegate() @safe m_stop;

	@disable this(this);

	/// Wraps `client`, closing it (stop monitors, drain pools) when the
	/// handle is destroyed.
	package this(MongoClient client)
	{
		m_client = client;
		m_stop = &client.close;
	}

	/// Test seam: wraps `client` with an explicit cleanup action run on destruction.
	package this(MongoClient client, void delegate() @safe stop)
	{
		m_client = client;
		m_stop = stop;
	}

	/// Closes the owned client unless ownership was released or moved away.
	~this()
	{
		if (m_stop is null)
			return;

		auto stop = m_stop;
		m_stop = null;
		stop();
	}

	/// The owned client. Every `MongoClient` member is also reachable directly on the handle.
	@property inout(MongoClient) client() inout { return m_client; }
	alias client this;

	/// Relinquishes ownership without closing the client; the caller takes over the client's
	/// lifetime and must call `close()` before discarding it.
	MongoClient release()
	{
		m_stop = null;
		auto c = m_client;
		m_client = null;
		return c;
	}
}

/// SDAM exponentially-weighted moving average of a server's round-trip time.
///
/// `sample` is the latest measured RTT, `prev` the running average; `first` seeds the
/// average with the raw sample on the very first measurement. Subsequent samples fold in
/// with alpha=0.2 per the SDAM spec: newAvg = alpha*sample + (1-alpha)*prev.
double ewmaRtt(double prev, double sample, bool first) @safe pure nothrow @nogc
{
	enum double alpha = 0.2;
	return first ? sample : alpha * sample + (1.0 - alpha) * prev;
}

/// ewmaRtt seeds on the first sample and folds later samples with alpha 0.2
unittest
{
	import std.math : isClose;

	// the first measurement seeds the average with the raw sample (prev is ignored)
	assert(ewmaRtt(0.0, 0.040, true) == 0.040,
		"the first RTT sample seeds the moving average");

	// a later sample folds in: 0.2*0.020 + 0.8*0.040 = 0.036
	assert(isClose(ewmaRtt(0.040, 0.020, false), 0.036),
		"a later sample is weighted 0.2 against the 0.8-weighted running average");

	// a steady sample equal to the average leaves it unchanged
	assert(isClose(ewmaRtt(0.030, 0.030, false), 0.030),
		"a sample equal to the running average leaves it unchanged");
}

/// The pool keys to prune: every currently-pooled host key absent from the desired set.
///
/// `desiredKeys` is the host-key set of the current topology; `pooledKeys` is the set of
/// per-host connection pools the client holds. A key in `pooledKeys` but not in
/// `desiredKeys` belongs to a host that left the deployment, so its pool (and its idle
/// sockets) must be dropped.
string[] poolKeysToPrune(string[] pooledKeys, string[] desiredKeys) @safe pure nothrow
{
	import std.algorithm : canFind, filter;
	import std.array : array;
	return pooledKeys.filter!(k => !desiredKeys.canFind(k)).array;
}

/// poolKeysToPrune drops pools for hosts no longer in the topology and keeps the rest
unittest
{
	// a removed host's pool key is pruned; a still-present one is kept; no spurious keys are invented
	auto toPrune = poolKeysToPrune(["a:27017", "b:27017", "c:27017"], ["a:27017", "c:27017"]);
	assert(toPrune == ["b:27017"], "only the pool whose host left the topology is pruned");

	assert(poolKeysToPrune(["a:27017"], ["a:27017"]).length == 0,
		"a host still in the topology keeps its pool");
	assert(poolKeysToPrune([], ["a:27017"]).length == 0,
		"a newly-desired host with no pool yet produces nothing to prune");
}

/// MongoClientHandle runs its stop action exactly once when it leaves scope.
unittest
{
	int stops;
	{
		auto handle = MongoClientHandle(null, () @safe { stops++; });
	} // ~this runs here

	assert(stops == 1, "leaving scope runs the stop action exactly once");
}

/// release() relinquishes ownership so the destructor does not stop monitoring.
unittest
{
	int stops;
	MongoClient raw;
	{
		auto handle = MongoClientHandle(null, () @safe { stops++; });
		raw = handle.release();
	} // ~this runs here, but ownership was released

	assert(stops == 0, "release suppresses the stop action");
	assert(raw is null, "release hands back the owned client");
}

/// Moving a handle transfers ownership: the stop action runs once, from the destination only.
unittest
{
	import std.algorithm.mutation : move;

	int stops;
	{
		auto src = MongoClientHandle(null, () @safe { stops++; });
		{
			auto dst = move(src);
			assert(stops == 0, "moving the handle does not run the stop action");
		} // dst ~this runs here

		assert(stops == 1, "the move destination runs the stop action exactly once");
	} // src ~this runs here on the moved-from handle

	assert(stops == 1, "the moved-from source does not run the stop action again");
}
