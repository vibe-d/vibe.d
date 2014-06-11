/**
	libevent based driver

	Copyright: © 2012-2014 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libevent2;

version(VibeLibeventDriver)
{

import vibe.core.driver;
import vibe.core.drivers.libevent2_tcp;
import vibe.core.drivers.threadedfile;
import vibe.core.drivers.timerqueue;
import vibe.core.drivers.utils;
import vibe.core.log;
import vibe.utils.array : ArraySet;
import vibe.utils.hashmap;
import vibe.utils.memory;

import core.memory;
import core.atomic;
import core.stdc.config;
import core.stdc.errno;
import core.stdc.stdlib;
import core.sync.condition;
import core.sync.mutex;
import core.sync.rwmutex;
import core.sys.posix.netinet.in_;
import core.sys.posix.netinet.tcp;
import core.thread;
import deimos.event2.bufferevent;
import deimos.event2.dns;
import deimos.event2.event;
import deimos.event2.thread;
import deimos.event2.util;
import std.conv;
import std.datetime;
import std.encoding : sanitize;
import std.exception;
import std.range : assumeSorted;
import std.string;


version (Windows)
{
	version(VibePragmaLib) pragma(lib, "event2");
	pragma(lib, "ws2_32.lib");
}
else
	version(VibePragmaLib) pragma(lib, "event");

version(Windows)
{
	import std.c.windows.winsock;

	alias WSAEWOULDBLOCK EWOULDBLOCK;
}


final class Libevent2Driver : EventDriver {
	import std.container : DList;
	import std.datetime : Clock;

	private {
		DriverCore m_core;
		event_base* m_eventLoop;
		evdns_base* m_dnsBase;
		bool m_exit = false;
		ArraySet!size_t m_ownedObjects;
		debug Thread m_ownerThread;

		event* m_timerEvent;
		TimerQueue!TimerInfo m_timers;
		DList!AddressInfo m_addressInfoCache;
		size_t m_addressInfoCacheLength = 0;
	}

	this(DriverCore core)
	{
		debug m_ownerThread = Thread.getThis();
		m_core = core;
		s_driverCore = core;

		if (!s_threadObjectsMutex) s_threadObjectsMutex = new Mutex;

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

		string hosts_file;
		version (Windows) hosts_file = `C:\Windows\System32\drivers\etc\hosts`;
		else hosts_file = `/etc/hosts`;
		if (existsFile(hosts_file)) {
			if (evdns_base_load_hosts(m_dnsBase, hosts_file.toStringz()) != 0)
				logError("Failed to load hosts file at %s", hosts_file);
		}

		m_timerEvent = event_new(m_eventLoop, -1, EV_TIMEOUT, &onTimerTimeout, cast(void*)this);
	}

	~this()
	{
		debug assert(Thread.getThis() is m_ownerThread, "Event loop destroyed in foreign thread.");

		event_free(m_timerEvent);

		// notify all other living objects about the shutdown
		synchronized (s_threadObjectsMutex) {
			// destroy all living objects owned by this driver
			foreach (ref key; m_ownedObjects) {
				assert(key);
				auto obj = cast(Libevent2Object)cast(void*)key;
				debug assert(obj.m_ownerThread is m_ownerThread, "Owned object with foreign thread ID detected.");
				debug assert(obj.m_driver is this, "Owned object with foreign driver reference detected.");
				key = 0;
				destroy(obj);
			}

			foreach (ref key; s_threadObjects) {
				assert(key);
				auto obj = cast(Libevent2Object)cast(void*)key;
				debug assert(obj.m_ownerThread !is m_ownerThread, "Live object of this thread detected after all owned mutexes have been destroyed.");
				debug assert(obj.m_driver !is this, "Live object of this driver detected with different thread ID after all owned mutexes have been destroyed.");
				obj.onThreadShutdown();
			}
		}

		// shutdown libevent for this thread
		evdns_base_free(m_dnsBase, 1);
		event_base_free(m_eventLoop);
		s_eventLoop = null;
		s_alreadyDeinitialized = true;
	}

	@property event_base* eventLoop() { return m_eventLoop; }
	@property evdns_base* dnsEngine() { return m_dnsBase; }

	int runEventLoop()
	{
		int ret;
		m_exit = false;
		while (!m_exit && (ret = event_base_loop(m_eventLoop, EVLOOP_ONCE)) == 0) {
			processTimers();
			s_driverCore.notifyIdle();
		}
		return ret;
	}

	int runEventLoopOnce()
	{
		auto ret = event_base_loop(m_eventLoop, EVLOOP_ONCE);
		processTimers();
		m_core.notifyIdle();
		return ret;
	}

	bool processEvents()
	{
		event_base_loop(m_eventLoop, EVLOOP_NONBLOCK);
		processTimers();
		if (m_exit) {
			m_exit = false;
			return false;
		}
		return true;
	}

	void exitEventLoop()
	{
		m_exit = true;
		enforce(event_base_loopbreak(m_eventLoop) == 0, "Failed to exit libevent event loop.");
	}

	ThreadedFileStream openFile(Path path, FileMode mode)
	{
		return new ThreadedFileStream(path, mode);
	}

	DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		assert(false, "watchDirectory is not yet implemented in the libevent driver.");
	}

	NetworkAddress resolveHost(string host, ushort family = AF_UNSPEC, bool use_dns = true)
	{
		assert(m_dnsBase);

		foreach (ai; m_addressInfoCache)
			if (ai.host == host && ai.family == family && ai.useDNS == use_dns)
				return ai.address;

		evutil_addrinfo hints;
		hints.ai_family = family;
		if (!use_dns) {
			//When this flag is set, we only resolve numeric IPv4 and IPv6
			//addresses; if the nodename would require a name lookup, we instead
			//give an EVUTIL_EAI_NONAME error.
			hints.ai_flags = EVUTIL_AI_NUMERICHOST;
		}

		logDebug("dnsresolve %s", host);
		GetAddrInfoMsg msg;
		msg.core = m_core;
		evdns_getaddrinfo_request* dnsReq = evdns_getaddrinfo(m_dnsBase, toStringz(host), null,
			&hints, &onAddrInfo, &msg);

		// wait if the request couldn't be fulfilled instantly
		if (!msg.done) {
			assert(dnsReq !is null);
			msg.task = Task.getThis();
			logDebug("dnsresolve yield");
			while (!msg.done) m_core.yieldForEvent();
		}

		logDebug("dnsresolve ret");
		enforce(msg.err == DNS_ERR_NONE, format("Failed to lookup host '%s': %s", host, to!string(evutil_gai_strerror(msg.err))));

		if (m_addressInfoCacheLength >= 10) m_addressInfoCache.removeFront();
		else m_addressInfoCacheLength++;
		m_addressInfoCache.insertBack(AddressInfo(msg.addr, host, family, use_dns));
		return msg.addr;
	}

	Libevent2TCPConnection connectTCP(NetworkAddress addr)
	{
		
		auto sockfd_raw = socket(addr.family, SOCK_STREAM, 0);
		// on Win64 socket() returns a 64-bit value but libevent expects an int
		static if (typeof(sockfd_raw).max > int.max) assert(sockfd_raw <= int.max || sockfd_raw == ~0);
		auto sockfd = cast(int)sockfd_raw;
		socketEnforce(sockfd != -1, "Failed to create socket.");

		NetworkAddress bind_addr;
		bind_addr.family = addr.family;
		if (addr.family == AF_INET) bind_addr.sockAddrInet4.sin_addr.s_addr = 0;
		else bind_addr.sockAddrInet6.sin6_addr.s6_addr[] = 0;
		socketEnforce(bind(sockfd, bind_addr.sockAddr, bind_addr.sockAddrLen) == 0, "Failed to bind socket.");
		socklen_t balen = bind_addr.sockAddrLen;
		socketEnforce(getsockname(sockfd, bind_addr.sockAddr, &balen) == 0, "getsockname failed.");
		
		if( evutil_make_socket_nonblocking(sockfd) )
			throw new Exception("Failed to make socket non-blocking.");
			
		auto buf_event = bufferevent_socket_new(m_eventLoop, sockfd, bufferevent_options.BEV_OPT_CLOSE_ON_FREE);
		if( !buf_event ) throw new Exception("Failed to create buffer event for socket.");

		auto cctx = TCPContextAlloc.alloc(m_core, m_eventLoop, sockfd, buf_event, bind_addr, addr);
		bufferevent_setcb(buf_event, &onSocketRead, &onSocketWrite, &onSocketEvent, cctx);
		if( bufferevent_enable(buf_event, EV_READ|EV_WRITE) )
			throw new Exception("Error enabling buffered I/O event for socket.");

		cctx.readOwner = Task.getThis();
		scope(exit) cctx.readOwner = Task();

		assert(cctx.exception is null);
		socketEnforce(bufferevent_socket_connect(buf_event, addr.sockAddr, addr.sockAddrLen) == 0,
			"Failed to connect to " ~ addr.toString());
		
		try {
			cctx.checkForException();

			// TODO: cctx.remote_addr6 = ...;

			while (cctx.status == 0)
				m_core.yieldForEvent();
		} catch (Exception e) {
			throw new Exception(format("Failed to connect to %s: %s", addr.toString(), e.msg));
		}
		
		logTrace("Connect result status: %d", cctx.status);
		enforce(cctx.status == BEV_EVENT_CONNECTED, format("Failed to connect to host %s: %s", addr.toString(), cctx.status));
		
		return new Libevent2TCPConnection(cctx);
	}

	Libevent2TCPListener listenTCP(ushort port, void delegate(TCPConnection conn) connection_callback, string address, TCPListenOptions options)
	{
		auto bind_addr = resolveHost(address, AF_UNSPEC, false);
		bind_addr.port = port;

		auto listenfd_raw = socket(bind_addr.family, SOCK_STREAM, 0);
		// on Win64 socket() returns a 64-bit value but libevent expects an int
		static if (typeof(listenfd_raw).max > int.max) assert(listenfd_raw <= int.max || listenfd_raw == ~0);
		auto listenfd = cast(int)listenfd_raw;
		socketEnforce(listenfd != -1, "Error creating listening socket");
		int tmp_reuse = 1; 
		socketEnforce(setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof) == 0,
			"Error enabling socket address reuse on listening socket");
		socketEnforce(bind(listenfd, bind_addr.sockAddr, bind_addr.sockAddrLen) == 0,
			"Error binding listening socket");
		socketEnforce(listen(listenfd, 128) == 0,
			"Error listening to listening socket");

		// Set socket for non-blocking I/O
		enforce(evutil_make_socket_nonblocking(listenfd) == 0,
			"Error setting listening socket to non-blocking I/O.");

		auto ret = new Libevent2TCPListener;

		static final class HandlerContext {
			Libevent2TCPListener listener;
			int listenfd;
			NetworkAddress bind_addr;
			void delegate(TCPConnection) connection_callback;
			TCPListenOptions options;
		}

		auto hc = new HandlerContext;
		hc.listener = ret;
		hc.listenfd = listenfd;
		hc.bind_addr = bind_addr;
		hc.connection_callback = connection_callback;
		hc.options = options;

		static void setupConnectionHandler(shared(HandlerContext) handler_context_)
		{
			auto handler_context = cast(HandlerContext)handler_context_;
			auto evloop = getThreadLibeventEventLoop();
			auto core = getThreadLibeventDriverCore();
			// Add an event to wait for connections
			auto ctx = TCPContextAlloc.alloc(core, evloop, handler_context.listenfd, null, handler_context.bind_addr, NetworkAddress());
			ctx.connectionCallback = handler_context.connection_callback;
			ctx.listenEvent = event_new(evloop, handler_context.listenfd, EV_READ | EV_PERSIST, &onConnect, ctx);
			ctx.listenOptions = handler_context.options;
			enforce(event_add(ctx.listenEvent, null) == 0,
				"Error scheduling connection event on the event loop.");
			handler_context.listener.addContext(ctx);
		}

		// FIXME: the API needs improvement with proper shared annotations, so the the following casts are not necessary
		if (options & TCPListenOptions.distribute) runWorkerTaskDist(&setupConnectionHandler, cast(shared)hc);
		else setupConnectionHandler(cast(shared)hc);

		return ret;
	}

	Libevent2UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
	{
		NetworkAddress bindaddr = resolveHost(bind_address, AF_UNSPEC, false);
		bindaddr.port = port;

		return new Libevent2UDPConnection(bindaddr, this);
	}

	Libevent2ManualEvent createManualEvent()
	{
		return new Libevent2ManualEvent(this);
	}

	Libevent2FileDescriptorEvent createFileDescriptorEvent(int fd, FileDescriptorEvent.Trigger events)
	{
		return new Libevent2FileDescriptorEvent(this, fd, events);
	}

	size_t createTimer(void delegate() callback) { return m_timers.create(TimerInfo(callback)); }

	void acquireTimer(size_t timer_id) { m_timers.getUserData(timer_id).refCount++; }
	void releaseTimer(size_t timer_id)
	{
		debug assert(m_ownerThread is Thread.getThis());
		if (!--m_timers.getUserData(timer_id).refCount)
			m_timers.destroy(timer_id);
	}

	bool isTimerPending(size_t timer_id) { return m_timers.isPending(timer_id); }

	void rearmTimer(size_t timer_id, Duration dur, bool periodic)
	{
		debug assert(m_ownerThread is Thread.getThis());
		if (!isTimerPending(timer_id)) acquireTimer(timer_id);
		m_timers.schedule(timer_id, dur, periodic);
		rescheduleTimerEvent(Clock.currTime(UTC()));
	}

	void stopTimer(size_t timer_id)
	{
		logTrace("Stopping timer %s", timer_id);
		if (m_timers.isPending(timer_id)) {
			m_timers.unschedule(timer_id);
			releaseTimer(timer_id);
		}
	}

	void waitTimer(size_t timer_id)
	{
		debug assert(m_ownerThread is Thread.getThis());
		while (true) {
			assert(!m_timers.isPeriodic(timer_id), "Cannot wait for a periodic timer.");
			if (!m_timers.isPending(timer_id)) return;
			auto data = &m_timers.getUserData(timer_id);
			assert(data.owner == Task.init, "Waiting for the same timer from multiple tasks is not supported.");
			data.owner = Task.getThis();
			scope (exit) m_timers.getUserData(timer_id).owner = Task.init;
			m_core.yieldForEvent();
		}
	}

	private void processTimers()
	{
		logTrace("Processing due timers");
		// process all timers that have expired up to now
		auto now = Clock.currTime(UTC());
		m_timers.consumeTimeouts(now, (timer, periodic, ref data) {
			Task owner = data.owner;
			auto callback = data.callback;

			logTrace("Timer %s fired (%s/%s)", timer, owner != Task.init, callback !is null);

			if (!periodic) releaseTimer(timer);

			if (owner && owner.running) m_core.resumeTask(owner);
			if (callback) runTask(callback);
		});

		rescheduleTimerEvent(now);
	}

	private void rescheduleTimerEvent(SysTime now)
	{
		auto next = m_timers.getFirstTimeout();
		if (next == SysTime.max) return;

		auto dur = next - now;
		event_del(m_timerEvent);
		assert(dur.total!"seconds"() <= int.max);
		dur += 9.hnsecs(); // round up to the next usec to avoid premature timer events
		timeval tvdur;
		tvdur.tv_sec = cast(int)dur.total!"seconds"();
		tvdur.tv_usec = dur.fracSec().usecs();
		event_add(m_timerEvent, &tvdur);
		assert(event_pending(m_timerEvent, EV_TIMEOUT, null));
		logTrace("Rescheduled timer event for %s seconds", dur.total!"usecs" * 1e-6);
	}

	private static nothrow extern(C)
	void onTimerTimeout(evutil_socket_t, short events, void* userptr)
	{
		logTrace("timer event fired");
		auto drv = cast(Libevent2Driver)userptr;
		try drv.processTimers();
		catch (Exception e) {
			logError("Failed to process timers: %s", e.msg);
			try logDiagnostic("Full error: %s", e.toString().sanitize); catch {}
		}
	}

	private static nothrow extern(C) void onAddrInfo(int err, evutil_addrinfo* res, void* arg)
	{
		auto msg = cast(GetAddrInfoMsg*)arg;
		msg.err = err;
		msg.done = true;
		if (err == DNS_ERR_NONE) {
			assert(res !is null);
			scope (exit) evutil_freeaddrinfo(res);

			// Note that we are only returning the first address and ignoring the
			// rest. Ideally we should return all of the NetworkAddress
			msg.addr.family = cast(ushort)res.ai_family;
			assert(res.ai_addrlen == msg.addr.sockAddrLen());
			switch (msg.addr.family) {
				case AF_INET:
					auto sock4 = cast(sockaddr_in*)res.ai_addr;
					msg.addr.sockAddrInet4.sin_addr.s_addr = sock4.sin_addr.s_addr;
					break;
				case AF_INET6:
					auto sock6 = cast(sockaddr_in6*)res.ai_addr;
					msg.addr.sockAddrInet6.sin6_addr.s6_addr = sock6.sin6_addr.s6_addr;
					break;
				default:
					logDiagnostic("DNS lookup yielded unknown address family: %s", msg.addr.family);
					err = DNS_ERR_UNKNOWN;
					break;
			}
		}
		if (msg.task && msg.task.running) {
			try msg.core.resumeTask(msg.task);
			catch (Exception e) logWarn("Error resuming DNS query task: %s", e.msg);
		}
	}

	private void registerObject(Libevent2Object obj)
	{
		debug assert(Thread.getThis() is m_ownerThread, "Event object created in foreign thread.");
		auto key = cast(size_t)cast(void*)obj;
		synchronized (s_threadObjectsMutex) {
			m_ownedObjects.insert(key);
			s_threadObjects.insert(key);
		}
	}

	private void unregisterObject(Libevent2Object obj)
	{
		auto key = cast(size_t)cast(void*)obj;
		synchronized (s_threadObjectsMutex) {
			m_ownedObjects.remove(key);
			s_threadObjects.remove(key);
		}
	}
}

private struct TimerInfo {
	size_t refCount = 1;
	void delegate() callback;
	Task owner;

	this(void delegate() callback) { this.callback = callback; }
}

struct AddressInfo {
	NetworkAddress address;
	string host;
	ushort family;
	bool useDNS;
}


private struct GetAddrInfoMsg {
	NetworkAddress addr;
	bool done = false;
	int err = 0;
	DriverCore core;
	Task task;
}

private class Libevent2Object {
	protected Libevent2Driver m_driver;
	debug private Thread m_ownerThread;

	this(Libevent2Driver driver)
	{
		m_driver = driver;
		m_driver.registerObject(this);
		debug m_ownerThread = driver.m_ownerThread;
	}

	~this()
	{
		// NOTE: m_driver will always be destroyed deterministically
		//       in static ~this(), so it can be used here safely
		m_driver.unregisterObject(this);
	}

	protected void onThreadShutdown() {}
}

/// private
struct ThreadSlot {
	Libevent2Driver driver;
	deimos.event2.event.event* event;
	ArraySet!Task tasks;
}
/// private
alias ThreadSlotMap = HashMap!(Thread, ThreadSlot);

final class Libevent2ManualEvent : Libevent2Object, ManualEvent {
	private {
		shared(int) m_emitCount = 0;
		core.sync.mutex.Mutex m_mutex;
		ThreadSlotMap m_waiters;
	}

	this(Libevent2Driver driver)
	{
		super(driver);
		m_mutex = new core.sync.mutex.Mutex;
		m_waiters = ThreadSlotMap(manualAllocator());
	}

	~this()
	{
		foreach (ts; m_waiters)
			event_free(ts.event);
	}

	void emit()
	{
		atomicOp!"+="(m_emitCount, 1);
		synchronized (m_mutex) {
			foreach (ref sl; m_waiters)
				event_active(sl.event, 0, 0);
		}
	}

	void wait()
	{
		wait(m_emitCount);
	}

	int wait(int reference_emit_count)
	{
		assert(!amOwner());
		acquire();
		scope(exit) release();
		auto ec = this.emitCount;
		while( ec == reference_emit_count ){
			getThreadLibeventDriverCore().yieldForEvent();
			ec = this.emitCount;
		}
		return ec;
	}

	int wait(Duration timeout, int reference_emit_count)
	{
		assert(!amOwner());
		acquire();
		scope(exit) release();
		auto tm = m_driver.createTimer(null);
		scope (exit) m_driver.releaseTimer(tm);
		m_driver.m_timers.getUserData(tm).owner = Task.getThis();
		m_driver.rearmTimer(tm, timeout, false);

		auto ec = this.emitCount;
		while( ec == reference_emit_count ){
			getThreadLibeventDriverCore().yieldForEvent();
			ec = this.emitCount;
			if (!m_driver.isTimerPending(tm)) break;
		}
		return ec;
	}

	void acquire()
	{
		auto task = Task.getThis();
		assert(task != Task(), "ManualEvent.wait works only when called from a task.");
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
			m_waiters[thread].tasks.insert(task);
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

	bool amOwner()
	{
		auto self = Task.getThis();
		synchronized (m_mutex) {
			if (self.thread !in m_waiters) return false;
			return self in m_waiters[self.thread].tasks;
		}
	}

	@property int emitCount() const { return atomicLoad(m_emitCount); }

	protected override void onThreadShutdown()
	{
		auto thr = Thread.getThis();
		synchronized (m_mutex) {
			if (thr in m_waiters) {
				event_free(m_waiters[thr].event);
				m_waiters.remove(thr);
			}
		}
	}

	private static nothrow extern(C)
	void onSignalTriggered(evutil_socket_t, short events, void* userptr)
	{
		try {
			auto sig = cast(Libevent2ManualEvent)userptr;
			auto thread = Thread.getThis();
			auto core = getThreadLibeventDriverCore();

			ArraySet!Task lst;
			synchronized (sig.m_mutex) {
				assert(thread in sig.m_waiters);
				lst = sig.m_waiters[thread].tasks.dup;
			}

			foreach (l; lst)
				core.resumeTask(l);
		} catch (Exception e) {
			logError("Exception while handling signal event: %s", e.msg);
			try logDiagnostic("Full error: %s", sanitize(e.msg));
			catch(Exception) {}
			debug assert(false);
		}
	}
}


final class Libevent2FileDescriptorEvent : Libevent2Object, FileDescriptorEvent {
	private {
		int m_fd;
		deimos.event2.event.event* m_event;
		Trigger m_activeEvents;
		Task m_waiter;
	}

	this(Libevent2Driver driver, int file_descriptor, Trigger events)
	{
		assert(events != Trigger.none);
		super(driver);
		m_fd = file_descriptor;
		short evts = 0;
		if (events & Trigger.read) evts |= EV_READ;
		if (events & Trigger.write) evts |= EV_WRITE;
		m_event = event_new(driver.eventLoop, file_descriptor, evts|EV_PERSIST, &onFileTriggered, cast(void*)this);
		event_add(m_event, null);
	}

	~this()
	{
		event_free(m_event);
	}

	void wait(Trigger which)
	{
		assert(!m_waiter, "Only one task may wait on a Libevent2FileEvent.");
		m_waiter = Task.getThis();
		scope (exit) {
			m_waiter = Task.init;
			m_activeEvents &= ~which;
		}

		while ((m_activeEvents & which) == Trigger.none)
			getThreadLibeventDriverCore().yieldForEvent();
	}

	bool wait(Duration timeout, Trigger which)
	{
		assert(!m_waiter, "Only one task may wait on a Libevent2FileEvent.");
		m_waiter = Task.getThis();
		scope (exit) {
			m_waiter = Task.init;
			m_activeEvents &= ~which;
		}

		auto tm = m_driver.createTimer(null);
		scope (exit) m_driver.releaseTimer(tm);
		m_driver.m_timers.getUserData(tm).owner = Task.getThis();
		m_driver.rearmTimer(tm, timeout, false);

		while ((m_activeEvents & which) == Trigger.none) {
			getThreadLibeventDriverCore().yieldForEvent();
			if (!m_driver.isTimerPending(tm)) break;
		}
		return (m_activeEvents & which) != Trigger.none;
	}

	private static nothrow extern(C)
	void onFileTriggered(evutil_socket_t fd, short events, void* userptr)
	{
		try {
			auto core = getThreadLibeventDriverCore();
			auto evt = cast(Libevent2FileDescriptorEvent)userptr;

			evt.m_activeEvents = Trigger.none;
			if (events & EV_READ) evt.m_activeEvents |= Trigger.read;
			if (events & EV_WRITE) evt.m_activeEvents |= Trigger.write;
			if (evt.m_waiter) core.resumeTask(evt.m_waiter);
		} catch (Exception e) {
			logError("Exception while handling file event: %s", e.msg);
			try logDiagnostic("Full error: %s", sanitize(e.msg));
			catch(Exception) {}
			debug assert(false);
		}
	}
}


final class Libevent2UDPConnection : UDPConnection {
	private {
		Libevent2Driver m_driver;
		TCPContext* m_ctx;
		NetworkAddress m_bindAddress;
		string m_bindAddressString;
		bool m_canBroadcast = false;
	}

	this(NetworkAddress bind_addr, Libevent2Driver driver)
	{
		m_driver = driver;

		m_bindAddress = bind_addr;
		char buf[64];
		void* ptr;
		if( bind_addr.family == AF_INET ) ptr = &bind_addr.sockAddrInet4.sin_addr;
		else ptr = &bind_addr.sockAddrInet6.sin6_addr;
		evutil_inet_ntop(bind_addr.family, ptr, buf.ptr, buf.length);
		m_bindAddressString = to!string(buf.ptr);

		auto sockfd_raw = socket(bind_addr.family, SOCK_DGRAM, IPPROTO_UDP);
		// on Win64 socket() returns a 64-bit value but libevent expects an int
		static if (typeof(sockfd_raw).max > int.max) assert(sockfd_raw <= int.max || sockfd_raw == ~0);
		auto sockfd = cast(int)sockfd_raw;
		socketEnforce(sockfd != -1, "Failed to create socket.");
		
		enforce(evutil_make_socket_nonblocking(sockfd) == 0, "Failed to make socket non-blocking.");

		int tmp_reuse = 1;
		socketEnforce(setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof) == 0,
			"Error enabling socket address reuse on listening socket");

		if( bind_addr.port )
			socketEnforce(bind(sockfd, bind_addr.sockAddr, bind_addr.sockAddrLen) == 0, "Failed to bind UDP socket.");
		
		m_ctx = TCPContextAlloc.alloc(driver.m_core, driver.m_eventLoop, sockfd, null, bind_addr, NetworkAddress());

		auto evt = event_new(driver.m_eventLoop, sockfd, EV_READ|EV_PERSIST, &onUDPRead, m_ctx);
		if( !evt ) throw new Exception("Failed to create buffer event for socket.");

		enforce(event_add(evt, null) == 0);
	}

	@property string bindAddress() const { return m_bindAddressString; }
	@property NetworkAddress localAddress() const { return m_bindAddress; }

	@property bool canBroadcast() const { return m_canBroadcast; }
	@property void canBroadcast(bool val)
	{
		int tmp_broad = val;
		enforce(setsockopt(m_ctx.socketfd, SOL_SOCKET, SO_BROADCAST, &tmp_broad, tmp_broad.sizeof) == 0,
			"Failed to change the socket broadcast flag.");
		m_canBroadcast = val;
	}


	bool amOwner() {
		return m_ctx !is null && m_ctx.readOwner != Task() && m_ctx.readOwner == Task.getThis() && m_ctx.readOwner == m_ctx.writeOwner;
	}

	void acquire()
	{
		assert(m_ctx, "Trying to acquire a closed UDP connection.");
		assert(m_ctx.readOwner == Task() && m_ctx.writeOwner == Task(),
			"Trying to acquire a UDP connection that is currently owned.");
		m_ctx.readOwner = m_ctx.writeOwner = Task.getThis();
	}

	void release()
	{
		if (!m_ctx) return;
		assert(m_ctx.readOwner == Task.getThis() && m_ctx.readOwner == m_ctx.writeOwner,
			"Trying to release a UDP connection that is not owned by the current task.");
		m_ctx.readOwner = m_ctx.writeOwner = Task.init;
	}

	void connect(string host, ushort port)
	{
		NetworkAddress addr = m_driver.resolveHost(host, m_ctx.local_addr.family);
		addr.port = port;
		connect(addr);
	}
	
	void connect(NetworkAddress addr)
	{
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
		return recv(Duration.max, buf, peer_address);
	}

	ubyte[] recv(Duration timeout, ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		size_t tm = size_t.max;
		if (timeout >= 0.seconds && timeout != Duration.max) {
			tm = m_driver.createTimer(null);
			m_driver.rearmTimer(tm, timeout, false);
			m_driver.acquireTimer(tm);
		}

		acquire();

		scope (exit) {
			release();
			if (tm != size_t.max) m_driver.releaseTimer(tm);
		}

		if (buf.length == 0) buf.length = 65507;

		NetworkAddress from;
		from.family = m_ctx.local_addr.family;
		assert(buf.length <= int.max);
		while (true) {
			socklen_t addr_len = from.sockAddrLen;
			auto ret = .recvfrom(m_ctx.socketfd, buf.ptr, cast(int)buf.length, 0, from.sockAddr, &addr_len);
			if (ret > 0) {
				if( peer_address ) *peer_address = from;
				return buf[0 .. ret];
			}
			if (ret < 0) {
				auto err = getLastSocketError();
				if (err != EWOULDBLOCK) {
					logDebugV("UDP recv err: %s", err);
					throw new Exception("Error receiving UDP packet.");
				}
				if (timeout != Duration.max) {
					enforce(timeout > 0.seconds && m_driver.isTimerPending(tm), "UDP receive timeout.");
				}
			}
			m_ctx.core.yieldForEvent();
		}
	}

	private static nothrow extern(C) void onUDPRead(evutil_socket_t sockfd, short evts, void* arg)
	{
		auto ctx = cast(TCPContext*)arg;
		logTrace("udp socket %d read event!", ctx.socketfd);

		try {
			auto f = ctx.readOwner;
			if (f && f.running)
				ctx.core.resumeTask(f);
		} catch( Throwable e ){
			logError("Exception onUDPRead: %s", e.msg);
			debug assert(false);
		}
	}
}

private {
	event_base* s_eventLoop; // TLS
	__gshared DriverCore s_driverCore;
	__gshared Mutex s_threadObjectsMutex;
	__gshared ArraySet!size_t s_threadObjects;
	bool s_alreadyDeinitialized = false;
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

struct LevCondition {
	Condition cond;
	LevMutex* mutex;
}

struct LevMutex {
	core.sync.mutex.Mutex mutex;
	ReadWriteMutex rwmutex;
}

alias FreeListObjectAlloc!(LevCondition, false) LevConditionAlloc;
alias FreeListObjectAlloc!(LevMutex, false) LevMutexAlloc;
alias FreeListObjectAlloc!(core.sync.mutex.Mutex, false) MutexAlloc;
alias FreeListObjectAlloc!(ReadWriteMutex, false) ReadWriteMutexAlloc;
alias FreeListObjectAlloc!(Condition, false) ConditionAlloc;

private nothrow extern(C)
{
	version (VibeDebugCatchAll) alias UncaughtException = Throwable;
	else alias UncaughtException = Exception;

	void* lev_alloc(size_t size)
	{
		try {
			auto mem = manualAllocator().alloc(size+size_t.sizeof);
			*cast(size_t*)mem.ptr = size;
			return mem.ptr + size_t.sizeof;
		} catch (UncaughtException th) {
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
		} catch (UncaughtException th) {
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
		} catch (UncaughtException th) {
			logCritical("Exception in lev_free: %s", th.msg);
			assert(false);
		}
	}

	debug __gshared size_t[void*] s_mutexes;
	debug __gshared Mutex s_mutexesLock;

	void* lev_alloc_mutex(uint locktype)
	{
		try {
			auto ret = LevMutexAlloc.alloc();
			if( locktype == EVTHREAD_LOCKTYPE_READWRITE ) ret.rwmutex = ReadWriteMutexAlloc.alloc();
			else ret.mutex = MutexAlloc.alloc();
			//logInfo("alloc mutex %s", cast(void*)ret);
			debug if (!s_mutexesLock) s_mutexesLock = new Mutex;
			debug synchronized (s_mutexesLock) s_mutexes[cast(void*)ret] = 0;
			return ret;
		} catch (UncaughtException th) {
			logWarn("Exception in lev_alloc_mutex: %s", th.msg);
			return null;
		}
	}

	void lev_free_mutex(void* lock, uint locktype)
	{
		try {
			import core.runtime;
			//logInfo("free mutex %s: %s", cast(void*)lock, defaultTraceHandler());
			debug synchronized (s_mutexesLock) {
				auto pl = lock in s_mutexes;
				assert(pl !is null);
				assert(*pl == 0);
				s_mutexes.remove(lock);
			}
			auto lm = cast(LevMutex*)lock;
			if (lm.mutex) MutexAlloc.free(lm.mutex);
			if (lm.rwmutex) ReadWriteMutexAlloc.free(lm.rwmutex);
			LevMutexAlloc.free(lm);
		} catch (UncaughtException th) {
			logCritical("Exception in lev_free_mutex: %s", th.msg);
			assert(false);
		}
	}

	int lev_lock_mutex(uint mode, void* lock)
	{
		try {
			//logInfo("lock mutex %s", cast(void*)lock);
			debug synchronized (s_mutexesLock) {
				auto pl = lock in s_mutexes;
				assert(pl !is null, "Unknown lock handle");
				(*pl)++;
			}
			auto mtx = cast(LevMutex*)lock;
			
			assert(mtx !is null, "null lock");
			assert(mtx.mutex !is null || mtx.rwmutex !is null, "lock contains no mutex");
			if( mode & EVTHREAD_WRITE ){
				if( mode & EVTHREAD_TRY ) return mtx.rwmutex.writer().tryLock() ? 0 : 1;
				else mtx.rwmutex.writer().lock();
			} else if( mode & EVTHREAD_READ ){
				if( mode & EVTHREAD_TRY ) return mtx.rwmutex.reader().tryLock() ? 0 : 1;
				else mtx.rwmutex.reader().lock();
			} else {
				assert(mtx.mutex !is null, "lock mutex is null");
				if( mode & EVTHREAD_TRY ) return mtx.mutex.tryLock() ? 0 : 1;
				else mtx.mutex.lock();
			}
			return 0;
		} catch (UncaughtException th) {
			logWarn("Exception in lev_lock_mutex: %s", th.msg);
			return -1;
		}
	}

	int lev_unlock_mutex(uint mode, void* lock)
	{
		try {
			//logInfo("unlock mutex %s", cast(void*)lock);
			debug synchronized (s_mutexesLock) {
				auto pl = lock in s_mutexes;
				assert(pl !is null, "Unknown lock handle");
				assert(*pl > 0, "Unlocking unlocked mutex");
				(*pl)--;
			}

			auto mtx = cast(LevMutex*)lock;

			if( mode & EVTHREAD_WRITE ){
				mtx.rwmutex.writer().unlock();
			} else if( mode & EVTHREAD_READ ){
				mtx.rwmutex.reader().unlock();
			} else {
				mtx.mutex.unlock();
			}
			return 0;
		} catch (UncaughtException th ) {
			logWarn("Exception in lev_unlock_mutex: %s", th.msg);
			return -1;
		}
	}

	void* lev_alloc_condition(uint condtype)
	{
		try {
			return LevConditionAlloc.alloc();
		} catch (UncaughtException th) {
			logWarn("Exception in lev_alloc_condition: %s", th.msg);
			return null;
		}
	}

	void lev_free_condition(void* cond)
	{
		try {
			auto lc = cast(LevCondition*)cond;
			if (lc.cond) ConditionAlloc.free(lc.cond);
			LevConditionAlloc.free(lc);
		} catch (UncaughtException th) {
			logCritical("Exception in lev_free_condition: %s", th.msg);
			assert(false);
		}
	}

	int lev_signal_condition(void* cond, int broadcast)
	{
		try {
			auto c = cast(LevCondition*)cond;
			if( c.cond ) c.cond.notifyAll();
			return 0;
		} catch (UncaughtException th) {
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
			if( c.cond is null ) c.cond = ConditionAlloc.alloc(c.mutex.mutex);
			if( timeout ){
				if( !c.cond.wait(dur!"seconds"(timeout.tv_sec) + dur!"usecs"(timeout.tv_usec)) )
					return 1;
			} else c.cond.wait();
			return 0;
		} catch (UncaughtException th) {
			logWarn("Exception in lev_wait_condition: %s", th.msg);
			return -1;
		}
	}

	c_ulong lev_get_thread_id()
	{
		try return cast(c_ulong)cast(void*)Thread.getThis();
		catch (UncaughtException th) {
			logWarn("Exception in lev_get_thread_id: %s", th.msg);
			return 0;
		}
	}
}

}
