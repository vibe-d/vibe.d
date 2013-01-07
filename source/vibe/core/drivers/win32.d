/**
	Win32 driver implementation using I/O completion ports

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig, Leonid Kramer
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.win32;

version(VibeWin32Driver)
{

import vibe.core.core;
import vibe.core.driver;
import vibe.core.log;
import vibe.inet.url;
import vibe.utils.array;

import core.atomic;
import core.sync.mutex;
import core.sys.windows.windows;
import core.time;
import core.thread;
import std.algorithm;
import std.conv;
import std.c.windows.windows;
import std.c.windows.winsock;
import std.exception;
import std.utf;

enum WM_USER_SIGNAL = WM_USER+101;
enum WM_USER_SOCKET = WM_USER+102;

pragma(lib, "wsock32.lib");

/******************************************************************************/
/* class Win32EventDriver                                                     */
/******************************************************************************/

class Win32EventDriver : EventDriver {
	private {
		HWND m_hwnd;
		DWORD m_tid;
		DriverCore m_core;
		bool m_exit = false;
		int m_timerIdCounter = 0;
		SocketEventHandler[SOCKET] m_socketHandlers;
		HANDLE[] m_registeredEvents;
		HANDLE m_fileCompletionEvent;
		bool[Win32TcpConnection] m_fileWriters;
	}

	this(DriverCore core)
	{
		setupWindowClass();

		m_core = core;
		m_tid = GetCurrentThreadId();
		m_hwnd = CreateWindowA("VibeWin32MessageWindow", "VibeWin32MessageWindow", 0, 0,0,0,0, HWND_MESSAGE,null,null,null);

		SetWindowLongPtrA(m_hwnd, GWLP_USERDATA, cast(ULONG_PTR)cast(void*)this);
		assert( cast(Win32EventDriver)cast(void*)GetWindowLongPtrA(m_hwnd, GWLP_USERDATA) == this );

		WSADATA wd;
		enforce(WSAStartup(0x0202, &wd) == 0, "Failed to initialize WinSock");

		m_fileCompletionEvent = CreateEventW(null, false, false, null);
		m_registeredEvents ~= m_fileCompletionEvent;
	}

	~this()
	{
//		DestroyWindow(m_hwnd);
	}

	int runEventLoop()
	{
		m_exit = false;
		while( !m_exit )
			runEventLoopOnce();
		return 0;
	}

	int runEventLoopOnce()
	{
		auto ret = doProcessEvents(INFINITE);
		m_core.notifyIdle();
		return ret;
	}

	int processEvents()
	{
		return doProcessEvents(0);
	}

	int doProcessEvents(uint timeout)
	{
		waitForEvents(timeout);
		assert(m_tid == GetCurrentThreadId());
		MSG msg;
		while( PeekMessageW(&msg, null, 0, 0, PM_REMOVE) ){
			if( msg.message == WM_QUIT ) break;
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		return 0;
	}

	private void waitForEvents(uint timeout)
	{
		auto ret = MsgWaitForMultipleObjectsEx(cast(DWORD)m_registeredEvents.length, m_registeredEvents.ptr, timeout, QS_ALLEVENTS, MWMO_ALERTABLE|MWMO_INPUTAVAILABLE);
		if( ret == WAIT_OBJECT_0 ){
			Win32TcpConnection[] to_remove;
			foreach( fw; m_fileWriters.byKey )
				if( fw.testFileWritten() )
					to_remove ~= fw;
			foreach( fw; to_remove )
			m_fileWriters.remove(fw);
		}
	}

	void exitEventLoop()
	{
		m_exit = true;
		PostThreadMessageW(m_tid, WM_QUIT, 0, 0);
	}

	Win32FileStream openFile(Path path, FileMode mode)
	{
		assert(m_tid == GetCurrentThreadId());
		return new Win32FileStream(m_core, path, mode);
	}

	DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		assert(m_tid == GetCurrentThreadId());
		return new Win32DirectoryWatcher(m_core, path, recursive);
	}

	NetworkAddress resolveHost(string host, ushort family = AF_UNSPEC, bool no_dns = false)
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


		LookupStatus status;
		status.task = Task.getThis();
		status.driver = this;
		status.finished = false;

		WSAOVERLAPPEDX overlapped;
		overlapped.Internal = 0;
		overlapped.InternalHigh = 0;
		overlapped.hEvent = cast(HANDLE)cast(void*)&status;

		void* aif;

		version(none){ // Windows 8+
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
			FreeAddrInfoW(addr_ret);
		} else {
			auto he = gethostbyname(toUTFz!(immutable(char)*)(host));
			enforce(he !is null, "Failed to look up host "~host~".");
			addr.family = he.h_addrtype;
			switch(addr.family){
				default: assert(false, "Invalid address family returned from host lookup.");
				case AF_INET: addr.sockAddrInet4.sin_addr = *cast(in_addr*)he.h_addr_list[0]; break;
				case AF_INET6: addr.sockAddrInet6.sin6_addr = *cast(in6_addr*)he.h_addr_list[0]; break;
			}
		}

		return addr;
	}

	Win32TcpConnection connectTcp(string host, ushort port)
	{
		assert(m_tid == GetCurrentThreadId());
		auto addr = resolveHost(host);
		addr.port = port;

		auto sock = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, null, 0, WSA_FLAG_OVERLAPPED);
		enforce(sock != INVALID_SOCKET, "Failed to create socket.");

		auto conn = new Win32TcpConnection(this, sock);
		conn.connect(addr);
		return conn;	
	}

	Win32TcpListener listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string bind_address)
	{
		assert(m_tid == GetCurrentThreadId());
		auto addr = resolveHost(bind_address);
		addr.port = port;

		auto sock = WSASocketW(AF_INET, SOCK_STREAM, IPPROTO_TCP, null, 0, WSA_FLAG_OVERLAPPED);
		enforce(sock != INVALID_SOCKET, "Failed to create socket.");

		enforce(bind(sock, addr.sockAddr, addr.sockAddrLen) == 0,
			"Failed to bind listening socket.");

		enforce(listen(sock, 128) == 0,
			"Failed to listen.");

		return new Win32TcpListener(this, sock, conn_callback);
	}

	UdpConnection listenUdp(ushort port, string bind_address = "0.0.0.0")
	{
		assert(m_tid == GetCurrentThreadId());
		auto addr = resolveHost(bind_address);
		addr.port = port;

		assert(false);
	}

	Win32Signal createSignal()
	{
		assert(m_tid == GetCurrentThreadId());
		return new Win32Signal(this);
	}

	Win32Timer createTimer(void delegate() callback)
	{
		assert(m_tid == GetCurrentThreadId());
		return new Win32Timer(this, callback);
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
			catch( Throwable th ) logWarn("Resuming task for DNS lookup has thrown: %s", th.msg);
	}

	private static nothrow extern(System)
	LRESULT onMessage(HWND wnd, UINT msg, WPARAM wparam, LPARAM lparam)
	{
		auto driver = cast(Win32EventDriver)cast(void*)GetWindowLongPtrA(wnd, GWLP_USERDATA);
		switch(msg){
			default: break;
			case WM_USER_SIGNAL:
				auto sig = cast(Win32Signal)cast(void*)lparam;
				DWORD[Task] lst;
				try {
					synchronized(sig.m_mutex) lst = sig.m_listeners.dup;
					foreach( task, tid; lst )
						if( tid == driver.m_tid && task )
							driver.m_core.resumeTask(task);
				} catch(Throwable th){
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


/******************************************************************************/
/* class Win32Signal                                                          */
/******************************************************************************/

class Win32Signal : Signal {
	private {
		Mutex m_mutex;
		Win32EventDriver m_driver;
		DWORD[Task] m_listeners;
		shared int m_emitCount = 0;
	}

	this(Win32EventDriver driver)
	{
		m_mutex = new Mutex;
		m_driver = driver;
	}

	void emit()
	{
		auto newcnt = atomicOp!"+="(m_emitCount, 1);
		logDebug("Signal %s emit %s", cast(void*)this, newcnt);
		bool[DWORD] threads;
		synchronized(m_mutex)
		{
			foreach( th; m_listeners )
				threads[th] = true;
		}
		foreach( th, _; threads )
			PostThreadMessageW(th, WM_USER_SIGNAL, 0, cast(LPARAM)cast(void*)this);
	}

	void wait()
	{
		wait(emitCount);
	}

	void wait(int reference_emit_count)
	{
		logDebug("Signal %s wait enter %s", cast(void*)this, reference_emit_count);
		assert(!isOwner());
		auto self = Fiber.getThis();
		acquire();
		scope(exit) release();
		while( atomicOp!"=="(m_emitCount, reference_emit_count) )
			m_driver.m_core.yieldForEvent();
		logDebug("Signal %s wait leave %s", cast(void*)this, m_emitCount);
	}

	void acquire()
	{
		synchronized(m_mutex)
		{
			m_listeners[Task.getThis()] = GetCurrentThreadId();
		}
	}

	void release()
	{
		auto self = Task.getThis();
		synchronized(m_mutex)
		{
			if( self in m_listeners )
				m_listeners.remove(self);
		}
	}

	bool isOwner()
	{
		synchronized(m_mutex)
		{
			return (Task.getThis() in m_listeners) !is null;
		}
	}

	@property int emitCount() const { return atomicLoad(m_emitCount); }
}


/******************************************************************************/
/* class Win32Timer                                                           */
/******************************************************************************/

class Win32Timer : Timer {
	private {
		Task m_owner;
		Win32EventDriver m_driver;
		void delegate() m_callback;
		bool m_pending;
		bool m_periodic;
		Duration m_timeout;
		UINT_PTR m_id;
	}

	this(Win32EventDriver driver, void delegate() callback)
	{
		m_driver = driver;
		m_callback = callback;
	}

	~this()
	{
		if( m_pending ) stop();
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

	@property bool pending() { return m_pending; }

	void rearm(Duration dur, bool periodic = false)
	{
		m_timeout = dur;
		if( m_pending ) stop();
		m_periodic = periodic;
		auto msecs = dur.total!"msecs"();
		assert(msecs < UINT.max, "Timeout is too large for windows timers!");
		m_id = SetTimer(null, 0, cast(UINT)msecs, &onTimer);
		s_timers[m_id] = this;
		m_pending = true;
	}

	void stop()
	{
		assert(m_pending);
		KillTimer(null, m_id);
	}

	void wait()
	{
		acquire();
		scope(exit) release();
		while( m_pending )
			m_driver.m_core.yieldForEvent();
	}

	private static extern(Windows) nothrow
	void onTimer(HWND hwnd, UINT msg, UINT_PTR id, uint time)
	{
		try{
			auto timer = id in s_timers;
			if( !timer ){
				logWarn("timer %d not registered", id);
				return;
			}
			if( timer.m_periodic ){
				timer.rearm(timer.m_timeout, true);
			} else {
				timer.m_pending = false;
			}
			if( timer.m_owner ) timer.m_driver.m_core.resumeTask(timer.m_owner);
			if( timer.m_callback ) timer.m_callback();
		} catch(Exception e){
			logError("Exception in onTimer: %s", e);
		}
	}
}


/******************************************************************************/
/* class Win32FileStream                                                      */
/******************************************************************************/

class Win32FileStream : FileStream {
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
		m_task = Task.getThis();
		auto nstr = m_path.toNativeString();

		auto access = m_mode == FileMode.ReadWrite? (GENERIC_WRITE | GENERIC_READ) :
						(m_mode == FileMode.CreateTrunc || m_mode == FileMode.Append)? GENERIC_WRITE : GENERIC_READ;

		auto shareMode = m_mode == FileMode.Read? FILE_SHARE_READ : 0;

		auto creation = m_mode == FileMode.CreateTrunc? CREATE_ALWAYS : m_mode == FileMode.Append? OPEN_ALWAYS : OPEN_EXISTING;

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
		if(mode == FileMode.CreateTrunc && errorcode == ERROR_ALREADY_EXISTS)
		{
			// truncate file
			// TODO: seek to start pos?
			BOOL ret = SetEndOfFile(m_handle);
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

	bool isOwner()
	{
		return m_task == Task.getThis();
	}

	void close()
	{
		if(m_handle == INVALID_HANDLE_VALUE)
			return;
		CloseHandle(m_handle);
		m_handle = INVALID_HANDLE_VALUE;
	}

	ulong tell()
	{
		return m_ptr;
	}

	@property Path path()
	const{
		return m_path;
	}

	@property ulong size()
	const {
		return m_size;
	}

	@property bool readable()
	const {
		return m_mode == FileMode.Read || m_mode == FileMode.ReadWrite;
	}

	@property bool writable()
	const {
		return m_mode == FileMode.Append || m_mode == FileMode.CreateTrunc || m_mode == FileMode.ReadWrite;
	}

	void seek(ulong offset)
	{
		m_ptr = offset;
	}


	@property bool empty() const { assert(this.readable); return m_ptr >= m_size; }
	@property ulong leastSize() const { assert(this.readable); return m_size - m_ptr; }
	@property bool dataAvailableForRead(){
		return leastSize() > 0;
	}

	const(ubyte)[] peek(){
		assert(false);
	}

	void read(ubyte[] dst){
		assert(this.readable);

		while( dst.length > 0 ){
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
		}
	}

	void write(in ubyte[] bytes_, bool do_flush = true){
		assert(this.writable);

		const(ubyte)[] bytes = bytes_;

		while( bytes.length > 0 ){
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
		}
		if(m_ptr > m_size) m_size = m_ptr;
	}

	void flush(){}

	void finalize(){}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}

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
		} catch( Throwable e ){
			logWarn("Exception while handling file I/O: %s", e.msg);
		}
	}
}


/******************************************************************************/
/* class Win32Directory Watcher                                               */
/******************************************************************************/

class Win32DirectoryWatcher : DirectoryWatcher {
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

	bool isOwner()
	{
		return m_task == Task.getThis();
	}

	bool readChanges(ref DirectoryChange[] dst, Duration timeout)
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
			logError("Failed to read directory changes in '{}'", m_path);
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
				default: kind = DirectoryChangeType.Modified; break;
				case 0x1: kind = DirectoryChangeType.Added; break;
				case 0x2: kind = DirectoryChangeType.Removed; break;
				case 0x3: kind = DirectoryChangeType.Modified; break;
				case 0x4: kind = DirectoryChangeType.Removed; break;
				case 0x5: kind = DirectoryChangeType.Added; break;
			}
			string filename = to!string(fni.FileName.ptr[0 .. fni.FileNameLength/2]);
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
			} catch( Throwable th ){
				logWarn("Exception in directory watcher callback: %s", th.msg);
			}
		}
	}
}


/******************************************************************************/
/* class Win32UdpConnection                                                   */
/******************************************************************************/

class Win32UdpConnection : UdpConnection, SocketEventHandler {
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
		m_task = Task.getThis();
		m_bindAddress = bind_addr;

		WSAAsyncSelect(sock, m_driver.m_hwnd, WM_USER_SOCKET, FD_READ|FD_WRITE|FD_CLOSE);

		//bind...
	}

	@property SOCKET socket() { return m_socket; }

	@property string bindAddress() const {
		wchar[64] buf;
		WORD buf_len = 64;
		WSAAddressToStringW(m_bindAddress.sockAddr, m_bindAddress.sockAddrLen, null, buf.ptr, &buf_len);
		return to!string(buf[0 .. buf_len]);
	}

	@property bool canBroadcast() const { return m_canBroadcast; }
	@property void canBroadcast(bool val)
	{
		int tmp_broad = val;
		enforce(setsockopt(m_socket, SOL_SOCKET, SO_BROADCAST, &tmp_broad, tmp_broad.sizeof) == 0,
				"Failed to change the socket broadcast flag.");
		m_canBroadcast = val;
	}


	bool isOwner() {
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

	void connect(string host, ushort port)
	{
		NetworkAddress addr = m_driver.resolveHost(host, m_bindAddress.family);
		addr.port = port;
		enforce(.connect(m_socket, addr.sockAddr, addr.sockAddrLen) == 0, "Failed to connect UDP socket."~to!string(WSAGetLastError()));
	}

	void send(in ubyte[] data, in NetworkAddress* peer_address = null)
	{
		assert(data.length <= int.max);
		sizediff_t ret;
		if( peer_address ){
			ret = .sendto(m_socket, data.ptr, cast(int)data.length, 0, peer_address.sockAddr, peer_address.sockAddrLen);
		} else {
			ret = .send(m_socket, data.ptr, cast(int)data.length, 0);
		}
		logTrace("send ret: %s, %s", ret, WSAGetLastError());
		enforce(ret >= 0, "Error sending UDP packet.");
		enforce(ret == data.length, "Unable to send full packet.");
	}

	ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null)
	{
		assert(buf.length <= int.max);
		if( buf.length == 0 ) buf.length = 65507;
		NetworkAddress from;
		from.family = m_bindAddress.family;
		while(true){
			uint addr_len = from.sockAddrLen;
			auto ret = .recvfrom(m_socket, buf.ptr, cast(int)buf.length, 0, from.sockAddr, &addr_len);
			if( ret > 0 ){
				if( peer_address ) *peer_address = from;
				return buf[0 .. ret];
			}
			if( ret < 0 ){
				auto err = WSAGetLastError();
				logDebug("UDP recv err: %s", err);
				enforce(err == WSAEWOULDBLOCK, "Error receiving UDP packet.");
			}
			m_driver.m_core.yieldForEvent();
		}
	}

	void notifySocketEvent(SOCKET sock, WORD event, WORD error)
	{
		assert(false);
	}

	private static nothrow extern(C) void onUdpRead(SOCKET sockfd, short evts, void* arg)
	{
		/*auto ctx = cast(TcpContext*)arg;
		logTrace("udp socket %d read event!", ctx.socketfd);

		try {
			auto f = ctx.task;
			if( f && f.state != Fiber.State.TERM )
				ctx.core.resumeTask(f);
		} catch( Throwable e ){
			logError("Exception onUdpRead: %s", e.msg);
			debug assert(false);
		}*/
	}
}


/******************************************************************************/
/* class Win32TcpConnection                                                   */
/******************************************************************************/

enum ConnectionStatus { Initialized, Connected, Disconnected }

class Win32TcpConnection : TcpConnection, SocketEventHandler {
	private {
		Win32EventDriver m_driver;
		Task m_task;
		bool m_tcpNoDelay;
		Duration m_readTimeout;
		SOCKET m_socket;
		NetworkAddress m_peerAddress;
		DWORD m_bytesTransferred;
		ConnectionStatus m_status = ConnectionStatus.Initialized;
		FixedRingBuffer!(ubyte, 64*1024) m_readBuffer;

		HANDLE m_transferredFile;
		OVERLAPPED m_fileOverlapped;
	}

	this(Win32EventDriver driver, SOCKET sock)
	{
		m_driver = driver;
		m_socket = sock;
		m_task = Task.getThis();
		m_driver.m_socketHandlers[sock] = this;

		// setup overlapped structure for copy-less file sending
		m_fileOverlapped.Internal = 0;
		m_fileOverlapped.InternalHigh = 0;
		m_fileOverlapped.Offset = 0;
		m_fileOverlapped.OffsetHigh = 0;
		m_fileOverlapped.hEvent = m_driver.m_fileCompletionEvent;

		WSAAsyncSelect(sock, m_driver.m_hwnd, WM_USER_SOCKET, FD_READ|FD_WRITE|FD_CLOSE);
	}

	this(Win32EventDriver driver, SOCKET sock, NetworkAddress peer_address)
	{
		this(driver, sock);
		m_peerAddress = peer_address;
		m_status = ConnectionStatus.Connected;
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
		auto ret = .connect(m_socket, addr.sockAddr, addr.sockAddrLen);
		//enforce(WSAConnect(m_socket, addr.sockAddr, addr.sockAddrLen, null, null, null, null), "Failed to connect to host");

		if( ret == 0 ){
m_status = ConnectionStatus.Connected;
			assert(m_status == ConnectionStatus.Connected);
			return;
		}

		while( m_status == ConnectionStatus.Initialized )
			m_driver.m_core.yieldForEvent();
	}

	void release()
	{
		assert(m_task == Task.getThis(), "Releasing TCP connection that is not owned by the calling task.");
		m_task = Task();
	}

	void acquire()
	{
		assert(m_task == Task(), "Acquiring TCP connection that is currently owned.");
		m_task = Task.getThis();
	}

	bool isOwner() { return Task.getThis() == m_task; }

	@property void tcpNoDelay(bool enabled)
	{
		m_tcpNoDelay = enabled;
		BOOL eni = enabled;
		setsockopt(m_socket, IPPROTO_TCP, TCP_NODELAY, &eni, eni.sizeof);
		assert(false);
	}
	@property bool tcpNoDelay() const { return m_tcpNoDelay; }

	@property void readTimeout(Duration v){
		m_readTimeout = v;
		auto msecs = v.total!"msecs"();
		assert(msecs < DWORD.max);
		DWORD vdw = cast(DWORD)msecs;
		setsockopt(m_socket, SOL_SOCKET, SO_RCVTIMEO, &vdw, vdw.sizeof);
	}
	@property Duration readTimeout() const { return m_readTimeout; }

	@property bool connected() const { return m_status == ConnectionStatus.Connected; }

	@property string peerAddress()
	const {
		//m_peerAddress
		return "xxx";
	}

	@property bool empty() { return leastSize == 0; }

	@property ulong leastSize()
	{
		while( m_readBuffer.empty ){
			if( !connected ) return 0;
			m_driver.m_core.yieldForEvent();
		}
		return m_readBuffer.length;
	}

	@property bool dataAvailableForRead() { return !m_readBuffer.empty; }

	void close()
	{
		WSASendDisconnect(m_socket, null);
		closesocket(m_socket);
		m_socket = -1;
		m_status = ConnectionStatus.Disconnected;
	}

	bool waitForData(Duration timeout)
	{
		auto tm = m_driver.createTimer(null);
		tm.acquire();
		tm.rearm(timeout);
		while( m_readBuffer.empty ){
			if( !connected ) return false;
			m_driver.m_core.yieldForEvent();
			if( !tm.pending ) return false;
		}
		return true;
	}

	const(ubyte)[] peek() { return m_readBuffer.peek(); }

	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			while( m_readBuffer.empty ){
				checkConnected();
				m_driver.m_core.yieldForEvent();
			}
			size_t amt = min(dst.length, m_readBuffer.length);

			m_readBuffer.read(dst[0 .. amt]);
			dst = dst[amt .. $];
		}
	}

	void write(in ubyte[] bytes_, bool do_flush = true)
	{
		checkConnected();
		const(ubyte)[] bytes = bytes_;
		logTrace("TCP write with %s bytes called", bytes.length);
		while( bytes.length > 0 ){
			WSABUF buf;
			buf.len = bytes.length;
			buf.buf = cast(ubyte*)bytes.ptr;

			WSAOVERLAPPEDX overlapped;
			overlapped.Internal = 0;
			overlapped.InternalHigh = 0;
			overlapped.Offset = 0;
			overlapped.OffsetHigh = 0;
			overlapped.hEvent = cast(HANDLE)cast(void*)this;

			m_bytesTransferred = 0;
			logTrace("Sending %s bytes TCP", buf.len);
			auto ret = WSASend(m_socket, &buf, 1, null, 0, &overlapped, &onIOCompleted);
			if( ret == SOCKET_ERROR ){
				auto err = WSAGetLastError();
				enforce(err == WSA_IO_PENDING, "WSASend failed with error "~to!string(err));
			}
			while( !m_bytesTransferred ) m_driver.m_core.yieldForEvent();

			assert(m_bytesTransferred <= bytes.length, "More data sent than requested!?");
			bytes = bytes[m_bytesTransferred .. $];
		}
	}

	void flush()
	{
		checkConnected();
	}

	void finalize()
	{
		flush();
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		import vibe.core.drivers.threadedfile;
		// special case sending of files
		if( auto fstream = cast(Win32FileStream)stream ){
			if( fstream.tell() == 0 && fstream.size <= 1<<31 ){
				logDebug("Using sendfile! %s %s %s", fstream.m_handle, fstream.tell(), fstream.size);

				m_bytesTransferred = 0;
				m_driver.m_fileWriters[this] = true;
				if( TransmitFile(m_socket, fstream.m_handle, 0, 0, &m_fileOverlapped, null, 0) )
					m_bytesTransferred = 1;

				enforce(WSAGetLastError() == WSA_IO_PENDING, "Failed to send file over TCP.");

				while( m_bytesTransferred < fstream.size ) m_driver.m_core.yieldForEvent();
				return;
			}
		}

		writeDefault(stream, nbytes, do_flush);
	}

	void checkConnected()
	{
		// TODO!
	}

	bool testFileWritten()
	{
		if( !GetOverlappedResult(m_transferredFile, &m_fileOverlapped, &m_bytesTransferred, false) ){
			if( GetLastError() != ERROR_IO_PENDING ){
				m_driver.m_core.resumeTask(m_task, new Exception("File transfer over TCP failed."));
				return true;
			}
			return false;
		} else {
			m_driver.m_core.resumeTask(m_task);
			return true;
		}
	}

	void notifySocketEvent(SOCKET sock, WORD event, WORD error)
	nothrow {
		try {
			logDebug("Socket event for %s: %s, error: %s", sock, event, error);
			assert(sock == m_socket);
			Exception ex;
			switch(event){
				default: break;
				case FD_READ:
					logTrace("TCP read event");
					while( m_readBuffer.freeSpace > 0 ){
						auto dst = m_readBuffer.peekDst();
						assert(dst.length <= int.max);
						logTrace("Try to read up to %s bytes", dst.length);
						auto ret = .recv(m_socket, dst.ptr, cast(int)dst.length, 0);
						if( ret >= 0 ){
							logTrace("received %s bytes", ret);
							if( ret == 0 ) break;
							m_readBuffer.putN(ret);
						} else {
							auto err = WSAGetLastError();
							if( err != WSAEWOULDBLOCK ){
								logTrace("receive error %s", err);
								ex = new Exception("Socket error: "~to!string(err));
							}
							break;
						}
					}

					//m_driver.m_core.resumeTask(m_task, ex);
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
						enforce(err == WSA_IO_PENDING, "WSARecv failed with error "~to!string(err));
					}
					while( !m_bytesTransferred ) m_driver.m_core.yieldForEvent();

					assert(m_bytesTransferred <= dst.length, "More data received than requested!?");
					m_readBuffer.pushN(m_bytesTransferred);*/
					break;
				case FD_WRITE:
					if( m_status == ConnectionStatus.Initialized ){
						if( error ){
							ex = new Exception("Failed to connect to host: "~to!string(error));
						} else m_status = ConnectionStatus.Connected;
					}
					break;
				case FD_CLOSE:
					if( error ){
						if( m_status == ConnectionStatus.Initialized ){
							ex = new Exception("Failed to connect to host: "~to!string(error));
						} else {
							ex = new Exception("The connection was closed with error: "~to!string(error));
						}
					} else {
						m_status = ConnectionStatus.Disconnected;
						closesocket(m_socket);
						m_socket = -1;
					}
					break;
			}
			if( m_task ) m_driver.m_core.resumeTask(m_task, ex);
		} catch( Throwable th ){
			logWarn("Exception while handling socket event: %s", th.msg);
		}
	}

	private static extern(System) nothrow
	void onIOCompleted(DWORD dwError, DWORD cbTransferred, WSAOVERLAPPEDX* lpOverlapped, DWORD dwFlags)
	{
		logTrace("IO completed for TCP send: %s (error=%s)", cbTransferred, dwError);
		try {
			auto conn = cast(Win32TcpConnection)(lpOverlapped.hEvent);
			conn.m_bytesTransferred = cbTransferred;
			if( conn.m_task ){
				Exception ex;
				if( dwError != 0 ) ex = new Exception("Socket I/O error: "~to!string(dwError));
				if( conn.m_task ) conn.m_driver.m_core.resumeTask(conn.m_task, ex);
			}
		} catch( Throwable th ){
			logWarn("Exception while handline TCP I/O: %s", th.msg);
		}
	}
}

/******************************************************************************/
/* class Win32TcpListener                                                     */
/******************************************************************************/

class Win32TcpListener : TcpListener, SocketEventHandler {
	private {
		Win32EventDriver m_driver;
		SOCKET m_socket;
		void delegate(TcpConnection conn) m_connectionCallback;
	}

	this(Win32EventDriver driver, SOCKET sock, void delegate(TcpConnection conn) conn_callback)
	{
		m_driver = driver;
		m_socket = sock;
		m_connectionCallback = conn_callback;
		m_driver.m_socketHandlers[sock] = this;

		WSAAsyncSelect(sock, m_driver.m_hwnd, WM_USER_SOCKET, FD_ACCEPT);
	}

	void stopListening()
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
					// TODO avoid GC allocations for delegate and Win32TcpConnection
					runTask({
						NetworkAddress addr;
						addr.family = AF_INET6;
						int addrlen = addr.sockAddrLen;
						auto clientsock = WSAAccept(sock, addr.sockAddr, &addrlen, null, 0);
						assert(addrlen == addr.sockAddrLen);
						auto conn = new Win32TcpConnection(m_driver, clientsock, addr);
						try {
							m_connectionCallback(conn);
							logDebug("task out (fd %d).", sock);
						} catch( Exception e ){
							logWarn("Handling of connection failed: %s", e.msg);
							logDebug("%s", e.toString());
						}
						if( conn.connected ) conn.close();
					});
				} catch( Exception e ){
					logWarn("Exception white accepting TCP connection: %s", e.msg);
					try logDebug("Exception white accepting TCP connection: %s", e.toString());
					catch( Exception ){}
				}
				break;
		}
	}
}


private {
	Win32Timer[UINT_PTR] s_timers;
	__gshared s_setupWindowClass = false;
}

void setupWindowClass()
{
	if( s_setupWindowClass ) return;
	WNDCLASS wc;
	wc.lpfnWndProc = &Win32EventDriver.onMessage;
	wc.lpszClassName = "VibeWin32MessageWindow";
	RegisterClassA(&wc);
	s_setupWindowClass = true;
}


private extern(System) nothrow
{
	enum HWND HWND_MESSAGE = cast(HWND)-3;
	enum {
		GWLP_WNDPROC = -4,
		GWLP_HINSTANCE = -6,
		GWLP_HWNDPARENT = -8,
		GWLP_USERDATA = -21,
		GWLP_ID = -12,
	}

	version(Win32){ // avoiding linking errors with out-of-the-box dmd
		alias SetWindowLongA SetWindowLongPtrA;
		alias GetWindowLongA GetWindowLongPtrA;
	} else {
		LONG_PTR SetWindowLongPtrA(HWND hWnd, int nIndex, LONG_PTR dwNewLong);
		LONG_PTR GetWindowLongPtrA(HWND hWnd, int nIndex);
	}
	LONG_PTR SetWindowLongPtrW(HWND hWnd, int nIndex, LONG_PTR dwNewLong);
	LONG_PTR GetWindowLongPtrW(HWND hWnd, int nIndex);
	LONG_PTR SetWindowLongA(HWND hWnd, int nIndex, LONG dwNewLong);
	LONG_PTR GetWindowLongA(HWND hWnd, int nIndex);

	alias void function(DWORD, DWORD, OVERLAPPED*) LPOVERLAPPED_COMPLETION_ROUTINE;

	DWORD GetCurrentThreadId();

	HANDLE CreateEventW(SECURITY_ATTRIBUTES* lpEventAttributes, BOOL bManualReset, BOOL bInitialState, LPCWSTR lpName);
	BOOL PostThreadMessageW(DWORD idThread, UINT Msg, WPARAM wParam, LPARAM lParam);
	DWORD MsgWaitForMultipleObjectsEx(DWORD nCount, const(HANDLE) *pHandles, DWORD dwMilliseconds, DWORD dwWakeMask, DWORD dwFlags);
	BOOL CloseHandle(HANDLE hObject);
	HANDLE CreateFileW(LPCWSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes,
					   DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
	BOOL WriteFileEx(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite, OVERLAPPED* lpOverlapped, 
					LPOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);
	BOOL ReadFileEx(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead, OVERLAPPED* lpOverlapped,
					LPOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);
	BOOL GetFileSizeEx(HANDLE hFile, long *lpFileSize);
	BOOL PeekMessageW(MSG *lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg);
	LONG DispatchMessageW(MSG *lpMsg);
	BOOL PostMessageW(HWND hwnd, UINT msg, WPARAM wPara, LPARAM lParam);
	BOOL SetEndOfFile(HANDLE hFile);
	BOOL GetOverlappedResult(HANDLE hFile, OVERLAPPED* lpOverlapped, DWORD* lpNumberOfBytesTransferred, BOOL bWait);

	enum {
		ERROR_ALREADY_EXISTS = 183,
		ERROR_IO_PENDING = 997
	}

	struct FILE_NOTIFY_INFORMATION {
		DWORD NextEntryOffset;
		DWORD Action;
		DWORD FileNameLength;
		WCHAR FileName[1];
	}

	BOOL ReadDirectoryChangesW(HANDLE hDirectory, void* lpBuffer, DWORD nBufferLength, BOOL bWatchSubtree, DWORD dwNotifyFilter, LPDWORD lpBytesReturned, void* lpOverlapped, void* lpCompletionRoutine);
	HANDLE FindFirstChangeNotificationW(LPCWSTR lpPathName, BOOL bWatchSubtree, DWORD dwNotifyFilter);
	HANDLE FindNextChangeNotification(HANDLE hChangeHandle);

	enum{
		WSAPROTOCOL_LEN  = 255,
		MAX_PROTOCOL_CHAIN = 7,
	};

	enum WSA_IO_PENDING = 997;

	struct WSAPROTOCOL_INFOW {
		DWORD            dwServiceFlags1;
		DWORD            dwServiceFlags2;
		DWORD            dwServiceFlags3;
		DWORD            dwServiceFlags4;
		DWORD            dwProviderFlags;
		GUID             ProviderId;
		DWORD            dwCatalogEntryId;
		WSAPROTOCOLCHAIN ProtocolChain;
		int              iVersion;
		int              iAddressFamily;
		int              iMaxSockAddr;
		int              iMinSockAddr;
		int              iSocketType;
		int              iProtocol;
		int              iProtocolMaxOffset;
		int              iNetworkByteOrder;
		int              iSecurityScheme;
		DWORD            dwMessageSize;
		DWORD            dwProviderReserved;
		wchar            szProtocol[WSAPROTOCOL_LEN+1];
	};

	struct WSAPROTOCOLCHAIN {
		int ChainLen;                   
		DWORD ChainEntries[MAX_PROTOCOL_CHAIN];
	};

	struct WSABUF {
		size_t   len;
		ubyte *buf;
	}

	struct WSAOVERLAPPEDX {
		ULONG_PTR Internal;
		ULONG_PTR InternalHigh;
		union {
			struct {
				DWORD Offset;
				DWORD OffsetHigh;
			}
			PVOID  Pointer;
		}
		HANDLE hEvent;
	}

	enum {
		WSA_FLAG_OVERLAPPED = 0x01
	}

	enum {
		FD_READ = 0x0001,
		FD_WRITE = 0x0002,
		FD_OOB = 0x0004,
		FD_ACCEPT = 0x0008,
		FD_CONNECT = 0x0010,
		FD_CLOSE = 0x0020,
		FD_QOS = 0x0040,
		FD_GROUP_QOS = 0x0080,
		FD_ROUTING_INTERFACE_CHANGE = 0x0100,
		FD_ADDRESS_LIST_CHANGE = 0x0200
	}

	struct ADDRINFOEXW {
		int ai_flags;
		int ai_family;
		int ai_socktype;
		int ai_protocol;
		size_t ai_addrlen;
		LPCWSTR ai_canonname;
		sockaddr* ai_addr;
		void* ai_blob;
		size_t ai_bloblen;
		GUID* ai_provider;
		ADDRINFOEXW* ai_next;
	}

	struct ADDRINFOA {
		int ai_flags;
		int ai_family;
		int ai_socktype;
		int ai_protocol;
		size_t ai_addrlen;
		LPSTR ai_canonname;
		sockaddr* ai_addr;
		ADDRINFOA* ai_next;
	}

	struct ADDRINFOW {
		int ai_flags;
		int ai_family;
		int ai_socktype;
		int ai_protocol;
		size_t ai_addrlen;
		LPWSTR ai_canonname;
		sockaddr* ai_addr;
		ADDRINFOW* ai_next;
	}

	enum {
		NS_ALL = 0,
		NS_DNS = 12
	}


	struct WSAPROTOCOL_INFO;
	alias sockaddr SOCKADDR;

	alias void function(DWORD, DWORD, WSAOVERLAPPEDX*, DWORD) LPWSAOVERLAPPED_COMPLETION_ROUTINEX;
	alias void function(DWORD, DWORD, WSAOVERLAPPEDX*) LPLOOKUPSERVICE_COMPLETION_ROUTINE;
	alias void* LPCONDITIONPROC;
	alias void* LPTRANSMIT_FILE_BUFFERS;

	SOCKET WSAAccept(SOCKET s, sockaddr *addr, INT* addrlen, LPCONDITIONPROC lpfnCondition, DWORD_PTR dwCallbackData);
	int WSAAsyncSelect(SOCKET s, HWND hWnd, uint wMsg, sizediff_t lEvent);
	SOCKET WSASocketW(int af, int type, int protocol, WSAPROTOCOL_INFOW *lpProtocolInfo, uint g, DWORD dwFlags);
	int WSARecv(SOCKET s, WSABUF* lpBuffers, DWORD dwBufferCount, DWORD* lpNumberOfBytesRecvd, DWORD* lpFlags, in WSAOVERLAPPEDX* lpOverlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINEX lpCompletionRoutine);
	int WSASend(SOCKET s, in WSABUF* lpBuffers, DWORD dwBufferCount, DWORD* lpNumberOfBytesSent, DWORD dwFlags, in WSAOVERLAPPEDX* lpOverlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINEX lpCompletionRoutine);
	int WSASendDisconnect(SOCKET s, WSABUF* lpOutboundDisconnectData);
	INT WSAStringToAddressW(in LPWSTR AddressString, INT AddressFamily, in WSAPROTOCOL_INFO* lpProtocolInfo, SOCKADDR* lpAddress, INT* lpAddressLength);
	INT WSAAddressToStringW(in SOCKADDR* lpsaAddress, DWORD dwAddressLength, in WSAPROTOCOL_INFO* lpProtocolInfo, LPWSTR lpszAddressString, WORD* lpdwAddressStringLength);
	int GetAddrInfoExW(LPCWSTR pName, LPCWSTR pServiceName, DWORD dwNameSpace, GUID* lpNspId, const ADDRINFOEXW *pHints, ADDRINFOEXW **ppResult, timeval *timeout, WSAOVERLAPPEDX* lpOverlapped, LPLOOKUPSERVICE_COMPLETION_ROUTINE lpCompletionRoutine, HANDLE* lpNameHandle);
	int GetAddrInfoW(LPCWSTR pName, LPCWSTR pServiceName, const ADDRINFOW *pHints, ADDRINFOW **ppResult);
	int getaddrinfo(LPCSTR pName, LPCSTR pServiceName, const ADDRINFOA *pHints, ADDRINFOA **ppResult);
	void FreeAddrInfoW(ADDRINFOEXW* pAddrInfo);
	void freeaddrinfo(ADDRINFOA* ai);
	BOOL TransmitFile(SOCKET hSocket, HANDLE hFile, DWORD nNumberOfBytesToWrite, DWORD nNumberOfBytesPerSend, OVERLAPPED* lpOverlapped, LPTRANSMIT_FILE_BUFFERS lpTransmitBuffers, DWORD dwFlags);


	struct GUID
	{
		uint Data1;
		ushort Data2;
		ushort Data3;
		ubyte  Data4[8];
	};

	enum WM_USER = 0x0400;

	enum {
		QS_ALLPOSTMESSAGE = 0x0100,
		QS_HOTKEY = 0x0080,
		QS_KEY = 0x0001,
		QS_MOUSEBUTTON = 0x0004,
		QS_MOUSEMOVE = 0x0002,
		QS_PAINT = 0x0020,
		QS_POSTMESSAGE = 0x0008,
		QS_RAWINPUT = 0x0400,
		QS_SENDMESSAGE = 0x0040,
		QS_TIMER = 0x0010, 

		QS_MOUSE = (QS_MOUSEMOVE | QS_MOUSEBUTTON),
		QS_INPUT = (QS_MOUSE | QS_KEY | QS_RAWINPUT),
		QS_ALLEVENTS = (QS_INPUT | QS_POSTMESSAGE | QS_TIMER | QS_PAINT | QS_HOTKEY),
		QS_ALLINPUT = (QS_INPUT | QS_POSTMESSAGE | QS_TIMER | QS_PAINT | QS_HOTKEY | QS_SENDMESSAGE),
	};

	enum {
		MWMO_ALERTABLE = 0x0002,
		MWMO_INPUTAVAILABLE = 0x0004,
		MWMO_WAITALL = 0x0001,
	};
}

} // version(VibeWin32Driver)
