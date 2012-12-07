/**
	Generic connection pool for reusing persistent connections across fibers.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.connectionpool;

import vibe.core.log;
import vibe.core.driver;

import core.thread;


/**
	Generic connection pool class.

	The connection pool is creating connections using the supplied factory function as needed
	whenever lockConnection() is called. Connections are associated to the calling fiber, as long
	as any copy of the returned LockedConnection object still exists. Connections that are not
	associated 
*/
class ConnectionPool(Connection : EventedObject)
{
	private {
		Connection delegate() m_connectionFactory;
		Connection[] m_connections;
		Connection[Fiber] m_locks;
		int[Connection] m_lockCount;
	}

	this(Connection delegate() connection_factory)
	{
		m_connectionFactory = connection_factory;
	}

	LockedConnection!Connection lockConnection()
	{
		auto fthis = Fiber.getThis();
		auto pconn = fthis in m_locks;
		if( pconn && *pconn ){
			m_lockCount[*pconn]++;
			return LockedConnection!Connection(this, *pconn);
		}

		size_t cidx = size_t.max;
		foreach( i, c; m_connections ){
			auto plc = c in m_lockCount;
			if( !plc || *plc == 0 ){
				cidx = i;
				break;
			}
		}

		if( cidx == size_t.max ){
			m_connections ~= m_connectionFactory();
			cidx = m_connections.length-1;
			if( fthis ) m_connections[cidx].release();
		}
		logDebug("returning %s connection %d of %d", Connection.stringof, cidx, m_connections.length);
		auto conn = m_connections[cidx];
		if( fthis ) conn.acquire();
		m_locks[fthis] = conn;
		m_lockCount[conn] = 1;
		auto ret = LockedConnection!Connection(this, m_connections[cidx]);
		return ret;
	}
}

struct LockedConnection(Connection : EventedObject) {
	private {
		ConnectionPool!Connection m_pool;
		Fiber m_fiber;
	}
	
	Connection m_conn;

	alias m_conn this;

	private this(ConnectionPool!Connection pool, Connection conn)
	{
		m_pool = pool;
		m_conn = conn;
		m_fiber = Fiber.getThis();
	}

	this(this)
	{
		if( m_conn ){
			auto fthis = Fiber.getThis();
			assert(fthis is m_fiber);
			m_pool.m_lockCount[m_conn]++;
			logTrace("conn %s copy %d", cast(void*)m_conn, m_pool.m_lockCount[m_conn]);
		}
	}

	~this()
	{
		if( m_conn ){
			auto fthis = Fiber.getThis();
			assert(fthis is m_fiber);
			logTrace("conn %s destroy %d", cast(void*)m_conn, m_pool.m_lockCount[m_conn]-1);
			if( --m_pool.m_lockCount[m_conn] == 0 ){
				m_pool.m_locks[m_fiber] = null;
				if( fthis ) m_conn.release();
				m_conn = null;
			}
		}
	}
}

/**
	Wraps an InputStream and automatically unlocks a locked connection as soon as all data has been
	read.
*/
class LockedInputStream(Connection : EventedObject) : InputStream {
	private {
		LockedConnection!Connection m_lock;
		InputStream m_stream;
	}


	this(LockedConnection!Connection conn, InputStream str)
	{
		m_lock = conn;
		m_stream = str;
	}

	@property bool empty() { return m_stream.empty; }

	@property ulong leastSize() { return m_stream.leastSize; }

	@property bool dataAvailableForRead() { return m_stream.dataAvailableForRead; }

	const(ubyte)[] peek() { return m_stream.peek(); }

	void read(ubyte[] dst)
	{
		m_stream.read(dst);
		if( this.empty ){
			LockedConnection!Connection unl;
			m_lock = unl;
		}
	}
}