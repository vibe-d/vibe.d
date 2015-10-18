/**
	Driver implementation for the libasync library

	Libasync is an asynchronous library completely written in D.

	See_Also:
		`vibe.core.driver` = interface definition
		https://github.com/etcimon/libasync = Github repository


	Copyright: © 2014-2015 RejectedSoftware e.K., GlobecSys Inc
	Authors: Sönke Ludwig, Etienne Cimon
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libasync;

version(VibeLibasyncDriver):

import vibe.core.core;
import vibe.core.driver;
import vibe.core.drivers.threadedfile;
import vibe.core.drivers.timerqueue;
import vibe.core.log;
import vibe.utils.array : FixedRingBuffer;

import libasync : AsyncDirectoryWatcher, AsyncDNS, AsyncFile, AsyncSignal, AsyncTimer,
	AsyncTCPConnection, AsyncTCPListener, AsyncUDPSocket, DWFileEvent, DWChangeInfo,
	EventLoop, NetworkAddressLA = NetworkAddress, UDPEvent, TCPEvent, TCPOption, fd_t,
	getThreadEventLoop;
import libasync.internals.memory;
import libasync.types : Status;

import std.algorithm : min, max;
import std.array;
import std.container : Array;
import std.conv;
import std.datetime;
import std.encoding;
import std.exception;
import std.string;
import std.stdio : File;
import std.typecons;

import core.atomic;
import core.memory;
import core.thread;
import core.sync.mutex;
import core.stdc.stdio;
import core.sys.posix.netinet.in_;

version (Posix) import core.sys.posix.sys.socket;
version (Windows) import core.sys.windows.winsock2;

private __gshared EventLoop gs_evLoop;
private EventLoop s_evLoop;
private DriverCore s_driverCore;

version(Windows) extern(C) {
	FILE* _wfopen(const(wchar)* filename, in wchar* mode);
	int _wchmod(in wchar*, int);
}

EventLoop getMainEventLoop() @trusted nothrow
{
	if (s_evLoop is null)
		return gs_evLoop;

	return s_evLoop;
}

DriverCore getDriverCore() @safe nothrow
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
@trusted:
	private {
		bool m_break = false;
		debug Thread m_ownerThread;
		AsyncTimer m_timerEvent;
		TimerQueue!TimerInfo m_timers;
		SysTime m_nextSched = SysTime.max;
		shared AsyncSignal m_exitSignal;
	}

	this(DriverCore core) nothrow
	{
		assert(!isControlThread, "Libasync driver created in control thread");
		try {
			import core.atomic : atomicOp;
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
		catch (Throwable) {
			assert(false, "Couldn't reserve necessary space for available Manual Events");
		}

		debug m_ownerThread = Thread.getThis();
		s_driverCore = core;
		s_evLoop = getThreadEventLoop();
		if (!gs_evLoop)
			gs_evLoop = s_evLoop;

		m_exitSignal = new shared AsyncSignal(getMainEventLoop());
		m_exitSignal.run({
				m_break = true;
			});
		logTrace("Loaded libasync backend in thread %s", Thread.getThis().name);

	}

	static @property bool isControlThread() nothrow {
		scope(failure) assert(false);
		return Thread.getThis().isDaemon && Thread.getThis().name == "CmdProcessor";
	}

	override void dispose()
	{
		logTrace("Deleting event driver");
		m_break = true;
		getMainEventLoop().exit();
	}

	override int runEventLoop()
	{
		while(!m_break && getMainEventLoop().loop(int.max.msecs)){
			processTimers();
			getDriverCore().notifyIdle();
		}
		m_break = false;
		logDebug("Event loop exit %d", m_break);
		return 0;
	}

	override int runEventLoopOnce()
	{
		getMainEventLoop().loop(int.max.msecs);
		processTimers();
		getDriverCore().notifyIdle();
		logTrace("runEventLoopOnce exit");
		return 0;
	}

	override bool processEvents()
	{
		getMainEventLoop().loop(0.seconds);
		processTimers();
		if (m_break) {
			m_break = false;
			return false;
		}
		return true;
	}

	override void exitEventLoop()
	{
		logDebug("Exiting (%s)", m_break);
		m_exitSignal.trigger();

	}

	override LibasyncFileStream openFile(Path path, FileMode mode)
	{
		return new LibasyncFileStream(path, mode);
	}

	override DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		return new LibasyncDirectoryWatcher(path, recursive);
	}

	/** Resolves the given host name or IP address string. */
	override NetworkAddress resolveHost(string host, ushort family = 2, bool use_dns = true)
	{
		import libasync.types : isIPv6;
		isIPv6 is_ipv6;

		if (family == AF_INET6)
			is_ipv6 = isIPv6.yes;
		else
			is_ipv6 = isIPv6.no;

		import std.regex : regex, Captures, Regex, matchFirst, ctRegex;
		import std.traits : ReturnType;

		auto IPv4Regex = ctRegex!(`^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$`, ``);
		auto IPv6Regex = ctRegex!(`^([0-9A-Fa-f]{0,4}:){2,7}([0-9A-Fa-f]{1,4}$|((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4})$`, ``);
		auto ipv4 = matchFirst(host, IPv4Regex);
		auto ipv6 = matchFirst(host, IPv6Regex);
		if (!ipv4.empty)
		{
			if (!ipv4.empty)
			is_ipv6 = isIPv6.no;
			use_dns = false;
		}
		else if (!ipv6.empty)
		{ // fixme: match host instead?
			is_ipv6 = isIPv6.yes;
			use_dns = false;
		}
		else
		{
			use_dns = true;
		}

		NetworkAddress ret;

		if (use_dns) {
			bool done;
			struct DNSCallback  {
				Task waiter;
				NetworkAddress* address;
				bool* finished;
				void handler(NetworkAddressLA addr) {
					*address = NetworkAddress(addr);
					*finished = true;
					if (waiter != Task() && waiter != Task.getThis())
						getDriverCore().resumeTask(waiter);
				}
			}

			DNSCallback* cb = FreeListObjectAlloc!DNSCallback.alloc();
			cb.waiter = Task.getThis();
			cb.address = &ret;
			cb.finished = &done;

			// todo: remove the shared attribute to avoid GC?
			shared AsyncDNS dns = new shared AsyncDNS(getMainEventLoop());
			scope(exit) dns.destroy();
			bool success = dns.handler(&cb.handler).resolveHost(host, is_ipv6);
			if (!success || dns.status.code != Status.OK)
				throw new Exception(dns.status.text);
			while(!done)
				getDriverCore.yieldForEvent();
			if (dns.status.code != Status.OK)
				throw new Exception(dns.status.text);
			assert(ret != NetworkAddress.init);
			assert(ret.family != 0);
			logTrace("Async resolved address %s", ret.toString());
			FreeListObjectAlloc!DNSCallback.free(cb);

			if (ret.family == 0)
				ret.family = family;

			return ret;
		}
		else {
			ret = NetworkAddress(getMainEventLoop().resolveIP(host, 0, is_ipv6));
			if (ret.family == 0)
				ret.family = family;
			return ret;
		}

	}

	override LibasyncTCPConnection connectTCP(NetworkAddress addr, NetworkAddress bind_addr)
	{
		AsyncTCPConnection conn = new AsyncTCPConnection(getMainEventLoop());

		LibasyncTCPConnection tcp_connection = new LibasyncTCPConnection(conn, (TCPConnection conn) {
			Task waiter = (cast(LibasyncTCPConnection) conn).m_settings.writer.task;
			if (waiter != Task()) {
				getDriverCore().resumeTask(waiter);
			}
		});

		if (Task.getThis() != Task())
			tcp_connection.m_settings.writer.acquire();

		tcp_connection.m_tcpImpl.conn = conn;
		//conn.local = bind_addr;
		conn.ip(bind_addr.toAddressString(), bind_addr.port);
		conn.peer = cast(NetworkAddressLA)addr;

		enforce(conn.run(&tcp_connection.handler), "An error occured while starting a new connection: " ~ conn.error);

		while (!tcp_connection.connected && !tcp_connection.m_error) getDriverCore().yieldForEvent();
		enforce(!tcp_connection.m_error, tcp_connection.m_error);
		tcp_connection.m_tcpImpl.localAddr = NetworkAddress(conn.local);

		if (Task.getThis() != Task())
			tcp_connection.m_settings.writer.release();
		return tcp_connection;
	}

	override LibasyncTCPListener listenTCP(ushort port, void delegate(TCPConnection conn) @safe conn_callback, string address, TCPListenOptions options)
	{
		NetworkAddress localaddr = getEventDriver().resolveHost(address);
		localaddr.port = port;

		return new LibasyncTCPListener(localaddr, conn_callback, options);
	}

	override LibasyncUDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
	{
		NetworkAddress localaddr = getEventDriver().resolveHost(bind_address);
		localaddr.port = port;
		AsyncUDPSocket sock = new AsyncUDPSocket(getMainEventLoop());
		sock.local = cast(NetworkAddressLA)localaddr;
		auto udp_connection = new LibasyncUDPConnection(sock);
		sock.run(&udp_connection.handler);
		return udp_connection;
	}

	override LibasyncManualEvent createManualEvent()
	{
		return new LibasyncManualEvent(this);
	}

	override FileDescriptorEvent createFileDescriptorEvent(int file_descriptor, FileDescriptorEvent.Trigger triggers, FileDescriptorEvent.Mode mode)
	{
		assert(false);
	}


	// The following timer implementation was adapted from the equivalent in libevent2.d

	override size_t createTimer(void delegate() @safe callback) { return m_timers.create(TimerInfo(callback)); }

	override void acquireTimer(size_t timer_id) { m_timers.getUserData(timer_id).refCount++; }
	override void releaseTimer(size_t timer_id)
	nothrow {
		debug assert(m_ownerThread is Thread.getThis());
		logTrace("Releasing timer %s", timer_id);
		if (!--m_timers.getUserData(timer_id).refCount)
			m_timers.destroy(timer_id);
	}

	override bool isTimerPending(size_t timer_id) nothrow { return m_timers.isPending(timer_id); }

	override void rearmTimer(size_t timer_id, Duration dur, bool periodic)
	{
		debug assert(m_ownerThread is Thread.getThis());
		if (!isTimerPending(timer_id)) acquireTimer(timer_id);
		m_timers.schedule(timer_id, dur, periodic);
		rescheduleTimerEvent(Clock.currTime(UTC()));
	}

	override void stopTimer(size_t timer_id)
	{
		logTrace("Stopping timer %s", timer_id);
		if (m_timers.isPending(timer_id)) {
			m_timers.unschedule(timer_id);
			releaseTimer(timer_id);
		}
	}

	override void waitTimer(size_t timer_id)
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
		// event loop timer will need to be rescheduled because we'll process everything until now
		m_nextSched = SysTime.max;

		m_timers.consumeTimeouts(now, (timer, periodic, ref data) {
			Task owner = data.owner;
			auto callback = data.callback;

			logTrace("Timer %s fired (%s/%s)", timer, owner != Task.init, callback !is null);

			if (!periodic) releaseTimer(timer);

			if (owner && owner.running && owner != Task.getThis()) {
				if (Task.getThis == Task.init) getDriverCore().resumeTask(owner);
				else getDriverCore().yieldAndResumeTask(owner);
			}
			if (callback) runTask(callback);
		});

		rescheduleTimerEvent(now);
	}

	private void rescheduleTimerEvent(SysTime now)
	{
		logTrace("Rescheduling timer event %s", Task.getThis());

		// don't bother scheduling, the timers will be processed before leaving for the event loop
		if (m_nextSched <= Clock.currTime(UTC()))
			return;

		bool first;
		auto next = m_timers.getFirstTimeout();
		Duration dur;
		if (next == SysTime.max) return;
		dur = max(1.msecs, next - now);
		if (m_nextSched != next)
			m_nextSched = next;
		else return;
		if (dur.total!"seconds"() >= int.max)
			return; // will never trigger, don't bother
		if (!m_timerEvent) {
			//logTrace("creating new async timer");
			m_timerEvent = new AsyncTimer(getMainEventLoop());
			bool success = m_timerEvent.duration(dur).run(&onTimerTimeout);
			assert(success, "Failed to run timer");
		}
		else {
			//logTrace("rearming the same timer instance");
			bool success = m_timerEvent.rearm(dur);
			assert(success, "Failed to rearm timer");
		}
		//logTrace("Rescheduled timer event for %s seconds in thread '%s' :: task '%s'", dur.total!"usecs" * 1e-6, Thread.getThis().name, Task.getThis());
	}

	private void onTimerTimeout()
	{
		import std.encoding : sanitize;

		logTrace("timer event fired");
		try processTimers();
		catch (Exception e) {
			logError("Failed to process timers: %s", e.msg);
			try logDiagnostic("Full error: %s", e.toString().sanitize); catch (Throwable) {}
		}
	}
}

/// Writes or reads asynchronously (in another thread) for sizes > 64kb to benefit from kernel page cache
/// in lower size operations.
final class LibasyncFileStream : FileStream {
@trusted:
	import vibe.core.path : Path;

	private {
		Path m_path;
		ulong m_size;
		ulong m_offset = 0;
		FileMode m_mode;
		Task m_task;
		Exception m_ex;
		shared AsyncFile m_impl;

		bool m_started;
		bool m_truncated;
		bool m_finished;
	}

	this(Path path, FileMode mode)
	{
		import std.file : getSize,exists;
		if (mode != FileMode.createTrunc)
			m_size = getSize(path.toNativeString());
		else {
			auto path_str = path.toNativeString();
			if (exists(path_str))
				removeFile(path);
			{ // touch
				import std.string : toStringz;
				version(Windows) {
					import std.utf : toUTF16z;
					auto path_str_utf = path_str.toUTF16z();
					FILE* f = _wfopen(path_str_utf, "w");
					_wchmod(path_str_utf, S_IREAD|S_IWRITE);
				}
				else FILE * f = fopen(path_str.toStringz, "w");
				fclose(f);
				m_truncated = true;
			}
		}
		m_path = path;
		m_mode = mode;

		m_impl = new shared AsyncFile(getMainEventLoop());
		m_impl.onReady(&handler);

		m_started = true;
	}

	~this()
	{
		try close();
		catch (Exception e) { assert(false, e.msg); }
	}

	override @property Path path() const { return m_path; }
	override @property bool isOpen() const { return m_started; }
	override @property ulong size() const { return m_size; }
	override @property bool readable() const { return m_mode != FileMode.append; }
	override @property bool writable() const { return m_mode != FileMode.read; }

	override void seek(ulong offset)
	{
		m_offset = offset;
	}

	override ulong tell() { return m_offset; }

	override void close()
	{
		if (m_impl) {
			m_impl.kill();
			m_impl = null;
		}
		m_started = false;
		if (m_task != Task() && Task.getThis() != Task())
			getDriverCore().yieldAndResumeTask(m_task, new Exception("The file was closed during an operation"));
		else if (m_task != Task() && Task.getThis() == Task())
			getDriverCore().resumeTask(m_task, new Exception("The file was closed during an operation"));

	}

	override @property bool empty() const { assert(this.readable); return m_offset >= m_size; }
	override @property ulong leastSize() const { assert(this.readable); return m_size - m_offset; }
	override @property bool dataAvailableForRead() { return true; }

	override const(ubyte)[] peek()
	{
		return null;
	}

	override size_t read(scope ubyte[] dst, IOMode)
	{
		scope(failure)
			close();
		assert(this.readable, "To read a file, it must be opened in a read-enabled mode.");
		shared ubyte[] bytes = cast(shared) dst;
		bool truncate_if_exists;
		if (!m_truncated && m_mode == FileMode.createTrunc) {
			truncate_if_exists = true;
			m_truncated = true;
			m_size = 0;
		}
		m_finished = false;
		enforce(dst.length <= leastSize);
		enforce(m_impl.read(m_path.toNativeString(), bytes, m_offset, true, truncate_if_exists), "Failed to read data from disk: " ~ m_impl.error);

		if (!m_finished) {
			acquire();
			scope(exit) release();
			getDriverCore().yieldForEvent();
		}
		m_finished = false;

		if (m_ex) throw m_ex;

		m_offset += dst.length;
		assert(m_impl.offset == m_offset, "Incoherent offset returned from file reader: " ~ m_offset.to!string ~ "B assumed but the implementation is at: " ~ m_impl.offset.to!string ~ "B");

		return dst.length;
	}

	alias Stream.write write;
	override size_t write(in ubyte[] bytes_, IOMode)
	{
		assert(this.writable, "To write to a file, it must be opened in a write-enabled mode.");

		shared const(ubyte)[] bytes = cast(shared const(ubyte)[]) bytes_;

		bool truncate_if_exists;
		if (!m_truncated && m_mode == FileMode.createTrunc) {
			truncate_if_exists = true;
			m_truncated = true;
			m_size = 0;
		}
		m_finished = false;

		if (m_mode == FileMode.append)
			enforce(m_impl.append(m_path.toNativeString(), cast(shared ubyte[]) bytes, true, truncate_if_exists), "Failed to write data to disk: " ~ m_impl.error);
		else
			enforce(m_impl.write(m_path.toNativeString(), bytes, m_offset, true, truncate_if_exists), "Failed to write data to disk: " ~ m_impl.error);

		if (!m_finished) {
			acquire();
			scope(exit) release();
			getDriverCore().yieldForEvent();
		}
		m_finished = false;

		if (m_ex) throw m_ex;

		if (m_mode == FileMode.append) {
			m_size += bytes.length;
		}
		else {
			m_offset += bytes.length;
			if (m_offset >= m_size)
				m_size += m_offset - m_size;
			assert(m_impl.offset == m_offset, "Incoherent offset returned from file writer.");
		}
		//assert(getSize(m_path.toNativeString()) == m_size, "Incoherency between local size and filesize: " ~ m_size.to!string ~ "B assumed for a file of size " ~ getSize(m_path.toNativeString()).to!string ~ "B");

		return bytes_.length;
	}

	override void flush()
	{
		assert(this.writable, "To write to a file, it must be opened in a write-enabled mode.");

	}

	override void finalize()
	{
		if (this.writable)
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

	private void handler() {
		// This may be called by the event loop if read/write > 64kb and another thread was delegated
		Exception ex;

		if (m_impl.status.code != Status.OK)
			ex = new Exception(m_impl.error);
		m_finished = true;
		if (m_task != Task())
			getDriverCore().resumeTask(m_task, ex);
		else m_ex = ex;
	}
}


final class LibasyncDirectoryWatcher : DirectoryWatcher {
@trusted:
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
		m_impl = new AsyncDirectoryWatcher(getMainEventLoop());
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

	override @property Path path() const { return m_path; }
	override @property bool recursive() const { return m_recursive; }

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

	override bool readChanges(ref DirectoryChange[] dst, Duration timeout)
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
@trusted:
	private {
		shared(int) m_emitCount = 0;
		shared(int) m_threadCount = 0;
		shared(size_t) m_instance;
		Array!(void*) ms_signals;

		core.sync.mutex.Mutex m_mutex;

		@property size_t instanceID() nothrow { return atomicLoad(m_instance); }
		@property void instanceID(size_t instance) nothrow{ atomicStore(m_instance, instance); }
	}

	this(LibasyncDriver driver)
	nothrow {
		m_mutex = new core.sync.mutex.Mutex;
		instanceID = generateID();
	}

	~this()
	{
		try {
			recycleID(instanceID);

			foreach (ref signal; ms_signals[]) {
				if (signal) {
					(cast(shared AsyncSignal) signal).kill();
					signal = null;
				}
			}
		} catch (Exception e) {
			import std.stdio;
			writefln("Exception thrown while finalizing LibasyncManualEvent: %s", e.msg);
		}
	}

	override void emit()
	{
		scope (failure) assert(false); // synchronized is not nothrow on DMD 2.066 and below and Array is not nothrow at all
		logTrace("Emitting signal");
		atomicOp!"+="(m_emitCount, 1);
		synchronized (m_mutex) {
			logTrace("Looping signals. found: " ~ ms_signals.length.to!string);
			foreach (ref signal; ms_signals[]) {
				auto evloop = getMainEventLoop();
				shared AsyncSignal sig = cast(shared AsyncSignal) signal;
				if (!sig.trigger(evloop)) logError("Failed to trigger ManualEvent: %s", sig.error);
			}
		}
	}

	override void wait() { wait(m_emitCount); }
	override int wait(int reference_emit_count) { return  doWait!true(reference_emit_count); }
	override int wait(Duration timeout, int reference_emit_count) { return doWait!true(timeout, reference_emit_count); }
	override int waitUninterruptible(int reference_emit_count) { return  doWait!false(reference_emit_count); }
	override int waitUninterruptible(Duration timeout, int reference_emit_count) { return doWait!false(timeout, reference_emit_count); }

	void acquire()
	{
		auto task = Task.getThis();

		bool signal_exists;

		size_t instance = instanceID;
		if (s_eventWaiters.length <= instance)
			expandWaiters();

		logTrace("Acquire event ID#%d", instance);
		auto taskList = s_eventWaiters[instance];
		if (taskList.length > 0)
			signal_exists = true;

		if (!signal_exists) {
			shared AsyncSignal sig = new shared AsyncSignal(getMainEventLoop());
			sig.run(&onSignal);
			synchronized (m_mutex) ms_signals.insertBack(cast(void*)sig);
		}
		s_eventWaiters[instance].insertBack(Task.getThis());
	}

	void release()
	{
		assert(amOwner(), "Releasing non-acquired signal.");

		import std.algorithm : countUntil;

		size_t instance = instanceID;
		auto taskList = s_eventWaiters[instance];
		auto idx = taskList[].countUntil!((a, b) => a == b)(Task.getThis());
		logTrace("Release event ID#%d", instance);
		s_eventWaiters[instance].linearRemove(taskList[idx .. idx+1]);

		if (s_eventWaiters[instance].empty) {
			removeMySignal();
		}
	}

	bool amOwner()
	{
		import std.algorithm : countUntil;
		size_t instance = instanceID;
		if (s_eventWaiters.length <= instance) return false;
		auto taskList = s_eventWaiters[instance];
		if (taskList.length == 0) return false;

		auto idx = taskList[].countUntil!((a, b) => a == b)(Task.getThis());

		return idx != -1;
	}

	override @property int emitCount() const { return atomicLoad(m_emitCount); }

	private int doWait(bool INTERRUPTIBLE)(int reference_emit_count)
	{
		try {
			assert(!amOwner());
			acquire();
			scope(exit) release();
			auto ec = this.emitCount;
			while( ec == reference_emit_count ){
				//synchronized(m_mutex) logTrace("Waiting for event with signal count: " ~ ms_signals.length.to!string);
				static if (INTERRUPTIBLE) getDriverCore().yieldForEvent();
				else getDriverCore().yieldForEventDeferThrow();
				ec = this.emitCount;
			}
			return ec;
		} catch (Exception e) {
			static if (!INTERRUPTIBLE)
				assert(false, e.msg); // still some function calls not marked nothrow
			else throw e;
		}
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
			if (idx >= 0)
				ms_signals.linearRemove(ms_signals[idx .. idx+1]);
		}
	}

	private void expandWaiters() {
		size_t maxID;
		synchronized(gs_mutex) maxID = gs_maxID;
		s_eventWaiters.reserve(maxID);
		logTrace("gs_maxID: %d", maxID);
		size_t s_ev_len = s_eventWaiters.length;
		size_t s_ev_cap = s_eventWaiters.capacity;
		assert(maxID > s_eventWaiters.length);
		foreach (i; s_ev_len .. s_ev_cap) {
			s_eventWaiters.insertBack(Array!Task.init);
		}
	}

	private void onSignal()
	{
		logTrace("Got signal in onSignal");
		try {
			auto thread = Thread.getThis();
			auto core = getDriverCore();

			size_t instance = instanceID;
			logTrace("Got context: %d", instance);
			foreach (Task task; s_eventWaiters[instance][]) {
				logTrace("Task Found");
				core.resumeTask(task);
			}
		} catch (Exception e) {
			logError("Exception while handling signal event: %s", e.msg);
			try logDebug("Full error: %s", sanitize(e.msg));
			catch (Exception) {}
		}
	}
}

final class LibasyncTCPListener : TCPListener {
@trusted:
	private {
		NetworkAddress m_local;
		void delegate(TCPConnection conn) @safe m_connectionCallback;
		TCPListenOptions m_options;
		AsyncTCPListener[] m_listeners;
		fd_t socket;
	}

	this(NetworkAddress addr, void delegate(TCPConnection conn) @safe connection_callback, TCPListenOptions options)
	{
		m_connectionCallback = connection_callback;
		m_options = options;
		m_local = addr;
		void function(shared LibasyncTCPListener) init = (shared LibasyncTCPListener ctxt){
			synchronized(ctxt) {
				LibasyncTCPListener ctxt2 = cast(LibasyncTCPListener)ctxt;
				AsyncTCPListener listener = new AsyncTCPListener(getMainEventLoop(), ctxt2.socket);
				listener.local = cast(NetworkAddressLA)ctxt2.m_local;

				enforce(listener.run(&ctxt2.initConnection), "Failed to start listening to local socket: " ~ listener.error);
				ctxt2.socket = listener.socket;
				ctxt2.m_listeners ~= listener;
			}
		};
		if (options & TCPListenOptions.distribute)	runWorkerTaskDist(init, cast(shared) this);
		else init(cast(shared) this);

	}

	override @property NetworkAddress bindAddress() { return m_local; }

	@property void delegate(TCPConnection) connectionCallback() { return m_connectionCallback; }

	private void delegate(TCPEvent) initConnection(AsyncTCPConnection conn) {
		logTrace("Connection initialized in thread: " ~ Thread.getThis().name);

		LibasyncTCPConnection native_conn = new LibasyncTCPConnection(conn, m_connectionCallback);
		native_conn.m_tcpImpl.conn = conn;
		native_conn.m_tcpImpl.localAddr = m_local;
		return &native_conn.handler;
	}

	override void stopListening()
	{
		synchronized(this) {
			foreach (listener; m_listeners) {
				listener.kill();
				listener = null;
			}
		}
	}
}

final class LibasyncTCPConnection : TCPConnection/*, Buffered*/ {
@trusted:
	private {
		FixedRingBuffer!ubyte m_readBuffer;
		ubyte[] m_buffer;
		ubyte[] m_slice;
		TCPConnectionImpl m_tcpImpl;
		Settings m_settings;

		bool m_closed = true;
		bool m_mustRecv = true;
		string m_error;

		// The socket descriptor is unavailable to motivate low-level/API feature additions
		// rather than high-lvl platform-dependent hacking
		// fd_t socket;
	}

	ubyte[] readChunk(ubyte[] buffer = null)
	{
		logTrace("readBuf TCP: %d", buffer.length);
		import std.algorithm : swap;
		ubyte[] ret;

		if (m_slice.length > 0) {
			swap(ret, m_slice);
			logTrace("readBuf returned instantly with slice length: %d", ret.length);
			return ret;
		}

		if (m_readBuffer.length > 0) {
			size_t amt = min(buffer.length, m_readBuffer.length);
			m_readBuffer.read(buffer[0 .. amt]);
			logTrace("readBuf returned with existing amount: %d", amt);
			return buffer[0 .. amt];
		}

		if (buffer) {
			m_buffer = buffer;
			m_readBuffer.dispose();
		}

		leastSize();

		swap(ret, m_slice);
		logTrace("readBuf returned with buffered length: %d", ret.length);
		return ret;
	}

	this(AsyncTCPConnection conn, void delegate(TCPConnection) @safe cb)
	in { assert(conn !is null); }
	body {
		m_settings.onConnect = cb;
		m_readBuffer.capacity = 64*1024;
	}

	private @property AsyncTCPConnection conn() {

		return m_tcpImpl.conn;
	}

	// Using this setting completely disables the internal buffers as well
	override @property void tcpNoDelay(bool enabled)
	{
		m_settings.tcpNoDelay = enabled;
		conn.setOption(TCPOption.NODELAY, enabled);
	}

	override @property bool tcpNoDelay() const { return m_settings.tcpNoDelay; }

	override @property void readTimeout(Duration dur)
	{
		m_settings.readTimeout = dur;
		conn.setOption(TCPOption.TIMEOUT_RECV, dur);
	}

	override @property Duration readTimeout() const { return m_settings.readTimeout; }

	override @property void keepAlive(bool enabled)
	{
		m_settings.keepAlive = enabled;
		conn.setOption(TCPOption.KEEPALIVE_ENABLE, enabled);
	}

	override @property bool keepAlive() const { return m_settings.keepAlive; }

	override @property bool connected() const { return !m_closed && m_tcpImpl.conn && m_tcpImpl.conn.isConnected; }

	override @property bool dataAvailableForRead(){
		logTrace("dataAvailableForRead");
		m_settings.reader.acquire();
		scope(exit) m_settings.reader.release();
		return !readEmpty;
	}

	private @property bool readEmpty() {
		return (m_buffer && !m_slice) || (!m_buffer && m_readBuffer.empty);
	}

	override @property string peerAddress() const { return m_tcpImpl.conn.peer.toString(); }

	override @property NetworkAddress localAddress() const { return m_tcpImpl.localAddr; }
	override @property NetworkAddress remoteAddress() const { return NetworkAddress(m_tcpImpl.conn.peer); }

	override @property bool empty() { return leastSize == 0; }

	override @property ulong leastSize()
	{
		logTrace("leastSize TCP");
		m_settings.reader.acquire();
		scope(exit) m_settings.reader.release();

		while( m_readBuffer.empty ){
			if (!connected)
				return 0;
			m_settings.reader.noExcept = true;
			getDriverCore().yieldForEvent();
			m_settings.reader.noExcept = false;
		}
		return (m_slice.length > 0) ? m_slice.length : m_readBuffer.length;
	}

	override void close()
	{
		logTrace("Close TCP enter");

		// resume any reader, so that the read operation can be ended with a failure
		Task reader = m_settings.reader.task;
		while (m_settings.reader.isWaiting && reader.running) {
			logTrace("resuming reader first");
			getDriverCore().yieldAndResumeTask(reader);
		}

		// test if the connection is already closed
		if (m_closed) {
			logTrace("connection already closed.");
			return;
		}

		//logTrace("closing");
		m_settings.writer.acquire();
		scope(exit) m_settings.writer.release();

		// checkConnected();
		m_readBuffer.dispose();
		onClose(null, false);
	}

	override bool waitForData(Duration timeout = Duration.max)
	{
		// 0 seconds is max. CHanging this would be breaking, might as well use -1 for immediate
		if (timeout == 0.seconds)
			timeout = Duration.max;
		logTrace("WaitForData enter, timeout %s :: Ptr %s",  timeout.toString(), (cast(void*)this).to!string);
		m_settings.reader.acquire();
		auto _driver = getEventDriver();
		auto tm = _driver.createTimer(null);
		scope(exit) {
			_driver.stopTimer(tm);
			_driver.releaseTimer(tm);
			m_settings.reader.release();
		}
		_driver.m_timers.getUserData(tm).owner = Task.getThis();
		if (timeout != Duration.max) _driver.rearmTimer(tm, timeout, false);
		logTrace("waitForData TCP");
		while (m_readBuffer.empty) {
			if (!connected) return false;

			if (m_mustRecv)
				onRead();
			else {
				//logTrace("Yielding for event in waitForData, waiting? %s", m_settings.reader.isWaiting);
				m_settings.reader.noExcept = true;
				getDriverCore().yieldForEvent();
				m_settings.reader.noExcept = false;
			}
			if (timeout != Duration.max && !_driver.isTimerPending(tm)) {
				logTrace("WaitForData TCP: timer signal");
				return false;
			}
		}
		if (m_readBuffer.empty && !connected) return false;
		logTrace("WaitForData exit: fiber resumed with read buffer");
		return !m_readBuffer.empty;
	}

	override const(ubyte)[] peek()
	{
		logTrace("Peek TCP enter");
		m_settings.reader.acquire();
		scope(exit) m_settings.reader.release();

		if (!readEmpty)
			return (m_slice.length > 0) ? cast(const(ubyte)[]) m_slice : m_readBuffer.peek();
		else
			return null;
	}

	override size_t read(scope ubyte[] dst, IOMode)
	{
		if (!dst.length) return 0;
		assert(dst !is null && !m_slice);
		logTrace("Read TCP");
		m_settings.reader.acquire();
		size_t len = 0;
		scope(exit) m_settings.reader.release();
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
			len += amt;
		}

		return len;
	}

	override size_t write(in ubyte[] bytes_, IOMode)
	{
		assert(bytes_ !is null);
		logTrace("%s", "write enter");
		m_settings.writer.acquire();
		scope(exit) m_settings.writer.release();
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

		return len;
	}

	override void flush()
	{
		logTrace("%s", "Flush");
		m_settings.writer.acquire();
		scope(exit) m_settings.writer.release();

		checkConnected();

	}

	override void finalize()
	{
		logTrace("%s", "finalize");
		flush();
	}

	private void checkConnected()
	{
		enforce(connected, "The remote peer has closed the connection.");
		logTrace("Check Connected");
	}

	private bool tryReadBuf() {
		//logTrace("TryReadBuf with m_buffer: %s", m_buffer.length);
		if (m_buffer) {
			ubyte[] buf = m_buffer[m_slice.length .. $];
			uint ret = conn.recv(buf);
			logTrace("Received: %s", buf[0 .. ret]);
			// check for overflow
			if (ret == buf.length) {
				logTrace("Overflow detected, revert to ring buffer");
				m_slice = null;
				m_readBuffer.capacity = 64*1024;
				m_readBuffer.put(buf);
				m_buffer = null;
				return false; // cancel slices and revert to the fixed ring buffer
			}

			if (m_slice.length > 0) {
				//logDebug("post-assign m_slice ");
				m_slice = m_slice.ptr[0 .. m_slice.length + ret];
			}
			else {
				//logDebug("using m_buffer");
				m_slice = m_buffer[0 .. ret];
			}
			return true;
		}
		logTrace("TryReadBuf exit with %d bytes in m_slice, %d bytes in m_readBuffer ", m_slice.length, m_readBuffer.length);

		return false;
	}

	private void onRead() {
		m_mustRecv = true; // assume we didn't receive everything

		if (tryReadBuf()) {
			m_mustRecv = false;
			return;
		}

		assert(!m_slice);

		logTrace("OnRead with %s", m_readBuffer.freeSpace);

		while( m_readBuffer.freeSpace > 0 ) {
			ubyte[] dst = m_readBuffer.peekDst();
			assert(dst.length <= int.max);
			logTrace("Try to read up to bytes: %s", dst.length);
			bool read_more;
			do {
				uint ret = conn.recv(dst);
				if( ret > 0 ){
					logTrace("received bytes: %s", ret);
					m_readBuffer.putN(ret);
				}
				read_more = ret == dst.length;
				// ret == 0! let's look for some errors
				if (read_more) {
					if (m_readBuffer.freeSpace == 0)
						m_readBuffer.capacity = m_readBuffer.capacity*2;
					dst = m_readBuffer.peekDst();
				}
			} while( read_more );
			if (conn.status.code == Status.ASYNC) {
				m_mustRecv = false; // we'll have to wait
				break; // the kernel's buffer is empty
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
	private void onClose(in string msg = null, bool wake_ex = true) {
		logTrace("onClose");

		if (msg)
			m_error = msg;
		if (!m_closed) {

			m_closed = true;

			if (m_tcpImpl.conn && m_tcpImpl.conn.isConnected) {
				m_tcpImpl.conn.kill(Task.getThis() != Task.init); // close the connection
				m_tcpImpl.conn = null;
			}
		}
		if (Task.getThis() != Task.init) {
			return;
		}
		Exception ex;
		if (!msg && wake_ex)
			ex = new Exception("Connection closed");
		else if (wake_ex)	ex = new Exception(msg);


		Task reader = m_settings.reader.task;
		Task writer = m_settings.writer.task;

		bool hasUniqueReader = m_settings.reader.isWaiting;
		bool hasUniqueWriter = m_settings.writer.isWaiting && reader != writer;

		if (hasUniqueWriter && Task.getThis() != writer && wake_ex) {
			getDriverCore().resumeTask(writer, ex);
		}
		if (hasUniqueReader && Task.getThis() != reader) {
			getDriverCore().resumeTask(reader, m_settings.reader.noExcept?null:ex);
		}
	}

	void onConnect() {
		scope(failure) onClose();

		if (m_tcpImpl.conn && m_tcpImpl.conn.isConnected)
		{
			bool inbound = m_tcpImpl.conn.inbound;

			try m_settings.onConnect(this);
			catch ( Exception e) {
				//logError(e.toString);
				throw e;
			}
			catch ( Throwable e) {
				logError("%s", e.toString);
				throw e;
			}
			if (inbound) close();
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
				m_settings.onConnect = null;
				break;
			case TCPEvent.READ:
				// fill the read buffer and resume any task if waiting
				try onRead();
				catch (Exception e) ex = e;
				if (m_settings.reader.isWaiting)
					getDriverCore().resumeTask(m_settings.reader.task, ex);
				goto case TCPEvent.WRITE; // sometimes the kernel notified write with read events
			case TCPEvent.WRITE:
				// The kernel is ready to have some more data written, all we need to do is wake up the writer
				if (m_settings.writer.isWaiting)
					getDriverCore().resumeTask(m_settings.writer.task, ex);
				break;
			case TCPEvent.CLOSE:
				m_closed = false;
				onClose();
				if (m_settings.onConnect)
					m_settings.onConnect(this);
				m_settings.onConnect = null;
				break;
			case TCPEvent.ERROR:
				m_closed = false;
				onClose(conn.error);
				if (m_settings.onConnect)
					m_settings.onConnect(this);
				m_settings.onConnect = null;
				break;
		}
		return;
	}

	struct Waiter {
		Task task; // we can only have one task waiting for read/write operations
		bool isWaiting; // if a task is actively waiting
		bool noExcept;

		void acquire() {
			assert(!this.isWaiting, "Acquiring waiter that is already in use.");
			if (Task.getThis() == Task()) return;
			logTrace("%s", "Acquire waiter");
			assert(!amOwner(), "Failed to acquire waiter in task: " ~ Task.getThis().fiber.to!string ~ ", it was busy with: " ~ this.task.to!string);
			this.task = Task.getThis();
			this.isWaiting = true;
		}

		void release() {
			if (Task.getThis() == Task()) return;
			logTrace("%s", "Release waiter");
			assert(amOwner());
			this.isWaiting = false;
		}

		bool amOwner() const {
			if (this.isWaiting && this.task == Task.getThis())
				return true;
			return false;
		}
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
@trusted:
	private {
		Task m_task;
		AsyncUDPSocket m_udpImpl;
		bool m_canBroadcast;
		NetworkAddressLA m_peer;

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

	override @property string bindAddress() const {

		return m_udpImpl.local.toAddressString();
	}

	override @property NetworkAddress localAddress() const { return NetworkAddress(m_udpImpl.local); }

	override @property bool canBroadcast() const { return m_canBroadcast; }
	override @property void canBroadcast(bool val)
	{
		socket.broadcast(val);
		m_canBroadcast = val;
	}

	override void close()
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

	override void connect(string host, ushort port)
	{
		// assert(m_peer == NetworkAddress.init, "Cannot connect to another peer");
		NetworkAddress addr = getEventDriver().resolveHost(host, localAddress.family, true);
		addr.port = port;
		connect(addr);
	}

	override void connect(NetworkAddress addr)
	{
		m_peer = cast(NetworkAddressLA)addr;
	}

	override void send(in ubyte[] data, in NetworkAddress* peer_address = null)
	{
		assert(data.length <= int.max);
		uint ret;
		size_t retries = 3;
		foreach  (i; 0 .. retries) {
			if( peer_address ){
				auto pa = cast(NetworkAddressLA)*cast(NetworkAddress*)peer_address;
				ret = socket.sendTo(data, pa);
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

	override ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		return recv(Duration.max, buf, peer_address);
	}

	override ubyte[] recv(Duration timeout, ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		size_t tm = size_t.max;
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
		NetworkAddressLA from;
		from.family = localAddress.family;
		while(true){
			auto ret = socket.recvFrom(buf, from);
			if( ret > 0 ){
				if( peer_address ) *peer_address = NetworkAddress(from);
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

	void addMembership(ref NetworkAddress multiaddr)
	{
		assert(false, "TODO!");
	}

	@property void multicastLoopback(bool loop)
	{
		assert(false, "TODO!");
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
__gshared size_t gs_maxID;
__gshared core.sync.mutex.Mutex gs_mutex;

private size_t generateID()
nothrow @trusted {
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
				gs_availID.insert( iota(gs_maxID + 1, max(32, gs_maxID * 2 + 1), 1) );
				gs_maxID = gs_availID[$-1];
				idx = getIdx();
			}
		}
	} catch (Exception e) {
		assert(false, "Failed to generate necessary ID for Manual Event waiters: " ~ e.msg);
	}

	return idx - 1;
}

void recycleID(size_t id)
@trusted nothrow {
	try {
		synchronized(gs_mutex) gs_availID.insert(id+1);
	}
	catch (Exception e) {
		assert(false, "Error destroying Manual Event ID: " ~ id.to!string ~ " [" ~ e.msg ~ "]");
	}
}
