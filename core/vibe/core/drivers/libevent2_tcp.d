/**
	TCP side of  the libevent driver

	For the base driver implementation, see `vibe.core.drivers.libevent2`.

	Copyright: © 2012-2015 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libevent2_tcp;

version(VibeLibeventDriver)
{

public import vibe.core.core;

import vibe.core.log;
import vibe.core.drivers.libevent2;
import vibe.core.drivers.utils;
import vibe.internal.freelistref;

import deimos.event2.buffer;
import deimos.event2.bufferevent;
import deimos.event2.bufferevent_ssl;
import deimos.event2.event;
import deimos.event2.util;

import std.algorithm;
import std.encoding : sanitize;
import std.exception;
import std.conv;
import std.string;

import core.stdc.errno;
import core.thread;
import core.sys.posix.netinet.in_;
import core.sys.posix.netinet.tcp;
import core.sys.posix.sys.socket;


private {
	version (Windows) {
		import core.sys.windows.winsock2;
		// make some neccessary parts of the socket interface public
		alias in6_addr = core.sys.windows.winsock2.in6_addr;
		alias INADDR_ANY = core.sys.windows.winsock2.INADDR_ANY;
		alias IN6ADDR_ANY = core.sys.windows.winsock2.IN6ADDR_ANY;

		enum EWOULDBLOCK = WSAEWOULDBLOCK;
	} else {
		alias in6_addr = core.sys.posix.netinet.in_.in6_addr;
		alias IN6ADDR_ANY = core.sys.posix.netinet.in_.in6addr_any;
		alias INADDR_ANY = core.sys.posix.netinet.in_.INADDR_ANY;
		alias TCP_NODELAY = core.sys.posix.netinet.tcp.TCP_NODELAY;
	}
}

package final class Libevent2TCPConnection : TCPConnection {
@safe:

	import vibe.utils.array : FixedRingBuffer;
	private {
		bool m_timeout_triggered;
		TCPContext* m_ctx;
		FixedRingBuffer!(ubyte, 4096, false) m_readBuffer;
		string m_peerAddress;
		bool m_tcpNoDelay = false;
		bool m_tcpKeepAlive = false;
		Duration m_readTimeout;
		char[64] m_peerAddressBuf;
		NetworkAddress m_localAddress, m_remoteAddress;
		event* m_waitDataEvent;
	}

	this(TCPContext* ctx)
	{
		m_ctx = ctx;
		m_waitDataEvent = () @trusted { return event_new(m_ctx.eventLoop, -1, 0, &onTimeout, cast(void*)this); } ();

		assert(!amOwner());

		m_localAddress = ctx.local_addr;
		m_remoteAddress = ctx.remote_addr;

		void* ptr;
		switch (ctx.remote_addr.family) {
			default: throw new Exception("Unsupported address family.");
			case AF_INET: ptr = &ctx.remote_addr.sockAddrInet4.sin_addr; break;
			case AF_INET6: ptr = &ctx.remote_addr.sockAddrInet6.sin6_addr; break;
			version (Posix) {
				case AF_UNIX: ptr = &ctx.remote_addr.sockAddrUnix.sun_path; break;
			}
		}

		if (() @trusted { return evutil_inet_ntop(ctx.remote_addr.family, ptr, m_peerAddressBuf.ptr, m_peerAddressBuf.length); } () !is null)
			m_peerAddress = () @trusted { return cast(string)m_peerAddressBuf[0 .. m_peerAddressBuf[].indexOf('\0')]; } ();

		() @trusted {
			bufferevent_setwatermark(m_ctx.event, EV_WRITE, 4096, 65536);
			bufferevent_setwatermark(m_ctx.event, EV_READ, 0, 65536);
		} ();
	}

	/*~this()
	{
		//assert(m_ctx is null, "Leaking TCPContext because it has not been cleaned up and we are not allowed to touch the GC in finalizers..");
	}*/

	@property void tcpNoDelay(bool enabled)
	{
		m_tcpNoDelay = enabled;
		auto fd = m_ctx.socketfd;
		int opt = enabled;
		assert(fd <= int.max, "Socket descriptor > int.max");
		() @trusted { setsockopt(cast(int)fd, IPPROTO_TCP, TCP_NODELAY, cast(char*)&opt, opt.sizeof); } ();
	}
	@property bool tcpNoDelay() const { return m_tcpNoDelay; }

	@property void readTimeout(Duration v)
	{
		m_readTimeout = v;
		if( v == dur!"seconds"(0) ){
			() @trusted { bufferevent_set_timeouts(m_ctx.event, null, null); } ();
		} else {
			assert(v.total!"seconds" <= int.max);
			timeval toread = v.toTimeVal();
			() @trusted { bufferevent_set_timeouts(m_ctx.event, &toread, null); } ();
		}
	}
	@property Duration readTimeout() const { return m_readTimeout; }

	@property void keepAlive(bool enable)
	{
		m_tcpKeepAlive = enable;
		auto fd = m_ctx.socketfd;
		ubyte opt = enable;
		assert(fd <= int.max, "Socket descriptor > int.max");
		() @trusted { setsockopt(cast(int)fd, SOL_SOCKET, SO_KEEPALIVE, &opt, opt.sizeof); } ();
	}
	@property bool keepAlive() const { return m_tcpKeepAlive; }

	@property NetworkAddress localAddress() const { return m_localAddress; }
	@property NetworkAddress remoteAddress() const { return m_remoteAddress; }

	private void acquire()
	@safe {
		assert(m_ctx, "Trying to acquire a closed TCP connection.");
		assert(m_ctx.readOwner == Task() && m_ctx.writeOwner == Task(), "Trying to acquire a TCP connection that is currently owned.");
		m_ctx.readOwner = m_ctx.writeOwner = Task.getThis();
	}

	private void release()
	@safe {
		if( !m_ctx ) return;
		assert(m_ctx.readOwner != Task() && m_ctx.writeOwner != Task(), "Trying to release a TCP connection that is not owned.");
		assert(m_ctx.readOwner == Task.getThis() && m_ctx.readOwner == m_ctx.writeOwner, "Trying to release a foreign TCP connection.");
		m_ctx.readOwner = m_ctx.writeOwner = Task();
	}

	private bool amOwner()
	@safe {
		return m_ctx !is null && m_ctx.readOwner != Task() && m_ctx.readOwner == Task.getThis() && m_ctx.readOwner == m_ctx.writeOwner;
	}

	/// Closes the connection.
	void close()
	{
		logDebug("TCP close request %s %s", m_ctx !is null, m_ctx ? m_ctx.state : ConnectionState.open);
		if (!m_ctx || m_ctx.state == ConnectionState.activeClose) return;

		if (!getThreadLibeventEventLoop()) {
			import std.stdio;
			() @trusted { stderr.writefln("Warning: Attempt to close dangling TCP connection to %s at shutdown. "
				~ "Please avoid closing connections in GC finalizers.", m_remoteAddress); } ();
			return;
		}

		// set the closing flag
		m_ctx.state = ConnectionState.activeClose;

		// resume any reader, so that the read operation can be ended with a failure
		while (m_ctx.readOwner != Task.init) {
			logTrace("resuming reader first");
			m_ctx.core.yieldAndResumeTask(m_ctx.readOwner);
			logTrace("back (%s)!", m_ctx !is null);
			// test if the resumed task has already closed the connection
			if (!m_ctx) return;
		}

		// acquire read+write access
		acquire();

		scope (exit) cleanup();

		if (m_ctx.event) {
			logDiagnostic("Actively closing TCP connection");
			auto fd = m_ctx.socketfd;

			scope (exit) () @trusted {
				version(Windows) shutdown(m_ctx.socketfd, SD_SEND);
				else shutdown(m_ctx.socketfd, SHUT_WR);
				if (m_ctx.event) bufferevent_free(m_ctx.event);
				logTrace("...socket %d closed.", fd);
			} ();

			m_ctx.shutdown = true;
			() @trusted {
				bufferevent_setwatermark(m_ctx.event, EV_WRITE, 1, 0);
				bufferevent_flush(m_ctx.event, EV_WRITE, bufferevent_flush_mode.BEV_FINISHED);
			} ();
			logTrace("Closing socket %d...", fd);
			auto buf = () @trusted { return bufferevent_get_output(m_ctx.event); } ();
			while (m_ctx.event && () @trusted { return evbuffer_get_length(buf); } () > 0)
				m_ctx.core.yieldForEvent();
		}
	}

	/// The 'connected' status of this connection
	@property bool connected() const { return m_ctx !is null && m_ctx.state == ConnectionState.open && m_ctx.event !is null; }

	@property bool empty() { return leastSize == 0; }

	@property ulong leastSize()
	{
		if (!m_ctx || !m_ctx.event || m_ctx.shutdown) return 0;
		if (m_readBuffer.length) {
			checkReader();
			return m_readBuffer.length;
		}
		acquireReader();
		scope(exit) releaseReader();
		fillReadBuffer(true, false);
		return m_readBuffer.length;
	}

	@property bool dataAvailableForRead()
	{
		if (!m_ctx || !m_ctx.event) return false;
		checkReader();
		if (!m_readBuffer.length)
			fillReadBuffer(false);
		return m_readBuffer.length > 0;
	}

	@property string peerAddress() const { return m_peerAddress; }

	const(ubyte)[] peek()
	{
		if (!m_ctx || !m_ctx.event) return null;
		checkReader();
		if (!m_readBuffer.length)
			fillReadBuffer(false);
		return m_readBuffer.peek();
	}

	void skip(ulong count)
	{
		checkConnected(false);

		if (m_readBuffer.length >= count) {
			checkReader();
			m_readBuffer.popFrontN(cast(size_t)count);
			if (m_readBuffer.empty) m_readBuffer.clear(); // start filling at index 0 again
			return;
		}

		acquireReader();
		scope(exit) releaseReader();

		while (true) {
			auto nbytes = min(count, m_readBuffer.length);
			m_readBuffer.popFrontN(nbytes);
			if (m_readBuffer.empty) m_readBuffer.clear(); // start filling at index 0 again
			count -= nbytes;

			if (!count) break;

			fillReadBuffer(true);
			checkConnected(false);
		}
	}

	/** Reads as many bytes as 'dst' can hold.
	*/
	size_t read(scope ubyte[] dst, IOMode)
	{
		checkConnected(false);

		if (m_readBuffer.length >= dst.length) {
			checkReader();
			m_readBuffer.read(dst);
			if (m_readBuffer.empty) m_readBuffer.clear(); // start filling at index 0 again
			return dst.length;
		}

		acquireReader();
		scope(exit) releaseReader();

		size_t len = dst.length;

		while (true) {
			auto nbytes = min(dst.length, m_readBuffer.length);
			m_readBuffer.read(dst[0 .. nbytes]);
			if (m_readBuffer.empty) m_readBuffer.clear(); // start filling at index 0 again
			dst = dst[nbytes .. $];

			if (!dst.length) break;

			fillReadBuffer(true);
			checkConnected(false);
		}
		logTrace("read data");

		return len;
	}

	bool waitForData(Duration timeout)
	{
		if (timeout == 0.seconds)
			logDebug("Warning: use Duration.max as an argument to waitForData() to wait infinitely, not 0.seconds.");

		if (dataAvailableForRead) return true;
		if (!m_ctx || m_ctx.state != ConnectionState.open) return false;

		acquireReader();
		scope(exit) releaseReader();
		m_timeout_triggered = false;

		if (timeout != 0.seconds && timeout != Duration.max) { // 0.seconds is for compatibility with old code
			assert(timeout.total!"seconds"() <= int.max, "Timeouts must not be larger than int.max seconds!");
			timeval t = timeout.toTimeVal();
			logTrace("add timeout event with %d/%d", t.tv_sec, t.tv_usec);
			() @trusted { event_add(m_waitDataEvent, &t); } ();
		}

		logTrace("wait for data");
		while (m_ctx && m_ctx.event) {
			if (m_readBuffer.length) return true;
			if (m_ctx.state != ConnectionState.open) return false;
			try {
				if (fillReadBuffer(true, false, true))
					return false;
			} catch (Exception e) {
				logDiagnostic("Connection error during waitForData: %s", e.msg);
			}
		}

		return false;
	}

	alias write = Stream.write;

	/** Writes the given byte array.
	*/
	size_t write(in ubyte[] bytes, IOMode)
	{
		checkConnected();
		acquireWriter();
		scope(exit) releaseWriter();

		if (!bytes.length) return 0;
		//logTrace("evbuffer_add (fd %d): %s", m_ctx.socketfd, bytes);
		//logTrace("evbuffer_add (fd %d): <%s>", m_ctx.socketfd, cast(string)bytes);
		logTrace("evbuffer_add (fd %d): %d B", m_ctx.socketfd, bytes.length);
		auto outbuf = () @trusted { return bufferevent_get_output(m_ctx.event); } ();
		if (() @trusted { return bufferevent_write(m_ctx.event, cast(char*)bytes.ptr, bytes.length); } () != 0 )
			throw new Exception("Failed to write data to buffer");

		// wait for the data to be written up the the low watermark
		while (() @trusted { return evbuffer_get_length(outbuf); } () > 4096) {
			rawYield();
			checkConnected();
		}

		return bytes.length;
	}

	/** Causes any buffered data to be written.
	*/
	void flush()
	{
		checkConnected();
		acquireWriter();
		scope(exit) releaseWriter();
		logTrace("bufferevent_flush");
		() @trusted { bufferevent_flush(m_ctx.event, EV_WRITE, bufferevent_flush_mode.BEV_NORMAL); } ();
	}

	void finalize()
	{
		flush();
	}

	private bool fillReadBuffer(bool block, bool throw_on_fail = true, bool wait_for_timeout = false)
	@safe {
		if (m_readBuffer.length) return false;
		m_readBuffer.clear();
		assert(m_readBuffer.peekDst.length > 0);
		while (m_ctx && m_ctx.event) {
			auto nbytes = () @trusted { return bufferevent_read(m_ctx.event, m_readBuffer.peekDst.ptr, m_readBuffer.peekDst.length); } ();
			m_readBuffer.putN(nbytes);
			if (m_readBuffer.length || !block) break;
			if (throw_on_fail) checkConnected(false);
			else if (!m_ctx || !m_ctx.event) return false;
			else if (m_ctx.state != ConnectionState.open
				&& () @trusted { return evbuffer_get_length(bufferevent_get_input(m_ctx.event)); } () == 0)
					return false;
			if (wait_for_timeout && m_timeout_triggered) return true;
			m_ctx.core.yieldForEvent();
		}
		return false;
	}

	private void checkReader() @safe { assert(m_ctx.readOwner == Task(), "Acquiring reader of already owned connection."); }
	private void acquireReader() @safe { checkReader(); m_ctx.readOwner = Task.getThis(); }
	private void releaseReader() @safe { if (!m_ctx) return; assert(m_ctx.readOwner == Task.getThis(), "Releasing reader of unowned connection."); m_ctx.readOwner = Task(); }

	private void acquireWriter() @safe { assert(m_ctx.writeOwner == Task(), "Acquiring writer of already owned connection."); m_ctx.writeOwner = Task.getThis(); }
	private void releaseWriter() @safe { if (!m_ctx) return; assert(m_ctx.writeOwner == Task.getThis(), "Releasing reader of already unowned connection."); m_ctx.writeOwner = Task(); }

	private void checkConnected(bool write = true)
	@safe {
		enforce(m_ctx !is null, "Operating on closed TCPConnection.");
		if (m_ctx.event is null) {
			cleanup();
			throw new Exception(format("Connection error while %s TCPConnection.", write ? "writing to" : "reading from"));
		}
		if (m_ctx.state == ConnectionState.activeClose) throw new Exception("Connection was actively closed.");
		enforce (!write || m_ctx.state == ConnectionState.open, "Remote hung up while writing to TCPConnection.");
		if (!write && m_ctx.state == ConnectionState.passiveClose) {
			auto buf = () @trusted { return bufferevent_get_input(m_ctx.event); } ();
			auto data_left = m_readBuffer.length > 0 || () @trusted { return evbuffer_get_length(buf); } () > 0;
			enforce(data_left, "Remote hung up while reading from TCPConnection.");
		}
	}

	private void cleanup()
	@safe {
		() @trusted {
			event_free(m_waitDataEvent);
			TCPContextAlloc.free(m_ctx);
		} ();
		m_ctx = null;
	}
}

final class Libevent2TCPListener : TCPListener {
@safe:

	private {
		TCPContext*[] m_ctx;
		NetworkAddress m_bindAddress;
	}

	this(NetworkAddress bind_address)
	{
		m_bindAddress = bind_address;
	}

	@property NetworkAddress bindAddress()
	{
		return m_bindAddress;
	}

	void addContext(TCPContext* ctx)
	{
		synchronized(this) m_ctx ~= ctx;
	}

	void stopListening()
	{
		synchronized(this)
		{
			foreach (ctx; m_ctx) () @trusted {
				event_free(ctx.listenEvent);
				evutil_closesocket(ctx.socketfd);
				TCPContextAlloc.free(ctx);
			} ();
			m_ctx = null;
		}
	}
}


/**************************************************************************************************/
/* Private types                                                                                  */
/**************************************************************************************************/

package struct TCPContext
{
	@safe:

	this(DriverCore c, event_base* evbase, int sock, bufferevent* evt, NetworkAddress bindaddr, NetworkAddress peeraddr){
		core = c;
		eventLoop = evbase;
		socketfd = sock;
		event = evt;
		local_addr = bindaddr;
		remote_addr = peeraddr;
	}

	this(DriverCore c, event_base* evbase, int sock, bufferevent* evt){
		core = c;
		eventLoop = evbase;
		socketfd = sock;
		event = evt;
	}

	~this()
	{
		magic__ = 0;
	}

	void checkForException() {
		if (auto ex = this.exception) {
			this.exception = null;
			throw ex;
		}
	}

	enum MAGIC = 0x1F3EC272;
	uint magic__ = MAGIC;
	DriverCore core;
	event_base* eventLoop;
	void delegate(TCPConnection conn) connectionCallback;
	bufferevent* event;
	deimos.event2.event_struct.event* listenEvent;
	NetworkAddress local_addr;
	NetworkAddress remote_addr;
	bool shutdown = false;
	int socketfd = -1;
	int status = 0;
	const(char)* statusMessage;
	Task readOwner;
	Task writeOwner;
	Exception exception; // set during onSocketEvent calls that were emitted synchronously
	TCPListenOptions listenOptions;
	ConnectionState state;
}
alias TCPContextAlloc = FreeListObjectAlloc!(TCPContext, false, true);

package enum ConnectionState {
	open,         // connection CTR and CTS
	activeClose,  // TCPConnection.close() was called
	passiveClose, // remote has hung up
}

/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

package nothrow extern(C)
{
	version (VibeDebugCatchAll) alias UncaughtException = Throwable;
	else alias UncaughtException = Exception;

	// should be a nested static struct in onConnect, but that triggers an ICE in ldc2-0.14.0
	private extern(D) struct ClientTask {
		TCPContext* listen_ctx;
		NetworkAddress bind_addr;
		NetworkAddress remote_addr;
		int sockfd;
		TCPListenOptions options;

		void execute()
		{
			assert(sockfd > 0);
			if( evutil_make_socket_nonblocking(sockfd) ){
				logError("Error setting non-blocking I/O on an incoming connection.");
			}

			auto eventloop = getThreadLibeventEventLoop();
			auto drivercore = getThreadLibeventDriverCore();

			// Initialize a buffered I/O event
			auto buf_event = bufferevent_socket_new(eventloop, sockfd, bufferevent_options.BEV_OPT_CLOSE_ON_FREE);
			if( !buf_event ){
				logError("Error initializing buffered I/O event for fd %d.", sockfd);
				return;
			}

			auto client_ctx = TCPContextAlloc.alloc(drivercore, eventloop, sockfd, buf_event, bind_addr, remote_addr);
			assert(client_ctx.event !is null, "event is null although it was just != null?");
			bufferevent_setcb(buf_event, &onSocketRead, &onSocketWrite, &onSocketEvent, client_ctx);
			if( bufferevent_enable(buf_event, EV_READ|EV_WRITE) ){
				bufferevent_free(buf_event);
				TCPContextAlloc.free(client_ctx);
				logError("Error enabling buffered I/O event for fd %d.", sockfd);
				return;
			}

			assert(client_ctx.event !is null, "Client task called without event!?");
			if (options & TCPListenOptions.disableAutoClose) {
				auto conn = new Libevent2TCPConnection(client_ctx);
				assert(conn.connected, "Connection closed directly after accept?!");
				logDebug("start task (fd %d).", client_ctx.socketfd);
				try {
					listen_ctx.connectionCallback(conn);
					logDebug("task out (fd %d).", client_ctx.socketfd);
				} catch (Exception e) {
					logWarn("Handling of connection failed: %s", e.msg);
					logDiagnostic("%s", e.toString().sanitize);
				} finally {
					logDebug("task finished.");
					FreeListObjectAlloc!ClientTask.free(&this);
				}
			} else {
				auto conn = FreeListRef!Libevent2TCPConnection(client_ctx);
				assert(conn.connected, "Connection closed directly after accept?!");
				logDebug("start task (fd %d).", client_ctx.socketfd);
				try {
					listen_ctx.connectionCallback(conn);
					logDebug("task out (fd %d).", client_ctx.socketfd);
				} catch (Exception e) {
					logWarn("Handling of connection failed: %s", e.msg);
					logDiagnostic("%s", e.toString().sanitize);
				} finally {
					logDebug("task finished.");
					FreeListObjectAlloc!ClientTask.free(&this);
					conn.close();
				}
			}
		}
	}

	void onConnect(evutil_socket_t listenfd, short evtype, void *arg)
	{
		logTrace("connect callback");
		auto ctx = cast(TCPContext*)arg;
		assert(ctx.magic__ == TCPContext.MAGIC);

		if( !(evtype & EV_READ) ){
			logError("Unknown event type in connect callback: 0x%hx", evtype);
			return;
		}

		try {
			// Accept and configure incoming connections (up to 10 connections in one go)
			foreach( i; 0 .. 10 ){
				logTrace("accept");
				assert(listenfd < int.max, "Listen socket descriptor >= int.max?!");
				sockaddr_in6 remote_addr;
				socklen_t addrlen = remote_addr.sizeof;
				auto sockfd_raw = accept(cast(int)listenfd, cast(sockaddr*)&remote_addr, &addrlen);
				logDebug("FD: %s", sockfd_raw);
				static if (typeof(sockfd_raw).max > int.max) assert(sockfd_raw <= int.max || sockfd_raw == ~0);
				auto sockfd = cast(int)sockfd_raw;
				logTrace("accepted %d", sockfd);
				if (sockfd == -1) {
					version(Windows) auto err = evutil_socket_geterror(sockfd);
					else auto err = errno;
					if( err != EWOULDBLOCK && err != EAGAIN && err != 0 ){
						version(Windows)
							logError("Error accepting an incoming connection: %s", to!string(evutil_socket_error_to_string(err)));
						else
							logError("Error accepting an incoming connection: %d", err);
					}
					break;
				}

				auto task = FreeListObjectAlloc!ClientTask.alloc();
				task.listen_ctx = ctx;
				task.bind_addr = ctx.local_addr;
				*cast(sockaddr_in6*)task.remote_addr.sockAddr = remote_addr;
				task.sockfd = sockfd;
				task.options = ctx.listenOptions;

				runTask(&task.execute);
			}
		} catch (UncaughtException e) {
			logWarn("Got exception while accepting new connections: %s", e.msg);
			try logDebug("Full error: %s", e.toString().sanitize());
			catch (Throwable) {}
		}

		logTrace("handled incoming connections...");
	}

	void onSocketRead(bufferevent *buf_event, void *arg)
	{
		auto ctx = cast(TCPContext*)arg;
		assert(ctx.magic__ == TCPContext.MAGIC);
		logTrace("socket %d read event!", ctx.socketfd);

		auto f = ctx.readOwner;
		try {
			if (f && f.running && !ctx.core.isScheduledForResume(f))
				ctx.core.resumeTask(f);
		} catch (UncaughtException e) {
			logWarn("Got exception when resuming task onSocketRead: %s", e.msg);
		}
	}

	void onSocketWrite(bufferevent *buf_event, void *arg)
	{
		try {
			auto ctx = cast(TCPContext*)arg;
			assert(ctx.magic__ == TCPContext.MAGIC);
			assert(ctx.event is buf_event, "Write event on bufferevent that does not match the TCPContext");
			logTrace("socket %d write event (%s)!", ctx.socketfd, ctx.shutdown);
			if (ctx.writeOwner != Task.init && ctx.writeOwner.running && !ctx.core.isScheduledForResume(ctx.writeOwner)) {
				bufferevent_flush(buf_event, EV_WRITE, bufferevent_flush_mode.BEV_FLUSH);
				ctx.core.resumeTask(ctx.writeOwner);
			}
		} catch (UncaughtException e) {
			logWarn("Got exception when resuming task onSocketRead: %s", e.msg);
		}
	}

	void onSocketEvent(bufferevent *buf_event, short status, void *arg)
	{
		try {
			auto ctx = cast(TCPContext*)arg;
			assert(ctx.magic__ == TCPContext.MAGIC);
			ctx.status = status;
			logDebug("Socket event on fd %d: %d (%s vs %s)", ctx.socketfd, status, cast(void*)buf_event, cast(void*)ctx.event);
			assert(ctx.event is buf_event, "Status event on bufferevent that does not match the TCPContext");

			Exception ex;
			bool free_event = false;

			string errorMessage;
			if (status & BEV_EVENT_EOF) {
				logDebug("Connection was closed by remote peer (fd %d).", ctx.socketfd);
				if (ctx.state != ConnectionState.activeClose)
					ctx.state = ConnectionState.passiveClose;
				evbuffer* buf = bufferevent_get_input(buf_event);
				if (evbuffer_get_length(buf) == 0) free_event = true;
			} else if (status & BEV_EVENT_TIMEOUT) {
				logDebug("Remote host on fd %d timed out.", ctx.socketfd);
				free_event = true;
			} else if (status & BEV_EVENT_ERROR) {
				//auto msg = format("Error %s socket %s",
				//	(status & BEV_EVENT_READING) ? "reading from" : (status & BEV_EVENT_WRITING) ? "writing to" : "on",
				//	ctx.socketfd);
				//ex = new SystemSocketException(msg);
				ctx.statusMessage = evutil_socket_error_to_string(EVUTIL_SOCKET_ERROR());
				free_event = true;
			}

			if (free_event) {
				bufferevent_free(buf_event);
				ctx.event = null;
			}

			ctx.core.eventException = ex;

			// ctx can be destroyed after resuming the reader, so get everything that is required from it first
			auto reader = ctx.readOwner;
			auto writer = ctx.writeOwner;
			auto core = ctx.core;

			if (ex && (reader && reader.fiber.state == Fiber.State.EXEC || writer && writer.fiber.state == Fiber.State.EXEC))
				ctx.exception = ex;

			if (writer && writer.running && writer.fiber.state != Fiber.State.EXEC) {
				logTrace("resuming corresponding write task%s...", ex is null ? "" : " with exception");
				core.resumeTask(writer, ex);
			}

			if (reader && writer != reader && reader.running && !core.isScheduledForResume(reader) && reader.fiber.state != Fiber.State.EXEC) {
				logTrace("resuming corresponding read task%s...", ex is null ? "" : " with exception");
				core.resumeTask(reader, ex);
			}
		} catch (UncaughtException e) {
			logWarn("Got exception when resuming task onSocketEvent: %s", e.msg);
			try logDiagnostic("Full error: %s", e.toString().sanitize); catch (Throwable) {}
		}
	}

	private extern(C) void onTimeout(evutil_socket_t, short events, void* userptr)
	{
		try {
			logTrace("data wait timeout");
			auto conn = cast(Libevent2TCPConnection)userptr;
			conn.m_timeout_triggered = true;
			if (conn.m_ctx) {
				if (conn.m_ctx.readOwner) conn.m_ctx.core.resumeTask(conn.m_ctx.readOwner);
			} else logDebug("waitForData timeout after connection was closed!");
		} catch (UncaughtException e) {
			logWarn("Exception onTimeout: %s", e.msg);
		}
	}
}

/// private
package void removeFromArray(T)(ref T[] array, T item)
{
	foreach( i; 0 .. array.length )
		if( array[i] is item ){
			array = array[0 .. i] ~ array[i+1 .. $];
			return;
		}
}

}
