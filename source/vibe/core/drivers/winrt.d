/**
	WinRT driver implementation

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.winrt;

class WinRtEventDriver : EventDriver {
	private {
		DriverCore m_core;
	}

	this(DriverCore core)
	{
		m_core = core;

	}

	int runEventLoop()
	{
		return 0;
	}

	int processEvents()
	{
		return 0;
	}

	void exitEventLoop()
	{
	}

	WinRtFileStream openFile(string path, FileMode mode)
	{
		return new WinRtFileStream(path, mode);
	}

	WinRtTcpConnection connectTcp(string host, ushort port)
	{
		assert(false);
	}

	void listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string bind_address)
	{
		assert(false);
	}

	WinRtSignal createSignal()
	{
		assert(false);
	}

	WinRtTimer createTimer(void delegate() callback)
	{
		return new WinRtTimer(this, callback);
	}
}

class WinRtSignal : Signal {
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

class WinRtTimer : Timer {
	private {
		WinRtEventDriver m_driver;
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

class WinRtFile : FileStream {
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

class WinRtTcpConnection : TcpConnection {
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
