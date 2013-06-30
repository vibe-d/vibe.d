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

	class WinRTEventDriver : EventDriver {
		private {
			DriverCore m_core;
			bool m_exit = false;
		}

		this(DriverCore core)
		{
			m_core = core;

		}

		version (HostWinRTDesktop) {
			import vibe.internal.win32;

			private DWORD m_tid;

			int runEventLoop()
			{
				m_exit = false;
				while( !m_exit && haveEvents() )
					runEventLoopOnce();
				return 0;
			}

			int runEventLoopOnce()
			{
				doProcessEvents(INFINITE);
				m_core.notifyIdle();
				return 0;
			}

			bool processEvents()
			{
				return doProcessEvents(0);
			}

			bool doProcessEvents(uint timeout)
			{
				waitForEvents(timeout);
				assert(m_tid == GetCurrentThreadId());
				MSG msg;
				while( PeekMessageW(&msg, null, 0, 0, PM_REMOVE) ){
					if( msg.message == WM_QUIT ) return false;
					TranslateMessage(&msg);
					DispatchMessageW(&msg);
				}
				return true;
			}

			private bool haveEvents()
			{
				version(VibePartialAutoExit)
					return !m_fileWriters.byKey.empty || !m_socketHandlers.byKey.empty;
				else return true;
			}

			private void waitForEvents(uint timeout)
			{
				auto ret = MsgWaitForMultipleObjectsEx(/*cast(DWORD)m_registeredEvents.length, m_registeredEvents.ptr*/0, null, timeout, QS_ALLEVENTS, MWMO_ALERTABLE|MWMO_INPUTAVAILABLE);
			}
		} else {
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
				ComPtr!ICoreWindowStatic windowStatic;
				auto windowClassName= HStringReference("Windows.UI.Core.CoreWindow");
				comCheck(GetActivationFactory(windowClassName, windowStatic._target), "ICoreWindowStatic");
				ComPtr!ICoreWindow window;
				comCheck(windowStatic.GetForCurrentThread(window._target), "GetWindowForCurrentThread");
				ComPtr!ICoreDispatcher dispatcher;
				comCheck(window.Dispatcher(dispatcher._target), "Dispatcher");
				comCheck(dispatcher.ProcessEvents(mode), "ProcessEvents");
				bool vis;
				comCheck(window.Visible(&vis));
				return vis;
			}
		}

		void exitEventLoop()
		{
			ComPtr!ICoreWindowStatic windowStatic;
			auto windowClassName = HStringReference("Windows.UI.Core.CoreWindow");
			comCheck(GetActivationFactory(windowClassName, windowStatic._target), "ICoreWindowStatic");
			ComPtr!ICoreWindow window;
			comCheck(windowStatic.GetForCurrentThread(window._target), "GetWindowForCurrentThread");
			comCheck(window.Close(), "window.Close");
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

		NetworkAddress resolveHost(string host, ushort family, bool no_dns)
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
			bool m_pending;
			bool m_periodic;
		}

		this(WinRTEventDriver driver, void delegate() callback)
		{
			m_driver = driver;
			m_callback = callback;
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
		this(Path path, FileMode mode)
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