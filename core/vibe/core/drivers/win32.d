/**
	Driver implementation for Win32 using WSAAsyncSelect

	See_Also:
		`vibe.core.driver` = interface definition

	Copyright: © 2012-2015 Sönke Ludwig
	Authors: Sönke Ludwig, Leonid Kramer
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.win32;

version(VibeWin32Driver)
{

import vibe.core.core;
import vibe.core.driver;
import vibe.core.drivers.timerqueue;
import vibe.core.drivers.utils;
import vibe.core.log;
import vibe.internal.win32;
import vibe.internal.meta.traits : synchronizedIsNothrow;
import vibe.utils.array;
import vibe.utils.hashmap;

import core.atomic;
import core.sync.mutex;
import core.sys.windows.windows;
import core.time;
import core.thread;
import std.algorithm;
import std.conv;
import std.datetime;
import std.exception;
import std.string : lastIndexOf;
import std.typecons;
import std.utf;

import core.sys.windows.windows;
import core.sys.windows.winsock2;

enum WM_USER_SIGNAL = WM_USER+101;
enum WM_USER_SOCKET = WM_USER+102;

pragma(lib, "wsock32");
pragma(lib, "ws2_32");

/******************************************************************************/
/* class Win32EventDriver                                                     */
/******************************************************************************/

final class Win32EventDriver : EventDriver {
@trusted:
	import std.container : Array, BinaryHeap, heapify;
	import std.datetime : Clock;

	private {
		HWND m_hwnd;
		DWORD m_tid;
		DriverCore m_core;
		bool m_exit = false;
		SocketEventHandler[SOCKET] m_socketHandlers;
		HANDLE[] m_registeredEvents;
		HANDLE m_fileCompletionEvent;
		bool[Win32TCPConnection] m_fileWriters;

		TimerQueue!TimerInfo m_timers;
	}

	this(DriverCore core)
	{
		setupWindowClass();

		m_core = core;
		m_tid = GetCurrentThreadId();
		m_hwnd = CreateWindowA("VibeWin32MessageWindow", "VibeWin32MessageWindow", 0, 0,0,0,0, HWND_MESSAGE,null,null,null);

		SetWindowLongPtrA(m_hwnd, GWLP_USERDATA, cast(ULONG_PTR)cast(void*)this);
		assert(cast(Win32EventDriver)cast(void*)GetWindowLongPtrA(m_hwnd, GWLP_USERDATA) is this);

		WSADATA wd;
		enforce(WSAStartup(0x0202, &wd) == 0, "Failed to initialize WinSock");

		m_fileCompletionEvent = CreateEventW(null, false, false, null);
		m_registeredEvents ~= m_fileCompletionEvent;
	}

	override void dispose()
	{
//		DestroyWindow(m_hwnd);
	}

	override int runEventLoop()
	{
		void removePendingQuitMessages() @trusted {
			MSG msg;
			while (PeekMessageW(&msg, null, WM_QUIT, WM_QUIT, PM_REMOVE)) {}
		}

		// clear all possibly outstanding WM_QUIT messages to avoid
		// them having an influence this runEventLoop()
		removePendingQuitMessages();

		m_exit = false;
		while (!m_exit && haveEvents())
			runEventLoopOnce();

		// remove quit messages here to avoid them having an influence on
		// processEvets or runEventLoopOnce
		removePendingQuitMessages();
		return 0;
	}

	override int runEventLoopOnce()
	{
		doProcessEvents(INFINITE);
		return 0;
	}

	override bool processEvents()
	{
		return doProcessEvents(0);
	}

	bool doProcessEvents(uint timeout_msecs)
	@trusted {
		assert(m_tid == GetCurrentThreadId());

		waitForEvents(timeout_msecs);

		processTimers();

		MSG msg;
		//uint cnt = 0;
		while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE)) {
			if( msg.message == WM_QUIT ) {
				m_exit = true;
				return false;
			}
			if( msg.message == WM_USER_SIGNAL )
				msg.hwnd = m_hwnd;
			TranslateMessage(&msg);
			DispatchMessageW(&msg);

			// process timers every now and then so that they don't get stuck
			//if (++cnt % 10 == 0) processTimers();
		}

		if (timeout_msecs != 0) m_core.notifyIdle();

		return true;
	}

	private bool haveEvents()
	@safe {
		version(VibePartialAutoExit)
			return !m_fileWriters.byKey.empty || !m_socketHandlers.byKey.empty;
		else return true;
	}

	private void waitForEvents(uint timeout_msecs)
	{
		// if timers are pending, limit the wait time to the first timer timeout
		auto next_timer = m_timers.getFirstTimeout();
		if (timeout_msecs > 0 && next_timer != SysTime.max) {
			auto now = Clock.currStdTime();
			auto timer_timeout = (next_timer.stdTime - now) / 10_000;
			if (timeout_msecs == INFINITE || timer_timeout < timeout_msecs)
				timeout_msecs = cast(uint)(timer_timeout < 0 ? 0 : timer_timeout > uint.max ? uint.max : timer_timeout);
		}

		auto ret = MsgWaitForMultipleObjectsEx(cast(DWORD)m_registeredEvents.length, m_registeredEvents.ptr, timeout_msecs, QS_ALLEVENTS, MWMO_ALERTABLE|MWMO_INPUTAVAILABLE);
		if( ret == WAIT_OBJECT_0 ){
			Win32TCPConnection[] to_remove;
			foreach( fw; m_fileWriters.byKey )
				if( fw.testFileWritten() )
					to_remove ~= fw;
			foreach( fw; to_remove )
			m_fileWriters.remove(fw);
		}
	}

	private void processTimers()
	{
		if (!m_timers.anyPending) return;

		// process all timers that have expired up to now
		auto now = Clock.currTime(UTC());
		m_timers.consumeTimeouts(now, (timer, periodic, ref data) {
			Task owner = data.owner;
			auto callback = data.callback;
			if (!periodic) releaseTimer(timer);
			if (owner && owner.running) m_core.resumeTask(owner);
			if (callback) runTask(callback);
		});
	}

	override void exitEventLoop()
	{
		m_exit = true;
		PostThreadMessageW(m_tid, WM_QUIT, 0, 0);
	}

	override Win32FileStream openFile(Path path, FileMode mode)
	{
		assert(m_tid == GetCurrentThreadId());
		return new Win32FileStream(m_core, path, mode);
	}

	override DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		assert(m_tid == GetCurrentThreadId());
		return new Win32DirectoryWatcher(m_core, path, recursive);
	}

	override NetworkAddress resolveHost(string host, ushort family = AF_UNSPEC, bool use_dns = true)
	{
		static immutable ushort[] addrfamilies = [AF_INET, AF_INET6];

		NetworkAddress addr;
		foreach( af; addrfamilies ){
			if( family != af && family != AF_UNSPEC ) continue;
			addr.family = af;

			INT addrlen = addr.sockAddrLen;
			auto ret = WSAStringToAddressW(toUTFz!(immutable(wchar)*)(host), af, null, addr.sockAddr, &addrlen);
			if( ret != 0 ) continue;
			assert(addrlen == addr.sockAddrLen);
			return addr;
		}

		enforce(use_dns, "Invalid IP address string: "~host);

		LookupStatus status;
		status.task = Task.getThis();
		status.driver = this;
		status.finished = false;

		WSAOVERLAPPEDX overlapped;
		overlapped.Internal = 0;
		overlapped.InternalHigh = 0;
		overlapped.hEvent = cast(HANDLE)cast(void*)&status;

		version(none){ // Windows 8+
			void* aif;
			ADDRINFOEXW addr_hint;
			ADDRINFOEXW* addr_ret;
			addr_hint.ai_family = family;
			addr_hint.ai_socktype = SOCK_STREAM;
			addr_hint.ai_protocol = IPPROTO_TCP;

			enforce(GetAddrInfoExW(toUTFz!(immutable(wchar)*)(host), null, NS_DNS, null, &addr_hint, &addr_ret, null, &overlapped, &onDnsResult, null) == 0, "Failed to lookup host");
			while( !status.finished ) m_core.yieldForEvent();
			enforce(!status.error, "Failed to lookup host: "~to!string(status.error));

			aif = addr_ret;
			addr.family = cast(ubyte)addr_ret.ai_family;
			switch(addr.family){
				default: assert(false, "Invalid address family returned from host lookup.");
				case AF_INET: addr.sockAddrInet4 = *cast(sockaddr_in*)addr_ret.ai_addr; break;
				case AF_INET6: addr.sockAddrInet6 = *cast(sockaddr_in6*)addr_ret.ai_addr; break;
			}
			FreeAddrInfoExW(addr_ret);
		} else {
			auto he = gethostbyname(toUTFz!(immutable(char)*)(host));
			socketEnforce(he !is null, "Failed to look up host "~host);
			addr.family = he.h_addrtype;
			switch(addr.family){
				default: assert(false, "Invalid address family returned from host lookup.");
				case AF_INET: addr.sockAddrInet4.sin_addr = *cast(in_addr*)he.h_addr_list[0]; break;
				case AF_INET6: addr.sockAddrInet6.sin6_addr = *cast(in6_addr*)he.h_addr_list[0]; break;
			}
		}

		return addr;
	}

	override Win32TCPConnection connectTCP(NetworkAddress addr, NetworkAddress bind_addr)
	{
		assert(m_tid == GetCurrentThreadId());

		auto sock = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, null, 0, WSA_FLAG_OVERLAPPED);
		socketEnforce(sock != INVALID_SOCKET, "Failed to create socket");

		socketEnforce(bind(sock, bind_addr.sockAddr, bind_addr.sockAddrLen) == 0, "Failed to bind socket");

		auto conn = new Win32TCPConnection(this, sock, addr);
		conn.connect(addr);
		return conn;
	}

	override Win32TCPListener listenTCP(ushort port, void delegate(TCPConnection conn) @safe conn_callback, string bind_address, TCPListenOptions options)
	{
		assert(m_tid == GetCurrentThreadId());
		auto addr = resolveHost(bind_address);
		addr.port = port;

		auto sock = WSASocketW(addr.family, SOCK_STREAM, IPPROTO_TCP, null, 0, WSA_FLAG_OVERLAPPED);
		socketEnforce(sock != INVALID_SOCKET, "Failed to create socket");

		socketEnforce(bind(sock, addr.sockAddr, addr.sockAddrLen) == 0,
			"Failed to bind listening socket");

		socketEnforce(listen(sock, 128) == 0,
			"Failed to listen");

		socklen_t balen = addr.sockAddrLen;
		socketEnforce(getsockname(sock, addr.sockAddr, &balen) == 0, "getsockname failed");

		// TODO: support TCPListenOptions.distribute

		return new Win32TCPListener(this, sock, addr, conn_callback, options);
	}

	override Win32UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
	{
		assert(m_tid == GetCurrentThreadId());
		/*auto addr = resolveHost(bind_address);
		addr.port = port;*/

		assert(false);
	}

	override Win32ManualEvent createManualEvent()
	{
		assert(m_tid == GetCurrentThreadId());
		return new Win32ManualEvent(this);
	}

	override FileDescriptorEvent createFileDescriptorEvent(int file_descriptor, FileDescriptorEvent.Trigger events, FileDescriptorEvent.Mode mode)
	{
		assert(false, "Not implemented.");
	}

	override size_t createTimer(void delegate() @safe callback) { return m_timers.create(TimerInfo(callback)); }

	override void acquireTimer(size_t timer_id) { m_timers.getUserData(timer_id).refCount++; }
	override void releaseTimer(size_t timer_id)
	nothrow {
		if (!--m_timers.getUserData(timer_id).refCount)
			m_timers.destroy(timer_id);
	}

	override bool isTimerPending(size_t timer_id) { return m_timers.isPending(timer_id); }

	override void rearmTimer(size_t timer_id, Duration dur, bool periodic)
	{
		if (!m_timers.isPending(timer_id))
			acquireTimer(timer_id);
		m_timers.schedule(timer_id, dur, periodic);
	}

	override void stopTimer(size_t timer_id)
	{
		if (m_timers.isPending(timer_id))
			releaseTimer(timer_id);
		m_timers.unschedule(timer_id);
	}

	override void waitTimer(size_t timer_id)
	{
		while (true) {
			auto data = &m_timers.getUserData(timer_id);
			assert(data.owner == Task.init, "Waiting for the same timer from multiple tasks is not supported.");
			if (!m_timers.isPending(timer_id)) return;
			data.owner = Task.getThis();
			scope (exit) m_timers.getUserData(timer_id).owner = Task.init;
			m_core.yieldForEvent();
		}
	}


	static struct LookupStatus {
		Task task;
		DWORD error;
		bool finished;
		Win32EventDriver driver;
	}

	private static nothrow extern(System)
	void onDnsResult(DWORD dwError, DWORD /*dwBytes*/, WSAOVERLAPPEDX* lpOverlapped)
	{
		auto stat = cast(LookupStatus*)cast(void*)lpOverlapped.hEvent;
		stat.error = dwError;
		stat.finished = true;
		if( stat.task )
			try stat.driver.m_core.resumeTask(stat.task);
			catch (UncaughtException th) logWarn("Resuming task for DNS lookup has thrown: %s", th.msg);
	}

	private static nothrow extern(System)
	LRESULT onMessage(HWND wnd, UINT msg, WPARAM wparam, LPARAM lparam)
	{
		auto driver = cast(Win32EventDriver)cast(void*)GetWindowLongPtrA(wnd, GWLP_USERDATA);
		switch(msg){
			default: break;
			case WM_USER_SIGNAL:
				auto sig = cast(Win32ManualEvent)cast(void*)lparam;
				Win32EventDriver[Task] lst;
				try {
					synchronized(sig.m_mutex) lst = sig.m_listeners.dup;
					foreach( task, tid; lst )
						if( tid is driver && task )
							driver.m_core.resumeTask(task);
				} catch(UncaughtException th){
					logWarn("Failed to resume signal listeners: %s", th.msg);
					return 0;
				}
				return 0;
			case WM_USER_SOCKET:
				SOCKET sock = cast(SOCKET)wparam;
				auto evt = LOWORD(lparam);
				auto err = HIWORD(lparam);
				auto ph = sock in driver.m_socketHandlers;
				if( ph is null ){
					logWarn("Socket %s has no associated handler for event %s/%s", sock, evt, err);
				} else ph.notifySocketEvent(sock, evt, err);
				return 0;
		}
		return DefWindowProcA(wnd, msg, wparam, lparam);
	}
}

interface SocketEventHandler {
	SOCKET socket() nothrow;
	void notifySocketEvent(SOCKET sock, WORD event, WORD error) nothrow;
}

private struct TimerInfo {
	size_t refCount = 1;
	void delegate() callback;
	Task owner;

	this(void delegate() callback) { this.callback = callback; }
}


/******************************************************************************/
/* class Win32ManualEvent                                                     */
/******************************************************************************/

final class Win32ManualEvent : ManualEvent {
@trusted:
	private {
		core.sync.mutex.Mutex m_mutex;
		Win32EventDriver m_driver;
		Win32EventDriver[Task] m_listeners;
		shared int m_emitCount = 0;
		Task m_waiter;
		bool m_timedOut;
	}

	this(Win32EventDriver driver)
	nothrow {
		scope (failure) assert(false); // Mutex.this() now nothrow < 2.070
		m_mutex = new core.sync.mutex.Mutex;
		m_driver = driver;
	}

	override void emit()
	{
		scope (failure) assert(false); // AA.opApply is not nothrow
		/*auto newcnt =*/ atomicOp!"+="(m_emitCount, 1);
		bool[Win32EventDriver] threads;
		synchronized(m_mutex)
		{
			foreach( th; m_listeners )
				threads[th] = true;
		}
		foreach( th, _; threads )
			if( !PostMessageW(th.m_hwnd, WM_USER_SIGNAL, 0, cast(LPARAM)cast(void*)this) )
				logWarn("Failed to post thread message.");
	}

	override void wait() { wait(m_emitCount); }
	override int wait(int reference_emit_count) { return  doWait!true(reference_emit_count); }
	override int wait(Duration timeout, int reference_emit_count) { return doWait!true(timeout, reference_emit_count); }
	override int waitUninterruptible(int reference_emit_count) { return  doWait!false(reference_emit_count); }
	override int waitUninterruptible(Duration timeout, int reference_emit_count) { return doWait!false(timeout, reference_emit_count); }

	void acquire()
	nothrow {
		static if (!synchronizedIsNothrow)
			scope (failure) assert(0, "Internal error: function should be nothrow");

		synchronized(m_mutex)
		{
			m_listeners[Task.getThis()] = cast(Win32EventDriver)getEventDriver();
		}
	}

	void release()
	nothrow {
		static if (!synchronizedIsNothrow)
			scope (failure) assert(0, "Internal error: function should be nothrow");

		auto self = Task.getThis();
		synchronized(m_mutex)
		{
			if( self in m_listeners )
				m_listeners.remove(self);
		}
	}

	bool amOwner()
	nothrow {
		static if (!synchronizedIsNothrow)
			scope (failure) assert(0, "Internal error: function should be nothrow");

		synchronized(m_mutex)
		{
			return (Task.getThis() in m_listeners) !is null;
		}
	}

	override @property int emitCount() const { return atomicLoad(m_emitCount); }

	private int doWait(bool INTERRUPTIBLE)(int reference_emit_count)
	{
		//logDebugV("Signal %s wait enter %s", cast(void*)this, reference_emit_count);
		acquire();
		scope(exit) release();
		auto ec = atomicLoad(m_emitCount);
		while( ec == reference_emit_count ){
			static if (INTERRUPTIBLE) m_driver.m_core.yieldForEvent();
			else m_driver.m_core.yieldForEventDeferThrow();
			ec = atomicLoad(m_emitCount);
		}
		//logDebugV("Signal %s wait leave %s", cast(void*)this, ec);
		return ec;
	}

	private int doWait(bool INTERRUPTIBLE)(Duration timeout, int reference_emit_count = emitCount)
	{
		static if (!INTERRUPTIBLE) scope (failure) assert(false); // timer functions are still not nothrow

		acquire();
		scope(exit) release();
		auto ec = atomicLoad(m_emitCount);
		m_timedOut = false;
		m_waiter = Task.getThis();
		auto timer = m_driver.createTimer(null);
		scope(exit) m_driver.releaseTimer(timer);
		m_driver.m_timers.getUserData(timer).owner = Task.getThis();
		m_driver.rearmTimer(timer, timeout, false);
		while (ec == reference_emit_count && !m_driver.isTimerPending(timer)) {
			static if (INTERRUPTIBLE) m_driver.m_core.yieldForEvent();
			else m_driver.m_core.yieldForEventDeferThrow();
			ec = atomicLoad(m_emitCount);
		}
		return ec;
	}
}


/******************************************************************************/
/* class Win32FileStream                                                      */
/******************************************************************************/

final class Win32FileStream : FileStream {
@trusted:
	private {
		Path m_path;
		HANDLE m_handle;
		FileMode m_mode;
		DriverCore m_driver;
		Task m_task;
		ulong m_size;
		ulong m_ptr = 0;
		DWORD m_bytesTransferred;
	}

	this(DriverCore driver, Path path, FileMode mode)
	{
		m_path = path;
		m_mode = mode;
		m_driver = driver;

		auto access = m_mode == FileMode.readWrite ? (GENERIC_WRITE | GENERIC_READ) :
						(m_mode == FileMode.createTrunc || m_mode == FileMode.append)? GENERIC_WRITE : GENERIC_READ;

		auto shareMode = m_mode == FileMode.read? FILE_SHARE_READ : 0;

		auto creation = m_mode == FileMode.createTrunc? CREATE_ALWAYS : m_mode == FileMode.append? OPEN_ALWAYS : OPEN_EXISTING;

		m_handle = CreateFileW(
					toUTF16z(m_path.toNativeString()),
					access,
					shareMode,
					null,
					creation,
					FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
					null);

		auto errorcode = GetLastError();
		enforce(m_handle != INVALID_HANDLE_VALUE, "Failed to open "~path.toNativeString()~": "~to!string(errorcode));
		if(mode == FileMode.createTrunc && errorcode == ERROR_ALREADY_EXISTS)
		{
			// truncate file
			// TODO: seek to start pos?
			BOOL ret = vibe.internal.win32.SetEndOfFile(m_handle);
			errorcode = GetLastError();
			enforce(ret, "Failed to call SetFileEndPos for path "~path.toNativeString()~", Error: " ~ to!string(errorcode));
		}

		long size;
		auto succeeded = GetFileSizeEx(m_handle, &size);
		enforce(succeeded);
		m_size = size;
	}

	~this()
	{
		close();
	}

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

	override void close()
	{
		if(m_handle == INVALID_HANDLE_VALUE)
			return;
		CloseHandle(m_handle);
		m_handle = INVALID_HANDLE_VALUE;
	}

	override ulong tell() { return m_ptr; }

	override @property Path path() const { return m_path; }

	override @property bool isOpen() const { return m_handle != INVALID_HANDLE_VALUE; }

	override @property ulong size() const { return m_size; }

	override @property bool readable()
	const {
		return m_mode != FileMode.append;
	}

	override @property bool writable()
	const {
		return m_mode == FileMode.append || m_mode == FileMode.createTrunc || m_mode == FileMode.readWrite;
	}

	override void seek(ulong offset)
	{
		m_ptr = offset;
	}


	override @property bool empty() const { assert(this.readable); return m_ptr >= m_size; }
	override @property ulong leastSize() const { assert(this.readable); return m_size - m_ptr; }
	override @property bool dataAvailableForRead(){
		return leastSize() > 0;
	}

	override const(ubyte)[] peek(){
		assert(false);
	}

	override size_t read(scope ubyte[] dst, IOMode)
	{
		assert(this.readable);
		acquire();
		scope(exit) release();

		size_t nbytes = 0;
		while (dst.length > 0) {
			enforce(dst.length <= leastSize);
			OVERLAPPED overlapped;
			overlapped.Internal = 0;
			overlapped.InternalHigh = 0;
			overlapped.Offset = cast(uint)(m_ptr & 0xFFFFFFFF);
			overlapped.OffsetHigh = cast(uint)(m_ptr >> 32);
			overlapped.hEvent = cast(HANDLE)cast(void*)this;
			m_bytesTransferred = 0;

			auto to_read = min(dst.length, DWORD.max);

			// request to write the data
			ReadFileEx(m_handle, cast(void*)dst, to_read, &overlapped, &onIOCompleted);

			// yield until the data is read
			while( !m_bytesTransferred ) m_driver.yieldForEvent();

			assert(m_bytesTransferred <= to_read, "More bytes read than requested!?");
			dst = dst[m_bytesTransferred .. $];
			m_ptr += m_bytesTransferred;
			nbytes += m_bytesTransferred;
		}

		return nbytes;
	}

	override size_t write(in ubyte[] bytes_, IOMode)
	{
		assert(this.writable, "File is not writable");
		acquire();
		scope(exit) release();

		const(ubyte)[] bytes = bytes_;

		size_t nbytes = 0;
		while (bytes.length > 0) {
			OVERLAPPED overlapped;
			overlapped.Internal = 0;
			overlapped.InternalHigh = 0;
			overlapped.Offset = cast(uint)(m_ptr & 0xFFFFFFFF);
			overlapped.OffsetHigh = cast(uint)(m_ptr >> 32);
			overlapped.hEvent = cast(HANDLE)cast(void*)this;
			m_bytesTransferred = 0;

			auto to_write = min(bytes.length, DWORD.max);

			// request to write the data
			WriteFileEx(m_handle, cast(void*)bytes, to_write, &overlapped, &onIOCompleted);

			// yield until the data is written
			while( !m_bytesTransferred ) m_driver.yieldForEvent();

			assert(m_bytesTransferred <= to_write, "More bytes written than requested!?");
			bytes = bytes[m_bytesTransferred .. $];
			m_ptr += m_bytesTransferred;
			nbytes += m_bytesTransferred;
		}
		if(m_ptr > m_size) m_size = m_ptr;

		return nbytes;
	}

	override void flush(){}

	override void finalize(){}

	private static extern(System) nothrow
	void onIOCompleted(DWORD dwError, DWORD cbTransferred, OVERLAPPED* overlapped)
	{
		try {
			auto fileStream = cast(Win32FileStream)(overlapped.hEvent);
			fileStream.m_bytesTransferred = cbTransferred;
			if( fileStream.m_task ){
				Exception ex;
				if( dwError != 0 ) ex = new Exception("File I/O error: "~to!string(dwError));
				if( fileStream.m_task ) fileStream.m_driver.resumeTask(fileStream.m_task, ex);
			}
		} catch( UncaughtException e ){
			logWarn("Exception while handling file I/O: %s", e.msg);
		}
	}
}


/******************************************************************************/
/* class Win32Directory Watcher                                               */
/******************************************************************************/

final class Win32DirectoryWatcher : DirectoryWatcher {
@trusted:
	private {
		Path m_path;
		bool m_recursive;
		HANDLE m_handle;
		DWORD m_bytesTransferred;
		DriverCore m_core;
		ubyte[16384] m_buffer;
		UINT m_notifications = FILE_NOTIFY_CHANGE_FILE_NAME|FILE_NOTIFY_CHANGE_DIR_NAME|
			FILE_NOTIFY_CHANGE_SIZE|FILE_NOTIFY_CHANGE_LAST_WRITE;
		Task m_task;
	}

	this(DriverCore core, Path path, bool recursive)
	{
		m_core = core;
		m_path = path;
		m_recursive = recursive;
		m_task = Task.getThis();

		auto pstr = m_path.toString();
		m_handle = CreateFileW(toUTFz!(const(wchar)*)(pstr),
							   FILE_LIST_DIRECTORY,
							   FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
							   null,
							   OPEN_EXISTING,
							   FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
							   null);
	}

	~this()
	{
		CloseHandle(m_handle);
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
		OVERLAPPED overlapped;
		overlapped.Internal = 0;
		overlapped.InternalHigh = 0;
		overlapped.Offset = 0;
		overlapped.OffsetHigh = 0;
		overlapped.hEvent = cast(HANDLE)cast(void*)this;

		m_bytesTransferred = 0;
		DWORD bytesReturned;
		if( !ReadDirectoryChangesW(m_handle, m_buffer.ptr, m_buffer.length, m_recursive,
								   m_notifications, &bytesReturned, &overlapped, &onIOCompleted) )
		{
			logError("Failed to read directory changes in '%s'", m_path);
			return false;
		}

		// FIXME: obey timeout!
		assert(timeout.isNegative());
		while( !m_bytesTransferred ) m_core.yieldForEvent();

		ubyte[] result = m_buffer[0 .. m_bytesTransferred];
		do {
			assert(result.length >= FILE_NOTIFY_INFORMATION.sizeof);
			auto fni = cast(FILE_NOTIFY_INFORMATION*)result.ptr;
			DirectoryChangeType kind;
			switch( fni.Action ){
				default: kind = DirectoryChangeType.modified; break;
				case 0x1: kind = DirectoryChangeType.added; break;
				case 0x2: kind = DirectoryChangeType.removed; break;
				case 0x3: kind = DirectoryChangeType.modified; break;
				case 0x4: kind = DirectoryChangeType.removed; break;
				case 0x5: kind = DirectoryChangeType.added; break;
			}
			string filename = to!string(fni.FileName[0 .. fni.FileNameLength/2]);
			dst ~= DirectoryChange(kind, Path(filename));
			//logTrace("File changed: %s", fni.FileName.ptr[0 .. fni.FileNameLength/2]);
			if( fni.NextEntryOffset == 0 ) break;
			result = result[fni.NextEntryOffset .. $];
		} while(result.length > 0);

		return true;
	}

	static nothrow extern(System)
	{
		void onIOCompleted(DWORD dwError, DWORD cbTransferred, OVERLAPPED* overlapped)
		{
			try {
				auto watcher = cast(Win32DirectoryWatcher)overlapped.hEvent;
				watcher.m_bytesTransferred = cbTransferred;
				if( watcher.m_task ){
					Exception ex;
					if( dwError != 0 ) ex = new Exception("Diretory watcher error: "~to!string(dwError));
					if( watcher.m_task ) watcher.m_core.resumeTask(watcher.m_task, ex);
				}
			} catch( UncaughtException th ){
				logWarn("Exception in directory watcher callback: %s", th.msg);
			}
		}
	}
}


/******************************************************************************/
/* class Win32UDPConnection                                                   */
/******************************************************************************/

final class Win32UDPConnection : UDPConnection, SocketEventHandler {
@trusted:
	private {
		Task m_task;
		Win32EventDriver m_driver;
		SOCKET m_socket;
		NetworkAddress m_bindAddress;
		bool m_canBroadcast;
	}

	this(Win32EventDriver driver, SOCKET sock, NetworkAddress bind_addr)
	{
		m_driver = driver;
		m_socket = sock;
		m_bindAddress = bind_addr;

		WSAAsyncSelect(sock, m_driver.m_hwnd, WM_USER_SOCKET, FD_READ|FD_WRITE|FD_CLOSE);

		//bind...
	}

	@property SOCKET socket() { return m_socket; }

	override @property string bindAddress() const {
		// NOTE: using WSAAddressToStringW instead of inet_ntop because that is only available from Vista up
		wchar[64] buf;
		DWORD buf_len = 64;
		WSAAddressToStringW(m_bindAddress.sockAddr, m_bindAddress.sockAddrLen, null, buf.ptr, &buf_len);
		auto ret = to!string(buf[0 .. buf_len]);
		ret = ret[0 .. ret.lastIndexOf(':')]; // strip the port number
		return ret;
	}

	override @property NetworkAddress localAddress() const { return m_bindAddress; }

	override @property bool canBroadcast() const { return m_canBroadcast; }
	override @property void canBroadcast(bool val)
	{
		int tmp_broad = val;
		socketEnforce(setsockopt(m_socket, SOL_SOCKET, SO_BROADCAST, &tmp_broad, tmp_broad.sizeof) == 0,
				"Failed to change the socket broadcast flag");
		m_canBroadcast = val;
	}

	override void close()
	{
		if (m_socket == INVALID_SOCKET) return;
		closesocket(m_socket);
		m_socket = INVALID_SOCKET;
	}

	bool amOwner() {
		return m_task != Task() && m_task == Task.getThis();
	}

	void acquire()
	{
		assert(m_task == Task(), "Trying to acquire a TCP connection that is currently owned.");
		m_task = Task.getThis();
	}

	void release()
	{
		assert(m_task != Task(), "Trying to release a TCP connection that is not owned.");
		assert(m_task == Task.getThis(), "Trying to release a foreign TCP connection.");
		m_task = Task();
	}

	override void connect(string host, ushort port)
	{
		NetworkAddress addr = m_driver.resolveHost(host, m_bindAddress.family);
		addr.port = port;
		connect(addr);
	}
	override void connect(NetworkAddress addr)
	{
		socketEnforce(.connect(m_socket, addr.sockAddr, addr.sockAddrLen) == 0, "Failed to connect UDP socket");
	}

	override void send(in ubyte[] data, in NetworkAddress* peer_address = null)
	{
		assert(data.length <= int.max);
		sizediff_t ret;
		if( peer_address ){
			ret = .sendto(m_socket, data.ptr, cast(int)data.length, 0, peer_address.sockAddr, peer_address.sockAddrLen);
		} else {
			ret = .send(m_socket, data.ptr, cast(int)data.length, 0);
		}
		logTrace("send ret: %s, %s", ret, WSAGetLastError());
		socketEnforce(ret >= 0, "Error sending UDP packet");
		enforce(ret == data.length, "Unable to send full packet.");
	}

	override ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		return recv(Duration.max, buf, peer_address);
	}

	override ubyte[] recv(Duration timeout, ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		size_t tm;
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
		from.family = m_bindAddress.family;
		while(true){
			socklen_t addr_len = from.sockAddrLen;
			auto ret = .recvfrom(m_socket, buf.ptr, cast(int)buf.length, 0, from.sockAddr, &addr_len);
			if( ret > 0 ){
				if( peer_address ) *peer_address = from;
				return buf[0 .. ret];
			}
			if( ret < 0 ){
				auto err = WSAGetLastError();
				logDebug("UDP recv err: %s", err);
				socketEnforce(err == WSAEWOULDBLOCK, "Error receiving UDP packet");

				if (timeout != Duration.max) {
					enforce(timeout > 0.seconds && m_driver.isTimerPending(tm), "UDP receive timeout.");
				}
			}
			m_driver.m_core.yieldForEvent();
		}
	}

	void notifySocketEvent(SOCKET sock, WORD event, WORD error)
	{
		assert(false);
	}

	void addMembership(ref NetworkAddress multiaddr)
	{
		assert(false, "TODO!");
	}

	@property void multicastLoopback(bool loop)
	{
		assert(false, "TODO!");
	}

	private static nothrow extern(C) void onUDPRead(SOCKET sockfd, short evts, void* arg)
	{
		/*auto ctx = cast(TCPContext*)arg;
		logTrace("udp socket %d read event!", ctx.socketfd);

		try {
			auto f = ctx.task;
			if( f && f.state != Fiber.State.TERM )
				ctx.core.resumeTask(f);
		} catch( UncaughtException e ){
			logError("Exception onUDPRead: %s", e.msg);
			debug assert(false);
		}*/
	}
}


/******************************************************************************/
/* class Win32TCPConnection                                                   */
/******************************************************************************/

enum ConnectionStatus { Initialized, Connected, Disconnected }

final class Win32TCPConnection : TCPConnection, SocketEventHandler {
@trusted:
	private {
		Win32EventDriver m_driver;
		Task m_readOwner;
		Task m_writeOwner;
		bool m_tcpNoDelay;
		Duration m_readTimeout;
		bool m_keepAlive;
		SOCKET m_socket;
		NetworkAddress m_localAddress;
		NetworkAddress m_peerAddress;
		string m_peerAddressString;
		DWORD m_bytesTransferred;
		ConnectionStatus m_status;
		FixedRingBuffer!(ubyte, 64*1024) m_readBuffer;
		void delegate(TCPConnection) m_connectionCallback;
		Exception m_exception;

		HANDLE m_transferredFile;
		OVERLAPPED m_fileOverlapped;
	}

	this(Win32EventDriver driver, SOCKET sock, NetworkAddress peer_address, ConnectionStatus status = ConnectionStatus.Initialized)
	{
		m_driver = driver;
		m_socket = sock;
		m_driver.m_socketHandlers[sock] = this;
		m_status = status;

		m_localAddress.family = peer_address.family;
		if (peer_address.family == AF_INET) m_localAddress.sockAddrInet4.sin_addr.s_addr = 0;
		else m_localAddress.sockAddrInet6.sin6_addr.s6_addr[] = 0;
		socklen_t balen = m_localAddress.sockAddrLen;
		socketEnforce(getsockname(sock, m_localAddress.sockAddr, &balen) == 0, "getsockname failed");

		m_peerAddress = peer_address;

		// NOTE: using WSAAddressToStringW instead of inet_ntop because that is only available from Vista up
		wchar[64] buf;
		DWORD buflen = buf.length;
		socketEnforce(WSAAddressToStringW(m_peerAddress.sockAddr, m_peerAddress.sockAddrLen, null, buf.ptr, &buflen) == 0, "Failed to get string representation of peer address");
		m_peerAddressString = to!string(buf[0 .. buflen]);
		m_peerAddressString = m_peerAddressString[0 .. m_peerAddressString.lastIndexOf(':')]; // strip the port number

		// setup overlapped structure for copy-less file sending
		m_fileOverlapped.Internal = 0;
		m_fileOverlapped.InternalHigh = 0;
		m_fileOverlapped.Offset = 0;
		m_fileOverlapped.OffsetHigh = 0;
		m_fileOverlapped.hEvent = m_driver.m_fileCompletionEvent;

		WSAAsyncSelect(sock, m_driver.m_hwnd, WM_USER_SOCKET, FD_READ|FD_WRITE|FD_CONNECT|FD_CLOSE);
	}

	~this()
	{
		/*if( m_socket != -1 ){
			closesocket(m_socket);
		}*/
	}

	@property SOCKET socket() { return m_socket; }

	private void connect(NetworkAddress addr)
	{
		enforce(m_status != ConnectionStatus.Connected, "Connection is already established.");
		acquire();
		scope(exit) release();

		auto ret = .connect(m_socket, addr.sockAddr, addr.sockAddrLen);
		//enforce(WSAConnect(m_socket, addr.sockAddr, addr.sockAddrLen, null, null, null, null), "Failed to connect to host");

		if (ret != 0) {
			auto err = WSAGetLastError();
			logDebugV("connect err: %s", err);
			import std.string;
			socketEnforce(err == WSAEWOULDBLOCK, "Connect call failed");
			while (m_status != ConnectionStatus.Connected) {
				m_driver.m_core.yieldForEvent();
				if (m_exception) throw m_exception;
			}
		}
		assert(m_status == ConnectionStatus.Connected);
	}

	void release()
	{
		assert(m_readOwner == Task.getThis() && m_readOwner == m_writeOwner, "Releasing TCP connection that is not owned by the calling task.");
		m_readOwner = m_writeOwner = Task();
	}

	void acquire()
	{
		assert(m_readOwner == Task() && m_writeOwner == Task(), "Acquiring TCP connection that is currently owned.");
		m_readOwner = m_writeOwner = Task.getThis();
	}

	bool amOwner() { return Task.getThis() == m_readOwner && m_readOwner == m_writeOwner; }

	override @property void tcpNoDelay(bool enabled)
	{
		m_tcpNoDelay = enabled;
		BOOL eni = enabled;
		setsockopt(m_socket, IPPROTO_TCP, TCP_NODELAY, &eni, eni.sizeof);
	}
	override @property bool tcpNoDelay() const { return m_tcpNoDelay; }

	override @property void readTimeout(Duration v)
	{
		m_readTimeout = v;
		auto msecs = v.total!"msecs"();
		assert(msecs < DWORD.max);
		DWORD vdw = cast(DWORD)msecs;
		setsockopt(m_socket, SOL_SOCKET, SO_RCVTIMEO, &vdw, vdw.sizeof);
	}
	override @property Duration readTimeout() const { return m_readTimeout; }

	override @property void keepAlive(bool enabled)
	{
		m_keepAlive = enabled;
		BOOL eni = enabled;
		setsockopt(m_socket, SOL_SOCKET, SO_KEEPALIVE, &eni, eni.sizeof);
	}
	override @property bool keepAlive() const { return m_keepAlive; }

	override @property bool connected() const { return m_status == ConnectionStatus.Connected; }

	override @property string peerAddress() const { return m_peerAddressString; }

	override @property NetworkAddress localAddress() const { return m_localAddress; }
	override @property NetworkAddress remoteAddress() const { return m_peerAddress; }

	override @property bool empty() { return leastSize == 0; }

	override @property ulong leastSize()
	{
		acquireReader();
		scope(exit) releaseReader();

		while( m_readBuffer.empty ){
			if( !connected ) return 0;
			m_driver.m_core.yieldForEvent();
		}
		return m_readBuffer.length;
	}

	override @property bool dataAvailableForRead()
	{
		acquireReader();
		scope(exit) releaseReader();
		return !m_readBuffer.empty;
	}

	override void close()
	{
		acquire();
		scope(exit) release();
		WSASendDisconnect(m_socket, null);
		closesocket(m_socket);
		m_socket = -1;
		m_status = ConnectionStatus.Disconnected;
	}

	override bool waitForData(Duration timeout)
	{
		if (timeout == 0.seconds)
			logDebug("Warning: use Duration.max as an argument to waitForData() to wait infinitely, not 0.seconds.");

		acquireReader();
		scope(exit) releaseReader();
		if (timeout != Duration.max && timeout != 0.seconds) {
			auto tm = m_driver.createTimer(null);
			scope(exit) m_driver.releaseTimer(tm);
			m_driver.m_timers.getUserData(tm).owner = Task.getThis();
			m_driver.rearmTimer(tm, timeout, false);
			while (m_readBuffer.empty) {
				if (!connected) return false;
				m_driver.m_core.yieldForEvent();
				if (!m_driver.isTimerPending(tm)) return false;
			}
		} else {
			while (m_readBuffer.empty) {
				if (!connected) return false;
				m_driver.m_core.yieldForEvent();
			}
		}
		return true;
	}

	override const(ubyte)[] peek()
	{
		acquireReader();
		scope(exit) releaseReader();
		return m_readBuffer.peek();
	}

	override size_t read(scope ubyte[] dst, IOMode)
	{
		acquireReader();
		scope(exit) releaseReader();

		size_t nbytes = 0;
		while (dst.length > 0) {
			while( m_readBuffer.empty ){
				checkConnected();
				m_driver.m_core.yieldForEvent();
			}
			size_t amt = min(dst.length, m_readBuffer.length);

			m_readBuffer.read(dst[0 .. amt]);
			dst = dst[amt .. $];
			nbytes += amt;
		}

		return nbytes;
	}

	override size_t write(in ubyte[] bytes_, IOMode)
	{
		acquireWriter();
		scope(exit) releaseWriter();

		checkConnected();
		const(ubyte)[] bytes = bytes_;
		logTrace("TCP write with %s bytes called", bytes.length);

		WSAOVERLAPPEDX overlapped;
		overlapped.Internal = 0;
		overlapped.InternalHigh = 0;
		overlapped.Offset = 0;
		overlapped.OffsetHigh = 0;
		overlapped.hEvent = cast(HANDLE)cast(void*)this;

		size_t nbytes = 0;
		while (bytes.length > 0) {
			WSABUF buf;
			buf.len = bytes.length;
			buf.buf = cast(ubyte*)bytes.ptr;

			m_bytesTransferred = 0;
			logTrace("Sending %s bytes TCP", buf.len);
			auto ret = WSASend(m_socket, &buf, 1, null, 0, &overlapped, &onIOWriteCompleted);
			if( ret == SOCKET_ERROR ){
				auto err = WSAGetLastError();
				socketEnforce(err == WSA_IO_PENDING, "Failed to send data");
			}
			while( !m_bytesTransferred ) m_driver.m_core.yieldForEvent();

			assert(m_bytesTransferred <= bytes.length, "More data sent than requested!?");
			bytes = bytes[m_bytesTransferred .. $];
			nbytes += m_bytesTransferred;
		}
		return nbytes;

	}

	override void flush()
	{
		acquireWriter();
		scope(exit) releaseWriter();

		checkConnected();
	}

	override void finalize()
	{
		flush();
	}

	void writeFile(Path filename)
	{
		auto fstream = m_driver.openFile(filename, FileMode.read);
		enforce(fstream.size <= 1<<31);
		acquireWriter();
		m_bytesTransferred = 0;
		m_driver.m_fileWriters[this] = true;
		scope(exit) releaseWriter();
		logDebug("Using sendfile! %s %s %s", fstream.m_handle, fstream.tell(), fstream.size);

		if (TransmitFile(m_socket, fstream.m_handle, 0, 0, &m_fileOverlapped, null, 0))
			m_bytesTransferred = 1;

		socketEnforce(WSAGetLastError() == WSA_IO_PENDING, "Failed to send file over TCP.");

		while (m_bytesTransferred < fstream.size) m_driver.m_core.yieldForEvent();
	}

	InputStream acquireReader() { assert(m_readOwner == Task()); m_readOwner = Task.getThis(); return this; }
	void releaseReader() { assert(m_readOwner == Task.getThis()); m_readOwner = Task(); }
	bool amReadOwner() const { return m_readOwner == Task.getThis(); }

	OutputStream acquireWriter() { assert(m_writeOwner == Task()); m_writeOwner = Task.getThis(); return this; }
	void releaseWriter() { assert(m_writeOwner == Task.getThis()); m_writeOwner = Task(); }
	bool amWriteOwner() const { return m_writeOwner == Task.getThis(); }

	private void checkConnected()
	{
		// TODO!
	}

	private bool testFileWritten()
	{
		if( !GetOverlappedResult(m_transferredFile, &m_fileOverlapped, &m_bytesTransferred, false) ){
			if( GetLastError() != ERROR_IO_PENDING ){
				auto ex = new Exception("File transfer over TCP failed.");
				if (m_writeOwner != Task.init) {
					m_driver.m_core.resumeTask(m_writeOwner, ex);
					return true;
				} else throw ex;
			}
			return false;
		} else {
			if (m_writeOwner != Task.init) m_driver.m_core.resumeTask(m_writeOwner);
			return true;
		}
	}

	void notifySocketEvent(SOCKET sock, WORD event, WORD error)
	nothrow {
		try {
			logDebugV("Socket event for %s: %s, error: %s", sock, event, error);
			if (m_socket == -1) {
				logDebug("Event for already closed socket - ignoring");
				return;
			}
			assert(sock == m_socket);
			Exception ex;
			switch(event){
				default: break;
				case FD_CONNECT: // doesn't seem to occur, but we handle it just in case
					if (error) {
						ex = new SystemSocketException("Failed to connect to host", error);
						m_status = ConnectionStatus.Disconnected;
					} else m_status = ConnectionStatus.Connected;
					if (m_writeOwner) m_driver.m_core.resumeTask(m_writeOwner, ex);
					break;
				case FD_READ:
					logTrace("TCP read event");
					while (m_readBuffer.freeSpace > 0) {
						auto dst = m_readBuffer.peekDst();
						assert(dst.length <= int.max);
						logTrace("Try to read up to %s bytes", dst.length);
						auto ret = .recv(m_socket, dst.ptr, cast(int)dst.length, 0);
						if (ret >= 0) {
							logTrace("received %s bytes", ret);
							if( ret == 0 ) break;
							m_readBuffer.putN(ret);
						} else {
							auto err = WSAGetLastError();
							if( err != WSAEWOULDBLOCK ){
								logTrace("receive error %s", err);
								ex = new SystemSocketException("Error reading data from socket", error);
							}
							break;
						}
					}

					//m_driver.m_core.resumeTask(m_readOwner, ex);
					/*WSABUF buf;
					buf.len = dst.length;
					buf.buf = dst.ptr;
					DWORD flags = 0;

					WSAOVERLAPPEDX overlapped;
					overlapped.Internal = 0;
					overlapped.InternalHigh = 0;
					overlapped.Offset = 0;
					overlapped.OffsetHigh = 0;
					overlapped.hEvent = cast(HANDLE)cast(void*)this;

					m_bytesTransferred = 0;
					auto ret = WSARecv(m_socket, &buf, 1, null, &flags, &overlapped, &onIOCompleted);
					if( ret == SOCKET_ERROR ){
						auto err = WSAGetLastError();
						socketEnforce(err == WSA_IO_PENDING, "Failed to receive data");
					}
					while( !m_bytesTransferred ) m_driver.m_core.yieldForEvent();

					assert(m_bytesTransferred <= dst.length, "More data received than requested!?");
					m_readBuffer.pushN(m_bytesTransferred);*/
					if (m_readOwner) m_driver.m_core.resumeTask(m_readOwner, ex);
					break;
				case FD_WRITE:
					if (m_status == ConnectionStatus.Initialized) {
						if( error ){
							ex = new SystemSocketException("Failed to connect to host", error);
						} else m_status = ConnectionStatus.Connected;
					}
					if (m_writeOwner) m_driver.m_core.resumeTask(m_writeOwner, ex);
					break;
				case FD_CLOSE:
					if (error) {
						if (m_status == ConnectionStatus.Initialized) {
							ex = new SystemSocketException("Failed to connect to host", error);
						} else {
							ex = new SystemSocketException("The connection was closed with an error", error);
						}
					} else {
						m_status = ConnectionStatus.Disconnected;
						closesocket(m_socket);
						m_socket = -1;
					}
					if (m_writeOwner) m_driver.m_core.resumeTask(m_writeOwner, ex);
					break;
			}

			if (ex) m_exception = ex;
		} catch( UncaughtException th ){
			logWarn("Exception while handling socket event: %s", th.msg);
		}
	}

	private void runConnectionCallback(TCPListenOptions options)
	{
		try {
			m_connectionCallback(this);
			logDebug("task out (fd %d).", m_socket);
		} catch( Exception e ){
			logWarn("Handling of connection failed: %s", e.msg);
			logDiagnostic("%s", e.toString());
		} finally {
			if (!(options & TCPListenOptions.disableAutoClose) && this.connected) close();
		}
	}

	private static extern(System) nothrow
	void onIOWriteCompleted(DWORD dwError, DWORD cbTransferred, WSAOVERLAPPEDX* lpOverlapped, DWORD dwFlags)
	{
		logTrace("IO completed for TCP send: %s (error=%s)", cbTransferred, dwError);
		try {
			auto conn = cast(Win32TCPConnection)(lpOverlapped.hEvent);
			conn.m_bytesTransferred = cbTransferred;
			if (conn.m_writeOwner != Task.init) {
				Exception ex;
				if( dwError != 0 ) ex = new Exception("Socket I/O error: "~to!string(dwError));
				conn.m_driver.m_core.resumeTask(conn.m_writeOwner, ex);
			}
		} catch( UncaughtException th ){
			logWarn("Exception while handling TCP I/O: %s", th.msg);
		}
	}
}

/******************************************************************************/
/* class Win32TCPListener                                                     */
/******************************************************************************/

final class Win32TCPListener : TCPListener, SocketEventHandler {
@trusted:
	private {
		Win32EventDriver m_driver;
		SOCKET m_socket;
		NetworkAddress m_bindAddress;
		void delegate(TCPConnection conn) m_connectionCallback;
		TCPListenOptions m_options;
	}

	this(Win32EventDriver driver, SOCKET sock, NetworkAddress bind_addr, void delegate(TCPConnection conn) @safe conn_callback, TCPListenOptions options)
	{
		m_driver = driver;
		m_socket = sock;
		m_bindAddress = bind_addr;
		m_connectionCallback = conn_callback;
		m_driver.m_socketHandlers[sock] = this;
		m_options = options;

		WSAAsyncSelect(sock, m_driver.m_hwnd, WM_USER_SOCKET, FD_ACCEPT);
	}

	override @property NetworkAddress bindAddress()
	{
		return m_bindAddress;
	}

	override void stopListening()
	{
		if( m_socket == -1 ) return;
		closesocket(m_socket);
		m_socket = -1;
	}

	SOCKET socket() nothrow { return m_socket; }

	void notifySocketEvent(SOCKET sock, WORD event, WORD error)
	nothrow {
		assert(sock == m_socket);
		switch(event){
			default: assert(false);
			case FD_ACCEPT:
				try {
					NetworkAddress addr;
					addr.family = AF_INET6;
					int addrlen = addr.sockAddrLen;
					auto clientsock = WSAAccept(sock, addr.sockAddr, &addrlen, null, 0);
					assert(addrlen == addr.sockAddrLen);
					// TODO avoid GC allocations for delegate and Win32TCPConnection
					auto conn = new Win32TCPConnection(m_driver, clientsock, addr, ConnectionStatus.Connected);
					conn.m_connectionCallback = m_connectionCallback;
					runTask(&conn.runConnectionCallback, m_options);
				} catch( Exception e ){
					logWarn("Exception white accepting TCP connection: %s", e.msg);
					try logDiagnostic("Exception white accepting TCP connection: %s", e.toString());
					catch( Exception ){}
				}
				break;
		}
	}
}


private {
	struct TimerMapTraits {
		enum clearValue = UINT_PTR.max;
		static bool equals(UINT_PTR a, UINT_PTR b) { return a == b; }
	}
	__gshared s_setupWindowClass = false;
}

void setupWindowClass() nothrow
@trusted {
	if( s_setupWindowClass ) return;
	WNDCLASSA wc;
	wc.lpfnWndProc = &Win32EventDriver.onMessage;
	wc.lpszClassName = "VibeWin32MessageWindow";
	RegisterClassA(&wc);
	s_setupWindowClass = true;
}

version (VibeDebugCatchAll) private alias UncaughtException = Throwable;
else private alias UncaughtException = Exception;

} // version(VibeWin32Driver)
