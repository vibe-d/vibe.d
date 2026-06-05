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

import core.time : Duration, seconds, msecs;
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

		ServerProber m_prober;
		ServerMonitor[string] m_monitors;
		MongoHost[string] m_monitorHosts;
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

		m_prober = (MongoHost host) @safe => probeServer(m_settings, host);
		startMonitoring();
	}

	/// Returns the read preference configured for this client.
	@property ReadPreference readPreference() const
	{
		return m_settings.readPreference;
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

	/// Resolves the host a read should target, retrying once after re-discovering the
	/// topology. A cursor pins to this host so its getMore/killCursors stay on the same server.
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

	private MongoHost resolveHost(bool toPrimary, ReadPreference pref)
	{
		auto topology = m_topology.load();
		auto selected = selectTarget(topology, toPrimary, pref,
			m_settings.localThresholdMS, m_settings.maxStalenessSeconds);

		enforce!MongoDriverException(!selected.isNull, toPrimary
			? "No primary server available for write"
			: "No suitable server found for read preference");

		return selected.get;
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
		auto key = host.name ~ ":" ~ host.port.to!string;

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

	private static string hostKey(MongoHost host)
	{
		return host.name ~ ":" ~ host.port.to!string;
	}

	/// Spawns a background monitor for every currently-known host.
	private void startMonitoring()
	{
		foreach (host; m_topology.load().allKnownHosts())
			ensureMonitor(host);
	}

	/// Starts a monitor for `host` if one is not already running for it.
	private void ensureMonitor(MongoHost host)
	{
		auto key = hostKey(host);
		if (key in m_monitors)
			return;

		// Transitional SDAM defaults (heartbeat, min-heartbeat); PR5 replaces
		// these literals with the parsed MongoClientSettings fields.
		auto monitor = new ServerMonitor(host, m_prober, &onMonitorResult, 10.seconds, 500.msecs);
		m_monitors[key] = monitor;
		m_monitorHosts[key] = host;
		monitor.start();
	}

	private void removeMonitor(MongoHost host)
	{
		auto key = hostKey(host);
		if (key !in m_monitors)
			return;

		m_monitors[key].stop();
		m_monitors.remove(key);
		m_monitorHosts.remove(key);
	}

	/**
	 * Called by each ServerMonitor with its latest probe result. Publishes the
	 * new immutable topology snapshot, wakes anyone waiting on a topology change,
	 * then reconciles the monitor set against the (possibly newly-discovered or
	 * removed) members. Runs synchronously within the event loop, so the snapshot
	 * swap and monitor-set mutations are atomic with respect to other fibers.
	 */
	private void onMonitorResult(MongoHost host, Nullable!ServerDescription desc, Duration rtt)
	{
		auto current = m_topology.load();
		m_topology.publish(desc.isNull ? applyFailed(current, host) : applyDescription(current, host, desc.get));
		m_topologyChanged.emit();

		auto reconciliation = reconcileMonitors(m_monitorHosts.values, m_topology.load().allKnownHosts());
		foreach (added; reconciliation.toStart)
			ensureMonitor(added);
		foreach (removed; reconciliation.toStop)
			removeMonitor(removed);
	}

	/// Stops all background server monitors. Call before discarding the client.
	void stopMonitoring()
	{
		foreach (monitor; m_monitors.byValue)
			monitor.stop();
		m_monitors.clear();
		m_monitorHosts.clear();
	}
}
