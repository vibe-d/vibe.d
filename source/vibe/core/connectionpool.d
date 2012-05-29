/**
	Generic connection pool for reusing persistent connections across fibers.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.connectionpool;

import vibe.core.log;
import vibe.core.driver;

import core.thread;


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

	LockedConnection lockConnection()
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
			m_connections ~= m_connectionFactory();
			cidx = m_connections.length-1;
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

	static struct LockedConnection {
		private {
			ConnectionPool m_pool;
			Fiber m_fiber;
		}
		
		Connection m_conn;

		alias m_conn this;

		private this(ConnectionPool pool, Connection conn)
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
					m_pool.m_locks.remove(m_fiber);
					m_pool.m_lockCount.remove(m_conn);
					if( fthis ) m_conn.release();
					m_conn = null;
				}
			}
		}
	}
}