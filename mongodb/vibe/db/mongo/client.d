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
import vibe.db.mongo.connection;
import vibe.db.mongo.settings;
import vibe.db.mongo.topology;

import std.conv;
import std.exception : enforce;

/**
	Represents a connection to a MongoDB server.

	Note that this class uses a ConnectionPool internally to create and reuse
	network connections to the server as necessary. It should be reused for all
	fibers in a thread for optimum performance in high concurrency scenarios.
 */
final class MongoClient {
@safe:

	private {
		ConnectionPool!MongoConnection m_connections;
		MongoClientSettings m_settings;
		TopologyDescription m_topology;
		bool m_discoveryInProgress;
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

		discoverTopology();

		m_connections = new ConnectionPool!MongoConnection(
			&createConnection,
			settings.maxConnections
		);

		// force a connection to cause an exception for wrong URLs
		lockConnection();
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
		m_connections.removeUnused((conn) nothrow @safe {
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

	package LockedConnection!MongoConnection lockConnection()
	{
		foreach (_; 0 .. 100)
		{
			auto conn = m_connections.lockConnection();

			if (conn.alive)
				return conn;

			m_connections.remove(conn.__conn);
			logDiagnostic("Evicted dead MongoDB connection from pool");
		}

		throw new MongoDriverException("Failed to acquire a live connection after evicting 100 dead connections");
	}

	package MongoHost getSelectedHost()
	{
		auto selected = selectServer(m_topology, m_settings.readPreference, m_settings.localThresholdMS, m_settings.maxStalenessSeconds);
		enforce!MongoDriverException(!selected.isNull, "No suitable server found for read preference");

		return selected.get;
	}

	private MongoConnection createConnection() @safe
	{
		auto targetHost = getSelectedHost();
		auto ret = new MongoConnection(m_settings);

		try {
			ret.connectToHost(targetHost);
			return ret;
		} catch (Exception e) {
			() @trusted { destroy(ret); } ();

			logWarn("Connection to %s:%s failed: %s — re-discovering topology",
				targetHost.name, targetHost.port, e.msg);
		}

		discoverTopology();
		targetHost = getSelectedHost();

		ret = new MongoConnection(m_settings);
		try {
			ret.connectToHost(targetHost);
		} catch (Exception e2) {
			() @trusted { destroy(ret); } ();
			throw e2;
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

		foreach (host; m_settings.hosts) {
			probeAndUpdate(newTopology, host, lastException);
		}

		foreach (host; newTopology.allKnownHosts()) {
			if (newTopology.servers.canFind!(s => s.host == host))
				continue;

			probeAndUpdate(newTopology, host, lastException);
		}

		auto selected = selectServer(newTopology, m_settings.readPreference, m_settings.localThresholdMS, m_settings.maxStalenessSeconds);

		if (selected.isNull) {
			throw lastException !is null
				? lastException
				: new MongoDriverException("No suitable server found during topology discovery");
		}

		m_topology = newTopology;
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
}
