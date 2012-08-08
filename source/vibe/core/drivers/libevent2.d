/**
	libevent based driver

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libevent2;

import vibe.core.driver;
import vibe.core.drivers.libevent2_tcp;
import vibe.core.drivers.threadedfile;
import vibe.core.log;
import vibe.utils.memory;

import deimos.event2.bufferevent;
import deimos.event2.dns;
import deimos.event2.event;
import deimos.event2.thread;
import deimos.event2.util;

import core.memory;
import core.stdc.stdlib;
import core.sync.condition;
import core.sync.mutex;
import core.sync.rwmutex;
import core.sys.posix.netinet.in_;
import core.sys.posix.netinet.tcp;
version(Windows) import std.c.windows.winsock;
import core.thread;
import std.conv;
import std.exception;
import std.range;
import std.string;

struct LevMutex {
	FreeListRef!Mutex mutex;
	FreeListRef!ReadWriteMutex rwmutex;
	alias FreeListObjectAlloc!(LevMutex, false, true) Alloc;
}

struct LevCondition {
	FreeListRef!Condition cond;
	LevMutex* mutex;
	alias FreeListObjectAlloc!(LevCondition, false, true) Alloc;
}

private extern(C){
	void* lev_alloc(size_t size){ return malloc(size); }
	void* lev_realloc(void* p, size_t newsize){ return realloc(p, newsize); }
	void lev_free(void* p){ free(p); }

	void* lev_alloc_mutex(uint locktype) {
		auto ret = LevMutex.Alloc.alloc();
		if( locktype == EVTHREAD_LOCKTYPE_READWRITE ) ret.rwmutex = FreeListRef!ReadWriteMutex();
		else ret.mutex = FreeListRef!Mutex();
		return ret;
	}
	void lev_free_mutex(void* lock, uint locktype) { LevMutex.Alloc.free(cast(LevMutex*)lock); }
	int lev_lock_mutex(uint mode, void* lock) {
		auto mtx = cast(LevMutex*)lock;
		
		if( mode & EVTHREAD_WRITE ){
			if( mode & EVTHREAD_TRY ) return mtx.rwmutex.writer().tryLock() ? 0 : 1;
			else mtx.rwmutex.writer().lock();
		} else if( mode & EVTHREAD_READ ){
			if( mode & EVTHREAD_TRY ) return mtx.rwmutex.reader().tryLock() ? 0 : 1;
			else mtx.rwmutex.reader().lock();
		} else {
			if( mode & EVTHREAD_TRY ) return mtx.mutex.tryLock() ? 0 : 1;
			else mtx.mutex.lock();
		}
		return 0;
	}
	int lev_unlock_mutex(uint mode, void* lock) {
		auto mtx = cast(LevMutex*)lock;

		if( mode & EVTHREAD_WRITE ){
			mtx.rwmutex.writer().unlock();
		} else if( mode & EVTHREAD_READ ){
			mtx.rwmutex.reader().unlock();
		} else {
			mtx.mutex.unlock();
		}
		return 0;
	}

	void* lev_alloc_condition(uint condtype) { return LevCondition.Alloc.alloc(); }
	void lev_free_condition(void* cond) { LevCondition.Alloc.free(cast(LevCondition*)cond); }
	int lev_signal_condition(void* cond, int broadcast) {
		auto c = cast(LevCondition*)cond;
		if( c.cond ) c.cond.notifyAll();
		return 0;
	}
	int lev_wait_condition(void* cond, void* lock, const(timeval)* timeout) {
		auto c = cast(LevCondition*)cond;
		if( c.mutex is null ) c.mutex = cast(LevMutex*)lock;
		assert(c.mutex.mutex !is null); // RW mutexes are not supported for conditions!
		assert(c.mutex is lock);
		if( c.cond is null ) c.cond = FreeListRef!Condition(c.mutex.mutex);
		if( timeout ){
			if( !c.cond.wait(dur!"seconds"(timeout.tv_sec) + dur!"usecs"(timeout.tv_usec)) )
				return 1;
		} else c.cond.wait();
		return 0;
	}

	size_t lev_get_thread_id() { return cast(size_t)cast(void*)Thread.getThis(); }
}

class Libevent2Driver : EventDriver {
	private {
		DriverCore m_core;
		event_base* m_eventLoop;
		evdns_base* m_dnsBase;
		bool m_exit = false;
	}

	this(DriverCore core)
	{
		m_core = core;
		s_driverCore = core;

		// set the malloc/free versions of our runtime so we don't run into trouble
		// because the libevent DLL uses a different one.
		event_set_mem_functions(&lev_alloc, &lev_realloc, &lev_free);

		evthread_lock_callbacks lcb;
		lcb.lock_api_version = EVTHREAD_LOCK_API_VERSION;
		lcb.supported_locktypes = EVTHREAD_LOCKTYPE_RECURSIVE|EVTHREAD_LOCKTYPE_READWRITE;
		lcb.alloc = &lev_alloc_mutex;
		lcb.free = &lev_free_mutex;
		lcb.lock = &lev_lock_mutex;
		lcb.unlock = &lev_unlock_mutex;
		evthread_set_lock_callbacks(&lcb);

		evthread_condition_callbacks ccb;
		ccb.condition_api_version = EVTHREAD_CONDITION_API_VERSION;
		ccb.alloc_condition = &lev_alloc_condition;
		ccb.free_condition = &lev_free_condition;
		ccb.signal_condition = &lev_signal_condition;
		ccb.wait_condition = &lev_wait_condition;
		evthread_set_condition_callbacks(&ccb);

		evthread_set_id_callback(&lev_get_thread_id);

		// initialize libevent
		logDebug("libevent version: %s", to!string(event_get_version()));
		m_eventLoop = event_base_new();
		s_eventLoop = m_eventLoop;
		logDebug("libevent is using %s for events.", to!string(event_base_get_method(m_eventLoop)));
		evthread_make_base_notifiable(m_eventLoop);
		
		m_dnsBase = evdns_base_new(m_eventLoop, 1);
		if( !m_dnsBase ) logError("Failed to initialize DNS lookup.");
	}

	~this()
	{
		s_alreadyDeinitialized = true;
		evdns_base_free(m_dnsBase, 1);
		event_base_free(m_eventLoop);
	}

	@property event_base* eventLoop() { return m_eventLoop; }
	@property evdns_base* dnsEngine() { return m_dnsBase; }

	int runEventLoop()
	{
		int ret;
		while( !m_exit && (ret = event_base_loop(m_eventLoop, EVLOOP_ONCE)) == 0 )
			s_driverCore.notifyIdle();
		return ret;
	}

	int runEventLoopOnce()
	{
		auto ret = event_base_loop(m_eventLoop, EVLOOP_ONCE);
		m_core.notifyIdle();
		return ret;
	}

	int processEvents()
	{
		auto ret = event_base_loop(m_eventLoop, EVLOOP_NONBLOCK);
		m_core.notifyIdle();
		return ret;
	}

	void exitEventLoop()
	{
		m_exit = true;
		enforce(event_base_loopbreak(m_eventLoop) == 0, "Failed to exit libevent event loop.");
	}

	FileStream openFile(string path, FileMode mode)
	{
		return new ThreadedFileStream(path, mode);
	}

	TcpConnection connectTcp(string host, ushort port)
	{
		auto af = AF_INET;
		auto sockfd = socket(af, SOCK_STREAM, 0);
		enforce(sockfd != -1, "Failed to create socket.");
		
		if( evutil_make_socket_nonblocking(sockfd) )
			throw new Exception("Failed to make socket non-blocking.");
			
		auto buf_event = bufferevent_socket_new(m_eventLoop, sockfd, bufferevent_options.BEV_OPT_CLOSE_ON_FREE);
		if( !buf_event ) throw new Exception("Failed to create buffer event for socket.");

		auto cctx = TcpContext.Alloc.alloc(m_core, m_eventLoop, sockfd, buf_event);
		cctx.task = Task.getThis();
		bufferevent_setcb(buf_event, &onSocketRead, &onSocketWrite, &onSocketEvent, cctx);
		if( bufferevent_enable(buf_event, EV_READ|EV_WRITE) )
			throw new Exception("Error enabling buffered I/O event for socket.");

		if( bufferevent_socket_connect_hostname(buf_event, m_dnsBase, af, toStringz(host), port) )
			throw new Exception("Failed to connect to host "~host~" on port "~to!string(port));

	// TODO: cctx.remove_addr6 = ...;
			
		while( cctx.status == 0 )
			m_core.yieldForEvent();
			
		logTrace("Connect result status: %d", cctx.status);
		
		if( cctx.status != BEV_EVENT_CONNECTED )
			throw new Exception("Failed to connect to host "~host~" on port "~to!string(port)~": "~to!string(cctx.status));

		return new Libevent2TcpConnection(cctx);
	}

	void listenTcp(ushort port, void delegate(TcpConnection conn) connection_callback, string address)
	{
		sockaddr_in addr_ip4;
		addr_ip4.sin_family = AF_INET;
		addr_ip4.sin_port = htons(port);
		auto ret = evutil_inet_pton(AF_INET, toStringz(address), &addr_ip4.sin_addr);
		if( ret == 1 ){
			auto rc = listenTcpGeneric(AF_INET, &addr_ip4, port, connection_callback);
			logInfo("Listening on %s port %d %s", address, port, (rc==0?"succeeded":"failed"));
			return;
		}

		sockaddr_in6 addr_ip6;
		addr_ip6.sin6_family = AF_INET6;
		addr_ip6.sin6_port = htons(port);
		ret = evutil_inet_pton(AF_INET6, toStringz(address), &addr_ip6.sin6_addr);
		if( ret == 1 ){
			auto rc = listenTcpGeneric(AF_INET6, &addr_ip6, port, connection_callback);
			logInfo("Listening on %s port %d %s", address, port, (rc==0?"succeeded":"failed"));
			return;
		}

		enforce(false, "Invalid IP address string: '"~address~"'");
	}

	Libevent2Signal createSignal()
	{
		return new Libevent2Signal(this);
	}

	Libevent2Timer createTimer(void delegate() callback)
	{
		return new Libevent2Timer(this, callback);
	}

	private int listenTcpGeneric(SOCKADDR)(int af, SOCKADDR* sock_addr, ushort port, void delegate(TcpConnection conn) connection_callback)
	{
		auto listenfd = socket(af, SOCK_STREAM, 0);
		if( listenfd == -1 ){
			logError("Error creating listening socket> %s", af);
			return -1;
		}
		int tmp_reuse = 1; 
		if( setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof) ){
			logError("Error enabling socket address reuse on listening socket");
			return -1;
		}
		if( bind(listenfd, cast(sockaddr*)sock_addr, SOCKADDR.sizeof) ){
			logError("Error binding listening socket");
			return -1;
		}
		if( listen(listenfd, 128) ){
			logError("Error listening to listening socket");
			return -1;
		}

		// Set socket for non-blocking I/O
		if( evutil_make_socket_nonblocking(listenfd) ){
			logError("Error setting listening socket to non-blocking I/O.");
			return -1;
		}
		
		version(Windows){} else evutil_make_listen_socket_reuseable(listenfd);

		// Add an event to wait for connections
		auto ctx = TcpContext.Alloc.alloc(m_core, m_eventLoop, listenfd, null, *sock_addr);
		ctx.connectionCallback = connection_callback;
		auto connect_event = event_new(m_eventLoop, listenfd, EV_READ | EV_PERSIST, &onConnect, ctx);
		if( event_add(connect_event, null) ){
			logError("Error scheduling connection event on the event loop.");
		}
		
		// TODO: do something with connect_event (at least store somewhere for clean up)
		
		return 0;
	}
}

class Libevent2Signal : Signal {
	private {
		Libevent2Driver m_driver;
		event* m_event;
		bool[Task] m_listeners;
		int m_emitCount = 0;
	}

	this(Libevent2Driver driver)
	{
		m_driver = driver;
		m_event = event_new(m_driver.eventLoop, -1, EV_PERSIST, &onSignalTriggered, cast(void*)this);
		event_add(m_event, null);
	}

	~this()
	{
		if( !s_alreadyDeinitialized )
			event_free(m_event);
	}

	void emit()
	{
		event_active(m_event, 0, 0);
	}

	void wait()
	{
		wait(m_emitCount);
	}

	void wait(int reference_emit_count)
	{
		assert(!isOwner());
		auto self = Fiber.getThis();
		acquire();
		scope(exit) release();
		while( m_emitCount == reference_emit_count )
			m_driver.m_core.yieldForEvent();
	}

	void acquire()
	{
		m_listeners[Task.getThis()] = true;
	}

	void release()
	{
		auto self = Task.getThis();
		if( isOwner() )
			m_listeners.remove(self);
	}

	bool isOwner()
	{
		return (Task.getThis() in m_listeners) !is null;
	}

	@property int emitCount() const { return m_emitCount; }
}

class Libevent2Timer : Timer {
	private {
		Libevent2Driver m_driver;
		Task m_owner;
		void delegate() m_callback;
		event* m_event;
		bool m_pending;
		bool m_periodic;
		timeval m_timeout;
	}

	this(Libevent2Driver driver, void delegate() callback)
	{
		m_driver = driver;
		m_callback = callback;
		m_event = event_new(m_driver.eventLoop, -1, 0, &onTimerTimeout, cast(void*)this);
	}

	~this()
	{
		if( !s_alreadyDeinitialized ){
			stop();
			event_free(m_event);
		}
	}

	void acquire()
	{
		assert(m_owner is null);
		m_owner = Task.getThis();
	}

	void release()
	{
		assert(m_owner is Fiber.getThis());
		m_owner = null;
	}

	bool isOwner()
	{
		return m_owner !is null && m_owner is Fiber.getThis();
	}

	@property bool pending()
	{
		return m_pending;
	}

	void rearm(Duration timeout, bool periodic = false)
	{
		stop();

		assert(timeout.total!"seconds"() <= int.max);
		m_timeout.tv_sec = cast(int)timeout.total!"seconds"();
		m_timeout.tv_usec = timeout.fracSec().usecs();
		assert(m_timeout.tv_sec > 0 || m_timeout.tv_usec > 0);
		event_add(m_event, &m_timeout);
		assert(event_pending(m_event, EV_TIMEOUT, null));
		m_pending = true;
		m_periodic = periodic;
	}

	void stop() nothrow
	{
		if( m_event ){
			event_del(m_event);
		}
		m_pending = false;
	}

	void wait()
	{
		acquire();
		scope(exit) release();

		while( pending )
			m_driver.m_core.yieldForEvent();
	}
}

private {
	event_base* s_eventLoop; // TLS
	__gshared DriverCore s_driverCore;
	shared s_alreadyDeinitialized = false;
}

package event_base* getThreadLibeventEventLoop()
{
	return s_eventLoop;
}

package DriverCore getThreadLibeventDriverCore()
{
	return s_driverCore;
}


private extern(C) nothrow
{
	void onSignalTriggered(evutil_socket_t, short events, void* userptr)
	{
		auto sig = cast(Libevent2Signal)userptr;

		sig.m_emitCount++;

		bool[Task] lst;
		try {
			lst = sig.m_listeners.dup;
			foreach( l, _; lst )
				sig.m_driver.m_core.resumeTask(l);
		} catch( Exception e ){
			logError("Exception while handling signal event: %s", e.msg);
			debug assert(false);
		}
	}

	void onTimerTimeout(evutil_socket_t, short events, void* userptr)
	{
		auto tm = cast(Libevent2Timer)userptr;
		logTrace("Timer event %s/%s", tm.m_pending, tm.m_periodic);
		if( !tm.m_pending ) return;
		try {
			if( tm.m_periodic ){
				event_del(tm.m_event);
				event_add(tm.m_event, &tm.m_timeout);
			} else {
				tm.stop();
			}

			runTask(tm.m_callback);
		} catch( Exception e ){
			logError("Exception while handling timer event: %s", e.msg);
			debug assert(false);
		}
	}
}
