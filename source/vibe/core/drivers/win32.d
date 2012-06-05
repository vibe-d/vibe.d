/**
	Win32 driver implementation using I/O completion ports

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.win32;

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
			MsgWaitForMultipleObjects(0, null, INFINITE, QS_ALLEVENTS, MWMO_ALERTABLE|MWMO_INPUTAVAILABLE);
			processEvents();
		}
		return 0;
	}

	int processEvents()
	{
		MSG msg;
		while( PeekMessageW(&msg, null, 0, 0, PM_REMOVE) ){
			if( msg.message == WM_QUIT ) return 0;
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
		}
		m_core.notifyIdle();
		return 0;
	}

	void exitEventLoop()
	{
		m_exit = true;
		PostMessage(m_hwnd, WM_QUIT, 0, 0);
	}

	Win32FileStream openFile(string path, FileMode mode)
	{
		return new Win32FileStream(path, mode);
	}

	Win32TcpConnection connectTcp(string host, ushort port)
	{
		getaddrinfo();
		auto sock = WSASocket(AF_INET, IPPROTO_TCP, NULL, 0, WSA_FLAG_OVERLAPPED);
		enforce(sock != INVALID_SOCKET, "Failed to create socket.");
		enforce(WSAConnect(sock, &addr, addr.sizeof, null, null, null, null), "Failed to connect to host");
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
	}

	@property int emitCount()
	const {
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
		void delegate() callback;
		bool m_pending;
		bool m_periodic;
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
	}

	@property bool pending() { return m_pending; }

	void rearm(Duration dur, bool periodic = false)
	{
		if( m_pending ) stop();
		m_periodic = periodic;
		SetTimer(m_hwnd, id, seconds.total!"msecs"(), &timerProc);
	}

	void stop()
	{
		assert(m_pending);
		KillTimer(m_driver.m_hwnd, cast(size_t)cast(void*)this);
	}

	void wait()
	{
		while( m_pending )
			m_driver.m_core.yieldForEvent();
	}

	private static extern(Windows) nothrow
	void onTimer(HWND hwnd, UINT msg, size_t id, uint time)
	{
		auto timer = cast(Timer)cast(void*)id;
		if( timer.m_periodic ){
			timer.rearm(m_timer.m_timeout, true);
		} else {
			timer.m_pending = false;
		}
		timer.m_callback();
	}
}

class Win32File : FileStream {
	void release()
	{
	}

	void acquire()
	{
	}

	bool isOwner()
	{
	}

	void close()
	{
	}

	@property ulong size()
	const {
	}

	@property bool readable()
	const {
	}

	@property bool writable()
	const {
	}

	void seek(ulong offset)
	{
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
	}

	@property void tcpNoDelay(bool enabled)
	{
	}

	void close()
	{
	}

	@property bool connected()
	const {
	}

	@property string peerAddress()
	const {
	}

	bool waitForData(Duration timeout)
	{
	}
}
