/**
	Driver implementation for the libevent library

	Libevent is a well-established event notification library.
	It is currently the default driver for Vibe.d

	See_Also:
		`vibe.core.driver` = interface definition
		http://libevent.org/ = Official website
		`vibe.core.drivers.libevent2_tcp` = Implementation of TCPConnection and TCPListener

	Copyright: © 2012-2015 RejectedSoftware e.K.
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
import vibe.internal.meta.traits : synchronizedIsNothrow;
import vibe.utils.array : ArraySet;
import vibe.utils.hashmap;
import vibe.internal.allocator;
import vibe.internal.freelistref;

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
import std.exception;
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
	import core.sys.windows.winsock2;
	alias EWOULDBLOCK = WSAEWOULDBLOCK;
}
else version(OSX)
{
	static if (__VERSION__ < 2077) {
		enum IP_ADD_MEMBERSHIP = 12;
		enum IP_MULTICAST_LOOP = 11;
	}
	else
		import core.sys.darwin.netinet.in_ : IP_ADD_MEMBERSHIP, IP_MULTICAST_LOOP;
}
else version (FreeBSD)
{
	static if (__VERSION__ < 2077) {
		enum IP_ADD_MEMBERSHIP  = 12;
		enum IP_MULTICAST_LOOP  = 11;
	}
	else
		import core.sys.freebsd.netinet.in_ : IP_ADD_MEMBERSHIP, IP_MULTICAST_LOOP;
}
else version (DragonFlyBSD)
{
    import core.sys.dragonflybsd.netinet.in_ : IP_ADD_MEMBERSHIP, IP_MULTICAST_LOOP;
}
else version (linux)
{
	static if (__VERSION__ < 2077) {
		enum IP_ADD_MEMBERSHIP =  35;
		enum IP_MULTICAST_LOOP =  34;
	}
	else
		import core.sys.linux.netinet.in_ : IP_ADD_MEMBERSHIP, IP_MULTICAST_LOOP;
}
else version (Solaris)
{
	enum IP_ADD_MEMBERSHIP = 0x13;
	enum IP_MULTICAST_LOOP = 0x12;
}
else static assert(false, "IP_ADD_MEMBERSHIP, IP_MULTICAST_LOOP required but not provided for this OS");

final class Libevent2Driver : EventDriver {
@safe:

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
		SysTime m_timerTimeout = SysTime.max;
		TimerQueue!TimerInfo m_timers;

		bool m_running = false; // runEventLoop in progress?

		IAllocator m_allocator;
	}

	this(DriverCore core) @trusted nothrow
	{
		debug m_ownerThread = () @trusted { return Thread.getThis(); } ();
		m_core = core;
		s_driverCore = core;

		m_allocator = Mallocator.instance.allocatorObject;
		s_driver = this;

		synchronized if (!s_threadObjectsMutex) {
			s_threadObjectsMutex = new Mutex;
			s_threadObjects.setAllocator(m_allocator);

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
		}

		// initialize libevent
		logDiagnostic("libevent version: %s", event_get_version());
		m_eventLoop = event_base_new();
		s_eventLoop = m_eventLoop;
		logDiagnostic("libevent is using %s for events.", event_base_get_method(m_eventLoop));
		evthread_make_base_notifiable(m_eventLoop);

		m_dnsBase = evdns_base_new(m_eventLoop, 1);
		if( !m_dnsBase ) logError("Failed to initialize DNS lookup.");
		evdns_base_set_option(m_dnsBase, "randomize-case:", "0");

		string hosts_file;
		version (Windows) hosts_file = `C:\Windows\System32\drivers\etc\hosts`;
		else hosts_file = `/etc/hosts`;
		if (existsFile(hosts_file)) {
			if (evdns_base_load_hosts(m_dnsBase, hosts_file.toStringz()) != 0)
				logError("Failed to load hosts file at %s", hosts_file);
		}

		m_timerEvent = () @trusted { return event_new(m_eventLoop, -1, EV_TIMEOUT, &onTimerTimeout, cast(void*)this); } ();
	}

	void dispose()
	{
		debug assert(() @trusted { return Thread.getThis(); } () is m_ownerThread, "Event loop destroyed in foreign thread.");

		() @trusted { event_free(m_timerEvent); } ();

		// notify all other living objects about the shutdown
		synchronized (() @trusted { return s_threadObjectsMutex; } ()) {
			// destroy all living objects owned by this driver
			foreach (ref key; m_ownedObjects) {
				assert(key);
				auto obj = () @trusted { return cast(Libevent2Object)cast(void*)key; } ();
				debug assert(obj.m_ownerThread is m_ownerThread, "Owned object with foreign thread ID detected.");
				debug assert(obj.m_driver is this, "Owned object with foreign driver reference detected.");
				key = 0;
				() @trusted { destroy(obj); } ();
			}

			ref getThreadObjects() @trusted { return s_threadObjects; }

			foreach (ref key; getThreadObjects()) {
				assert(key);
				auto obj = () @trusted { return cast(Libevent2Object)cast(void*)key; } ();
				debug assert(obj.m_ownerThread !is m_ownerThread, "Live object of this thread detected after all owned mutexes have been destroyed.");
				debug assert(obj.m_driver !is this, "Live object of this driver detected with different thread ID after all owned mutexes have been destroyed.");
				// WORKAROUND for a possible race-condition in case of concurrent GC collections
				// Since this only occurs on shutdown and rarely, this should be an acceptable
				// "solution" until this is all switched to RC.
				if (auto me = cast(Libevent2ManualEvent)obj)
					if (!me.m_mutex) continue;
				obj.onThreadShutdown();
			}
		}

		// shutdown libevent for this thread
		() @trusted {
			evdns_base_free(m_dnsBase, 1);
			event_base_free(m_eventLoop);
		} ();
		s_eventLoop = null;
		s_alreadyDeinitialized = true;
	}

	@property event_base* eventLoop() nothrow { return m_eventLoop; }
	@property evdns_base* dnsEngine() nothrow { return m_dnsBase; }

	int runEventLoop()
	{
		m_running = true;
		scope (exit) m_running = false;

		int ret;
		m_exit = false;
		while (!m_exit && (ret = () @trusted { return event_base_loop(m_eventLoop, EVLOOP_ONCE); } ()) == 0) {
			processTimers();
			() @trusted { return s_driverCore; } ().notifyIdle();
		}
		m_exit = false;
		return ret;
	}

	int runEventLoopOnce()
	{
		auto ret = () @trusted { return event_base_loop(m_eventLoop, EVLOOP_ONCE); } ();
		processTimers();
		m_core.notifyIdle();
		return ret;
	}

	bool processEvents()
	{
		logDebugV("process events with exit == %s", m_exit);
		() @trusted { event_base_loop(m_eventLoop, EVLOOP_NONBLOCK|EVLOOP_ONCE); } ();
		processTimers();
		logDebugV("processed events with exit == %s", m_exit);
		if (m_exit) {
			// leave the flag set, if the event loop is still running to let it exit, too
			if (!m_running) m_exit = false;
			return false;
		}
		return true;
	}

	void exitEventLoop()
	{
		logDebug("Libevent2Driver.exitEventLoop called");
		m_exit = true;
		enforce(() @trusted { return event_base_loopbreak(m_eventLoop); } () == 0, "Failed to exit libevent event loop.");
	}

	ThreadedFileStream openFile(Path path, FileMode mode)
	{
		return new ThreadedFileStream(path, mode);
	}

	DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		version (linux) return new InotifyDirectoryWatcher(m_core, path, recursive);
		assert(false, "watchDirectory is not yet implemented in the libevent driver.");
	}

	NetworkAddress resolveHost(string host, ushort family = AF_UNSPEC, bool use_dns = true)
	{
		assert(m_dnsBase);

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
		evdns_getaddrinfo_request* dnsReq = () @trusted { return evdns_getaddrinfo(m_dnsBase, toStringz(host), null,
			&hints, &onAddrInfo, &msg); } ();

		// wait if the request couldn't be fulfilled instantly
		if (!msg.done) {
			assert(dnsReq !is null);
			msg.task = Task.getThis();
			logDebug("dnsresolve yield");
			while (!msg.done) m_core.yieldForEvent();
		}

		logDebug("dnsresolve ret");
		enforce(msg.err == DNS_ERR_NONE, format("Failed to lookup host '%s': %s", host, () @trusted { return evutil_gai_strerror(msg.err); } ()));

		return msg.addr;
	}

	Libevent2TCPConnection connectTCP(NetworkAddress addr, NetworkAddress bind_addr)
	{
		assert(addr.family == bind_addr.family, "Mismatching bind and target address.");

		auto sockfd_raw = () @trusted { return socket(addr.family, SOCK_STREAM, 0); } ();
		// on Win64 socket() returns a 64-bit value but libevent expects an int
		static if (typeof(sockfd_raw).max > int.max) assert(sockfd_raw <= int.max || sockfd_raw == ~0);
		auto sockfd = cast(int)sockfd_raw;
		socketEnforce(sockfd != -1, "Failed to create socket.");

		socketEnforce(() @trusted { return bind(sockfd, bind_addr.sockAddr, bind_addr.sockAddrLen); } () == 0, "Failed to bind socket.");

		if (() @trusted { return evutil_make_socket_nonblocking(sockfd); } ())
			throw new Exception("Failed to make socket non-blocking.");

		auto buf_event = () @trusted { return bufferevent_socket_new(m_eventLoop, sockfd, bufferevent_options.BEV_OPT_CLOSE_ON_FREE); } ();
		if (!buf_event) throw new Exception("Failed to create buffer event for socket.");

		auto cctx = () @trusted { return TCPContextAlloc.alloc(m_core, m_eventLoop, sockfd, buf_event, bind_addr, addr); } ();
		scope(failure) () @trusted {
			if (cctx.event) bufferevent_free(cctx.event);
			TCPContextAlloc.free(cctx);
		} ();
		() @trusted { bufferevent_setcb(buf_event, &onSocketRead, &onSocketWrite, &onSocketEvent, cctx); } ();
		if (() @trusted { return bufferevent_enable(buf_event, EV_READ|EV_WRITE); } ())
			throw new Exception("Error enabling buffered I/O event for socket.");

		cctx.readOwner = Task.getThis();
		scope(exit) cctx.readOwner = Task();

		assert(cctx.exception is null);
		socketEnforce(() @trusted { return bufferevent_socket_connect(buf_event, addr.sockAddr, addr.sockAddrLen); } () == 0,
			"Failed to connect to " ~ addr.toString());

		try {
			cctx.checkForException();

			// TODO: cctx.remote_addr6 = ...;

			while (cctx.status == 0)
				m_core.yieldForEvent();
		} catch (InterruptException e) {
			throw e;
		} catch (Exception e) {
			throw new Exception(format("Failed to connect to %s: %s", addr.toString(), e.msg));
		}

		logTrace("Connect result status: %d", cctx.status);
		enforce(cctx.status == BEV_EVENT_CONNECTED, cctx.statusMessage
			? format("Failed to connect to host %s: %s", addr.toString(), cctx.statusMessage)
			: format("Failed to connect to host %s: %s", addr.toString(), cctx.status));

		socklen_t balen = bind_addr.sockAddrLen;
		socketEnforce(() @trusted { return getsockname(sockfd, bind_addr.sockAddr, &balen); } () == 0, "getsockname failed.");
		cctx.local_addr = bind_addr;

		return new Libevent2TCPConnection(cctx);
	}

	Libevent2TCPListener listenTCP(ushort port, void delegate(TCPConnection conn) @safe connection_callback, string address, TCPListenOptions options)
	{
		auto bind_addr = resolveHost(address, AF_UNSPEC, false);
		bind_addr.port = port;

		auto listenfd_raw = () @trusted { return socket(bind_addr.family, SOCK_STREAM, 0); } ();
		// on Win64 socket() returns a 64-bit value but libevent expects an int
		static if (typeof(listenfd_raw).max > int.max) assert(listenfd_raw <= int.max || listenfd_raw == ~0);
		auto listenfd = cast(int)listenfd_raw;
		socketEnforce(listenfd != -1, "Error creating listening socket");
		int tmp_reuse = 1;
		socketEnforce(() @trusted { return setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof); } () == 0,
			"Error enabling socket address reuse on listening socket");
		static if (is(typeof(SO_REUSEPORT))) {
			if (options & TCPListenOptions.reusePort) {
				if (() @trusted { return setsockopt(listenfd, SOL_SOCKET, SO_REUSEPORT, &tmp_reuse, tmp_reuse.sizeof); } ()) {
					if (errno != EINVAL && errno != ENOPROTOOPT) {
						socketEnforce(false, "Error enabling socket port reuse on listening socket");
					}
				}
			}
		}
		socketEnforce(() @trusted { return bind(listenfd, bind_addr.sockAddr, bind_addr.sockAddrLen); } () == 0,
			"Error binding listening socket");

		socketEnforce(() @trusted { return listen(listenfd, 128); } () == 0,
			"Error listening to listening socket");

		// Set socket for non-blocking I/O
		enforce(() @trusted { return evutil_make_socket_nonblocking(listenfd); } () == 0,
			"Error setting listening socket to non-blocking I/O.");

		socklen_t balen = bind_addr.sockAddrLen;
		socketEnforce(() @trusted { return getsockname(listenfd, bind_addr.sockAddr, &balen); } () == 0, "getsockname failed.");

		auto ret = new Libevent2TCPListener(bind_addr);

		static final class HandlerContext {
			Libevent2TCPListener listener;
			int listenfd;
			NetworkAddress bind_addr;
			void delegate(TCPConnection) @safe connection_callback;
			TCPListenOptions options;
		}

		auto hc = new HandlerContext;
		hc.listener = ret;
		hc.listenfd = listenfd;
		hc.bind_addr = bind_addr;
		hc.connection_callback = connection_callback;
		hc.options = options;

		static void setupConnectionHandler(shared(HandlerContext) handler_context_)
		@safe {
			auto handler_context = () @trusted { return cast(HandlerContext)handler_context_; } ();
			auto evloop = getThreadLibeventEventLoop();
			auto core = getThreadLibeventDriverCore();
			// Add an event to wait for connections
			auto ctx = () @trusted { return TCPContextAlloc.alloc(core, evloop, handler_context.listenfd, null, handler_context.bind_addr, NetworkAddress()); } ();
			scope(failure) () @trusted { TCPContextAlloc.free(ctx); } ();
			ctx.connectionCallback = handler_context.connection_callback;
			ctx.listenEvent = () @trusted { return event_new(evloop, handler_context.listenfd, EV_READ | EV_PERSIST, &onConnect, ctx); } ();
			ctx.listenOptions = handler_context.options;
			enforce(() @trusted { return event_add(ctx.listenEvent, null); } () == 0,
				"Error scheduling connection event on the event loop.");
			handler_context.listener.addContext(ctx);
		}

		// FIXME: the API needs improvement with proper shared annotations, so the the following casts are not necessary
		if (options & TCPListenOptions.distribute) () @trusted { return runWorkerTaskDist(&setupConnectionHandler, cast(shared)hc); } ();
		else setupConnectionHandler(() @trusted { return cast(shared)hc; } ());

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

	Libevent2FileDescriptorEvent createFileDescriptorEvent(int fd, FileDescriptorEvent.Trigger events, FileDescriptorEvent.Mode mode)
	{
		return new Libevent2FileDescriptorEvent(this, fd, events, mode);
	}

	size_t createTimer(void delegate() @safe callback) { return m_timers.create(TimerInfo(callback)); }

	void acquireTimer(size_t timer_id) { m_timers.getUserData(timer_id).refCount++; }
	void releaseTimer(size_t timer_id)
	nothrow {
		debug assert(m_ownerThread is () @trusted { return Thread.getThis(); } ());
		if (!--m_timers.getUserData(timer_id).refCount)
			m_timers.destroy(timer_id);
	}

	bool isTimerPending(size_t timer_id) { return m_timers.isPending(timer_id); }

	void rearmTimer(size_t timer_id, Duration dur, bool periodic)
	{
		debug assert(m_ownerThread is () @trusted { return Thread.getThis(); } ());
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
		debug assert(m_ownerThread is () @trusted { return Thread.getThis(); } ());
		while (true) {
			assert(!m_timers.isPeriodic(timer_id), "Cannot wait for a periodic timer.");
			if (!m_timers.isPending(timer_id)) return;
			auto data = () @trusted { return &m_timers.getUserData(timer_id); } ();
			assert(data.owner == Task.init, "Waiting for the same timer from multiple tasks is not supported.");
			data.owner = Task.getThis();
			scope (exit) m_timers.getUserData(timer_id).owner = Task.init;
			m_core.yieldForEvent();
		}
	}

	private void processTimers()
	{
		if (!m_timers.anyPending) return;

		logTrace("Processing due timers");
		// process all timers that have expired up to now
		auto now = Clock.currTime(UTC());
		m_timers.consumeTimeouts(now, (timer, periodic, ref data) @safe {
			Task owner = data.owner;
			auto callback = data.callback;

			logTrace("Timer %s fired (%s/%s)", timer, owner != Task.init, callback !is null);

			if (!periodic) releaseTimer(timer);

			if (owner && owner.running) m_core.resumeTask(owner);
			if (callback) () @trusted { runTask(callback); } ();
		});

		rescheduleTimerEvent(now);
	}

	private void rescheduleTimerEvent(SysTime now)
	{
		auto next = m_timers.getFirstTimeout();
		if (next == SysTime.max || next == m_timerTimeout) return;

		m_timerTimeout = now;
		auto dur = next - now;
		() @trusted { event_del(m_timerEvent); } ();
		assert(dur.total!"seconds"() <= int.max);
		dur += 9.hnsecs(); // round up to the next usec to avoid premature timer events
		timeval tvdur = dur.toTimeVal();
		() @trusted { event_add(m_timerEvent, &tvdur); } ();
		assert(() @trusted { return event_pending(m_timerEvent, EV_TIMEOUT, null); } ());
		logTrace("Rescheduled timer event for %s seconds", dur.total!"usecs" * 1e-6);
	}

	private static nothrow extern(C)
	void onTimerTimeout(evutil_socket_t, short events, void* userptr)
	{
		import std.encoding : sanitize;

		logTrace("timer event fired");
		auto drv = () @trusted { return cast(Libevent2Driver)userptr; } ();
		try drv.processTimers();
		catch (Exception e) {
			logError("Failed to process timers: %s", e.msg);
			try logDiagnostic("Full error: %s", () @trusted { return e.toString().sanitize; } ());
			catch (Exception e) {
				logError("Failed to process timers: %s", e.msg);
			}
		}
	}

	private static nothrow extern(C) void onAddrInfo(int err, evutil_addrinfo* res, void* arg)
	{
		auto msg = () @trusted { return cast(GetAddrInfoMsg*)arg; } ();
		msg.err = err;
		msg.done = true;
		if (err == DNS_ERR_NONE) {
			assert(res !is null);
			scope (exit) () @trusted { evutil_freeaddrinfo(res); } ();

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
					auto sock6 = () @trusted { return cast(sockaddr_in6*)res.ai_addr; } ();
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
	nothrow {
		debug assert(() @trusted { return Thread.getThis(); } () is m_ownerThread, "Event object created in foreign thread.");
		auto key = () @trusted { return cast(size_t)cast(void*)obj; } ();
		m_ownedObjects.insert(key);
		if (obj.m_threadObject)
			() @trusted {
				scope (failure) assert(false); // synchronized is not nothrow
				synchronized (s_threadObjectsMutex)
					s_threadObjects.insert(key);
			} ();
	}

	private void unregisterObject(Libevent2Object obj)
	nothrow {
		scope (failure) assert(false); // synchronized is not nothrow

		auto key = () @trusted { return cast(size_t)cast(void*)obj; } ();
		m_ownedObjects.remove(key);
		if (obj.m_threadObject)
			() @trusted {
				synchronized (s_threadObjectsMutex)
					s_threadObjects.remove(key);
			} ();
	}
}

private struct TimerInfo {
	size_t refCount = 1;
	void delegate() @safe callback;
	Task owner;

	this(void delegate() @safe callback) @safe { this.callback = callback; }
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
	private bool m_threadObject;

	this(Libevent2Driver driver, bool thread_object)
	nothrow @safe {
		m_threadObject = thread_object;
		m_driver = driver;
		m_driver.registerObject(this);
		debug m_ownerThread = driver.m_ownerThread;
	}

	~this()
	@trusted {
		// NOTE: m_driver will always be destroyed deterministically
		//       in static ~this(), so it can be used here safely
		m_driver.unregisterObject(this);
	}

	protected void onThreadShutdown() @safe {}
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
@safe:

	private {
		shared(int) m_emitCount = 0;
		core.sync.mutex.Mutex m_mutex;
		ThreadSlotMap m_waiters;
	}

	this(Libevent2Driver driver)
	nothrow {
		super(driver, true);
		scope (failure) assert(false);
		m_mutex = new core.sync.mutex.Mutex;
		m_waiters = ThreadSlotMap(driver.m_allocator);
	}

	~this()
	{
		m_mutex = null; // Optimistic race-condition detection (see Libevent2Driver.dispose())
		foreach (ref m_waiters.Value ts; m_waiters)
			() @trusted { event_free(ts.event); } ();
	}

	void emit()
	{
		static if (!synchronizedIsNothrow)
			scope (failure) assert(0, "Internal error: function should be nothrow");

		() @trusted { atomicOp!"+="(m_emitCount, 1); } ();
		synchronized (m_mutex) {
			foreach (ref m_waiters.Value sl; m_waiters)
				() @trusted { event_active(sl.event, 0, 0); } ();
		}
	}

	void wait() { wait(m_emitCount); }
	int wait(int reference_emit_count) { return  doWait!true(reference_emit_count); }
	int wait(Duration timeout, int reference_emit_count) { return doWait!true(timeout, reference_emit_count); }
	int waitUninterruptible(int reference_emit_count) { return  doWait!false(reference_emit_count); }
	int waitUninterruptible(Duration timeout, int reference_emit_count) { return doWait!false(timeout, reference_emit_count); }

	void acquire()
	{
		auto task = Task.getThis();
		auto thread = task == Task() ? () @trusted { return Thread.getThis(); } () : task.thread;

		synchronized (m_mutex) {
			if (thread !in m_waiters) {
				ThreadSlot slot;
				slot.driver = cast(Libevent2Driver)getEventDriver();
				slot.event = () @trusted { return event_new(slot.driver.eventLoop, -1, EV_PERSIST, &onSignalTriggered, cast(void*)this); } ();
				() @trusted { event_add(slot.event, null); } ();
				m_waiters[thread] = slot;
			}

			if (task != Task()) {
				assert(task !in m_waiters[thread].tasks, "Double acquisition of signal.");
				m_waiters[thread].tasks.insert(task);
			}
		}
	}

	void release()
	{
		auto self = Task.getThis();
		if (self == Task()) return;

		synchronized (m_mutex) {
			assert(self.thread in m_waiters && self in m_waiters[self.thread].tasks,
				"Releasing non-acquired signal.");
			m_waiters[self.thread].tasks.remove(self);
		}
	}

	bool amOwner()
	{
		auto self = Task.getThis();
		if (self == Task()) return false;
		synchronized (m_mutex) {
			if (self.thread !in m_waiters) return false;
			return self in m_waiters[self.thread].tasks;
		}
	}

	@property int emitCount() const @trusted { return atomicLoad(m_emitCount); }

	protected override void onThreadShutdown()
	{
		auto thr = () @trusted { return Thread.getThis(); } ();
		synchronized (m_mutex) {
			if (thr in m_waiters) {
				() @trusted { event_free(m_waiters[thr].event); } ();
				m_waiters.remove(thr);
			}
		}
	}

	private int doWait(bool INTERRUPTIBLE)(int reference_emit_count)
	{
		static if (!INTERRUPTIBLE) scope (failure) assert(false); // still some function calls not marked nothrow
		assert(!amOwner());

		auto ec = this.emitCount;
		if (ec != reference_emit_count) return ec;

		acquire();
		scope(exit) release();

		while (ec == reference_emit_count) {
			static if (INTERRUPTIBLE) getThreadLibeventDriverCore().yieldForEvent();
			else getThreadLibeventDriverCore().yieldForEventDeferThrow();
			ec = this.emitCount;
		}
		return ec;
	}

	private int doWait(bool INTERRUPTIBLE)(Duration timeout, int reference_emit_count)
	{
		static if (!INTERRUPTIBLE) scope (failure) assert(false); // still some function calls not marked nothrow
		assert(!amOwner());

		auto ec = this.emitCount;
		if (ec != reference_emit_count) return ec;

		acquire();
		scope(exit) release();
		auto tm = m_driver.createTimer(null);
		scope (exit) m_driver.releaseTimer(tm);
		m_driver.m_timers.getUserData(tm).owner = Task.getThis();
		m_driver.rearmTimer(tm, timeout, false);

		while (ec == reference_emit_count) {
			static if (INTERRUPTIBLE) getThreadLibeventDriverCore().yieldForEvent();
			else getThreadLibeventDriverCore().yieldForEventDeferThrow();
			ec = this.emitCount;
			if (!m_driver.isTimerPending(tm)) break;
		}
		return ec;
	}

	private static nothrow extern(C)
	void onSignalTriggered(evutil_socket_t, short events, void* userptr)
	{
		import std.encoding : sanitize;

		try {
			auto sig = () @trusted { return cast(Libevent2ManualEvent)userptr; } ();
			auto thread = () @trusted { return Thread.getThis(); } ();
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
			try logDiagnostic("Full error: %s", () @trusted { return sanitize(e.msg); } ());
			catch(Exception) {}
			debug assert(false);
		}
	}
}


final class Libevent2FileDescriptorEvent : Libevent2Object, FileDescriptorEvent {
@safe:

	private {
		int m_fd;
		deimos.event2.event.event* m_event;
		bool m_persistent;
		Trigger m_activeEvents;
		Task m_waiter;
	}

	this(Libevent2Driver driver, int file_descriptor, Trigger events, Mode mode)
	{
		assert(events != Trigger.none);
		super(driver, false);
		m_fd = file_descriptor;
		m_persistent = mode != Mode.nonPersistent;
		short evts = 0;
		if (events & Trigger.read) evts |= EV_READ;
		if (events & Trigger.write) evts |= EV_WRITE;
		if (m_persistent) evts |= EV_PERSIST;
		if (mode == Mode.edgeTriggered) evts |= EV_ET;
		m_event = () @trusted { return event_new(driver.eventLoop, file_descriptor, evts, &onFileTriggered, cast(void*)this); } ();
		if (m_persistent) () @trusted { event_add(m_event, null); } ();
	}

	~this()
	{
		() @trusted { event_free(m_event); } ();
	}

	Trigger wait(Trigger which)
	{
		assert(!m_waiter, "Only one task may wait on a Libevent2FileEvent.");
		m_waiter = Task.getThis();
		scope (exit) {
			m_waiter = Task.init;
			m_activeEvents &= ~which;
		}

		while ((m_activeEvents & which) == Trigger.none) {
			if (!m_persistent) () @trusted { event_add(m_event, null); } ();
			getThreadLibeventDriverCore().yieldForEvent();
		}
		return m_activeEvents & which;
	}

	Trigger wait(Duration timeout, Trigger which)
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
			if (!m_persistent) () @trusted { event_add(m_event, null); } ();
			getThreadLibeventDriverCore().yieldForEvent();
			if (!m_driver.isTimerPending(tm)) break;
		}
		return m_activeEvents & which;
	}

	private static nothrow extern(C)
	void onFileTriggered(evutil_socket_t fd, short events, void* userptr)
	{
		import std.encoding : sanitize;

		try {
			auto core = getThreadLibeventDriverCore();
			auto evt = () @trusted { return cast(Libevent2FileDescriptorEvent)userptr; } ();

			evt.m_activeEvents = Trigger.none;
			if (events & EV_READ) evt.m_activeEvents |= Trigger.read;
			if (events & EV_WRITE) evt.m_activeEvents |= Trigger.write;
			if (evt.m_waiter) core.resumeTask(evt.m_waiter);
		} catch (Exception e) {
			logError("Exception while handling file event: %s", e.msg);
			try logDiagnostic("Full error: %s", () @trusted { return sanitize(e.msg); } ());
			catch(Exception) {}
			debug assert(false);
		}
	}
}


final class Libevent2UDPConnection : UDPConnection {
@safe:

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

		auto sockfd_raw = () @trusted { return socket(bind_addr.family, SOCK_DGRAM, IPPROTO_UDP); } ();
		// on Win64 socket() returns a 64-bit value but libevent expects an int
		static if (typeof(sockfd_raw).max > int.max) assert(sockfd_raw <= int.max || sockfd_raw == ~0);
		auto sockfd = cast(int)sockfd_raw;
		socketEnforce(sockfd != -1, "Failed to create socket.");

		enforce(() @trusted { return evutil_make_socket_nonblocking(sockfd); } () == 0, "Failed to make socket non-blocking.");

		int tmp_reuse = 1;
		socketEnforce(() @trusted { return setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof); } () == 0,
			"Error enabling socket address reuse on listening socket");

		// bind the socket to a local inteface/port
		socketEnforce(() @trusted { return bind(sockfd, bind_addr.sockAddr, bind_addr.sockAddrLen); } () == 0, "Failed to bind UDP socket.");
		// read back the actual bind address
		socklen_t balen = bind_addr.sockAddrLen;
		socketEnforce(() @trusted { return getsockname(sockfd, bind_addr.sockAddr, &balen); } () == 0, "getsockname failed.");

		// generate the bind address string
		m_bindAddress = bind_addr;
		char[64] buf;
		void* ptr;
		if( bind_addr.family == AF_INET ) ptr = &bind_addr.sockAddrInet4.sin_addr;
		else ptr = &bind_addr.sockAddrInet6.sin6_addr;
		() @trusted { evutil_inet_ntop(bind_addr.family, ptr, buf.ptr, buf.length); } ();
		m_bindAddressString = () @trusted { return to!string(buf.ptr); } ();

		// create a context for storing connection information
		m_ctx = () @trusted { return TCPContextAlloc.alloc(driver.m_core, driver.m_eventLoop, sockfd, null, bind_addr, NetworkAddress()); } ();
		scope(failure) () @trusted { TCPContextAlloc.free(m_ctx); } ();
		m_ctx.listenEvent = () @trusted { return event_new(driver.m_eventLoop, sockfd, EV_READ|EV_PERSIST, &onUDPRead, m_ctx); } ();
		if (!m_ctx.listenEvent) throw new Exception("Failed to create buffer event for socket.");
	}

	@property string bindAddress() const { return m_bindAddressString; }
	@property NetworkAddress localAddress() const { return m_bindAddress; }

	@property bool canBroadcast() const { return m_canBroadcast; }
	@property void canBroadcast(bool val)
	{
		int tmp_broad = val;
		enforce(() @trusted { return setsockopt(m_ctx.socketfd, SOL_SOCKET, SO_BROADCAST, &tmp_broad, tmp_broad.sizeof); } () == 0,
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

	void close()
	{
		if (!m_ctx) return;
		acquire();

		if (m_ctx.listenEvent) () @trusted { event_free(m_ctx.listenEvent); } ();
		() @trusted { TCPContextAlloc.free(m_ctx); } ();
		m_ctx = null;
	}

	void connect(string host, ushort port)
	{
		NetworkAddress addr = m_driver.resolveHost(host, m_ctx.local_addr.family);
		addr.port = port;
		connect(addr);
	}

	void connect(NetworkAddress addr)
	{
		enforce(() @trusted { return .connect(m_ctx.socketfd, addr.sockAddr, addr.sockAddrLen); } () == 0, "Failed to connect UDP socket."~to!string(getLastSocketError()));
	}

	void send(in ubyte[] data, in NetworkAddress* peer_address = null)
	{
		sizediff_t ret;
		assert(data.length <= int.max);
		if( peer_address ){
			ret = () @trusted { return .sendto(m_ctx.socketfd, data.ptr, cast(int)data.length, 0, peer_address.sockAddr, peer_address.sockAddrLen); } ();
		} else {
			ret = () @trusted { return .send(m_ctx.socketfd, data.ptr, cast(int)data.length, 0); } ();
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
			m_driver.m_timers.getUserData(tm).owner = Task.getThis();
			m_driver.rearmTimer(tm, timeout, false);
		}

		acquire();
		// TODO: adds the event only when we actually read to avoid event loop
		// spinning when data is available, see #715. Since this may be
		// performance critical, a proper benchmark should be performed!
		enforce(() @trusted { return event_add(m_ctx.listenEvent, null); } () == 0);

		scope (exit) {
			() @trusted { event_del(m_ctx.listenEvent); } ();
			release();
			if (tm != size_t.max) m_driver.releaseTimer(tm);
		}

		if (buf.length == 0) buf.length = 65507;

		NetworkAddress from;
		from.family = m_ctx.local_addr.family;
		assert(buf.length <= int.max);
		while (true) {
			socklen_t addr_len = from.sockAddrLen;
			auto ret = () @trusted { return .recvfrom(m_ctx.socketfd, buf.ptr, cast(int)buf.length, 0, from.sockAddr, &addr_len); } ();
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

	override void addMembership(ref NetworkAddress multiaddr)
	{
		if (multiaddr.family == AF_INET)
		{
			version (Windows)
			{
				alias in_addr = core.sys.windows.winsock2.in_addr;
			} else
			{
				static import core.sys.posix.arpa.inet;
				alias in_addr = core.sys.posix.arpa.inet.in_addr;
			}
			struct ip_mreq {
				in_addr imr_multiaddr;   /* IP multicast address of group */
				in_addr imr_interface;   /* local IP address of interface */
			}
			auto inaddr = in_addr();
			inaddr.s_addr = htonl(INADDR_ANY);
			auto mreq = ip_mreq(multiaddr.sockAddrInet4.sin_addr, inaddr);
			enforce(() @trusted { return setsockopt (m_ctx.socketfd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, ip_mreq.sizeof); } () == 0,
				"Failed to add to multicast group");
		} else
		{
			version (Windows)
			{
				alias in6_addr = core.sys.windows.winsock2.in6_addr;
				struct ipv6_mreq {
					in6_addr ipv6mr_multiaddr;
					uint ipv6mr_interface;
				}
			}
			auto mreq = ipv6_mreq(multiaddr.sockAddrInet6.sin6_addr, 0);
			enforce(() @trusted { return setsockopt (m_ctx.socketfd, IPPROTO_IP, IPV6_JOIN_GROUP, &mreq, ipv6_mreq.sizeof); } () == 0,
				"Failed to add to multicast group");
		}
	}

	@property void multicastLoopback(bool loop)
	{
		int tmp_loop = loop;
		enforce(() @trusted { return setsockopt (m_ctx.socketfd, IPPROTO_IP, IP_MULTICAST_LOOP, &tmp_loop, tmp_loop.sizeof); } () == 0,
			"Failed to add to multicast loopback");
	}

	private static nothrow extern(C) void onUDPRead(evutil_socket_t sockfd, short evts, void* arg)
	{
		auto ctx = () @trusted { return cast(TCPContext*)arg; } ();
		logTrace("udp socket %d read event!", ctx.socketfd);

		try {
			auto f = ctx.readOwner;
			if (f && f.running)
				ctx.core.resumeTask(f);
		} catch( Exception e ){
			logError("Exception onUDPRead: %s", e.msg);
			debug assert(false);
		}
	}
}

/******************************************************************************/
/* InotifyDirectoryWatcher                                                    */
/******************************************************************************/

version (linux)
final class InotifyDirectoryWatcher : DirectoryWatcher {
@safe:

	import core.sys.posix.fcntl, core.sys.posix.unistd, core.sys.linux.sys.inotify;
	import std.file;

	private {
		Path m_path;
		string[int] m_watches;
		bool m_recursive;
		int m_handle;
		DriverCore m_core;
		Task m_owner;
	}

	this(DriverCore core, Path path, bool recursive)
	{
		m_core = core;
		m_recursive = recursive;
		m_path = path;

		enum IN_NONBLOCK = 0x800; // value in core.sys.linux.sys.inotify is incorrect
		m_handle = () @trusted { return inotify_init1(IN_NONBLOCK); } ();
		errnoEnforce(m_handle != -1, "Failed to initialize inotify.");

		auto spath = m_path.toString();
		addWatch(spath);
		if (recursive && spath.isDir)
		{
			() @trusted {
				foreach (de; spath.dirEntries(SpanMode.shallow))
					if (de.isDir) addWatch(de.name);
			} ();
		}
	}

	~this()
	{
		errnoEnforce(() @trusted { return close(m_handle); } () == 0);
	}

	@property Path path() const { return m_path; }
	@property bool recursive() const { return m_recursive; }

	void release()
	@safe {
		assert(m_owner == Task.getThis(), "Releasing DirectoyWatcher that is not owned by the calling task.");
		m_owner = Task();
	}

	void acquire()
	@safe {
		assert(m_owner == Task(), "Acquiring DirectoyWatcher that is already owned.");
		m_owner = Task.getThis();
	}

	bool amOwner()
	@safe {
		return m_owner == Task.getThis();
	}

	bool readChanges(ref DirectoryChange[] dst, Duration timeout)
	{
		import core.stdc.stdio : FILENAME_MAX;
		import core.stdc.string : strlen;

		acquire();
		scope(exit) release();

		ubyte[inotify_event.sizeof + FILENAME_MAX + 1] buf = void;
		auto nread = () @trusted { return read(m_handle, buf.ptr, buf.sizeof); } ();

		if (nread == -1 && errno == EAGAIN)
		{
			if (!waitReadable(m_handle, timeout))
				return false;
			nread = () @trusted { return read(m_handle, buf.ptr, buf.sizeof); } ();
		}
		errnoEnforce(nread != -1, "Error while reading inotify handle.");
		assert(nread > 0);

		dst.length = 0;
		do
		{
			for (size_t i = 0; i < nread;) {
				auto ev = &(cast(inotify_event[])buf[i .. i+inotify_event.sizeof])[0];
				if (ev.wd !in m_watches) {
					logDebug("Got unknown inotify watch ID %s. Ignoring.", ev.wd);
					continue;
				}

				DirectoryChangeType type;
				if (ev.mask & (IN_CREATE|IN_MOVED_TO))
					type = DirectoryChangeType.added;
				else if (ev.mask & (IN_DELETE|IN_DELETE_SELF|IN_MOVE_SELF|IN_MOVED_FROM))
					type = DirectoryChangeType.removed;
				else if (ev.mask & IN_MODIFY)
					type = DirectoryChangeType.modified;

				import std.path : buildPath;
				auto name = () @trusted { return ev.name.ptr[0 .. ev.name.ptr.strlen]; } ();
				auto path = Path(buildPath(m_watches[ev.wd], name));

				dst ~= DirectoryChange(type, path);

				i += inotify_event.sizeof + ev.len;
			}
			nread = () @trusted { return read(m_handle, buf.ptr, buf.sizeof); } ();
			errnoEnforce(nread != -1 || errno == EAGAIN, "Error while reading inotify handle.");
		} while (nread > 0);
		return true;
	}

	private bool waitReadable(int fd, Duration timeout)
	@safe {
		static struct Args { InotifyDirectoryWatcher watcher; bool readable, timeout; }

		static extern(System) void cb(int fd, short what, void* p) {
			with (() @trusted { return cast(Args*)p; } ()) {
				if (what & EV_READ) readable = true;
				if (what & EV_TIMEOUT) timeout = true;
				if (watcher.m_owner)
					watcher.m_core.resumeTask(watcher.m_owner);
			}
		}

		auto loop = getThreadLibeventEventLoop();
		auto args = Args(this);
		auto ev = () @trusted { return event_new(loop, fd, EV_READ, &cb, &args); } ();
		scope(exit) () @trusted { event_free(ev); } ();

		if (!timeout.isNegative) {
			auto tv = timeout.toTimeVal();
			() @trusted { event_add(ev, &tv); } ();
		} else {
			() @trusted { event_add(ev, null); } ();
		}
		while (!args.readable && !args.timeout)
			m_core.yieldForEvent();
		return args.readable;
	}

	private void addWatch(string path)
	@safe {
		enum EVENTS = IN_CREATE | IN_DELETE | IN_DELETE_SELF | IN_MODIFY |
			IN_MOVE_SELF | IN_MOVED_FROM | IN_MOVED_TO;
		immutable wd = () @trusted { return inotify_add_watch(m_handle, path.toStringz, EVENTS); } ();
		errnoEnforce(wd != -1, "Failed to add inotify watch.");
		m_watches[wd] = path;
	}
}


private {

	event_base* s_eventLoop; // TLS
	Libevent2Driver s_driver;
	__gshared DriverCore s_driverCore;
	// protects s_threadObjects and the m_ownerThread and m_driver fields of Libevent2Object
	__gshared Mutex s_threadObjectsMutex;
	__gshared ArraySet!size_t s_threadObjects;
	debug __gshared size_t[void*] s_mutexes;
	debug __gshared Mutex s_mutexesLock;
	bool s_alreadyDeinitialized = false;
}

package event_base* getThreadLibeventEventLoop() @safe nothrow
{
	return s_eventLoop;
}

package DriverCore getThreadLibeventDriverCore() @trusted nothrow
{
	return s_driverCore;
}

private int getLastSocketError() @trusted nothrow
{
	version(Windows) {
		return WSAGetLastError();
	} else {
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

alias LevConditionAlloc = FreeListObjectAlloc!(LevCondition, false);
alias LevMutexAlloc = FreeListObjectAlloc!(LevMutex, false);
alias MutexAlloc = FreeListObjectAlloc!(core.sync.mutex.Mutex, false);
alias ReadWriteMutexAlloc = FreeListObjectAlloc!(ReadWriteMutex, false);
alias ConditionAlloc = FreeListObjectAlloc!(Condition, false);

private nothrow extern(C)
{
	version (VibeDebugCatchAll) alias UncaughtException = Throwable;
	else alias UncaughtException = Exception;

	void* lev_alloc(size_t size)
	{
		try {
			auto mem = s_driver.m_allocator.allocate(size+size_t.sizeof);
			if (!mem.ptr) return null;
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
			auto newmem = oldmem;
			if (!s_driver.m_allocator.reallocate(newmem, newsize+size_t.sizeof))
				return null;
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
			s_driver.m_allocator.deallocate(mem);
		} catch (UncaughtException th) {
			logCritical("Exception in lev_free: %s", th.msg);
			assert(false);
		}
	}

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

package timeval toTimeVal(Duration dur)
@safe {
	timeval tvdur;
	dur.split!("seconds", "usecs")(tvdur.tv_sec, tvdur.tv_usec);
	return tvdur;
}

}
