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
class ConnectionPool(Connection)
{
	private {
		Connection delegate() m_connectionFactory;
		Connection[] m_connections;
		int[const(Connection)] m_lockCount;
	}

	this(Connection delegate() connection_factory)
	{
		m_connectionFactory = connection_factory;
	}

	LockedConnection!Connection lockConnection()
	{
		size_t cidx = size_t.max;
		foreach( i, c; m_connections ){
			auto plc = c in m_lockCount;
			if( !plc || *plc == 0 ){
				cidx = i;
				break;
			}
		}

		Connection conn;
		if( cidx != size_t.max ){
			logTrace("returning %s connection %d of %d", Connection.stringof, cidx, m_connections.length);
			conn = m_connections[cidx];
		} else {
			logDebug("creating new %s connection, all %d are in use", Connection.stringof, m_connections.length);
			conn = m_connectionFactory(); // NOTE: may block
			logDebug(" ... %s", cast(void*)conn);
		}
		m_lockCount[conn] = 1;
		if( cidx == size_t.max ){
			m_connections ~= conn;
			logDebug("Now got %d connections", m_connections.length);
		}
		auto ret = LockedConnection!Connection(this, conn);
		return ret;
	}
}

struct LockedConnection(Connection) {
	private {
		ConnectionPool!Connection m_pool;
		Task m_task;
		Connection m_conn;
	}
	
	private this(ConnectionPool!Connection pool, Connection conn)
	{
		assert(conn !is null);
		m_pool = pool;
		m_conn = conn;
		m_task = Task.getThis();
	}

	this(this)
	{
		if( m_conn ){
			auto fthis = Fiber.getThis();
			assert(fthis is m_task);
			m_pool.m_lockCount[m_conn]++;
			logTrace("conn %s copy %d", cast(void*)m_conn, m_pool.m_lockCount[m_conn]);
		}
	}

	~this()
	{
		if( m_conn ){
			auto fthis = Fiber.getThis();
			assert(fthis is m_task, "Locked connection destroyed in foreign fiber.");
			auto plc = m_conn in m_pool.m_lockCount;
			assert(plc !is null);
			assert(*plc >= 1);
			//logTrace("conn %s destroy %d", cast(void*)m_conn, *plc-1);
			if( --*plc == 0 ){
				//logTrace("conn %s release", cast(void*)m_conn);
			}
			m_conn = null;
		}
	}


	@property int __refCount() const { return m_pool.m_lockCount.get(m_conn, 0); }
	@property inout(Connection) __conn() inout { return m_conn; }

	alias __conn this;
}
