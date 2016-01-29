/**
	libev based driver implementation

	Copyright: © 2012-2014 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libev;

version(VibeLibevDriver)
{

import vibe.core.core;
import vibe.core.driver;
import vibe.core.drivers.threadedfile;
import vibe.core.drivers.timerqueue;
import vibe.core.log;

import deimos.ev;

import std.algorithm : min;
import std.array;
import std.datetime;
import std.encoding;
import std.exception;
import std.conv;
import std.string;
import std.typecons;

import core.atomic;
import core.memory;
import core.sys.posix.netinet.tcp;
import core.thread;

version(Windows){
	import std.c.windows.winsock;
} else {
	import core.sys.posix.sys.socket;
	import core.sys.posix.sys.time;
 	import core.sys.posix.fcntl;
	import core.sys.posix.netdb;
	import core.sys.posix.netinet.in_;
	import core.sys.posix.unistd;
	import core.stdc.errno;
}


private extern(C){
	void* myrealloc(void* p, sizediff_t newsize){ return GC.realloc(p, newsize); }
}

final class LibevDriver : EventDriver {
	private {
		DriverCore m_core;
		ev_loop_t* m_loop;
		bool m_break = false;
		static __gshared DriverCore ms_core;
		static bool ms_alreadyDeinitialized;
		ev_timer m_timer;
		SysTime m_timerTimeout = SysTime.max;
		TimerQueue!TimerInfo m_timers;
		debug Thread m_ownerThread;
	}

	this(DriverCore core) nothrow
	{
		m_core = core;
		ms_core = core;
		ev_set_allocator(&myrealloc);
		m_loop = ev_loop_new(EVFLAG_AUTO);
		ev_timer_init(&m_timer, &onTimerTimeout, 0, 0);
		m_timer.data = cast(void*)this;
		assert(m_loop !is null, "Failed to create libev loop");
		debug m_ownerThread = Thread.getThis();
		logDiagnostic("Got libev backend: %d", ev_backend(m_loop));
	}

	void dispose()
	{
		ms_alreadyDeinitialized = true;
	}

	int runEventLoop()
	{
		while(!m_break){
			ev_run(m_loop, EVRUN_ONCE);
			m_core.notifyIdle();
		}
		m_break = false;
		logDebug("Event loop exit", m_break);
		return 0;
	}

	int runEventLoopOnce()
	{
		ev_run(m_loop, EVRUN_ONCE);
		m_core.notifyIdle();
		return 0;
	}

	bool processEvents()
	{
		ev_run(m_loop, EVRUN_NOWAIT);
		if (m_break) {
			m_break = false;
			return false;
		}
		return true;
	}

	void exitEventLoop()
	{
		logDebug("Exiting (%s)", m_break);
		m_break = true;
		ev_break(m_loop, EVBREAK_ALL);
	}

	ThreadedFileStream openFile(Path path, FileMode mode)
	{
		return new ThreadedFileStream(path, mode);
	}

	DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		assert(false);
	}

	/** Resolves the given host name or IP address string.
	*/
	NetworkAddress resolveHost(string host, ushort family, bool use_dns)
	{
		NetworkAddress addr;
		addr.family = AF_INET;
		enforce(inet_pton(AF_INET, toStringz(host), &addr.sockAddrInet4.sin_addr) == 1, "Only IP4 addresses supported by the libev backend at the moment.");
		return addr;
	}

	TCPConnection connectTCP(NetworkAddress addr)
	{
		int client_sd = socket(addr.family, SOCK_STREAM, 0);
		enforce(client_sd != -1, "Error creating socket.");

		// FIXME: perform connection in non-blocking mode!
		enforce(connect(client_sd, addr.sockAddr, addr.sockAddrLen) == 0, "Failed to connect to host.");

		setNonBlocking(client_sd);

		ev_io* r_client = new ev_io;
		ev_io* w_client = new ev_io;
		ev_io_init(r_client, &read_cb, client_sd, EV_READ);
		ev_io_init(w_client, &read_cb, client_sd, EV_WRITE);


		return new LibevTCPConnection(this, client_sd, r_client, w_client);
	}

	LibevTCPListener listenTCP(ushort port, void delegate(TCPConnection conn) conn_callback, string address, TCPListenOptions options)
	{
		sockaddr_in addr_ip4;
		addr_ip4.sin_family = AF_INET;
		addr_ip4.sin_port = htons(port);
		int ret;
		version(Windows){
			ret = 1;
			addr_ip4.sin_addr.s_addr = inet_addr(toStringz(address));
			// FIXME: support IPv6
			if( addr_ip4.sin_addr.s_addr  == INADDR_NONE ){
				logError("Not an IPv4 address: '%s'", address);
				return null;
			}
		} else {
			ret = inet_pton(AF_INET, toStringz(address), &addr_ip4.sin_addr);
		}
		if( ret == 1 ){
			auto rc = listenTCPGeneric(AF_INET, &addr_ip4, port, conn_callback, options);
			logInfo("Listening on %s port %d %s", address, port, (rc?"succeeded":"failed"));
			return rc;
		}

		version(Windows){}
		else {
			sockaddr_in6 addr_ip6;
			addr_ip6.sin6_family = AF_INET6;
			addr_ip6.sin6_port = htons(port);
			ret = inet_pton(AF_INET6, toStringz(address), &addr_ip6.sin6_addr);
			if( ret == 1 ){
				auto rc = listenTCPGeneric(AF_INET6, &addr_ip6, port, conn_callback, options);
				logInfo("Listening on %s port %d %s", address, port, (rc?"succeeded":"failed"));
				return rc;
			}
		}

		enforce(false, "Invalid IP address string: '"~address~"'");
		assert(false);
	}

	UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
	{
		assert(false);
	}

	LibevManualEvent createManualEvent()
	{
		return new LibevManualEvent;
	}

	FileDescriptorEvent createFileDescriptorEvent(int file_descriptor, FileDescriptorEvent.Trigger triggers)
	{
		assert(false);
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
		if (!m_timers.anyPending) return;

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
		if (next == SysTime.max || next == m_timerTimeout) return;

		m_timerTimeout = now;
		auto dur = next - now;
		assert(dur.total!"seconds"() <= int.max);
		dur += 9.hnsecs(); // round up to the next usec to avoid premature timer events
		ev_timer_stop(m_loop, &m_timer);
		ev_timer_set(&m_timer, dur.total!"usecs" * 1e-6, 0);
		ev_timer_start(m_loop, &m_timer);

		logTrace("Rescheduled timer event for %s seconds", dur.total!"usecs" * 1e-6);
	}

	private static nothrow extern(C)
	void onTimerTimeout(ev_loop_t *loop, ev_timer *w, int revents)
	{
		import std.encoding : sanitize;

		logTrace("timer event fired");
		auto drv = cast(LibevDriver)w.data;
		try drv.processTimers();
		catch (Exception e) {
			logError("Failed to process timers: %s", e.msg);
			try logDiagnostic("Full error: %s", e.toString().sanitize); catch (Throwable) {}
		}
	}

	private LibevTCPListener listenTCPGeneric(SOCKADDR)(int af, SOCKADDR* sock_addr, ushort port, void delegate(TCPConnection conn) connection_callback, TCPListenOptions options)
	{
		auto listenfd = socket(af, SOCK_STREAM, 0);
		if( listenfd == -1 ){
			logError("Error creating listening socket> %s", af);
			return null;
		}
		int tmp_reuse = 1;
		if( setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof) ){
			logError("Error enabling socket address reuse on listening socket");
			return null;
		}
		version(linux) {
			import vibe.core.drivers.utils;
			if (options & TCPListenOptions.reusePort) {
				if (setsockopt(listenfd, SOL_SOCKET, SO_REUSEPORT, &tmp_reuse, tmp_reuse.sizeof)) {
					// ignore invalid and not supported errors
					if (errno != EINVAL && errno != ENOPROTOOPT) {
						logError("Error enabling socket port reuse on listening socket");
						return null;
					}
				}
			}
		}
		if( bind(listenfd, cast(
sockaddr*)sock_addr, SOCKADDR.sizeof) ){
			logError("Error binding listening socket");
			return null;
		}
		if( listen(listenfd, 128) ){
			logError("Error listening to listening socket");
			return null;
		}

		// Set socket for non-blocking I/O
		setNonBlocking(listenfd);

		auto w_accept = new ev_io;
		ev_io_init(w_accept, &accept_cb, listenfd, EV_READ);
		ev_io_start(m_loop, w_accept);

		w_accept.data = cast(void*)this;
		//addEventReceiver(m_core, listenfd, new LibevTCPListener(connection_callback));

		// TODO: support TCPListenOptions.distribute

		return new LibevTCPListener(this, listenfd, w_accept, connection_callback, options);
	}
}


final class LibevManualEvent : ManualEvent {
	private {
		struct ThreadSlot {
			LibevDriver driver;
			ev_async signal;
			bool[Task] tasks;
		}
		shared int m_emitCount = 0;
		__gshared core.sync.mutex.Mutex m_mutex;
		__gshared ThreadSlot*[Thread] m_waiters;
	}

	this()
	nothrow {
		static if (__VERSION__ <= 2066) scope (failure) assert(false);
		m_mutex = new core.sync.mutex.Mutex;
	}

	/*~this()
	{
		if( !LibevDriver.ms_alreadyDeinitialized ){
			// FIXME: this is illegal (accessing GC memory)
			foreach (ts; m_waiters)
				ev_...();
		}
	}*/

	void emit()
	{
		scope (failure) assert(false); // synchronized is not nothrow on DMD 2.066 and below, AA.opApply is not nothrow
		atomicOp!"+="(m_emitCount, 1);
		synchronized (m_mutex) {
			foreach (th, sl; m_waiters) {
				if (!sl.tasks.length) continue;
				if (!ev_async_pending(&sl.signal))
					ev_async_send(sl.driver.m_loop, &sl.signal);
			}
		}
	}

	void wait() { wait(m_emitCount); }
	int wait(int reference_emit_count) { return doWait!true(reference_emit_count); }
	int wait(Duration timeout, int reference_emit_count) { return doWait!true(timeout, reference_emit_count); }
	int waitUninterruptible(int reference_emit_count) { return doWait!false(reference_emit_count); }
	int waitUninterruptible(Duration timeout, int reference_emit_count) { return doWait!false(timeout, reference_emit_count); }

	void acquire()
	{
		auto task = Task.getThis();
		auto thread = task == Task.init ? Thread.getThis() : task.thread;
		synchronized (m_mutex) {
			if (thread !in m_waiters) {
				auto slot = new ThreadSlot;
				m_waiters[thread] = slot;
				slot.driver = cast(LibevDriver)getEventDriver();
				ev_async_init(&slot.signal, &onSignal);
				ev_async_start(slot.driver.m_loop, &slot.signal);
				slot.signal.data = cast(void*)this;
			}
			assert(task !in m_waiters[thread].tasks, "Double acquisition of signal.");
			m_waiters[thread].tasks[task] = true;
		}
	}

	void release()
	{
		auto self = Task.getThis();
		auto thread = self == Task.init ? Thread.getThis() : self.thread;

		synchronized (m_mutex) {
			assert(thread in m_waiters && self in m_waiters[thread].tasks,
				"Releasing non-acquired signal.");
			m_waiters[thread].tasks.remove(self);
		}
	}

	bool amOwner()
	{
		auto self = Task.getThis();

		synchronized (m_mutex) {
			if (self.thread !in m_waiters) return false;
			return (self in m_waiters[self.thread].tasks) !is null;
		}
	}

	@property int emitCount() const { return atomicLoad(m_emitCount); }

	private int doWait(bool INTERRUPTIBLE)(int reference_emit_count)
	{
		static if (!INTERRUPTIBLE) scope (failure) assert(false); // some functions are still not annotated nothrow
		assert(!amOwner());
		acquire();
		scope(exit) release();
		auto ec = this.emitCount;
		while( ec == reference_emit_count ){
			static if (INTERRUPTIBLE) LibevDriver.ms_core.yieldForEvent();
			else LibevDriver.ms_core.yieldForEventDeferThrow();
			ec = this.emitCount;
		}
		return ec;
	}

	private int doWait(bool INTERRUPTIBLE)(Duration timeout, int reference_emit_count)
	{
		assert(false, "Not implemented!");
	}


	private static nothrow extern(C)
	void onSignal(ev_loop_t* loop, ev_async* w, int revents)
	{
		try {
			auto sig = cast(LibevManualEvent)w.data;
			auto thread = Thread.getThis();
			auto core = LibevDriver.ms_core;

			bool[Task] lst;
			synchronized (sig.m_mutex) {
				assert(thread in sig.m_waiters, "Thread \""~thread.name~"\" not in waiter list, yet received a signal?");
				lst = sig.m_waiters[thread].tasks.dup;
			}

			foreach (l; lst.byKey)
				if (l != Task.init)
					core.resumeTask(l);
		} catch (Exception e) {
			logError("Exception while handling signal event: %s", e.msg);
			try logDebug("Full error: %s", sanitize(e.msg));
			catch (Exception) {}
			debug assert(false);
		}
	}
}


/*class LibevTimer : Timer {
	mixin SingleOwnerEventedObject;

	private {
		LibevDriver m_driver;
		ev_timer m_timer;
		void delegate() m_callback;
		bool m_pending;
	}

	this(LibevDriver driver, void delegate() callback)
	{
		m_driver = driver;
		m_callback = callback;
		ev_timer_init(&m_timer, &onTimer, 0, 0);
		m_timer.data = cast(void*)this;
	}

	@property bool pending() { return m_pending; }

	void rearm(Duration dur, bool periodic = false)
	{
		stop();

		auto tstamp = dur.total!"hnsecs"() * 1e-7;
		ev_timer_set(&m_timer, tstamp, periodic ? tstamp : 0);
		ev_timer_start(m_driver.m_loop, &m_timer);
		m_pending = true;
	}

	void stop()
	{
		ev_timer_stop(m_driver.m_loop, &m_timer);
		m_pending = false;
	}

	void wait()
	{
		acquire();
		scope(exit) release();

		while (pending)
			m_driver.m_core.yieldForEvent();
	}

	extern(C) static nothrow onTimer(ev_loop_t *loop, ev_timer *w, int revents)
	{
		auto tm = cast(LibevTimer)w.data;

		logTrace("Timer event %s/%s", tm.m_pending, w.repeat > 0);
		if (!tm.m_pending) return;
		try {
			if( tm.m_owner && tm.m_owner.running ) tm.m_driver.m_core.resumeTask(tm.m_owner);
			if( tm.m_callback ) runTask(tm.m_callback);
		} catch (UncaughtException e) {
			logError("Exception while handling timer event: %s", e.msg);
			try logDebug("Full exception: %s", sanitize(e.toString())); catch {}
			debug assert(false);
		}
	}
}*/


final class LibevTCPListener : TCPListener {
	private {
		LibevDriver m_driver;
		int m_socket;
		ev_io* m_io;
		void delegate(TCPConnection conn) m_connectionCallback;
		TCPListenOptions m_options;
	}

	this(LibevDriver driver, int sock, ev_io* io, void delegate(TCPConnection conn) connection_callback, TCPListenOptions options)
	{
		m_driver = driver;
		m_socket = sock;
		m_io = io;
		m_connectionCallback = connection_callback;
		m_io.data = cast(void*)this;
		m_options = options;
	}

	@property void delegate(TCPConnection conn) connectionCallback() { return m_connectionCallback; }

	void stopListening()
	{
		// TODO!
	}
}

final class LibevTCPConnection : TCPConnection {
	mixin SingleOwnerEventedObject;

	private {
		Task m_owner;
		LibevDriver m_driver;
		int m_socket;
		ubyte[64*1024] m_readBuffer;
		ubyte[] m_readBufferContent;
		ev_io* m_readWatcher;
		ev_io* m_writeWatcher;
		int m_eventsExpected = 0;
		Appender!(ubyte[]) m_writeBuffer;
		bool m_tcpNoDelay = false;
		bool m_keepAlive = false;
		Duration m_readTimeout;
	}

	this(LibevDriver driver, int fd, ev_io* read_watcher, ev_io* write_watcher)
	{
		assert(fd >= 0);
		m_owner = Task.getThis();
		m_driver = driver;
		m_socket = fd;
		m_readWatcher = read_watcher;
		m_readWatcher.data = cast(void*)this;
		m_writeWatcher = write_watcher;
		m_writeWatcher.data = cast(void*)this;
		//logInfo("fd %d %d", fd, watcher.fd);
	}

	@property void tcpNoDelay(bool enabled)
	{
		m_tcpNoDelay = enabled;
		ubyte opt = enabled;
		setsockopt(m_socket, IPPROTO_TCP, TCP_NODELAY, &opt, opt.sizeof);
	}
	@property bool tcpNoDelay() const { return m_tcpNoDelay; }

	@property void readTimeout(Duration v)
	{
		m_readTimeout = v;
		if( v == dur!"seconds"(0) ){
			// ...
		} else {
			assert(false);
		}
	}
	@property Duration readTimeout() const { return m_readTimeout; }

	@property void keepAlive(bool enabled)
	{
		m_keepAlive = enabled;
		ubyte opt = enabled;
		setsockopt(m_socket, SOL_SOCKET, SO_KEEPALIVE, &opt, opt.sizeof);
	}
	@property bool keepAlive() const { return m_keepAlive; }

	@property bool connected() const { return m_socket >= 0; }

	@property bool dataAvailableForRead(){ return m_readBufferContent.length > 0; }

	@property string peerAddress() const { return "xxx"; } // TODO!
	@property NetworkAddress localAddress() const { return NetworkAddress.init; } // TODO!
	@property NetworkAddress remoteAddress() const { return NetworkAddress.init; } // TODO!

	@property bool empty() { return leastSize == 0; }

	@property ulong leastSize()
	{
		if( m_readBufferContent.length == 0 ){
			readChunk();
			//assert(m_readBufferContent.length > 0);
		}
		return m_readBufferContent.length;
	}

	void close()
	{
		//logTrace("closing");
		enforce(m_socket >= 0);
		//logInfo("shut %d", m_socket);
		shutdown(m_socket, SHUT_WR);
		while(true){
			ubyte[1024] buffer;
		//logInfo("shutrecv %d", m_socket);
			auto ret = recv(m_socket, buffer.ptr, buffer.length, 0);
			if( ret == 0 ) break;
			int err = errno;
			//logInfo("shutrecv %d: %d %d", m_socket, ret, err);
			if( err != EWOULDBLOCK && err != EAGAIN ){
				//logInfo("Socket error on shutdown: %d", err);
				break;
			}
			//logInfo("shutyield %d", m_socket);
			yieldFor(EV_READ);
		}
		stopYield();
		//logInfo("close %d", m_socket);
		.close(m_socket);
		m_socket = -1;

	}

	bool waitForData(Duration timeout)
	{
		if (timeout == 0.seconds)
			logDebug("Warning: use Duration.max as an argument to waitForData() to wait infinitely, not 0.seconds.");

		if (!m_readBufferContent.empty) return true;

		logTrace("wait for data");

		auto timer = m_driver.createTimer(null);
		scope (exit) m_driver.releaseTimer(timer);
		if (timeout > 0.seconds() && timeout != Duration.max) {
			m_driver.m_timers.getUserData(timer).owner = Task.getThis();
			m_driver.rearmTimer(timer, timeout, false);
		}

		while (this.connected) {
			if (readChunk(true))
				return true;

			// wait for read event
			yieldFor(EV_READ);

			// check for timeout
			if (timeout > 0.seconds && timeout != Duration.max && !m_driver.isTimerPending(timer))
				return false;
		}

		return readChunk(true);
	}

	const(ubyte)[] peek()
	{
		return null;
	}

	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			checkConnected();
			if( !m_readBufferContent.length ) readChunk();
			enforce(m_readBufferContent.length > 0, "Remote end hung up during read.");
			size_t n = min(dst.length, m_readBufferContent.length);
			dst[0 .. n] = m_readBufferContent[0 .. n];
			dst = dst[n .. $];
			m_readBufferContent = m_readBufferContent[n .. $];
		}
	}

	const(ubyte)[] peek(size_t nbytes = 0)
	{
		if( !m_readBufferContent.length ) readChunk();
		return m_readBufferContent;
	}

	void drain(size_t nbytes){
		while( nbytes > 0 ){
			if( m_readBufferContent.length == 0 ) readChunk();
			size_t amt = min(nbytes, m_readBufferContent.length);
			m_readBufferContent = m_readBufferContent[amt .. $];
			nbytes -= amt;
		}
	}

	void write(in ubyte[] bytes_)
	{
		m_writeBuffer.put(bytes_);

		/*if( do_flush )*/ flush();
	}

	void flush()
	{
		const(ubyte)[] bytes = m_writeBuffer.data();//bytes_;
		scope(exit) m_writeBuffer.clear();
		scope(exit) stopYield();
		while( bytes.length > 0 ){
			checkConnected();
			logTrace("send %d: %s", bytes.length,cast(string)bytes);
			auto nbytes = send(m_socket, bytes.ptr, bytes.length, 0);
			logTrace(" .. got %d", nbytes);
			if( nbytes == bytes.length ) break;
			if( nbytes < 0 ){
				int err = errno;
				enforce(err != EPIPE, "Remote end hung before all data was sent.");
				enforce(err == EAGAIN || err == EWOULDBLOCK, "Error sending data: "~to!string(errno));
			} else bytes = bytes[nbytes .. $];
			if( bytes.length > 0 ) yieldFor(EV_WRITE);
		}
	}

	void finalize()
	{
		flush();
	}

	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}

	private bool readChunk(bool try_only = false)
	{
		if (try_only && !connected) return false;
		else checkConnected();
		logTrace("Reading next chunk!");
		assert(m_readBufferContent.length == 0);
		ptrdiff_t nbytes;
		scope(exit) stopYield();
		while(true){
			nbytes = recv(m_socket, m_readBuffer.ptr, m_readBuffer.length, 0);
			logTrace(" .. got %d, %d", nbytes, errno);
			if( nbytes >= 0 ) break;
			int err = errno;
			if (try_only) return false;
			enforce(err == EWOULDBLOCK || err == EAGAIN, "Socket error on read: "~to!string(err));
			yieldFor(EV_READ);
		}

		logTrace(" <%s>", cast(string)m_readBuffer[0 .. nbytes]);
		if( nbytes == 0 ){
			logDebug("detected connection close during read!");
			close();
			return false;
		}
		m_readBufferContent = m_readBuffer[0 .. nbytes];
		return true;
	}

	private void checkConnected()
	{
		enforce(m_socket >= 0, "Operating on closed connection.");
	}

	private void yieldFor(int events)
	{
		if( m_eventsExpected != events ){
			if( events & EV_READ ) ev_io_start(m_driver.m_loop, m_readWatcher);
			if( events & EV_WRITE ) ev_io_start(m_driver.m_loop, m_writeWatcher);
			m_eventsExpected = events;
		}
		LibevDriver.ms_core.yieldForEvent();
	}

	private void stopYield()
	{
		if( m_eventsExpected ){
			if( m_eventsExpected & EV_READ ) ev_io_stop(m_driver.m_loop, m_readWatcher);
			if( m_eventsExpected & EV_WRITE ) ev_io_stop(m_driver.m_loop, m_writeWatcher);
			m_eventsExpected = 0;
		}
	}
}

private struct TimerInfo {
	size_t refCount = 1;
	void delegate() callback;
	Task owner;

	this(void delegate() callback) { this.callback = callback; }
}

private extern(C){
	void accept_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		sockaddr_in client_addr;
		socklen_t client_len = client_addr.sizeof;
		enforce((EV_ERROR & revents) == 0);

		auto client_sd = accept(watcher.fd, cast(sockaddr*)&client_addr, &client_len);

		setNonBlocking(client_sd);

		enforce(client_sd >= 0);

		logDebug("client %d connected.", client_sd);

		/*ev_io* w_client = new ev_io;
		ev_io_init(w_client, &write_cb, client_sd, EV_WRITE);
		ev_io_start(loop, w_client);*/

		auto obj = cast(LibevTCPListener)watcher.data;
		auto driver = obj.m_driver;

		void client_task()
		{
			ev_io* r_client = new ev_io;
			ev_io* w_client = new ev_io;
			ev_io_init(r_client, &read_cb, client_sd, EV_READ);
			ev_io_init(w_client, &read_cb, client_sd, EV_WRITE);

			auto conn = new LibevTCPConnection(driver, client_sd, r_client, w_client);
			logTrace("client task in");
			logTrace("calling connection callback");
			try {
				obj.m_connectionCallback(conn);
			} catch( Exception e ){
				logWarn("Unhandled exception in connection handler: %s", e.toString());
			} finally {
				logTrace("client task out");
				if (conn.connected && !(obj.m_options & TCPListenOptions.disableAutoClose)) conn.close();
			}
		}

		runTask(&client_task);
	}

	void read_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		logTrace("i/o event on %d: %d", watcher.fd, revents);
		auto conn = cast(LibevTCPConnection)watcher.data;

		if( (conn.m_eventsExpected & revents) != 0 )
			LibevDriver.ms_core.resumeTask(conn.m_owner);
	}

	void write_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		logTrace("write event on %d: %d", watcher.fd, revents);
		auto conn = cast(LibevTCPConnection)watcher.data;
		LibevDriver.ms_core.resumeTask(conn.m_owner);
	}
}

private void setNonBlocking(int fd)
{
	version(Windows){
		uint p = 1;
		ioctlsocket(fd, FIONBIO, &p);
	} else {
		int flags;
		flags = fcntl(fd, F_GETFL);
		flags |= O_NONBLOCK;
		fcntl(fd, F_SETFL, flags);
	}
}

private mixin template SingleOwnerEventedObject() {
	protected {
		Task m_owner;
	}

	protected void release()
	{
		assert(amOwner(), "Releasing evented object that is not owned by the calling task.");
		m_owner = Task();
	}

	protected void acquire()
	{
		assert(m_owner == Task(), "Acquiring evented object that is already owned.");
		m_owner = Task.getThis();
	}

	protected bool amOwner()
	{
		return m_owner != Task() && m_owner == Task.getThis();
	}
}

private mixin template MultiOwnerEventedObject() {
	protected {
		Task[] m_owners;
	}

	protected void release()
	{
		auto self = Task.getThis();
		auto idx = m_owners.countUntil(self);
		assert(idx >= 0, "Releasing evented object that is not owned by the calling task.");
		m_owners = m_owners[0 .. idx] ~ m_owners[idx+1 .. $];
	}

	protected void acquire()
	{
		auto self = Task.getThis();
		assert(!amOwner(), "Acquiring evented object that is already owned by the calling task.");
		m_owners ~= self;
	}

	protected bool amOwner()
	{
		return m_owners.countUntil(Task.getThis()) >= 0;
	}
}

} // version(VibeLibevDriver)
