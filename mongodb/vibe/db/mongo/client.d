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
import vibe.db.mongo.impl.bulkwrite;
import vibe.db.mongo.impl.serversession : ServerSession, ServerSessionPool, MongoClientSession, endSessionsCommand;
import vibe.db.mongo.impl.wireversion : WireVersion;
import vibe.db.mongo.impl.changestream;
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
	// OS threads. The connection pools, the session pool, m_topologyChanged
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
		ServerSessionPool m_sessionPool;
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
			// In load-balancer mode discoverTopology() fixes the topology to the single
			// configured host without probing; otherwise it runs full SDAM discovery.
			discoverTopology();

			// The monitor registry is always constructed so its call sites
			// (handleStaleCommandError / stopMonitoring / activeMonitorCount, and
			// resolveHost's requestAllChecks) operate on a real object, never a null. It
			// is built BEFORE lockConnection() so server selection during that connect
			// cannot dereference a null registry. In load-balancer mode the LB owns server
			// health, so the registry is left empty (no reconcile = no monitors started).
			ServerProber prober = (MongoHost host) @safe => probeServer(m_settings, host);
			m_monitors = new MonitorRegistry(prober, &onMonitorResult,
				m_settings.heartbeatFrequencyMS.msecs, m_settings.minHeartbeatFrequencyMS.msecs);

			// force a connection to cause an exception for wrong URLs (and, in
			// load-balancer mode, to run the serviceId-required handshake check)
			lockConnection();

			// Start the monitors only after the connection succeeds, so a ctor failure
			// does not leak background monitor tasks.
			if (!m_settings.loadBalanced)
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

	/** Starts an explicit logical session.

		The returned handle carries a logical session id (`lsid`) drawn from the
		client's session pool. Call `endSession()` on it when done to return the
		underlying server session to the pool for reuse.
	*/
	MongoClientSession startSession()
	{
		return MongoClientSession(m_sessionPool.acquire(), &releaseServerSession, &runSessionCommand);
	}

	/// Runs a session control command (commitTransaction/abortTransaction) on the primary.
	private Bson runSessionCommand(Bson command) @safe
	{
		return lockConnectionToPrimary().runCommand("admin", command);
	}

	/// Checks out a server session for an implicit session on a single operation.
	package ServerSession acquireServerSession()
	{
		return m_sessionPool.acquire();
	}

	/// Returns a server session to the pool once its operation (or explicit session) ends.
	package void releaseServerSession(ServerSession session)
	{
		m_sessionPool.release(session);
	}

	/// Whether retryable writes are enabled for this client.
	@property bool retryWrites() const
	{
		return m_settings.retryWrites;
	}

	/// Whether the current deployment accepts retryable writes. Standalone
	/// servers (topology type `single`) reject `lsid`/`txnNumber` with
	/// "Transaction numbers are only allowed on a replica set member or mongos",
	/// so retryable writes apply only to replica sets and sharded clusters.
	package bool supportsRetryableWrites()
	{
		return vibe.db.mongo.topology.supportsRetryableWrites(m_topology.load().type);
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
		Performs a server-level bulk write (MongoDB 8.0+) across one or more
		collections and databases in a single command.

		Each `ClientBulkWriteModel` describes one insert/update/replace/delete
		operation targeting a `db.collection` namespace; build them with the
		`ClientBulkWriteModel.insertOne`/`updateOne`/... factories. The command runs
		on the `admin` database against the primary, and its result cursor is fully
		drained (via `getMore`) before parsing.

		Params:
			models = the write operations to perform (must be non-empty)
			options = command-level options (ordered, verboseResults, writeConcern, ...)

		Returns:
			A `ClientBulkWriteResult` summarizing the writes. When
			`options.verboseResults` is set, the per-operation result maps are
			populated, keyed by operation index.

		Throws:
			$(D MongoException) if the server does not support the `bulkWrite`
			command (MongoDB < 8.0). $(D MongoClientBulkWriteException) if individual
			operations fail or a write-concern error occurs; its `partialResult`
			carries the summary counts for the writes that did apply.
	*/
	ClientBulkWriteResult bulkWrite(ClientBulkWriteModel[] models,
		ClientBulkWriteOptions options = ClientBulkWriteOptions.init)
	{
		import std.string : indexOf;

		models = ensureInsertIds(models);
		const verbose = !options.verboseResults.isNull && options.verboseResults.get;
		// TODO(L16.1 — batch splitting): the spec requires splitting into multiple commands
		// when the op count exceeds maxWriteBatchSize or the encoded command exceeds
		// maxMessageSizeBytes. The pure partitioner (partitionBulkWriteOps in impl.bulkwrite,
		// fully unit-tested) is landed and ready; wiring it in needs three connection-bound
		// pieces that are deferred to keep the suite green: (1) capturing the server's real
		// maxWriteBatchSize/maxMessageSizeBytes (ServerDescription does not yet deserialize them
		// from the hello reply — partitionBulkWriteOps currently has defaultMax* fallbacks);
		// (2) offsetting each batch response's per-op `idx`/error indices by the batch start so
		// the merged verbose/error maps stay globally indexed; (3) honoring ordered=true by
		// stopping after the first batch that reports a write error. Until then a single command
		// is sent, which is correct for every write within the protocol default limits.
		Bson cmd = buildClientBulkWriteCommand(models, options);

		// The command runs on the primary (runWriteCommandChecked), so the 8.0 wire-version
		// gate must be evaluated against the primary too — a read-preference-selected secondary
		// may advertise a different version than the host the write actually reaches.
		{
			auto primary = lockConnectionToPrimary();
			enforce(primary.description.maxWireVersion >= WireVersion.v80,
				"bulkWrite requires a MongoDB 8.0+ server");
		}

		// TODO(L13.3 — bulkWrite getMore primary pinning): the result cursor is created on the
		// primary by runWriteCommandChecked, but the getMore loop below re-resolves the primary
		// through admin.runCommandChecked(toPrimary=true) on each call. After a step-down between
		// batches, getMore targets the NEW primary and fails with CursorNotFound, whereas
		// MongoFindCursor pins the cursor to its creating host (captured m_pinnedHost, reused via
		// lockConnectionToHost). Fixing this requires runWriteCommandChecked to surface the
		// LockedConnection/host it used so the same connection can be re-locked for getMore and
		// the failure-path killCursors; that plumbing is connection-bound and deferred.
		auto admin = getDatabase("admin");
		Bson response = admin.runWriteCommandChecked(cmd);

		// A w:0 (unacknowledged) bulkWrite returns ok:1 with no cursor; skip cursor
		// draining and let parseClientBulkWriteResult report acknowledged=false.
		if (!response.tryIndex("cursor").isNull)
		{
			Bson cursor = response["cursor"];
			Bson[] entries = cursor["firstBatch"].get!(Bson[]);
			long cursorId = cursor["id"].get!long;

			if (cursorId != 0) {
				string ns = cursor["ns"].get!string;
				string collection = ns[ns.indexOf('.') + 1 .. $];

				// A throw mid-drain (e.g. a getMore network error) must not orphan the open
				// server-side cursor: kill it on the way out. Mirrors MongoCursor's destructor,
				// which calls killCursors when an unconsumed cursor is dropped.
				scope(failure)
					killBulkWriteCursor(admin, collection, cursorId);

				while (cursorId != 0) {
					Bson getMoreCmd = Bson.emptyObject; // order matters: getMore must be the first field
					getMoreCmd["getMore"] = Bson(cursorId);
					getMoreCmd["collection"] = Bson(collection);
					Bson more = admin.runCommandChecked(getMoreCmd, __FUNCTION__, __FILE__, __LINE__, true);
					Bson moreCursor = more["cursor"];
					entries ~= moreCursor["nextBatch"].get!(Bson[]);
					cursorId = moreCursor["id"].get!long;
				}

				Bson[string] drainedCursor;
				foreach (string key, value; cursor.byKeyValue)
					drainedCursor[key] = value;
				drainedCursor["firstBatch"] = Bson(entries);
				response["cursor"] = Bson(drainedCursor);
			}
		}

		return parseClientBulkWriteResult(response, models, verbose);
	}

	/// Best-effort kill of an open server-level bulkWrite result cursor on the admin db, used
	/// when draining the cursor throws so the server is not left holding an orphaned cursor.
	/// Swallows errors from the kill itself: the original drain failure is the one worth surfacing.
	private void killBulkWriteCursor(MongoDatabase admin, string collection, long cursorId) @safe nothrow
	{
		if (cursorId == 0)
			return;

		try {
			Bson kill = Bson.emptyObject; // order matters: killCursors must be the first field
			kill["killCursors"] = Bson(collection);
			kill["cursors"] = Bson([Bson(cursorId)]);
			admin.runCommandUnchecked(kill, __FUNCTION__, __FILE__, __LINE__, true);
		} catch (Exception e) {
			logWarn("Failed to kill orphaned bulkWrite cursor %s: %s", cursorId, e.msg);
		}
	}

	/** Opens a change stream over the entire deployment (all databases).

		Returns a ChangeStream input range that tracks resume tokens and resumes on
		transient errors. Requires a replica set or sharded cluster.

		See_Also: $(LINK https://www.mongodb.com/docs/manual/changeStreams/)
	*/
	ChangeStream!R watch(R = Bson, S = Bson)(S[] pipeline = null, ChangeStreamOptions options = ChangeStreamOptions.init) @safe
	{
		options.allChangesForCluster = true;
		return getDatabase("admin").watch!(R, S)(pipeline, options);
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

		// Load-balancer mode runs no SDAM because the topology is fixed to the single
		// configured host and the load balancer fronts the real backends, so there
		// is nothing to probe or monitor. The serviceId check fires on first connect.
		if (m_settings.loadBalanced)
		{
			publishTopology(loadBalancedTopology(m_settings.hosts[0]));
			return;
		}

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

	/// Publishes a new topology snapshot and notifies waiters, then recomputes
	/// the session timeout from the snapshot.
	private void publishTopology(TopologyDescription topology)
	{
		m_topology.publish(topology);
		m_topologyChanged.emit();
		refreshSessionTimeout();
	}

	/// Recomputes the session pool's idle timeout from the topology-advertised
	/// logical session timeout (the MIN across data-bearing servers).
	private void refreshSessionTimeout()
	{
		import std.algorithm : map;
		import std.array : array;
		auto servers = m_topology.load().servers.map!(r => r.description).array;
		m_sessionPool.updateTimeout(sessionPoolTimeout(logicalSessionTimeout(servers)));
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
		endPooledSessions();
		m_monitors.stopAll();
	}

	/// Tears the client all the way down: ends pooled sessions, stops the background
	/// monitors, disconnects the idle pooled connections, and drops every connection
	/// pool. Call before discarding a client to release its background tasks and
	/// sockets. endPooledSessions and cleanupConnections both need a live pool, so they
	/// run before the pools are dropped. Connections still checked out by an in-flight
	/// operation are closed when that operation returns them.
	void close()
	{
		stopMonitoring();
		cleanupConnections();
		m_connectionPools = null;
	}

	/// Asks the server, on a best-effort basis, to free this client's pooled logical sessions.
	private void endPooledSessions()
	{
		auto lsids = m_sessionPool.takeAllLsids();
		if (!lsids.length)
			return;

		try
			getDatabase("admin").runCommandUnchecked(endSessionsCommand(lsids));
		catch (Exception e)
			logDiagnostic("endSessions on shutdown failed: %s", e.msg);
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
	process), ends pooled sessions, and drains the connection pools.

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

	/// Wraps `client`, closing it (stop monitors, end sessions, drain pools) when the
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

/// Maps a topology-advertised logical session timeout to the session pool's idle window.
///
/// A null `advertised` means at least one data-bearing server does not advertise a
/// logicalSessionTimeout (e.g. a pre-3.6 member) — the sessions spec treats sessions as
/// unsupported in that case. Rather than silently keeping a previously-known (now stale)
/// timeout, we collapse the window to zero so every pooled session expires immediately and
/// no stale lsid is reused once session support is lost.
Nullable!Duration sessionPoolTimeout(Nullable!Duration advertised) @safe pure nothrow
{
	import core.time : Duration;
	return advertised.isNull ? Nullable!Duration(Duration.zero) : advertised;
}

/// sessionPoolTimeout passes a present timeout through and collapses a null one to zero
unittest
{
	import core.time : minutes, Duration;

	// a server-advertised timeout is used as-is for the idle window
	auto present = sessionPoolTimeout(Nullable!Duration(30.minutes));
	assert(!present.isNull && present.get == 30.minutes,
		"an advertised session timeout is passed through unchanged");

	// no advertised timeout (sessions unsupported) collapses the window so pooled sessions expire at once
	auto absent = sessionPoolTimeout(Nullable!Duration.init);
	assert(!absent.isNull && absent.get == Duration.zero,
		"a null advertised timeout marks sessions unsupported by expiring pooled sessions immediately");
}

/// Whether a failed op may be retried: idempotent reads and/or session-supported writes.
struct RetryPolicy
{
	bool idempotent;
	bool sessionSupport;
}

/// Whether a failed op may be retried once: a raw network failure (on an
/// idempotent read or a session-supported write), a step-down/stale-topology
/// error, or a retryable-write error.
bool isRetryableError(MongoDriverException e, RetryPolicy policy) @safe
{
	bool networkRetryable = (cast(MongoNetworkException) e !is null) && (policy.idempotent || policy.sessionSupport);
	return networkRetryable
		|| shouldRetryAfterStepDown(e.code, policy.idempotent, policy.sessionSupport)
		|| shouldRetryWrite(e.code, policy.sessionSupport);
}

/// isRetryableError classifies network, step-down and retryable-write failures
unittest
{
	auto network = new MongoNetworkException("connection reset");
	assert(isRetryableError(network, RetryPolicy(true, false)), "a network failure on an idempotent read is retryable");
	assert(isRetryableError(network, RetryPolicy(false, true)), "a network failure on a session-supported write is retryable");
	assert(!isRetryableError(network, RetryPolicy(false, false)), "a network failure with neither idempotence nor session support is not retryable");

	auto stepDown = new MongoStepDownException("stepped down", MongoServerErrorCode.notWritablePrimary);
	assert(isRetryableError(stepDown, RetryPolicy(true, false)), "an idempotent step-down error is retryable");
	assert(!isRetryableError(stepDown, RetryPolicy(false, false)), "a step-down error without idempotence or session support is not retryable");

	auto writeError = new MongoDriverException("network timeout");
	writeError.code = MongoServerErrorCode.networkTimeout;
	assert(isRetryableError(writeError, RetryPolicy(false, true)), "a retryable-write code on a session-supported write is retryable");
	assert(!isRetryableError(writeError, RetryPolicy(false, false)), "a retryable-write code without session support is not retryable");

	auto duplicateKey = new MongoDriverException("duplicate key");
	duplicateKey.code = MongoServerErrorCode.duplicateKey;
	assert(!isRetryableError(duplicateKey, RetryPolicy(true, true)), "a non-retryable error code is never retried");
}

/// Surfaces a retryable writeConcernError as a throw so the write-retry path re-sends the
/// (txnNumber-deduplicated) write. A no-op for a clean reply, a non-retryable code, or a
/// write without session support (which cannot be retried anyway).
void enforceWriteConcernRetry(Bson reply, bool sessionSupport) @safe
{
	auto code = writeConcernErrorCode(reply);
	if (!shouldRetryWrite(code, sessionSupport))
		return;
	auto e = new MongoDriverException("retryable writeConcernError");
	e.code = code;
	throw e;
}

/// enforceWriteConcernRetry surfaces a retryable writeConcernError so the write is retried
unittest
{
	import std.exception : assertThrown, assertNotThrown;

	auto shutdownReply = Bson([
		"ok": Bson(1.0),
		"writeConcernError": Bson(["code": Bson(91), "errmsg": Bson("ShutdownInProgress")])
	]);

	assertThrown!MongoDriverException(enforceWriteConcernRetry(shutdownReply, true),
		"a retryable writeConcernError on a session-supported write is surfaced for retry");
	assertNotThrown(enforceWriteConcernRetry(shutdownReply, false),
		"without session support the write cannot be retried, so it is not converted to a throw");
	assertNotThrown(enforceWriteConcernRetry(Bson(["ok": Bson(1.0)]), true),
		"a clean reply does not throw");
	assertNotThrown(enforceWriteConcernRetry(Bson(["ok": Bson(1.0),
		"writeConcernError": Bson(["code": Bson(11000)])]), true),
		"a non-retryable writeConcernError code is not retried");
}

/// retries the op once, after refreshing topology, when the first call fails with a
/// retryable error, meaning a raw network failure, a step-down/stale-topology error, or a
/// retryable-write error.
T retryOnceOnRetryableError(T)(scope T delegate() @safe op, RetryPolicy policy, scope void delegate() @safe refresh) @safe
{
	try
		return op();
	catch (MongoDriverException e)
	{
		if (!isRetryableError(e, policy))
			throw e;
		refresh();
		return op();
	}
}

/// retries once after refreshing topology when the first call hits a step-down (retryable) error
unittest {
	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		if (opCalls == 1)
			throw new MongoStepDownException("primary stepped down", MongoServerErrorCode.notWritablePrimary);
		return 42;
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	auto result = retryOnceOnRetryableError!int(op, RetryPolicy(true, false), refresh);

	assert(result == 42, "expected the second op call's result 42");
	assert(opCalls == 2, "expected op to be called twice");
	assert(refreshCalls == 1, "expected refresh to be called once");
}

/// retries a retryable-write code that is not a stale-topology code when session support is on
unittest {
	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		if (opCalls == 1)
			throw new MongoStepDownException("network timeout", MongoServerErrorCode.networkTimeout);
		return 42;
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	auto result = retryOnceOnRetryableError!int(op, RetryPolicy(false, true), refresh);

	assert(result == 42, "a retryable-write error is retried once and returns the second attempt");
	assert(opCalls == 2, "the write op is retried exactly once");
	assert(refreshCalls == 1, "the retry refreshes the topology");
}

/// retries a plain MongoDriverException carrying a retryable-write code when session support is on
unittest {
	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		if (opCalls == 1)
		{
			auto e = new MongoDriverException("network timeout");
			e.code = MongoServerErrorCode.networkTimeout;
			throw e;
		}
		return 7;
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	auto result = retryOnceOnRetryableError!int(op, RetryPolicy(false, true), refresh);

	assert(result == 7, "a code-carrying retryable command error is retried once");
	assert(opCalls == 2, "the op is retried exactly once");
	assert(refreshCalls == 1, "the retry refreshes first");
}

/// rethrows without refresh or retry when the op is not retryable
unittest {
	import std.exception : assertThrown;

	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		throw new MongoStepDownException("primary stepped down", MongoServerErrorCode.notWritablePrimary);
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	assertThrown!MongoStepDownException(retryOnceOnRetryableError!int(op, RetryPolicy(false, false), refresh));

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
		throw new MongoStepDownException("primary stepped down again", MongoServerErrorCode.notWritablePrimary);
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	assertThrown!MongoStepDownException(retryOnceOnRetryableError!int(op, RetryPolicy(true, false), refresh));

	assert(opCalls == 2, "expected exactly one retry, not an infinite loop");
	assert(refreshCalls == 1, "expected topology to be refreshed exactly once");
}

/// retries a codeless MongoNetworkException once when session support is on
unittest {
	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		if (opCalls == 1)
			throw new MongoNetworkException("connection reset");
		return 7;
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	auto result = retryOnceOnRetryableError!int(op, RetryPolicy(false, true), refresh);

	assert(result == 7, "a network failure on a session-supported write is retried once");
	assert(opCalls == 2, "the op is retried exactly once");
	assert(refreshCalls == 1, "the retry refreshes first");
}

/// does not retry a network failure on a write with neither session support nor idempotence
unittest {
	import std.exception : assertThrown;

	int opCalls = 0;
	int refreshCalls = 0;

	int delegate() @safe op = () @safe {
		opCalls++;
		throw new MongoNetworkException("connection reset");
	};

	void delegate() @safe refresh = () @safe {
		refreshCalls++;
	};

	assertThrown!MongoNetworkException(retryOnceOnRetryableError!int(op, RetryPolicy(false, false), refresh));

	assert(opCalls == 1, "a network failure without session support or idempotence is not retried");
	assert(refreshCalls == 0, "no refresh when the error is not retried");
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
