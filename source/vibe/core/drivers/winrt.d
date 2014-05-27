/**
	WinRT driver implementation

	Copyright: © 2012-2013 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.winrt;

version(VibeWinrtDriver)
{

	import vibe.core.driver;
	import vibe.inet.url;
	import deimos.winrt.windows.applicationmodel.core;
	import deimos.winrt.windows.ui.core;
	import deimos.winrt.windows.ui.xaml._ : DispatcherTimer;
	import winrtd.generics;
	import deimos.winrt.windows.foundation._;
	import deimos.winrt._;
	import deimos.winrt.roapi;
	import winrtd.comsupport;
	import winrtd.roapi;

	import core.atomic;
	import core.time;

	shared static this()
	{
		comCheck(RoInitialize(RO_INIT_TYPE.MULTITHREADED), "RoInitialize");
	}

	shared static ~this()
	{
		RoUninitialize();
	}

	final class WinRTEventDriver : EventDriver {
		private {
			DriverCore m_core;
			bool m_exit = false;
		}

		this(DriverCore core)
		{
			m_core = core;

		}

		int runEventLoop()
		{
			processEventsInternal(CoreProcessEventsOption.ProcessUntilQuit);
			return 0;
		}

		int runEventLoopOnce()
		{
			processEventsInternal(CoreProcessEventsOption.ProcessOneAndAllPending);
			return 0;
		}

		bool processEvents()
		{
			return processEventsInternal(CoreProcessEventsOption.ProcessAllIfPresent);
		}

		bool processEventsInternal(CoreProcessEventsOption mode)
		{
			auto window = CoreWindow.getForCurrentThread();
			window.dispatcher.processEvents(mode);
			return window.visible;
		}

		void exitEventLoop()
		{
			CoreWindow.getForCurrentThread().close();
			//CoreApplication.exit();
		}

		FileStream openFile(Path path, FileMode mode)
		{
			//return new WinRTFileStream(path, mode);
			import vibe.core.drivers.threadedfile;
			return new ThreadedFileStream(path, mode);
		}

		DirectoryWatcher watchDirectory(Path path, bool recursive)
		{
			assert(false);
		}

		NetworkAddress resolveHost(string host, ushort family, bool use_dns)
		{
			assert(false);
		}

		WinRTTCPConnection connectTCP(string host, ushort port)
		{
			assert(false);
		}

		TCPListener listenTCP(ushort port, void delegate(TCPConnection conn) conn_callback, string bind_address, TCPListenOptions options)
		{
			assert(false);
		}

		UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
		{
			assert(false);
		}

		WinRTManualEvent createManualEvent()
		{
			return new WinRTManualEvent(this);
		}

		WinRTTimer createTimer(void delegate() callback)
		{
			return new WinRTTimer(this, callback);
		}
	}

	class WinRTManualEvent : ManualEvent {
		private {
			WinRTEventDriver m_driver;
			shared(int) m_emitCount;
			Task[] m_waiters;
		}

		this(WinRTEventDriver driver)
		{
			m_driver = driver;
		}

		@property int emitCount() const { return m_emitCount; }

		void emit()
		{
			atomicOp!"+="(m_emitCount, 1);
			auto wtrs = m_waiters;
			m_waiters = null;
			foreach (t; wtrs)
				m_driver.m_core.resumeTask(t);
		}

		void wait()
		{
			wait(this.emitCount);
		}

		int wait(int reference_emit_count)
		{
			m_waiters ~= Task.getThis();
			int rc;
			while ((rc = this.emitCount) == reference_emit_count) m_driver.m_core.yieldForEvent();
			return rc;
		}

		int wait(Duration timeout, int reference_emit_count)
		{
			assert(false);
		}
	}

	class WinRTTimer : Timer {
		private {
			WinRTEventDriver m_driver;
			void delegate() m_callback;
			DispatcherTimer m_timer;
			EventConnection m_eventConn;
			bool m_periodic;
			Task[] m_waiters;
		}

		this(WinRTEventDriver driver, void delegate() callback)
		{
			m_driver = driver;
			m_callback = callback;
			m_eventConn = m_timer.invokeOnTick((sender, timer) {
				if (m_callback) m_callback();
				foreach (t; m_waiters)
					m_driver.m_core.resumeTask(t);
			});
		}

		~this()
		{
			m_eventConn.disconnect();
		}

		@property bool pending() { return m_timer.isEnabled; }

		void rearm(Duration dur, bool periodic = false)
		{
			if (m_timer) m_timer.stop();
			else m_timer = new DispatcherTimer;
			m_timer.interval = TimeSpan(dur.total!"hnsecs"());
			m_timer.start();
			m_periodic = periodic;
		}

		void stop()
		{
			if (m_timer.isEnabled)
				m_timer.stop();
		}

		void wait()
		{
			while (m_timer.isEnabled)
				m_driver.m_core.yieldForEvent();
		}
	}

	class WinRTFileStream : FileStream {
		private {
		}

		this(Path path, FileMode mode)
		{
			assert(false);
		}

		void close()
		{
		}

		@property Path path() const { assert(false); }

		@property bool isOpen() const { assert(false); }

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

		void write(in ubyte[] bytes)
		{
		}

		void flush()
		{
		}

		void finalize()
		{
		}

		void write(InputStream stream, ulong nbytes = 0)
		{
			writeDefault(stream, nbytes);
		}
	}

	class WinRTTCPConnection : TCPConnection {
		private {
			bool m_tcpNoDelay;
			bool m_keepAlive;
			Duration m_readTimeout;
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

		@property void keepAlive(bool enabled)
		{
			m_keepAlive = enabled;
			assert(false);
		}
		@property bool keepAlive() const { return m_keepAlive; }

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

		void write(in ubyte[] bytes)
		{
		}

		void flush()
		{
		}

		void finalize()
		{
		}

		void write(InputStream stream, ulong nbytes = 0)
		{
			writeDefault(stream, nbytes);
		}
	}

} // version(VibeWinrtDriver)