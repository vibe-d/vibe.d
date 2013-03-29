/**
	libevent based driver

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libevent2;

version(VibeLibeventDriver)
{

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
import core.stdc.config;
import core.stdc.errno;
import core.stdc.stdlib;
import core.sync.condition;
import core.sync.mutex;
import core.sync.rwmutex;
import core.sys.posix.netinet.in_;
import core.sys.posix.netinet.tcp;
version(Windows) import std.c.windows.winsock;
import core.atomic;
import core.thread;
import std.conv;
import std.encoding : sanitize;
import std.exception;
import std.range;
import std.string;

version(Windows)
{
	alias WSAEWOULDBLOCK EWOULDBLOCK;
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
		logDiagnostic("libevent version: %s", to!string(event_get_version()));
		m_eventLoop = event_base_new();
		s_eventLoop = m_eventLoop;
		logDiagnostic("libevent is using %s for events.", to!string(event_base_get_method(m_eventLoop)));
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
		return ret;
	}

	void exitEventLoop()
	{
		m_exit = true;
		enforce(event_base_loopbreak(m_eventLoop) == 0, "Failed to exit libevent event loop.");
	}

	FileStream openFile(Path path, FileMode mode)
	{
		return new ThreadedFileStream(path, mode);
	}

	DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		assert(false);
	}

	NetworkAddress resolveHost(string host, ushort family = AF_UNSPEC, bool no_dns = false)
	{
		static immutable ushort[] addrfamilies = [AF_INET, AF_INET6];

		NetworkAddress addr;
		// first try to decode as IP address
		foreach( af; addrfamilies ){
			if( family != af && family != AF_UNSPEC ) continue;
			addr.family = af;
			void* ptr;
			if( af == AF_INET ) ptr = &addr.sockAddrInet4.sin_addr;
			else ptr = &addr.sockAddrInet6.sin6_addr;
			auto ret = evutil_inet_pton(af, toStringz(host), ptr);
			if( ret == 1 ) return addr;
		}

		enforce(!no_dns, "Invalid IP address string: "~host);

		// then try a DNS lookup
		foreach( af; addrfamilies ){
			DnsLookupInfo dnsinfo;
			dnsinfo.core = m_core;
			dnsinfo.task = Task.getThis();
			dnsinfo.addr = &addr;
			addr.family = af;

			evdns_request* dnsreq;
logDebug("dnsresolve");
			if( af == AF_INET ) dnsreq = evdns_base_resolve_ipv4(m_dnsBase, toStringz(host), 0, &onDnsResult, &dnsinfo);
			else dnsreq = evdns_base_resolve_ipv6(m_dnsBase, toStringz(host), 0, &onDnsResult, &dnsinfo);

logDebug("dnsresolve yield");
			while( !dnsinfo.done ) m_core.yieldForEvent();
logDebug("dnsresolve ret %s", dnsinfo.status);
			if( dnsinfo.status == DNS_ERR_NONE ) return addr;
		}

		throw new Exception("Failed to lookup host: "~host);
	}

	TcpConnection connectTcp(string host, ushort port)
	{
		auto addr = resolveHost(host);
		addr.port = port;

		auto sockfd = socket(addr.family, SOCK_STREAM, 0);
		enforce(sockfd != -1, "Failed to create socket.");
		
		if( evutil_make_socket_nonblocking(sockfd) )
			throw new Exception("Failed to make socket non-blocking.");
			
		auto buf_event = bufferevent_socket_new(m_eventLoop, sockfd, bufferevent_options.BEV_OPT_CLOSE_ON_FREE);
		if( !buf_event ) throw new Exception("Failed to create buffer event for socket.");

		auto cctx = TcpContextAlloc.alloc(m_core, m_eventLoop, sockfd, buf_event, addr);
		cctx.task = Task.getThis();
		bufferevent_setcb(buf_event, &onSocketRead, &onSocketWrite, &onSocketEvent, cctx);
		if( bufferevent_enable(buf_event, EV_READ|EV_WRITE) )
			throw new Exception("Error enabling buffered I/O event for socket.");

		if( bufferevent_socket_connect(buf_event, addr.sockAddr, addr.sockAddrLen) )
			throw new Exception("Failed to connect to host "~host~" on port "~to!string(port));

	// TODO: cctx.remove_addr6 = ...;
		
		try {
			while( cctx.status == 0 )
				m_core.yieldForEvent();
		} catch( Exception ){}
			
		logTrace("Connect result status: %d", cctx.status);
		
		if( cctx.status != BEV_EVENT_CONNECTED )
			throw new Exception("Failed to connect to host "~host~" on port "~to!string(port)~": "~to!string(cctx.status));

		return new Libevent2TcpConnection(cctx);
	}

	TcpListener listenTcp(ushort port, void delegate(TcpConnection conn) connection_callback, string address, TcpListenOptions options)
	{
		auto bind_addr = resolveHost(address, AF_UNSPEC, true);
		bind_addr.port = port;

		auto listenfd = socket(bind_addr.family, SOCK_STREAM, 0);
		enforce(listenfd != -1, "Error creating listening socket");
		int tmp_reuse = 1; 
		enforce(setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof) == 0,
			"Error enabling socket address reuse on listening socket");
		enforce(bind(listenfd, bind_addr.sockAddr, bind_addr.sockAddrLen) == 0,
			"Error binding listening socket");
		enforce(listen(listenfd, 128) == 0,
			"Error listening to listening socket");

		// Set socket for non-blocking I/O
		enforce(evutil_make_socket_nonblocking(listenfd) == 0,
			"Error setting listening socket to non-blocking I/O.");

		auto ret = new LibeventTcpListener;

		void setupConnectionHandler()
		{
			auto evloop = getThreadLibeventEventLoop();
			auto core = getThreadLibeventDriverCore();
			// Add an event to wait for connections
			auto ctx = TcpContextAlloc.alloc(core, evloop, listenfd, null, bind_addr);
			ctx.connectionCallback = connection_callback;
			ctx.listenEvent = event_new(evloop, listenfd, EV_READ | EV_PERSIST, &onConnect, ctx);
			enforce(event_add(ctx.listenEvent, null) == 0,
				"Error scheduling connection event on the event loop.");
			ret.addContext(ctx);
		}

		if (options & TcpListenOptions.distribute) runWorkerTaskDist(&setupConnectionHandler);
		else setupConnectionHandler();
		
		return ret;
	}

	UdpConnection listenUdp(ushort port, string bind_address = "0.0.0.0")
	{
		NetworkAddress bindaddr = resolveHost(bind_address, AF_UNSPEC, true);
		bindaddr.port = port;

		return new Libevent2UdpConnection(bindaddr, this);
	}

	Libevent2ManualEvent createManualEvent()
	{
		return new Libevent2ManualEvent;
	}

	Libevent2Timer createTimer(void delegate() callback)
	{
		return new Libevent2Timer(this, callback);
	}

	static struct DnsLookupInfo {
		NetworkAddress* addr;
		Task task;
		DriverCore core;
		bool done = false;
		int status = 0;
	}

	private static nothrow extern(C) void onDnsResult(int result, char type, int count, int ttl, void* addresses, void* arg)
	{
		auto info = cast(DnsLookupInfo*)arg;
		if( count <= 0 ){
			info.done = true;
			info.status = result;
			return;
		}
		info.done = true;
		info.status = result;
		try {
			switch( info.addr.family ){
				default: assert(false, "Unimplmeneted address family");
				case AF_INET: info.addr.sockAddrInet4.sin_addr.s_addr = *cast(uint*)addresses; break;
				case AF_INET6: info.addr.sockAddrInet6.sin6_addr.s6_addr = *cast(ubyte[16]*)addresses; break;
			}
			if( info.task && info.task.state != Fiber.State.TERM ) info.core.resumeTask(info.task);
		} catch( Throwable e ){
			logWarn("Got exception while getting DNS results: %s", e.msg);
		}
	}
}

class Libevent2ManualEvent : ManualEvent {
	private {
		struct ThreadSlot {
			Libevent2Driver driver;
			deimos.event2.event.event* event;
			bool[Task] tasks;
		}
		shared int m_emitCount = 0;
		__gshared core.sync.mutex.Mutex m_mutex;
		__gshared ThreadSlot[Thread] m_waiters;
	}

	this()
	{
		m_mutex = new core.sync.mutex.Mutex;
	}

	~this()
	{
		if( !s_alreadyDeinitialized ){
			// FIXME: this is illegal (accessing GC memory)
			foreach (ts; m_waiters)
				event_free(ts.event);
		}
	}

	void emit()
	{
		atomicOp!"+="(m_emitCount, 1);
		synchronized (m_mutex) {
			foreach (sl; m_waiters)
				event_active(sl.event, 0, 0);
		}
	}

	void wait()
	{
		wait(m_emitCount);
	}

	int wait(int reference_emit_count)
	{
		assert(!isOwner());
		auto self = Fiber.getThis();
		acquire();
		scope(exit) release();
		auto ec = this.emitCount;
		while( ec == reference_emit_count ){
			getThreadLibeventDriverCore().yieldForEvent();
			ec = this.emitCount;
		}
		return ec;
	}

	void acquire()
	{
		auto task = Task.getThis();
		auto thread = task.thread;
		synchronized (m_mutex) {
			if (thread !in m_waiters) {
				ThreadSlot slot;
				slot.driver = cast(Libevent2Driver)getEventDriver();
				slot.event = event_new(slot.driver.eventLoop, -1, EV_PERSIST, &onSignalTriggered, cast(void*)this);
				event_add(slot.event, null);
				m_waiters[thread] = slot;
			}
			assert(task !in m_waiters[thread].tasks, "Double acquisition of signal.");
			m_waiters[thread].tasks[task] = true;
		}
	}

	void release()
	{
		auto self = Task.getThis();
		synchronized (m_mutex) {
			assert(self.thread in m_waiters && self in m_waiters[self.thread].tasks,
				"Releasing non-acquired signal.");
			m_waiters[self.thread].tasks.remove(self);
		}
	}

	bool isOwner()
	{
		auto self = Task.getThis();
		synchronized (m_mutex) {
			if (self.thread !in m_waiters) return false;
			return (self in m_waiters[self.thread].tasks) !is null;
		}
	}

	@property int emitCount() const { return atomicLoad(m_emitCount); }

	private static nothrow extern(C)
	void onSignalTriggered(evutil_socket_t, short events, void* userptr)
	{
		try {
			auto sig = cast(Libevent2ManualEvent)userptr;
			auto thread = Thread.getThis();
			auto core = getThreadLibeventDriverCore();

			bool[Task] lst;
			synchronized (sig.m_mutex) {
				assert(thread in sig.m_waiters);
				lst = sig.m_waiters[thread].tasks.dup;
			}

			foreach (l; lst.byKey)
				core.resumeTask(l);
		} catch (Exception e) {
			logError("Exception while handling signal event: %s", e.msg);
			try logDiagnostic("Full error: %s", sanitize(e.msg));
			catch(Exception) {}
			debug assert(false);
		}
	}
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
		m_event = event_new(m_driver.eventLoop, -1, EV_TIMEOUT, &onTimerTimeout, cast(void*)this);
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
		assert(m_owner == Task());
		m_owner = Task.getThis();
	}

	void release()
	{
		assert(m_owner == Task.getThis());
		m_owner = Task();
	}

	bool isOwner()
	{
		return m_owner != Task() && m_owner == Task.getThis();
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

	private static nothrow extern(C)
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

			if( tm.m_owner && tm.m_owner.running ) tm.m_driver.m_core.resumeTask(tm.m_owner);
			if( tm.m_callback ) runTask(tm.m_callback);
		} catch( Throwable e ){
			logError("Exception while handling timer event: %s", e.msg);
			try logDiagnostic("Full exception: %s", sanitize(e.toString())); catch {}
			debug assert(false);
		}
	}
}

class Libevent2UdpConnection : UdpConnection {
	private {
		Libevent2Driver m_driver;
		TcpContext* m_ctx;
		string m_bindAddress;
		bool m_canBroadcast = false;
	}

	this(NetworkAddress bind_addr, Libevent2Driver driver)
	{
		m_driver = driver;

		char buf[64];
		void* ptr;
		if( bind_addr.family == AF_INET ) ptr = &bind_addr.sockAddrInet4.sin_addr;
		else ptr = &bind_addr.sockAddrInet6.sin6_addr;
		evutil_inet_ntop(bind_addr.family, ptr, buf.ptr, buf.length);
		m_bindAddress = to!string(buf.ptr);

		auto sockfd = socket(bind_addr.family, SOCK_DGRAM, IPPROTO_UDP);
		enforce(sockfd != -1, "Failed to create socket.");
		
		enforce(evutil_make_socket_nonblocking(sockfd) == 0, "Failed to make socket non-blocking.");

		int tmp_reuse = 1;
		enforce(setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof) == 0,
			"Error enabling socket address reuse on listening socket");

		if( bind_addr.port )
			enforce(bind(sockfd, bind_addr.sockAddr, bind_addr.sockAddrLen) == 0, "Failed to bind UDP socket.");
		
		m_ctx = TcpContextAlloc.alloc(driver.m_core, driver.m_eventLoop, sockfd, null, bind_addr);
		m_ctx.task = Task.getThis();

		auto evt = event_new(driver.m_eventLoop, sockfd, EV_READ|EV_PERSIST, &onUdpRead, m_ctx);
		if( !evt ) throw new Exception("Failed to create buffer event for socket.");

		enforce(event_add(evt, null) == 0);
	}

	@property string bindAddress() const { return m_bindAddress; }

	@property bool canBroadcast() const { return m_canBroadcast; }
	@property void canBroadcast(bool val)
	{
		int tmp_broad = val;
		enforce(setsockopt(m_ctx.socketfd, SOL_SOCKET, SO_BROADCAST, &tmp_broad, tmp_broad.sizeof) == 0,
			"Failed to change the socket broadcast flag.");
		m_canBroadcast = val;
	}


	bool isOwner() {
		return m_ctx !is null && m_ctx.task != Task() && m_ctx.task == Task.getThis();
	}

	void acquire()
	{
		assert(m_ctx, "Trying to acquire a closed TCP connection.");
		assert(m_ctx.task is null, "Trying to acquire a TCP connection that is currently owned.");
		m_ctx.task = Task.getThis();
	}

	void release()
	{
		if( !m_ctx ) return;
		assert(m_ctx.task != Task(), "Trying to release a TCP connection that is not owned.");
		assert(m_ctx.task == Task.getThis(), "Trying to release a foreign TCP connection.");
		m_ctx.task = Task();
	}

	void connect(string host, ushort port)
	{
		NetworkAddress addr = m_driver.resolveHost(host, m_ctx.remote_addr.family);
		addr.port = port;
		enforce(.connect(m_ctx.socketfd, addr.sockAddr, addr.sockAddrLen) == 0, "Failed to connect UDP socket."~to!string(getLastSocketError()));
	}

	void send(in ubyte[] data, in NetworkAddress* peer_address = null)
	{
		sizediff_t ret;
		assert(data.length <= int.max);
		if( peer_address ){
			ret = .sendto(m_ctx.socketfd, data.ptr, cast(int)data.length, 0, peer_address.sockAddr, peer_address.sockAddrLen);
		} else {
			ret = .send(m_ctx.socketfd, data.ptr, cast(int)data.length, 0);
		}
		logTrace("send ret: %s, %s", ret, getLastSocketError());
		enforce(ret >= 0, "Error sending UDP packet.");
		enforce(ret == data.length, "Unable to send full packet.");
	}

	ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		if( buf.length == 0 ) buf.length = 65507;
		NetworkAddress from;
		from.family = m_ctx.remote_addr.family;
		assert(buf.length <= int.max);
		while(true){
			uint addr_len = from.sockAddrLen;
			auto ret = .recvfrom(m_ctx.socketfd, buf.ptr, cast(int)buf.length, 0, from.sockAddr, &addr_len);
			if( ret > 0 ){
				if( peer_address ) *peer_address = from;
				return buf[0 .. ret];
			}
			if( ret < 0 ){
				auto err = getLastSocketError();
				logDiagnostic("UDP recv err: %s", err);
				enforce(err == EWOULDBLOCK, "Error receiving UDP packet.");
			}
			m_ctx.core.yieldForEvent();
		}
	}

	private static nothrow extern(C) void onUdpRead(evutil_socket_t sockfd, short evts, void* arg)
	{
		auto ctx = cast(TcpContext*)arg;
		logTrace("udp socket %d read event!", ctx.socketfd);

		try {
			auto f = ctx.task;
			if( f && f.state != Fiber.State.TERM )
				ctx.core.resumeTask(f);
		} catch( Throwable e ){
			logError("Exception onUdpRead: %s", e.msg);
			debug assert(false);
		}
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

private int getLastSocketError()
{
	version(Windows) return WSAGetLastError();
	else {
		import core.stdc.errno;
		return errno;
	}
}

struct LevMutex {
	vibe.utils.memory.FreeListRef!(core.sync.mutex.Mutex) mutex;
	vibe.utils.memory.FreeListRef!ReadWriteMutex rwmutex;
}
alias FreeListObjectAlloc!(LevMutex, false, true) LevMutexAlloc;

struct LevCondition {
	vibe.utils.memory.FreeListRef!Condition cond;
	LevMutex* mutex;
}
alias FreeListObjectAlloc!(LevCondition, false, true) LevConditionAlloc;

private nothrow extern(C)
{
	void* lev_alloc(size_t size)
	{
		try {
			auto mem = manualAllocator().alloc(size+size_t.sizeof);
			*cast(size_t*)mem.ptr = size;
			return mem.ptr + size_t.sizeof;
		} catch( Throwable th ){
			logWarn("Exception in lev_alloc: %s", th.msg);
			return null;
		}
	}
	void* lev_realloc(void* p, size_t newsize)
	{
		try {
			if( !p ) return lev_alloc(newsize);
			auto oldsize = *cast(size_t*)(p-size_t.sizeof);
			auto oldmem = (p-size_t.sizeof)[0 .. oldsize+size_t.sizeof];
			auto newmem = manualAllocator().realloc(oldmem, newsize+size_t.sizeof);
			*cast(size_t*)newmem.ptr = newsize;
			return newmem.ptr + size_t.sizeof;
		} catch( Throwable th ){
			logWarn("Exception in lev_realloc: %s", th.msg);
			return null;
		}
	}
	void lev_free(void* p)
	{
		try {
			auto size = *cast(size_t*)(p-size_t.sizeof);
			auto mem = (p-size_t.sizeof)[0 .. size+size_t.sizeof];
			manualAllocator().free(mem);
		} catch( Throwable th ){
			logWarn("Exception in lev_free: %s", th.msg);
		}
	}

	void* lev_alloc_mutex(uint locktype)
	{
		try {
			auto ret = LevMutexAlloc.alloc();
			if( locktype == EVTHREAD_LOCKTYPE_READWRITE ) ret.rwmutex = FreeListRef!ReadWriteMutex();
			else ret.mutex = FreeListRef!(core.sync.mutex.Mutex)();
			return ret;
		} catch( Throwable th ){
			logWarn("Exception in lev_alloc_mutex: %s", th.msg);
			return null;
		}
	}

	void lev_free_mutex(void* lock, uint locktype)
	{
		try LevMutexAlloc.free(cast(LevMutex*)lock);
		catch( Throwable th ){
			logWarn("Exception in lev_free_mutex: %s", th.msg);
		}
	}

	int lev_lock_mutex(uint mode, void* lock)
	{
		try {
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
		} catch( Throwable th ){
			logWarn("Exception in lev_lock_mutex: %s", th.msg);
			return -1;
		}
	}

	int lev_unlock_mutex(uint mode, void* lock)
	{
		try {
			auto mtx = cast(LevMutex*)lock;

			if( mode & EVTHREAD_WRITE ){
				mtx.rwmutex.writer().unlock();
			} else if( mode & EVTHREAD_READ ){
				mtx.rwmutex.reader().unlock();
			} else {
				mtx.mutex.unlock();
			}
			return 0;
		} catch( Throwable th ){
			logWarn("Exception in lev_unlock_mutex: %s", th.msg);
			return -1;
		}
	}

	void* lev_alloc_condition(uint condtype)
	{
		try return LevConditionAlloc.alloc();
		catch( Throwable th ){
			logWarn("Exception in lev_alloc_condition: %s", th.msg);
			return null;
		}
	}

	void lev_free_condition(void* cond)
	{
		try LevConditionAlloc.free(cast(LevCondition*)cond);
		catch( Throwable th ){
			logWarn("Exception in lev_free_condition: %s", th.msg);
		}
	}

	int lev_signal_condition(void* cond, int broadcast)
	{
		try {
			auto c = cast(LevCondition*)cond;
			if( c.cond ) c.cond.notifyAll();
			return 0;
		} catch( Throwable th ){
			logWarn("Exception in lev_signal_condition: %s", th.msg);
			return -1;
		}
	}

	int lev_wait_condition(void* cond, void* lock, const(timeval)* timeout)
	{
		try {
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
		} catch( Throwable th ){
			logWarn("Exception in lev_wait_condition: %s", th.msg);
			return -1;
		}
	}

	c_ulong lev_get_thread_id()
	{
		try return cast(c_ulong)cast(void*)Thread.getThis();
		catch( Throwable th ){
			logWarn("Exception in lev_get_thread_id: %s", th.msg);
			return 0;
		}
	}
}

}
