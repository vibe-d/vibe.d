/**
	Uses libasync

	Copyright: © 2014 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libasync;

version(VibeLibasyncDriver):

import vibe.core.core;
import vibe.core.driver;
import vibe.core.drivers.threadedfile;
import vibe.core.log;
import vibe.inet.path;

import libasync;
import libasync.types : Status;

import std.algorithm : min;
import std.array;
import std.encoding;
import std.exception;
import std.conv;
import std.string;
import std.typecons;
import std.datetime;

import core.atomic;
import core.memory;
import core.thread;
import core.sync.mutex;
import std.container : Array;

import vibe.core.drivers.timerqueue;
import libasync.internals.memory;
import vibe.utils.array : FixedRingBuffer;
import std.stdio : File;

private __gshared EventLoop gs_evLoop;
private EventLoop s_evLoop;
private DriverCore s_driverCore;

EventLoop getEventLoop() nothrow
{
	if (s_evLoop is null)
		return gs_evLoop;

	return s_evLoop;
}

DriverCore getDriverCore() nothrow
{
	assert(s_driverCore !is null);
	return s_driverCore;
}

private struct TimerInfo {
	size_t refCount = 1;
	void delegate() callback;
	Task owner;
	
	this(void delegate() callback) { this.callback = callback; }
}

/// one per thread
final class LibasyncDriver : EventDriver {
	private {
		bool m_break = false;
		debug Thread m_ownerThread;
		AsyncTimer m_timerEvent;
		TimerQueue!TimerInfo m_timers;
		SysTime m_nextSched;
	}
		
	this(DriverCore core) nothrow
	{
		//if (isControlThread) return;

		try {
			if (!gs_mutex) {
				import core.sync.mutex;
				gs_mutex = new core.sync.mutex.Mutex;
				
				gs_availID.reserve(32);
				
				foreach (i; gs_availID.length .. gs_availID.capacity) {
					gs_availID.insertBack(i + 1);
				}
				
				gs_maxID = 32;
			}
		}
		catch {
			assert(false, "Couldn't reserve necessary space for available Manual Events");
		}

		debug m_ownerThread = Thread.getThis();
		s_driverCore = core;
		s_evLoop = getThreadEventLoop();
		if (!gs_evLoop)
			gs_evLoop = s_evLoop;
		logTrace("Loaded libasync backend in thread %s", Thread.getThis().name);

	}

	static @property bool isControlThread() {
		return Thread.getThis().isDaemon && Thread.getThis().name == "CmdProcessor" ;
	}

	void dispose() {
		logTrace("Deleting event driver");
		m_break = true;
		getEventLoop().exit();
	}
	
	int runEventLoop()
	{
		while(!m_break && getEventLoop().loop()){
			getDriverCore().notifyIdle();
		}
		m_break = false;
		logInfo("Event loop exit", m_break);
		return 0;
	}
	
	int runEventLoopOnce()
	{
		getEventLoop().loop(0.seconds);
		getDriverCore().notifyIdle();
		logTrace("runEventLoopOnce exit");
		return 0;
	}
	
	bool processEvents()
	{
		getEventLoop().loop(0.seconds);
		if (m_break) {
			m_break = false;
			return false;
		}
		return true;
	}
	
	void exitEventLoop()
	{
		logInfo("Exiting (%s)", m_break);
		m_break = true;

	}
	
	LibasyncFileStream openFile(Path path, FileMode mode)
	{
		return new LibasyncFileStream(path, mode);
	}
	
	DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		return new LibasyncDirectoryWatcher(path, recursive);
	}
	
	/** Resolves the given host name or IP address string. */
	NetworkAddress resolveHost(string host, ushort family = 2, bool use_dns = true)
	{
		// todo: force use_dns false if host is an IP to avoid yielding... do this at a lower level?

		NetworkAddress ret;

		enum : ushort {
			AF_INET = 2,
			AF_INET6 = 23
		}

		import libasync.types : isIPv6;
		isIPv6 is_ipv6;
		if (family == AF_INET6)
			is_ipv6 = isIPv6.yes;
		else
			is_ipv6 = isIPv6.no;

		if (use_dns) {
			bool done;
			struct DNSCallback  {
				Task waiter;
				NetworkAddress* address;
				bool* finished;
				void handler(NetworkAddress addr) {
					*address = addr;
					Exception ex;
					if (addr == NetworkAddress.init)
						ex = new Exception("Could not resolve the specified host.");
					*finished = true;
					if (waiter != Task())
						getDriverCore().resumeTask(waiter, ex);
					else if (ex)
						throw ex;
				}
			}

			DNSCallback* cb = FreeListObjectAlloc!DNSCallback.alloc();
			cb.waiter = Task.getThis();
			cb.address = &ret;
			cb.finished = &done;

			// todo: remove the shared attribute to avoid GC?
			shared AsyncDNS dns = new shared AsyncDNS(getEventLoop());

			bool success = dns.handler(&cb.handler).resolveHost(host, is_ipv6);
			if (!success)
				throw new Exception(dns.status.text);
			while(!done)
				getDriverCore.yieldForEvent();
			assert(ret != NetworkAddress.init);
			assert(ret.family != 0);
			logTrace("Async resolved address %s", ret.toString());
			FreeListObjectAlloc!DNSCallback.free(cb);

			if (ret.family == 0)
				ret.family = family;

			return ret;
		} 
		else {
			ret = getEventLoop().resolveIP(host, 0, is_ipv6);
			if (ret.family == 0)
				ret.family = family;
			return ret;
		}

	}
	
	LibasyncTCPConnection connectTCP(NetworkAddress addr)
	{
		AsyncTCPConnection conn = new AsyncTCPConnection(getEventLoop());

		LibasyncTCPConnection tcp_connection = new LibasyncTCPConnection(conn, (TCPConnection conn) { 
			Task waiter = (cast(LibasyncTCPConnection) conn).m_settings.writer.task;
			if (waiter != Task()) {
				getDriverCore().resumeTask(waiter);
			}
		});

		if (Task.getThis() != Task()) 
			tcp_connection.acquireWriter();

		tcp_connection.m_tcpImpl.conn = conn;
		conn.peer = addr;

		enforce(conn.run(&tcp_connection.handler), "An error occured while starting a new connection: " ~ conn.error);

		while (!tcp_connection.connected) getDriverCore().yieldForEvent();
		
		tcp_connection.m_tcpImpl.localAddr = conn.local;
		
		if (Task.getThis() != Task()) 
			tcp_connection.releaseWriter();
		return tcp_connection;
	}
	
	LibasyncTCPListener listenTCP(ushort port, void delegate(TCPConnection conn) conn_callback, string address, TCPListenOptions options)
	{
		NetworkAddress localaddr = getEventDriver().resolveHost(address);
		localaddr.port = port;

		return new LibasyncTCPListener(localaddr, conn_callback, options);
	}
	
	LibasyncUDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
	{
		NetworkAddress localaddr = getEventDriver().resolveHost(bind_address);
		localaddr.port = port;
		AsyncUDPSocket sock = new AsyncUDPSocket(getEventLoop());
		sock.local = localaddr;
		auto udp_connection = new LibasyncUDPConnection(sock);
		sock.run(&udp_connection.handler);
		return udp_connection;
	}
	
	LibasyncManualEvent createManualEvent()
	{
		return new LibasyncManualEvent(this);
	}
	
	FileDescriptorEvent createFileDescriptorEvent(int file_descriptor, FileDescriptorEvent.Trigger triggers)
	{
		assert(false);
	}
	

	// The following timer implementation was adapted from the equivalent in libevent2.d

	size_t createTimer(void delegate() callback) { return m_timers.create(TimerInfo(callback)); }
	
	void acquireTimer(size_t timer_id) { m_timers.getUserData(timer_id).refCount++; }
	void releaseTimer(size_t timer_id)
	{
		debug assert(m_ownerThread is Thread.getThis());
		logTrace("Releasing timer %s", timer_id);
		if (!--m_timers.getUserData(timer_id).refCount) 
			m_timers.destroy(timer_id);
	}
	
	bool isTimerPending(size_t timer_id) nothrow { return m_timers.isPending(timer_id); }
	
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
		logTrace("Waiting for timer in %s", Task.getThis());
		debug assert(m_ownerThread is Thread.getThis());
		while (true) {
			assert(!m_timers.isPeriodic(timer_id), "Cannot wait for a periodic timer.");
			if (!m_timers.isPending(timer_id)) {
				// logTrace("Timer is not pending");
				return;
			}
			auto data = &m_timers.getUserData(timer_id);
			assert(data.owner == Task.init, "Waiting for the same timer from multiple tasks is not supported.");
			data.owner = Task.getThis();
			scope (exit) m_timers.getUserData(timer_id).owner = Task.init;
			getDriverCore().yieldForEvent();
		}
	}

	/// If the timer has an owner, it will resume the task.
	/// if the timer has a callback, it will run a new task.
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
			
			if (owner && owner.running) getDriverCore().resumeTask(owner);
			if (callback) runTask(callback);
		});
		
		rescheduleTimerEvent(now);
	}

	private void rescheduleTimerEvent(SysTime now)
	{
		// logTrace("Rescheduling timer event %s", Task.getThis());

		bool first;
		auto next = m_timers.getFirstTimeout();
		if (next == SysTime.max) return;
		if (m_nextSched == next)
			return;
		else
			m_nextSched = next;
		Duration dur = next - now;
		if (dur == Duration.zero || dur.isNegative) return;
		assert(dur.total!"seconds"() <= int.max);
		if (!m_timerEvent) {
			//logTrace("creating new async timer");
			m_timerEvent = new AsyncTimer(getEventLoop());
			bool success = m_timerEvent.duration(dur).run(&onTimerTimeout);
			assert(success, "Failed to run timer");
		}
		else {
			//logTrace("rearming the same timer instance");
			bool success = m_timerEvent.rearm(dur);
			assert(success, "Failed to rearm timer");
		}
		logTrace("Rescheduled timer event for %s seconds in thread '%s' :: task '%s'", dur.total!"usecs" * 1e-6, Thread.getThis().name, Task.getThis());
	}
	
	private void onTimerTimeout()
	{
		import std.encoding : sanitize;
		
		logTrace("timer event fired");
		try processTimers();
		catch (Exception e) {
			logError("Failed to process timers: %s", e.msg);
			try logDiagnostic("Full error: %s", e.toString().sanitize); catch {}
		}
	}
}


final class LibasyncFileStream : FileStream {
	private {
		Path m_path;
		ulong m_size;
		ulong m_offset = 0;
		FileMode m_mode;

		Task m_task;
		shared AsyncFile m_impl;

		bool m_started;
		bool m_truncated;
		bool m_finished;
	}

	this(Path path, FileMode mode)
	{
		import std.file : getSize;
		if (mode != FileMode.createTrunc)
			m_size = getSize(path.toNativeString());
		m_path = path;
		m_mode = mode;

		m_impl = new shared AsyncFile(getEventLoop());
		m_impl.onReady(&handler);

		m_started = true;
	}
	
	~this()
	{
		close();
	}

	@property Path path() const { return m_path; }
	@property bool isOpen() const { return m_started; }
	@property ulong size() const { return m_size; }
	@property bool readable() const { return m_mode != FileMode.append; }
	@property bool writable() const { return m_mode != FileMode.read; }

	void seek(ulong offset)
	{
		m_offset = offset;
	}
	
	ulong tell() { return m_offset; }
	
	void close()
	{
		if (m_impl) {
			m_impl.kill();
			m_impl = null;
		}
		m_started = false;
	}
	
	@property bool empty() const { assert(this.readable); return m_offset >= m_size; }
	@property ulong leastSize() const { assert(this.readable); return m_size - m_offset; }
	@property bool dataAvailableForRead() { return true; }
	
	const(ubyte)[] peek()
	{
		auto sz = min(1,leastSize);
		auto ub = new ubyte[min(1, cast(size_t)leastSize)];
		read(ub);
		m_offset -= sz;
		return ub;
	}
	
	void read(ubyte[] dst)
	{
		assert(this.readable, "To read a file, it must be opened in a read-enabled mode.");
		acquire();
		scope(exit) release();
		shared ubyte[] bytes = cast(shared) dst;
		bool truncate_if_exists;
		if (!m_truncated && m_mode == FileMode.createTrunc) {
			truncate_if_exists = true;
			m_truncated = true;
			m_size = 0;
		}
		enforce(dst.length <= leastSize);
		enforce(m_impl.read(m_path.toNativeString(), bytes, m_offset, true, truncate_if_exists), "Failed to read data from disk: " ~ m_impl.error);
		while(!m_finished) {
			getDriverCore().yieldForEvent();
		}
		m_finished = false;
		m_offset += dst.length;
		assert(m_impl.offset == m_offset, "Incoherent offset returned from file reader: " ~ m_offset.to!string ~ "B assumed but the implementation is at: " ~ m_impl.offset.to!string ~ "B");
	}
	
	alias Stream.write write;
	void write(in ubyte[] bytes_)
	{
		assert(this.writable, "To write to a file, it must be opened in a write-enabled mode.");
		acquire();
		scope(exit) release();
		shared const(ubyte)[] bytes = cast(shared const(ubyte)[]) bytes_;

		bool truncate_if_exists;
		if (!m_truncated && m_mode == FileMode.createTrunc) {
			truncate_if_exists = true;
			m_truncated = true;
			m_size = 0;
		}

		if (m_mode == FileMode.append)
			enforce(m_impl.append(m_path.toNativeString(), cast(shared ubyte[]) bytes, true, truncate_if_exists), "Failed to write data to disk: " ~ m_impl.error);
		else
			enforce(m_impl.write(m_path.toNativeString(), bytes, m_offset, true, truncate_if_exists), "Failed to write data to disk: " ~ m_impl.error);

		while(!m_finished) {
			getDriverCore().yieldForEvent();
		}
		m_finished = false;

		if (m_mode == FileMode.append) {
			m_size += bytes.length;
			import std.file : getSize;
		}
		else {
			m_offset += bytes.length;
			if (m_offset >= m_size)
				m_size += m_offset - m_size;
			assert(m_impl.offset == m_offset, "Incoherent offset returned from file writer.");
		}
		import std.file : getSize;
		assert(getSize(m_path.toNativeString()) == m_size, "Incoherency between local size and filesize: " ~ m_size.to!string ~ "B assumed for a file of size " ~ getSize(m_path.toNativeString()).to!string ~ "B");
	}
	
	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}
	
	void flush()
	{
		assert(this.writable, "To write to a file, it must be opened in a write-enabled mode.");
	}
	
	void finalize()
	{
		flush();
	}

	void release()
	{
		assert(Task.getThis() == Task() || m_task == Task.getThis(), "Releasing FileStream that is not owned by the calling task.");
		m_task = Task();
	}
	
	void acquire()
	{
		assert(Task.getThis() == Task() || m_task == Task(), "Acquiring FileStream that is already owned.");
		m_task = Task.getThis();
	}
	
	bool amOwner()
	{
		return m_task == Task.getThis();
	}

	private void handler() {
		Exception ex;
		if (m_impl.status.code != Status.OK)
			ex = new Exception(m_impl.error);
		m_finished = true;
		if (m_task != Task())
			getDriverCore().resumeTask(m_task, ex);
	}
}


final class LibasyncDirectoryWatcher : DirectoryWatcher {
	private {
		Path m_path;
		bool m_recursive;
		Task m_task;
		AsyncDirectoryWatcher m_impl;
		Array!DirectoryChange m_changes;
		Exception m_error;
	}
	
	this(Path path, bool recursive)
	{
		m_impl = new AsyncDirectoryWatcher(getEventLoop());
		m_impl.run(&handler);
		m_path = path;
		m_recursive = recursive;
		watch(path, recursive);
		// logTrace("DirectoryWatcher called with: %s", path.toNativeString());
	}
	
	~this()
	{
		m_impl.kill();
	}
	
	@property Path path() const { return m_path; }
	@property bool recursive() const { return m_recursive; }
	
	void release()
	{
		assert(m_task == Task.getThis(), "Releasing FileStream that is not owned by the calling task.");
		m_task = Task();
	}
	
	void acquire()
	{
		assert(m_task == Task(), "Acquiring FileStream that is already owned.");
		m_task = Task.getThis();
	}
	
	bool amOwner()
	{
		return m_task == Task.getThis();
	}
	
	bool readChanges(ref DirectoryChange[] dst, Duration timeout)
	{
		dst.length = 0;
		assert(!amOwner());
		if (m_error)
			throw m_error;
		acquire();
		scope(exit) release();
		void consumeChanges() {
			if (m_impl.status.code == Status.ERROR) {
				throw new Exception(m_impl.error);
			}

			foreach (ref change; m_changes[]) {
				//logTrace("Adding change: %s", change.to!string);
				dst ~= change;
			}

			//logTrace("Consumed change 1: %s", dst.to!string);
			import std.array : array;
			import std.algorithm : uniq;
			dst = cast(DirectoryChange[]) uniq!((a, b) => a.path == b.path && a.type == b.type)(dst).array;
			logTrace("Consumed change: %s", dst.to!string);
			m_changes.clear();
		}

		if (!m_changes.empty) {
			consumeChanges();
			return true;
		}

		auto tm = getEventDriver().createTimer(null);
		getEventDriver().m_timers.getUserData(tm).owner = Task.getThis();
		getEventDriver().rearmTimer(tm, timeout, false);

		while (m_changes.empty) {
			getDriverCore().yieldForEvent();
			if (!getEventDriver().isTimerPending(tm)) break;
		}

		if (!m_changes.empty) {
			consumeChanges();
			return true;
		}

		return false;
	}

	private void watch(Path path, bool recursive) {
		m_impl.watchDir(path.toNativeString(), DWFileEvent.ALL, recursive);
	}

	private void handler() {
		import std.stdio;
		DWChangeInfo[] changes = allocArray!DWChangeInfo(manualAllocator(), 128);
		scope(exit) freeArray(manualAllocator(), changes);
		Exception ex;
		try {
			uint cnt;
			do {
				cnt = m_impl.readChanges(changes);
				size_t i;
				foreach (DWChangeInfo change; changes) {
					DirectoryChange dc;

					final switch (change.event){
						case DWFileEvent.CREATED: dc.type = DirectoryChangeType.added; break;
						case DWFileEvent.DELETED: dc.type = DirectoryChangeType.removed; break;
						case DWFileEvent.MODIFIED: dc.type = DirectoryChangeType.modified; break;
						case DWFileEvent.MOVED_FROM: dc.type = DirectoryChangeType.removed; break;
						case DWFileEvent.MOVED_TO: dc.type = DirectoryChangeType.added; break;
						case DWFileEvent.ALL: break; // impossible
						case DWFileEvent.ERROR: throw new Exception(m_impl.error);
					}

					dc.path = Path(change.path);
					//logTrace("Inserted %s absolute %s", dc.to!string, dc.path.absolute.to!string);
					m_changes.insert(dc);
					i++;
					if (cnt == i) break;
				}
			} while(cnt == 0 && m_impl.status.code == Status.OK);
			if (m_impl.status.code == Status.ERROR) {
				ex = new Exception(m_impl.error);
			}

		}
		catch (Exception e) {
			ex = e;
		}
		if (m_task != Task()) getDriverCore().resumeTask(m_task, ex);
		else m_error = ex;
	}

}



final class LibasyncManualEvent : ManualEvent {
	private {
		shared(int) m_emitCount = 0;
		shared(int) m_threadCount = 0;
		shared(size_t) m_instance;
		Array!(void*) ms_signals;

		core.sync.mutex.Mutex m_mutex;
	}
	
	this(LibasyncDriver driver)
	{
		m_mutex = new core.sync.mutex.Mutex;
		m_instance = generateID();
		assert(m_instance != 0);
	}

	~this()
	{
		recycleID(m_instance);
		synchronized (m_mutex) {
			foreach (ref signal; ms_signals[]) {
				if (signal) {
					(cast(shared AsyncSignal) signal).kill();
					signal = null;
				}
			}
		}
	}

	void emit()
	{
		scope (failure) assert(false); // synchronized is not nothrow on DMD 2.066 and below and Array is not nothrow at all
		logTrace("Emitting signal");
		atomicOp!"+="(m_emitCount, 1);
		synchronized (m_mutex) {
			logTrace("Looping signals. found: " ~ ms_signals.length.to!string);
			foreach (ref signal; ms_signals[]) {
				auto evloop = getEventLoop();
				shared AsyncSignal sig = cast(shared AsyncSignal) signal;
				if (!sig.trigger(evloop)) logError("Failed to trigger ManualEvent: %s", sig.error);
			}
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

		bool signal_exists;

		if (s_eventWaiters.length <= m_instance) {
			expandWaiters();
		}
		logTrace("Acquire event ID#%d", m_instance);
		auto taskList = s_eventWaiters[m_instance];
		if (taskList.length > 0)
			signal_exists = true;

		if (!signal_exists) {
			shared AsyncSignal sig = new shared AsyncSignal(getEventLoop());
			sig.run(&onSignal);
			synchronized (m_mutex) ms_signals.insertBack(cast(void*)sig);
		}
		s_eventWaiters[m_instance].insertBack(Task.getThis());
	}
	
	void release()
	{
		assert(amOwner(), "Releasing non-acquired signal.");

		import std.algorithm : countUntil;
		auto taskList = s_eventWaiters[m_instance];
		auto idx = taskList[].countUntil!((a, b) => a == b)(Task.getThis());
		logTrace("Release event ID#%d", m_instance);
		s_eventWaiters[m_instance].linearRemove(taskList[idx .. idx+1]);

		if (s_eventWaiters[m_instance].empty) {
			removeMySignal();
		}
	}
	
	bool amOwner()
	{
		import std.algorithm : countUntil;
		if (s_eventWaiters.length <= m_instance) return false;
		auto taskList = s_eventWaiters[m_instance];
		if (taskList.length == 0) return false;

		auto idx = taskList[].countUntil!((a, b) => a == b)(Task.getThis());

		return idx != -1;
	}
	
	@property int emitCount() const { return atomicLoad(m_emitCount); }

	private int doWait(bool INTERRUPTIBLE)(int reference_emit_count)
	{
		static if (!INTERRUPTIBLE) scope (failure) assert(false); // still some function calls not marked nothrow
		assert(!amOwner());
		acquire();
		scope(exit) release();
		auto ec = this.emitCount;
		while( ec == reference_emit_count ){
			synchronized(m_mutex) logTrace("Waiting for event with signal count: " ~ ms_signals.length.to!string);
			static if (INTERRUPTIBLE) getDriverCore().yieldForEvent();
			else getDriverCore().yieldForEventDeferThrow();
			ec = this.emitCount;
		}
		return ec;
	}
	
	private int doWait(bool INTERRUPTIBLE)(Duration timeout, int reference_emit_count)
	{
		static if (!INTERRUPTIBLE) scope (failure) assert(false); // still some function calls not marked nothrow
		assert(!amOwner());
		acquire();
		scope(exit) release();
		auto tm = getEventDriver().createTimer(null);
		scope (exit) getEventDriver().releaseTimer(tm);
		getEventDriver().m_timers.getUserData(tm).owner = Task.getThis();
		getEventDriver().rearmTimer(tm, timeout, false);
		
		auto ec = this.emitCount;
		while (ec == reference_emit_count) {
			static if (INTERRUPTIBLE) getDriverCore().yieldForEvent();
			else getDriverCore().yieldForEventDeferThrow();
			ec = this.emitCount;
			if (!getEventDriver().isTimerPending(tm)) break;
		} 
		return ec;
	}

	private void removeMySignal() {
		import std.algorithm : countUntil;
		synchronized(m_mutex) {
			auto idx = ms_signals[].countUntil!((void* a, LibasyncManualEvent b) { return ((cast(shared AsyncSignal) a).owner == Thread.getThis() && this is b);})(this);
			ms_signals.linearRemove(ms_signals[idx .. idx+1]);				
		}
	}

	private void expandWaiters() {
		size_t maxID;
		synchronized(gs_mutex) maxID = gs_maxID;
		s_eventWaiters.reserve(maxID + 1);
		logTrace("gs_maxID: %d", maxID);
		foreach (i; s_eventWaiters.length .. s_eventWaiters.capacity) {
			s_eventWaiters.insertBack(Array!Task.init);
		}
	}

	private void onSignal()
	{
		logTrace("Got signal in onSignal");
		try {
			auto thread = Thread.getThis();
			auto core = getDriverCore();

			logTrace("Got context: %d", m_instance);
			foreach (Task task; s_eventWaiters[m_instance][]) {
				logTrace("Task Found");
				core.resumeTask(task);
			}
		} catch (Exception e) {
			logError("Exception while handling signal event: %s", e.msg);
			try logDebug("Full error: %s", sanitize(e.msg));
			catch (Exception) {}
			debug assert(false);
		}
	}
}

final class LibasyncTCPListener : TCPListener {
	private {
		NetworkAddress m_local;
		void delegate(TCPConnection conn) m_connectionCallback;
		TCPListenOptions m_options;
		AsyncTCPListener[] m_listeners;
		fd_t socket;
	}
	
	this(NetworkAddress addr, void delegate(TCPConnection conn) connection_callback, TCPListenOptions options)
	{
		m_connectionCallback = connection_callback;
		m_options = options;
		m_local = addr;
		void function(shared LibasyncTCPListener) init = (shared LibasyncTCPListener ctxt){
			synchronized(ctxt) {
				LibasyncTCPListener ctxt2 = cast(LibasyncTCPListener)ctxt;
				AsyncTCPListener listener = new AsyncTCPListener(getEventLoop(), ctxt2.socket);
				listener.local = ctxt2.m_local;

				enforce(listener.run(&ctxt2.initConnection), "Failed to start listening to local socket: " ~ listener.error);
				ctxt2.socket = listener.socket;
				ctxt2.m_listeners ~= listener;
			}
		};
		if (options & TCPListenOptions.distribute)	runWorkerTaskDist(init, cast(shared) this);
		else init(cast(shared) this);

	}
	
	@property void delegate(TCPConnection) connectionCallback() { return m_connectionCallback; }

	private void delegate(TCPEvent) initConnection(AsyncTCPConnection conn) {
		logTrace("Connection initialized in thread: " ~ Thread.getThis().name);

		LibasyncTCPConnection native_conn = new LibasyncTCPConnection(conn, m_connectionCallback);
		native_conn.m_tcpImpl.conn = conn;
		native_conn.m_tcpImpl.localAddr = m_local;
		return &native_conn.handler;
	}

	void stopListening()
	{
		synchronized(this) {
			foreach (listener; m_listeners) {
				listener.kill();
				listener = null;
			}
		}
	}
}

final class LibasyncTCPConnection : TCPConnection {

	private {
		FixedRingBuffer!ubyte m_readBuffer; // todo: use a file failover for tasks too busy to read
		TCPConnectionImpl m_tcpImpl;
		Settings m_settings;

		bool m_closed = true;
		bool m_mustRecv = true;

		// The socket descriptor is unavailable to motivate low-level/API feature additions 
		// rather than high-lvl platform-dependent hacking
		// fd_t socket; 
	}

	this(AsyncTCPConnection conn, void delegate(TCPConnection) cb)
	in { assert(conn !is null); }
	body {
		m_settings.onConnect = cb;
		m_readBuffer.freeOnDestruct = true;
		m_readBuffer.capacity = 64*1024;
	}

	private @property AsyncTCPConnection conn() {

		return m_tcpImpl.conn;
	}

	// Using this setting completely disables the internal buffers as well
	@property void tcpNoDelay(bool enabled)
	{
		m_settings.tcpNoDelay = enabled;
		conn.setOption(TCPOption.NODELAY, enabled);
	}

	@property bool tcpNoDelay() const { return m_settings.tcpNoDelay; }
	
	@property void readTimeout(Duration dur)
	{
		m_settings.readTimeout = dur;
		conn.setOption(TCPOption.TIMEOUT_RECV, dur);
	}

	@property Duration readTimeout() const { return m_settings.readTimeout; }
	
	@property void keepAlive(bool enabled)
	{
		m_settings.keepAlive = enabled;
		conn.setOption(TCPOption.KEEPALIVE_ENABLE, enabled);
	}

	@property bool keepAlive() const { return m_settings.keepAlive; }
	
	@property bool connected() const { return !m_closed && m_tcpImpl.conn && m_tcpImpl.conn.isConnected; }
	
	@property bool dataAvailableForRead(){ 
		logTrace("dataAvailableForRead");
		acquireReader();
		scope(exit) releaseReader();
		return !m_readBuffer.empty;
	}
	
	@property string peerAddress() const { return m_tcpImpl.conn.peer.toString(); }

	@property NetworkAddress localAddress() const { return m_tcpImpl.localAddr; }
	@property NetworkAddress remoteAddress() const { return m_tcpImpl.conn.peer; }
	
	@property bool empty() { return leastSize == 0; }
	
	@property ulong leastSize()
	{
		logTrace("leastSize()");
		acquireReader();
		scope(exit) releaseReader();
		
		while( m_readBuffer.empty ){
			checkConnected();
			getDriverCore().yieldForEvent();
		}
		return m_readBuffer.length;
	}
	
	void close()
	{
		logTrace("%s", "Close enter");
		//logTrace("closing");
		acquireWriter();
		scope(exit) releaseWriter();

		// checkConnected();

		onClose();
	}

	bool waitForData(Duration timeout = 0.seconds) 
	{
		logTrace("WaitForData enter, timeout %s :: Ptr %s",  timeout.toString(), (cast(void*)this).to!string);
		acquireReader();
		auto _driver = getEventDriver();
		auto tm = _driver.createTimer(null);
		scope(exit) { 
			_driver.releaseTimer(tm);
			_driver.processTimers();
			releaseReader();
		}
		_driver.m_timers.getUserData(tm).owner = Task.getThis();
		_driver.rearmTimer(tm, timeout, false);
		logTrace("waitForData()");
		while (m_readBuffer.empty) {
			checkConnected();
			if (m_mustRecv)
				onRead();
			else {
				logTrace("Yielding for event in waitForData, waiting? %s", m_settings.reader.isWaiting);
				getDriverCore().yieldForEvent();
			}
			if (!_driver.isTimerPending(tm)) {
				logTrace("WaitForData exit: timer signal");
				return false;
			}
		}
		logTrace("WaitForData exit: fiber resumed with read buffer");
		return true;
	}
	
	const(ubyte)[] peek()
	{
		logTrace("%s", "Peek enter");
		acquireReader();
		scope(exit) releaseReader();

		if (!m_readBuffer.empty)
			return m_readBuffer.peek();
		else
			return null;
	}
	
	void read(ubyte[] dst)
	{
		assert(dst !is null);
		logTrace("Read enter :: ptr %s",  (cast(void*)this).to!string);
		acquireReader();
		scope(exit) releaseReader();
		while( dst.length > 0 ){
			while( m_readBuffer.empty ){
				checkConnected();
				if (m_mustRecv)
					onRead();
				else {
					getDriverCore().yieldForEvent();
					checkConnected();
				}
			}
			size_t amt = min(dst.length, m_readBuffer.length);

			m_readBuffer.read(dst[0 .. amt]);
			dst = dst[amt .. $];
		}
	}
	
	void write(in ubyte[] bytes_)
	{
		assert(bytes_ !is null);
		logTrace("%s", "write enter");
		acquireWriter();
		scope(exit) releaseWriter();
		checkConnected();
		const(ubyte)[] bytes = bytes_;
		logTrace("TCP write with %s bytes called", bytes.length);

		bool first = true;
		size_t offset;
		size_t len = bytes.length;
		do {
			if (!first) {
				getDriverCore().yieldForEvent();
			}
			checkConnected();
			offset += conn.send(bytes[offset .. $]);
			
			if (conn.hasError) {
				throw new Exception(conn.error);
			}
			first = false;
		} while (offset != len);

	}
	
	void flush()
	{
		logTrace("%s", "Flush");
		acquireWriter();
		scope(exit) releaseWriter();
		
		checkConnected();

	}
	
	void finalize()
	{
		logTrace("%s", "finalize");
		flush();
	}
	
	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}
	
	void acquireReader() { 
		if (Task.getThis() == Task()) {
			logTrace("Reading without task");
			return;
		}
		logTrace("%s", "Acquire Reader");
		assert(!amReadOwner()); 
		m_settings.reader.task = Task.getThis();
		logTrace("Task waiting in: " ~ (cast(void*)cast(LibasyncTCPConnection)this).to!string);
		m_settings.reader.isWaiting = true;
	}

	void releaseReader() { 
		if (Task.getThis() == Task()) return;
		logTrace("%s", "Release Reader");
		assert(amReadOwner());
		m_settings.reader.isWaiting = false;
	}

	bool amReadOwner() const {
		if (m_settings.reader.isWaiting && m_settings.reader.task == Task.getThis())
			return true;
		return false;
	}
	
	void acquireWriter() { 
		if (Task.getThis() == Task()) return;
		logTrace("%s", "Acquire Writer");
		assert(!amWriteOwner(), "Failed to acquire writer in task: " ~ Task.getThis().fiber.to!string ~ ", it was busy with: " ~ m_settings.writer.task.to!string);
		m_settings.writer.task = Task.getThis(); 
		m_settings.writer.isWaiting = true;
	}

	void releaseWriter() { 
		if (Task.getThis() == Task()) return;
		logTrace("%s", "Release Writer");
		assert(amWriteOwner()); 
		m_settings.writer.isWaiting = false;
	}

	bool amWriteOwner() const { 
		if (m_settings.writer.isWaiting && m_settings.writer.task == Task.getThis()) 
			return true;
		return false;
	}

	private void checkConnected()
	{
		enforce(connected, "The remote peer has closed the connection.");
		logTrace("Check Connected");
	}

	private void onRead() {
		m_mustRecv = true; // assume we didn't receive everything
		logTrace("OnRead with %s", m_readBuffer.freeSpace);
		while( m_readBuffer.freeSpace > 0 ) {
			ubyte[] dst = m_readBuffer.peekDst();
			assert(dst.length <= int.max);
			logTrace("Try to read up to bytes: %s", dst.length);
			uint ret = conn.recv(dst);
			if( ret > 0 ){
				logTrace("received bytes: %s", ret);
				m_readBuffer.putN(ret);
				if (ret < dst.length) { // the kernel's buffer is too empty...
					m_mustRecv = false; // ..so we have everything!
					break;
				}
			} 
			// ret == 0! let's look for some errors
			else if (conn.status.code == Status.ASYNC) {
				m_mustRecv = false; // we'll have to wait
				break; // the kernel's buffer is empty
			}
			else if (conn.status.code != Status.OK) {
				// We have a read error and the socket may now even be closed...
				auto err = conn.error;

				logTrace("receive error %s %s", err, conn.status.code);
				throw new Exception("Socket error: " ~ conn.status.code.to!string);
			}
			else {
				m_mustRecv = false;
				break;
			}
		}
		logTrace("OnRead exit with free bytes: %s", m_readBuffer.freeSpace);
	}

	/* The AsyncTCPConnection object will be automatically disposed when this returns.
	 * We're given some time to cleanup.
	*/
	private void onClose(in string msg = null) {
		logTrace("onClose");

		if (m_closed)
			return;

		if (m_tcpImpl.conn && m_tcpImpl.conn.isConnected) {
			m_tcpImpl.conn.kill(true); // close the connection
			destroy(m_readBuffer);
			m_tcpImpl.conn = null;
		}
		m_closed = true;
		Exception ex;
		if (!msg)
			ex = new Exception("Connection closed");
		else	ex = new Exception(msg);

		bool hasUniqueReader;
		bool hasUniqueWriter;
		Task reader;
		Task writer;

		if (m_settings.reader.isWaiting && m_settings.reader.task != writer) 
		{
			reader = m_settings.reader.task;
			hasUniqueReader = true;
		}
		if (m_settings.writer.isWaiting) {
			writer = m_settings.writer.task;
			hasUniqueWriter = true;
		}
		if (hasUniqueReader && Task.getThis() != reader) {
			getDriverCore().resumeTask(reader, ex);
		}
		if (hasUniqueWriter && Task.getThis() != writer) {
			getDriverCore().resumeTask(writer, ex);
		}
	}

	void onConnect() {
		scope(failure) onClose();

		if (m_tcpImpl.conn && m_tcpImpl.conn.isConnected)
		{
			bool inbound = m_tcpImpl.conn.inbound;

			try m_settings.onConnect(this); 
			catch ( Exception e) {
				logError(e.toString);
				throw e;
			}
			catch ( Throwable e) {
				logError(e.toString);
				throw e;
			}
			if (inbound) onClose();
		}
		logTrace("Finished callback");
	}

	void handler(TCPEvent ev) {
		logTrace("Handler");
		Exception ex;
		final switch (ev) {
			case TCPEvent.CONNECT:
				m_closed = false;
				// read & write are guaranteed to be successful on any platform at this point

				if (m_tcpImpl.conn.inbound)
					runTask(&onConnect);
				else onConnect();

				break;
			case TCPEvent.READ:
				// fill the read buffer and resume any task if waiting
				try onRead();
				catch (Exception e) ex = e;
				if (m_settings.reader.isWaiting) 
					getDriverCore().resumeTask(m_settings.reader.task, ex);
				break;
			case TCPEvent.WRITE:
				// The kernel is ready to have some more data written, all we need to do is wake up the writer
				if (m_settings.writer.isWaiting) 
					getDriverCore().resumeTask(m_settings.writer.task, ex);
				break;
			case TCPEvent.CLOSE:
				onClose();
				break;
			case TCPEvent.ERROR:
				onClose(conn.error);
				break;
		}
		return;
	}
	
	struct Waiter {
		Task task; // we can only have one task waiting for read/write operations
		bool isWaiting; // if a task is actively waiting
	}
	
	struct Settings {
		void delegate(TCPConnection) onConnect;
		Duration readTimeout;
		bool keepAlive;
		bool tcpNoDelay;
		Waiter reader;
		Waiter writer;
	}
	
	struct TCPConnectionImpl {
		NetworkAddress localAddr;
		AsyncTCPConnection conn;
	}
}

int total_conn;

final class LibasyncUDPConnection : UDPConnection {
	private {
		Task m_task;
		AsyncUDPSocket m_udpImpl;
		bool m_canBroadcast;
		NetworkAddress m_peer;

		bool m_waiting;
	}
	
	private @property AsyncUDPSocket socket() {
		return m_udpImpl;
	}

	this(AsyncUDPSocket conn)
	in { assert(conn !is null); }
	body {
		m_udpImpl = conn;
	}
		
	@property string bindAddress() const {

		return m_udpImpl.local.toAddressString();
	}
	
	@property NetworkAddress localAddress() const { return m_udpImpl.local; }
	
	@property bool canBroadcast() const { return m_canBroadcast; }
	@property void canBroadcast(bool val)
	{
		socket.broadcast(val);
		m_canBroadcast = val;
	}
	
	void close()
	{
		socket.kill();
		m_udpImpl = null;
	}
	
	bool amOwner() {
		return m_task != Task() && m_task == Task.getThis();
	}
	
	void acquire()
	{
		assert(m_task == Task(), "Trying to acquire a UDP socket that is currently owned.");
		m_task = Task.getThis();
	}
	
	void release()
	{
		assert(m_task != Task(), "Trying to release a UDP socket that is not owned.");
		assert(m_task == Task.getThis(), "Trying to release a foreign UDP socket.");
		m_task = Task();
	}
	
	void connect(string host, ushort port)
	{
		// assert(m_peer == NetworkAddress.init, "Cannot connect to another peer");
		NetworkAddress addr = getEventDriver().resolveHost(host, localAddress.family, true);
		addr.port = port;
		connect(addr);
	}

	void connect(NetworkAddress addr)
	{
		m_peer = addr;
	}
	
	void send(in ubyte[] data, in NetworkAddress* peer_address = null)
	{
		assert(data.length <= int.max);
		uint ret;
		size_t retries = 3;
		foreach  (i; 0 .. retries) {
			if( peer_address ){
				ret = socket.sendTo(data, *peer_address);
			} else {
				ret = socket.sendTo(data, m_peer);
			}
			if (socket.status.code == Status.ASYNC) { 
				m_waiting = true;
				getDriverCore().yieldForEvent();
			}
			else break;
		}

		logTrace("send ret: %s, %s", ret, socket.status.text);
		enforce(socket.status.code == Status.OK, "Error sending UDP packet: " ~ socket.status.text);

		enforce(ret == data.length, "Unable to send full packet.");
	}
	
	ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		return recv(Duration.max, buf, peer_address);
	}
	
	ubyte[] recv(Duration timeout, ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		size_t tm;
		auto m_driver = getEventDriver();
		if (timeout != Duration.max && timeout > 0.seconds) {
			tm = m_driver.createTimer(null);
			m_driver.rearmTimer(tm, timeout, false);
			m_driver.acquireTimer(tm);
		}
		
		acquire();
		scope(exit) {
			release();
			if (tm != size_t.max) m_driver.releaseTimer(tm);
		}
		
		assert(buf.length <= int.max);
		if( buf.length == 0 ) buf.length = 65507;
		NetworkAddress from;
		from.family = localAddress.family;
		while(true){
			auto ret = socket.recvFrom(buf, from);
			if( ret > 0 ){
				if( peer_address ) *peer_address = from;
				return buf[0 .. ret];
			}
			else if( socket.status.code != Status.OK ){
				auto err = socket.status.text;
				logDebug("UDP recv err: %s", err);
				enforce(socket.status.code == Status.ASYNC, "Error receiving UDP packet");
				
				if (timeout != Duration.max) {
					enforce(timeout > 0.seconds && m_driver.isTimerPending(tm), "UDP receive timeout.");
				}
			}
			m_waiting = true;
			getDriverCore().yieldForEvent();
		}
	}

	private void handler(UDPEvent ev)
	{
		logTrace("UDPConnection %p event", this);

		Exception ex;
		final switch (ev) {
			case UDPEvent.READ:
				if (m_waiting) {
					m_waiting = false;
					getDriverCore().resumeTask(m_task, null);
				}
				break;
			case UDPEvent.WRITE:
				if (m_waiting) {
					m_waiting = false;
					getDriverCore().resumeTask(m_task, null);
				}
				break;
			case UDPEvent.ERROR:
				getDriverCore.resumeTask(m_task, new Exception(socket.error));
				break;
		}

	}
}



/* The following is used for LibasyncManualEvent */

import std.container : Array;
Array!(Array!Task) s_eventWaiters; // Task list in the current thread per instance ID
__gshared Array!size_t gs_availID;
__gshared size_t gs_maxID = 1;
__gshared core.sync.mutex.Mutex gs_mutex;

private size_t generateID() {
	size_t idx;
	import std.algorithm : max;
	try {
		size_t getIdx() {
			if (!gs_availID.empty) {
				immutable size_t ret = gs_availID.back;
				gs_availID.removeBack();
				return ret;
			}
			return 0;
		}
		
		synchronized(gs_mutex) {
			idx = getIdx();
			if (idx == 0) {
				import std.range : iota;
				gs_availID.insert( iota(gs_maxID, max(32, gs_maxID * 2), 1) );
				gs_maxID = max(32, gs_maxID * 2);
				idx = getIdx();
			}
		}
	} catch (Exception e) {
		assert(false, "Failed to generate necessary ID for Manual Event waiters: " ~ e.msg);
	}
	
	return idx;
}

void recycleID(size_t id) {
	try {
		synchronized(gs_mutex) gs_availID.insert(id);		
	}
	catch (Exception e) {
		assert(false, "Error destroying Manual Event ID: " ~ id.to!string ~ " [" ~ e.msg ~ "]");
	}
}