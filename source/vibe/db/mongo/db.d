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
import std.string;

/**
	Represents a single remote MongoDB.
*/
class MongoDB {
	private {
		MongoClientSettings settings;
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
		Runs a command on the specified database.

		See_Also: $(LINK http://www.mongodb.org/display/DOCS/Commands)
	*/
	Bson runCommand(string db, Bson command_and_options)
	{
		return getCollection(db~".$cmd").findOne(command_and_options);
	}

	/// See $(LINK http://www.mongodb.org/display/DOCS/getLog+Command)
	Bson getLog(string db, string mask){ return runCommand(db, Bson(["getLog" : Bson(mask)])); }

	/// See $(LINK http://www.mongodb.org/display/DOCS/fsync+Command)
	Bson fsync(string db, bool async = false){ return runCommand(db, Bson(["fsync" : Bson(1), "async" : Bson(async)])); }

	/// See $(LINK http://www.mongodb.org/display/DOCS/getLastError+Command) 
	Bson getLastError(string db){ return runCommand(db, Bson(["getlasterror" : Bson(1)])); }

	/**
		Accesses the collections inside this DB.
	 
	 	Examples:
	 	---
	 	auto db = connectMongoDB("mongodb://localhost/mydatabase");
	 	auto col = db["mycollection"];
	 
	 	auto db = connectMongoDB("mongodb://localhost");
	 	auto col = db["mydatabase.mycollection"];
	 	---

		Throws: Exception if a DB communication error occured.
	*/
	MongoCollection opIndex(string name) 
	{ 
		string realname;
			
		// If a database has been set in the MongoClientSettings prepend that name.
		if(settings.database != string.init)
		{
			if(name.startsWith("."))
				realname = settings.database ~ name;
			else 
				realname = settings.database ~ "." ~ name;
		} else {
			realname = name;
		}
		
		logTrace("Returning collection for '%s' in response to request for '%s'", realname, name);
		
		return MongoCollection(this, realname); 
	}
	
	/** 
	 * Return: MongoCollection for the given database and collecting specified.
	 * 
	 * If a default database has been set in the MongoClientSettings it is NOT used here. 
	 * The full database.collection path must be specified. 
	 *
	 * Example:
	 * ---
	 * auto col = db.getCollection("mydb.mycollection");
	 * ---
	 *  
	 * The opIndex function should be used to get a relative collection name where the 
	 * default database is taken into consideration.
	 * 
	 * Most user code should use opIndex.
	 */ 
	MongoCollection getCollection(string db_and_col)
	{
		return MongoCollection(this, db_and_col);
	}

	package auto lockConnection() { return m_connections.lockConnection(); }
}