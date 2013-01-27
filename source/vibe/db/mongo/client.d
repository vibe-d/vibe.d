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
	 * Throws: an exception if the URL cannot be parsed as a valid MongoDB URL. 
	 * 
	 * Url must be in the form documented at
	 * $(LINK http://www.mongodb.org/display/DOCS/Connections) which is:
	 * 
	 * mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
	 *
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
	 * Return: MongoCollection for the given combined database and collectiion name(path)
	 * 
	 * The full database.collection path must be specified.
	 *
	 * Example:
	 * ---
	 * auto col = client.getCollection("test.collection");
	 * ---
	 *
	 * The opIndex function of MongoDatabase class should be used to get a relative
	 * collection name where the according database is taken into consideration.
   */
	MongoCollection getCollection(string path)
	{
		return MongoCollection(this, path);
	}

	/**
	* Return: MongoDatabase instance representing requested database
	*
	* Access to database entity ( root for group of collection ).
	* Two main use cases:
	*  1) Accessing collections using relative path
	*  2) Performing service commands on database itself
	*
	* There is no performance gain in accessing collections via relative path
	* with comparison to getCollection() and absolute one.
	*
	* Example:
	* ---
	* auto db = client.getDatabase("test");
	* auto coll = db["collection"];
	* ---
*/
	MongoDatabase getDatabase(string dbName)
	{
		return MongoDatabase(this, dbName);
	}

	package auto lockConnection() { return m_connections.lockConnection(); }
}
