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

		discoverTopology();

		// force a connection to cause an exception for wrong URLs
		lockConnection();

		ServerProber prober = (MongoHost host) @safe => probeServer(m_settings, host);
		m_monitors = new MonitorRegistry(prober, &onMonitorResult,
			m_settings.heartbeatFrequencyMS.msecs, m_settings.minHeartbeatFrequencyMS.msecs);
		m_monitors.reconcileWith(m_topology.load().allKnownHosts());
	}

	/// Returns the read preference configured for this client.
	@property ReadPreference readPreference() const
	{
		return m_settings.readPreference;
	}

	/// Whether retryable writes are enabled for this client.
	@property bool retryWrites() const
	{
		return m_settings.retryWrites;
	}

	/// Re-discovers the topology after a primary step-down so the next write
	/// finds the newly elected primary. Best-effort: if no primary has been
	/// elected yet, the following primary re-lock blocks until one appears, so
	/// a failed re-discovery here must not abort the retry.
	package void refreshTopology()
	{
		try
			discoverTopology();
		catch (Exception e)
			logDiagnostic("Topology refresh after step-down found no primary yet: %s", e.msg);
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
				m_settings.localThresholdMS, m_settings.maxStalenessSeconds);
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
	private void handleStaleCommandError(MongoHost host, int code) @safe nothrow
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
		newTopology.seedCount = cast(uint) m_settings.hosts.length;
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

		auto selected = selectServer(newTopology, m_settings.readPreference, m_settings.localThresholdMS, m_settings.maxStalenessSeconds);

		if (selected.isNull) {
			throw lastException !is null
				? lastException
				: new MongoDriverException("No suitable server found during topology discovery");
		}

		m_topology.publish(newTopology);
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
		m_topology.publish(desc.isNull ? applyFailed(current, host) : applyDescription(current, host, desc.get));
		m_topologyChanged.emit();

		m_monitors.reconcileWith(m_topology.load().allKnownHosts());
	}

	/// Stops all background server monitors. Call before discarding the client.
	void stopMonitoring()
	{
		m_monitors.stopAll();
	}

	/// Number of background server monitors currently running.
	size_t activeMonitorCount() const @property
	{
		return m_monitors.length;
	}
}

/// retries once after refreshing topology when the first call steps down
T retryOnceOnStepDown(T)(scope T delegate() @safe op, bool idempotent, bool sessionSupport, scope void delegate() @safe refresh) @safe
{
	try
		return op();
	catch (MongoStepDownException e)
	{
		if (!shouldRetryAfterStepDown(e.code, idempotent, sessionSupport))
			throw e;
		refresh();
		return op();
	}
}

/// retries once after refreshing topology when the first call steps down
unittest {
	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		if (opCalls == 1)
			throw new MongoStepDownException("primary stepped down", 10107);
		return 42;
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	auto result = retryOnceOnStepDown!int(op, true, false, refresh);

	assert(result == 42, "expected the second op call's result 42");
	assert(opCalls == 2, "expected op to be called twice");
	assert(refreshCalls == 1, "expected refresh to be called once");
}

/// rethrows without refresh or retry when the op is not retryable
unittest {
	import std.exception : assertThrown;

	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		throw new MongoStepDownException("primary stepped down", 10107);
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	assertThrown!MongoStepDownException(retryOnceOnStepDown!int(op, false, false, refresh));

	assert(opCalls == 1, "expected op to be called once with no retry");
	assert(refreshCalls == 0, "expected refresh to never be called");
}

/// retries at most once so a second step-down propagates instead of looping
unittest {
	import std.exception : assertThrown;

	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		throw new MongoStepDownException("primary stepped down again", 10107);
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	assertThrown!MongoStepDownException(retryOnceOnStepDown!int(op, true, false, refresh));

	assert(opCalls == 2, "expected exactly one retry, not an infinite loop");
	assert(refreshCalls == 1, "expected topology to be refreshed exactly once");
}
