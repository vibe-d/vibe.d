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

import core.atomic;
import core.sync.mutex;
import core.sys.windows.windows;
import core.time;
import core.thread;
import std.conv;
import std.c.windows.windows;
import std.c.windows.winsock;
import std.exception;
import std.utf;


class Win32EventDriver : EventDriver {
	private {
		HWND m_hwnd;
		DWORD m_tid;
		DriverCore m_core;
		bool m_exit = false;
		int m_timerIdCounter = 0;
	}

	this(DriverCore core)
	{
		m_core = core;
		m_tid = GetCurrentThreadId();

		WSADATA wd;
		enforce(WSAStartup(0x0202, &wd) == 0, "Failed to initialize WinSock");
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
			if( msg.message == WM_QUIT ) return 0;
			if( msg.message == WM_USER_SIGNAL ){
				auto sig = cast(Win32Signal)cast(void*)msg.lParam;
				DWORD[Task] lst;
				synchronized(sig.m_mutex) lst = sig.m_listeners.dup;
				foreach( task, tid; lst )
					if( tid == m_tid && task )
						m_core.resumeTask(task);
			}
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		return 0;
	}

	private void waitForEvents(uint timeout)
	{
		MsgWaitForMultipleObjectsEx(0, null, timeout, QS_ALLEVENTS, MWMO_ALERTABLE|MWMO_INPUTAVAILABLE);
	}

	void exitEventLoop()
	{
		m_exit = true;
		PostThreadMessageW(m_tid, WM_QUIT, 0, 0);
	}

	Win32FileStream openFile(string path, FileMode mode)
	{
		assert(m_tid == GetCurrentThreadId());
		return new Win32FileStream(m_core, Path(path), mode);
	}

	NetworkAddress resolveHost(string host, ushort family = AF_UNSPEC, bool no_dns = false)
	{
		assert(false);
	}

	Win32TcpConnection connectTcp(string host, ushort port)
	{
		assert(m_tid == GetCurrentThreadId());
		//getaddrinfo();
		//auto sock = WSASocketW(AF_INET, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
		//enforce(sock != INVALID_SOCKET, "Failed to create socket.");
		//enforce(WSAConnect(sock, &addr, addr.sizeof, null, null, null, null), "Failed to connect to host");
		assert(false);
	}

	void listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string bind_address)
	{
		assert(m_tid == GetCurrentThreadId());

	}

	UdpConnection listenUdp(ushort port, string bind_address = "0.0.0.0")
	{
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
}

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
		m_owner = Task.getThis();
	}

	~this()
	{
		if( m_pending ) stop();
	}

	void release()
	{
		assert(false, "not supported");
	}

	void acquire()
	{
		assert(false, "not supported");
	}

	bool isOwner()
	{
		assert(false, "not supported");
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

class Win32FileStream : FileStream {

	private{
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

		auto creation = m_mode == FileMode.CreateTrunc? CREATE_ALWAYS : OPEN_ALWAYS;

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

	void release()
	{
		assert(m_task is Task.getThis(), "Releasing FileStream that is not owned by the calling task.");
		m_task = null;
	}

	void acquire()
	{
		assert(m_task is null, "Acquiring FileStream that is already owned.");
		m_task = Task.getThis();
	}

	bool isOwner()
	{
		return m_task is Task.getThis();
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

			// request to write the data
			ReadFileEx(m_handle, cast(void*)dst, dst.length, &overlapped, &onIOCompleted);
			
			// yield until the data is read
			while( !m_bytesTransferred ) m_driver.yieldForEvent();

			assert(m_bytesTransferred <= dst.length, "More bytes read than requested!?");
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

			// request to write the data
			WriteFileEx(m_handle, cast(void*)bytes, bytes.length, &overlapped, &onIOCompleted);

			// yield until the data is written
			while( !m_bytesTransferred ) m_driver.yieldForEvent();

			assert(m_bytesTransferred <= bytes.length, "More bytes written than requested!?");
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

	private static extern(System)
	void onIOCompleted(DWORD dwError, DWORD cbTransferred, OVERLAPPED* overlapped)
	{
		auto fileStream = cast(Win32FileStream)(overlapped.hEvent);
		fileStream.m_bytesTransferred = cbTransferred;
		if( fileStream.m_task ){
			Exception ex;
			if( dwError != 0 ) ex = new Exception("File I/O error: "~to!string(dwError));
			fileStream.m_driver.resumeTask(fileStream.m_task, ex);
		}
	}
}

class Win32TcpConnection : TcpConnection {
	private {
		DriverCore m_driver;
		Task m_task;
		bool m_tcpNoDelay;
		Duration m_readTimeout;
		SOCKET m_socket;
		DWORD m_bytesTransferred;
	}

	this(DriverCore driver, SOCKET sock)
	{
		m_driver = driver;
		m_socket = sock;
		m_task = Task.getThis();
	}

	void release()
	{
		assert(m_task is Task.getThis(), "Releasing TCP connection that is not owned by the calling task.");
		m_task = null;
	}

	void acquire()
	{
		assert(m_task is null, "Acquiring TCP connection that is currently owned.");
		m_task = Task.getThis();
	}

	bool isOwner() { return Task.getThis() is m_task; }

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

	@property bool connected() const { return m_socket != -1; }

	@property string peerAddress()
	const {
		assert(false);
	}

	@property bool empty()
	{
		assert(false);
	}

	@property ulong leastSize()
	{
		//WSAIoctl(m_socket, FIONREAD, null, 0, &v, &vsize, &overlapped, &onIOCompleted);
		assert(false);
	}

	@property bool dataAvailableForRead()
	{
		assert(false);
	}

	void close()
	{
		WSASendDisconnect(m_socket, null);
		closesocket(m_socket);
		m_socket = -1;
	}

	bool waitForData(Duration timeout)
	{
		assert(false);
	}

	const(ubyte)[] peek()
	{
		assert(false);
	}

	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			WSABUF buf;
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
			while( !m_bytesTransferred ) m_driver.yieldForEvent();

			assert(m_bytesTransferred <= dst.length, "More data received than requested!?");
			dst = dst[m_bytesTransferred .. $];
		}
	}

	void write(in ubyte[] bytes_, bool do_flush = true)
	{
		const(ubyte)[] bytes = bytes_;
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
			auto ret = WSASend(m_socket, &buf, 1, null, 0, &overlapped, &onIOCompleted);
			if( ret == SOCKET_ERROR ){
				auto err = WSAGetLastError();
				enforce(err == WSA_IO_PENDING, "WSARecv failed with error "~to!string(err));
			}
			while( !m_bytesTransferred ) m_driver.yieldForEvent();

			assert(m_bytesTransferred <= bytes.length, "More data sent than requested!?");
			bytes = bytes[m_bytesTransferred .. $];
		}
	}

	void flush()
	{
		assert(false);
	}

	void finalize()
	{
		assert(false);
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		assert(false);
	}

	private static extern(System)
	void onIOCompleted(DWORD dwError, DWORD cbTransferred, WSAOVERLAPPEDX* lpOverlapped, DWORD dwFlags)
	{
		auto fileStream = cast(Win32FileStream)(lpOverlapped.hEvent);
		fileStream.m_bytesTransferred = cbTransferred;
		if( fileStream.m_task ){
			Exception ex;
			if( dwError != 0 ) ex = new Exception("Socket I/O error: "~to!string(dwError));
			fileStream.m_driver.resumeTask(fileStream.m_task, ex);
		}
	}
}

private {
	Win32Timer[UINT_PTR] s_timers;
}


private extern(System)
{
	alias void function(DWORD, DWORD, OVERLAPPED*) LPOVERLAPPED_COMPLETION_ROUTINE;

	DWORD GetCurrentThreadId();
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
	SOCKET WSASocketW(int af, int type, int protocol, WSAPROTOCOL_INFOW *lpProtocolInfo, uint g, DWORD dwFlags);

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

	alias void function(DWORD, DWORD, WSAOVERLAPPEDX*, DWORD) LPWSAOVERLAPPED_COMPLETION_ROUTINEX;

	int WSARecv(SOCKET s, WSABUF* lpBuffers, DWORD dwBufferCount, DWORD* lpNumberOfBytesRecvd, DWORD* lpFlags, in WSAOVERLAPPEDX* lpOverlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINEX lpCompletionRoutine);
	int WSASend(SOCKET s, in WSABUF* lpBuffers, DWORD dwBufferCount, DWORD* lpNumberOfBytesSent, DWORD dwFlags, in WSAOVERLAPPEDX* lpOverlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINEX lpCompletionRoutine);
	int WSASendDisconnect(SOCKET s, WSABUF* lpOutboundDisconnectData);


	const uint ERROR_ALREADY_EXISTS = 183;

	struct GUID
	{
		uint Data1;
		ushort Data2;
		ushort Data3;
		ubyte  Data4[8];
	};

	enum WM_USER = 0x0400;
	enum WM_USER_SIGNAL = WM_USER+101;

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
