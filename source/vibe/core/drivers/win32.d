/**
	Win32 driver implementation using I/O completion ports

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.win32;

import vibe.core.driver;
import vibe.core.log;
import vibe.inet.url;

import core.sys.windows.windows;
import core.time;
import core.thread;
import std.c.windows.windows;
import std.c.windows.winsock;
import std.exception;

private extern(System)
{
	DWORD MsgWaitForMultipleObjects(DWORD nCount, const(HANDLE) *pHandles, BOOL bWaitAll, DWORD dwMilliseconds, DWORD dwWakeMask);
	HANDLE CreateFileW(LPCTSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes,
							DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
	BOOL WriteFileEx(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite, OVERLAPPED* lpOverlapped, 
					 void function(DWORD, DWORD, OVERLAPPED) lpCompletionRoutine);
	BOOL PeekMessageW(MSG *lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg);
	LONG DispatchMessageW(MSG *lpMsg);
	BOOL PostMessageW(HWND hwnd, UINT msg, WPARAM wPara, LPARAM lParam);
	SOCKET WSASocketW(int af, int type, int protocol, WSAPROTOCOL_INFOW *lpProtocolInfo, uint g, DWORD dwFlags);

	enum{
		WSAPROTOCOL_LEN  = 255,
		MAX_PROTOCOL_CHAIN = 7
	};

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

	struct GUID
	{
		size_t  Data1;
		ushort Data2;
		ushort Data3;
		ubyte  Data4[8];
	};

	enum{
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

	enum{
		MWMO_ALERTABLE = 0x0002,
		MWMO_INPUTAVAILABLE = 0x0004,
		MWMO_WAITALL = 0x0001,
	};
}

class Win32EventDriver : EventDriver {
	private {
		HWND m_hwnd;
		DriverCore m_core;
		bool m_exit = false;
		int m_timerIdCounter = 0;
	}

	this(DriverCore core)
	{
		m_core = core;

		WSADATA wd;
		enforce(WSAStartup(0x0202, &wd) == 0, "Failed to initialize WinSock");
	}

	int runEventLoop()
	{
		m_exit = false;
		while( !m_exit ){
			waitForEvents(INFINITE);
			processEvents();
		}
		return 0;
	}

	int processEvents()
	{
		waitForEvents(0);
		MSG msg;
		while( PeekMessageW(&msg, null, 0, 0, PM_REMOVE) ){
			if( msg.message == WM_QUIT ) return 0;
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		//m_core.notifyIdle();
		return 0;
	}

	private void waitForEvents(uint timeout)
	{
		MsgWaitForMultipleObjects(0, null, timeout, QS_ALLEVENTS, MWMO_ALERTABLE|MWMO_INPUTAVAILABLE);
	}

	void exitEventLoop()
	{
		m_exit = true;
		PostMessageW(m_hwnd, WM_QUIT, 0, 0);
	}

	void runWorkerTask(void delegate() f)
	{

	}

	Win32FileStream openFile(string path, FileMode mode)
	{
		return new Win32FileStream(m_core, Path(path), mode);
	}

	Win32TcpConnection connectTcp(string host, ushort port)
	{
		//getaddrinfo();
		//auto sock = WSASocketW(AF_INET, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
		//enforce(sock != INVALID_SOCKET, "Failed to create socket.");
		//enforce(WSAConnect(sock, &addr, addr.sizeof, null, null, null, null), "Failed to connect to host");
		assert(false);
	}

	void listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string bind_address)
	{

	}

	Win32Signal createSignal()
	{
		assert(false);
	}

	Win32Timer createTimer(void delegate() callback)
	{
		return new Win32Timer(this, callback);
	}
}

class Win32Signal : Signal {
	void release()
	{
	}

	void acquire()
	{
	}

	bool isOwner()
	{
		assert(false);
	}

	@property int emitCount()
	const {
		assert(false);
	}

	void emit()
	{
	}

	void wait()
	{
	}
}

class Win32Timer : Timer {
	private {
		Win32EventDriver m_driver;
		void delegate() m_callback;
		bool m_pending;
		bool m_periodic;
		Duration m_timeout;
	}

	this(Win32EventDriver driver, void delegate() callback)
	{
		m_driver = driver;
		m_callback = callback;
	}

	void release()
	{
	}

	void acquire()
	{
	}

	bool isOwner()
	{
		assert(false);
	}

	@property bool pending() { return m_pending; }

	void rearm(Duration dur, bool periodic = false)
	{
		m_timeout = dur;
		if( m_pending ) stop();
		m_periodic = periodic;
		//SetTimer(m_hwnd, id, seconds.total!"msecs"(), &timerProc);
		assert(false);
	}

	void stop()
	{
		assert(m_pending);
		//KillTimer(m_driver.m_hwnd, cast(size_t)cast(void*)this);
		assert(false);
	}

	void wait()
	{
		while( m_pending )
			m_driver.m_core.yieldForEvent();
	}

	private static extern(Windows) nothrow
	void onTimer(HWND hwnd, UINT msg, size_t id, uint time)
	{
		try{
			auto timer = cast(Win32Timer)cast(void*)id;
			if( timer.m_periodic ){
				timer.rearm(timer.m_timeout, true);
			} else {
				timer.m_pending = false;
			}
			timer.m_callback();
		} catch(Exception e)
		{
			logError("onTimer Exception: %s", e);
		}
	}
}

class Win32FileStream : FileStream {

	private{
		Path m_path;
		HANDLE m_handle;
		FileMode m_mode;
		DriverCore m_driver;
		Fiber m_fiber;
	}

	this(DriverCore driver, Path path, FileMode mode)
	{
		m_path = path;
		m_mode = mode;
		m_driver = driver;
		m_fiber = Fiber.getThis();
		m_handle = CreateFileW(
					cast(immutable(char)*)(m_path.toNativeString()),
					m_mode == (m_mode == FileMode.CreateTrunc || m_mode == FileMode.Append) ? GENERIC_READ : GENERIC_WRITE,
					m_mode == FileMode.Read ? FILE_SHARE_READ : 0,
					null,
					m_mode == FileMode.CreateTrunc ? TRUNCATE_EXISTING : OPEN_ALWAYS,
					FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
					null);
	}

	void release()
	{
		this.m_fiber = null;
	}

	void acquire()
	{
		this.m_fiber.getThis();
	}

	bool isOwner()
	{
		assert(false);
	}

	void close()
	{
	}

	@property Path path()
	const{
		return m_path;
	}

	@property ulong size()
	const {
		assert(false);
	}

	@property bool readable()
	const {
		return m_mode == FileMode.Read;
	}

	@property bool writable()
	const {
		return m_mode == FileMode.Append || m_mode == FileMode.CreateTrunc;
	}

	void seek(ulong offset)
	{
	}

	@property bool empty()
	{
		return false;
	}

	@property ulong leastSize(){
		assert(false);
	}

	@property bool dataAvailableForRead(){
		assert(false);
	}

	const(ubyte)[] peek(){
		assert(false);
	}

	void read(ubyte[] dst){
		assert(false);
	}

	void write(in ubyte[] bytes, bool do_flush = true){

		OVERLAPPED overlapped;
		overlapped.Internal = 0;
		overlapped.InternalHigh = 0;
		overlapped.Offset = 0;
		overlapped.OffsetHigh = 0;
		overlapped.hEvent = cast(HANDLE)cast(void*)this;
		WriteFileEx(m_handle, cast(void*)bytes, bytes.length, &overlapped, &fileStreamOperationComplete);

		m_driver.yieldForEvent();
	}

	void flush(){}

	void finalize(){}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}
}

class Win32TcpConnection : TcpConnection {
	void release()
	{
	}

	void acquire()
	{
	}

	bool isOwner()
	{
		assert(false);
	}

	@property void tcpNoDelay(bool enabled)
	{
	}

	void close()
	{
	}

	@property bool connected()
	const {
		assert(false);
	}

	@property string peerAddress()
	const {
		assert(false);
	}

	bool waitForData(Duration timeout)
	{
		assert(false);
	}

	@property bool empty()
	{
		assert(false);
	}

	@property ulong leastSize()
	{
		assert(false);
	}

	@property bool dataAvailableForRead()
	{
		assert(false);
	}

	const(ubyte)[] peek()
	{
		assert(false);
	}

	void read(ubyte[] dst)
	{
		assert(false);
	}

	void write(in ubyte[] bytes, bool do_flush = true)
	{
		assert(false);
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
}

private extern(System)
{
	void fileStreamOperationComplete(DWORD errorCode, DWORD numberOfBytesTransfered, OVERLAPPED overlapped)
	{
		auto fileStream = cast(Win32FileStream)(overlapped.hEvent);
		fileStream.m_driver.resumeTask(fileStream.m_fiber);
		//resume fiber
		// set flag operation done

		logInfo("fileStreamOperationComplete");
	}

}
