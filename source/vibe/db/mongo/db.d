/**
	MongoDB class doing connection management.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.db;

public import vibe.db.mongo.collection;

import vibe.db.mongo.connection;
import vibe.core.log;

import core.thread;


/**
	Represents a single remote MongoDB.
*/
class MongoDB {
	private {
		string m_host;
		ushort m_port;
		MongoConnection[] m_connections;
		MongoConnection[Fiber] m_locks;
		int[MongoConnection] m_lockCount;
	}

	enum defaultPort = 27017;

	package this(string host, ushort port = defaultPort)
	{
		m_host = host;
		m_port = port;
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
	MongoCollection opIndex(string name){
		return MongoCollection(this, name);
	}

	package LockedConnection lockConnection()
	{
		auto fthis = Fiber.getThis();
		if( auto pconn = fthis in m_locks ){
			m_lockCount[*pconn]++;
			return LockedConnection(this, *pconn);
		}

		size_t cidx = size_t.max;
		foreach( i, c; m_connections )
			if( c !in m_lockCount ){
				cidx = i;
				break;
			}

		if( cidx == size_t.max ){
			m_connections ~= new MongoConnection(m_host, m_port);
			cidx = m_connections.length-1;
			m_connections[cidx].connect();
			if( fthis ) m_connections[cidx].release();
		}
		logDebug("returning mongo connection %d of %d", cidx, m_connections.length);
		auto conn = m_connections[cidx];
		if( fthis ) conn.acquire();
		m_locks[fthis] = conn;
		m_lockCount[conn] = 1;
		auto ret = LockedConnection(this, m_connections[cidx]);
		return ret;
	}
}


package struct LockedConnection {
	private {
		MongoDB m_db;
		Fiber m_fiber;
	}
		MongoConnection m_conn;

	alias m_conn this;

	private this(MongoDB db, MongoConnection conn)
	{
		m_db = db;
		m_conn = conn;
		m_fiber = Fiber.getThis();
	}

	this(this)
	{
		if( m_conn ){
			auto fthis = Fiber.getThis();
			assert(fthis is m_fiber);
			m_db.m_lockCount[m_conn]++;
			logTrace("conn %s copy %d", cast(void*)m_conn, m_db.m_lockCount[m_conn]);
		}
	}

	~this()
	{
		if( m_conn ){
			auto fthis = Fiber.getThis();
			assert(fthis is m_fiber);
			logTrace("conn %s destroy %d", cast(void*)m_conn, m_db.m_lockCount[m_conn]-1);
			if( --m_db.m_lockCount[m_conn] == 0 ){
				m_db.m_locks.remove(m_fiber);
				m_db.m_lockCount.remove(m_conn);
				if( fthis ) m_conn.release();
				m_conn = null;
			}
		}
	}
}
