/**
	WinRT driver implementation

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.winrt;

version(VibeWinrtDriver)
{

import vibe.core.driver;
import vibe.inet.url;

import core.time;


class WinRTEventDriver : EventDriver {
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

	int runEventLoopOnce()
	{
		return 0;
	}

	bool processEvents()
	{
		return 0;
	}

	void exitEventLoop()
	{
	}

	void runWorkerTask(void delegate() f)
	{
	}

	WinRTFileStream openFile(string path, FileMode mode)
	{
		return new WinRTFileStream(path, mode);
	}

	DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		assert(false);
	}

	WinRTTCPConnection connectTCP(string host, ushort port)
	{
		assert(false);
	}

	void listenTCP(ushort port, void delegate(TCPConnection conn) conn_callback, string bind_address, TCPListenOptions options)
	{
		assert(false);
	}

	WinRTManualEvent createManualEvent()
	{
		assert(false);
	}

	WinRTTimer createTimer(void delegate() callback)
	{
		return new WinRTTimer(this, callback);
	}
}

class WinRTManualEvent : ManualEvent {
	void release()
	{
	}

	void acquire()
	{
	}

	bool amOwner()
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

class WinRTTimer : Timer {
	private {
		WinRTEventDriver m_driver;
		void delegate() m_callback;
		bool m_pending;
		bool m_periodic;
	}

	this(WinRTEventDriver driver, void delegate() callback)
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

	bool amOwner()
	{
		assert(false);
	}

	@property bool pending() { return m_pending; }

	void rearm(Duration dur, bool periodic = false)
	{
		if( m_pending ) stop();
		m_periodic = periodic;
		//SetTimer(m_hwnd, id, seconds.total!"msecs"(), &timerProc);
	}

	void stop()
	{
		assert(m_pending);
		//KillTimer(m_driver.m_hwnd, cast(size_t)cast(void*)this);
	}

	void wait()
	{
		while( m_pending )
			m_driver.m_core.yieldForEvent();
	}
}

class WinRTFileStream : FileStream {
	this(string path, FileMode mode)
	{
		assert(false);
	}

	void release()
	{
	}

	void acquire()
	{
	}

	bool amOwner()
	{
		assert(false);
	}

	void close()
	{
	}

	@property Path path() const { assert(false); }

	@property ulong size()
	const {
		assert(false);
	}

	@property bool readable()
	const {
		assert(false);
	}

	@property bool writable()
	const {
		assert(false);
	}

	void seek(ulong offset)
	{
	}

	ulong tell()
	{
		assert(false);
	}

	@property bool empty() { assert(false); }

	@property ulong leastSize() { assert(false); }

	@property bool dataAvailableForRead() { assert(false); }

	const(ubyte)[] peek() { assert(false); }

	void read(ubyte[] dst)
	{
	}

	void write(in ubyte[] bytes, bool do_flush = true)
	{
	}

	void flush()
	{
	}

	void finalize()
	{
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}
}

class WinRTTCPConnection : TCPConnection {
	private {
		bool m_tcpNoDelay;
		Duration m_readTimeout;
	}

	void release()
	{
	}

	void acquire()
	{
	}

	bool amOwner()
	{
		assert(false);
	}

	@property void tcpNoDelay(bool enabled)
	{
		m_tcpNoDelay = enabled;
		assert(false);
	}
	@property bool tcpNoDelay() const { return m_tcpNoDelay; }

	@property void readTimeout(Duration v){
		m_readTimeout = v;
		assert(false);
	}
	@property Duration readTimeout() const { return m_readTimeout; }

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

	@property bool empty() { assert(false); }

	@property ulong leastSize() { assert(false); }

	@property bool dataAvailableForRead() { assert(false); }

	const(ubyte)[] peek() { assert(false); }

	void read(ubyte[] dst)
	{
	}

	void write(in ubyte[] bytes, bool do_flush = true)
	{
	}

	void flush()
	{
	}

	void finalize()
	{
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}
}

} // version(VibeWinrtDriver)