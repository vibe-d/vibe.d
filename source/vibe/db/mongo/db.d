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


/**
	Represents a single remote MongoDB.
*/
class MongoDB {
	private {
		string m_host;
		ushort m_port;
		ConnectionPool!MongoConnection m_connections;
	}

	enum defaultPort = 27017;

	package this(string host, ushort port = defaultPort)
	{
		m_host = host;
		m_port = port;
		m_connections = new ConnectionPool!MongoConnection({
				auto ret = new MongoConnection(m_host, m_port);
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
