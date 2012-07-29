/**
	MongoDB class doing connection management.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.db;

public import vibe.db.mongo.collection;

import vibe.core.connectionpool;
import vibe.core.log;
import vibe.db.mongo.connection;

import core.thread;

import std.conv;

/**
	Represents a single remote MongoDB.
*/
class MongoDB {
	private {
		MongoConnectionConfig config;
		ConnectionPool!MongoConnection m_connections;
	}

	enum defaultPort = 27017;

	package this(string host, ushort port = defaultPort)
	{
		this("mongodb://" ~ host ~ ":" ~ to!string(port));
	}
	
	/**
	 * Throws an exception if the URL cannot be parsed as a valid MongoDB URL. 
	 * 
	 * Url must be in the form documented at
	 * http://www.mongodb.org/display/DOCS/Connections which is:
	 * 
	 * mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
	 *
	 */
	package this(string url)
	{
		auto goodUrl = parseMongoDBUrl(config, url);
		
		if(!goodUrl) throw new Exception("Unable to parse mongodb URL: " ~ url);
			
		m_connections = new ConnectionPool!MongoConnection({
				auto ret = new MongoConnection(config);
				ret.connect();
				return ret;
			});
	}

	/**
		Runs a command on the specified database.

		See_Also: http://www.mongodb.org/display/DOCS/Commands
	*/
	Bson runCommand(string db, Bson[string] command_and_options)
	{
		return this[db~".$cmd"].findOne(command_and_options);
	}

	/// See http://www.mongodb.org/display/DOCS/getLog+Command
	Bson getLog(string db, string mask){ return runCommand(db, ["getLog" : Bson(mask)]); }

	/// http://www.mongodb.org/display/DOCS/fsync+Command
	Bson fsync(string db, bool async = false){ return runCommand(db, ["fsync" : Bson(1), "async" : Bson(async)]); }

	/// http://www.mongodb.org/display/DOCS/getLastError+Command
	Bson getLastError(string db){ return runCommand(db, ["getlasterror" : Bson(1)]); }

	/**
		Accesses the collections inside this DB.

		Throws: Exception if a DB communication error occured.
	*/
	MongoCollection opIndex(string name) { return MongoCollection(this, name); }

	package auto lockConnection() { return m_connections.lockConnection(); }
}