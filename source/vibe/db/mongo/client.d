/**
	MongoClient class doing connection management. Usually this is a main entry point
	for client code.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
 */
module vibe.db.mongo.client;

public import vibe.db.mongo.collection;
public import vibe.db.mongo.database;

import vibe.core.connectionpool;
import vibe.core.log;
import vibe.db.mongo.connection;

import core.thread;

import std.conv;
import std.string;

/**
	Represents a single remote MongoClient. Abstracts away management of connections
	to mongo service.
 */
class MongoClient {
	private {
		ConnectionPool!MongoConnection m_connections;
	}

	package this(string host, ushort port = MongoConnection.defaultPort)
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

		m_connections = new ConnectionPool!MongoConnection({
			auto ret = new MongoConnection(settings);
			ret.connect();
			return ret;
		});

		// force a connection to cause an exception for wrong URLs
		lockConnection();
	}

	/**
		Accesses a collection using an absolute path.

		The full database.collection path must be specified. To access
		collections using a path relative to their database, use getDatabase in
		conjunction with MongoDatabase.opIndex.

		Returns:
			MongoCollection for the given combined database and collectiion name(path)
		
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

	package auto lockConnection() { return m_connections.lockConnection(); }
}
