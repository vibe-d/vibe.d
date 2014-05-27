/**
	libevent based driver

	Copyright: © 2012-2014 RejectedSoftware e.K.
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
import vibe.utils.memory;

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
	version(Windows){
		import std.c.windows.winsock;
		enum EWOULDBLOCK = WSAEWOULDBLOCK;

		// make some neccessary parts of the socket interface public
		alias std.c.windows.winsock.in6_addr in6_addr;
		alias std.c.windows.winsock.INADDR_ANY INADDR_ANY;
		alias std.c.windows.winsock.IN6ADDR_ANY IN6ADDR_ANY;
	} else {
		alias core.sys.posix.netinet.in_.in6_addr in6_addr;	
		alias core.sys.posix.netinet.in_.in6addr_any IN6ADDR_ANY;	
		alias core.sys.posix.netinet.in_.INADDR_ANY INADDR_ANY;	
		alias core.sys.posix.netinet.tcp.TCP_NODELAY TCP_NODELAY;
	}
}

package final class Libevent2TCPConnection : TCPConnection {
	private {
		bool m_timeout_triggered;
		TCPContext* m_ctx;
		string m_peerAddress;
		ubyte[64] m_peekBuffer;
		bool m_tcpNoDelay = false;
		bool m_tcpKeepAlive = false;
		Duration m_readTimeout;
		char[64] m_peerAddressBuf;
		NetworkAddress m_localAddress, m_remoteAddress;
	}
	
	this(TCPContext* ctx)
	{
		m_ctx = ctx;

		assert(!amOwner());

		m_localAddress = ctx.local_addr;
		m_remoteAddress = ctx.remote_addr;

		void* ptr;
		if( ctx.remote_addr.family == AF_INET ) ptr = &ctx.remote_addr.sockAddrInet4.sin_addr;
		else ptr = &ctx.remote_addr.sockAddrInet6.sin6_addr;
		evutil_inet_ntop(ctx.remote_addr.family, ptr, m_peerAddressBuf.ptr, m_peerAddressBuf.length);
		m_peerAddress = cast(string)m_peerAddressBuf[0 .. m_peerAddressBuf.indexOf('\0')];

		bufferevent_setwatermark(m_ctx.event, EV_WRITE, 4096, 65536);
		bufferevent_setwatermark(m_ctx.event, EV_READ, 0, 65536);
	}
	
	/*~this()
	{
		//assert(m_ctx is null, "Leaking TCPContext because it has not been cleaned up and we are not allowed to touch the GC in finalizers..");
	}*/
	
	@property void tcpNoDelay(bool enabled)
	{
		m_tcpNoDelay = enabled;
		auto fd = m_ctx.socketfd;
		ubyte opt = enabled;
		assert(fd <= int.max, "Socket descriptor > int.max");
		setsockopt(cast(int)fd, IPPROTO_TCP, TCP_NODELAY, &opt, opt.sizeof);
	}
	@property bool tcpNoDelay() const { return m_tcpNoDelay; }

	@property void readTimeout(Duration v)
	{
		m_readTimeout = v;
		if( v == dur!"seconds"(0) ){
			bufferevent_set_timeouts(m_ctx.event, null, null);
		} else {
			assert(v.total!"seconds" <= int.max);
			timeval toread = {tv_sec: cast(int)v.total!"seconds", tv_usec: v.fracSec.usecs};
			bufferevent_set_timeouts(m_ctx.event, &toread, null);
		}
	}
	@property Duration readTimeout() const { return m_readTimeout; }

	@property void keepAlive(bool enable)
	{
		m_tcpKeepAlive = enable;
		auto fd = m_ctx.socketfd;
		ubyte opt = enable;
		assert(fd <= int.max, "Socket descriptor > int.max");
		setsockopt(cast(int)fd, SOL_SOCKET, SO_KEEPALIVE, &opt, opt.sizeof);
	}
	@property bool keepAlive() const { return m_tcpKeepAlive; }

	@property NetworkAddress localAddress() const { return m_localAddress; }
	@property NetworkAddress remoteAddress() const { return m_remoteAddress; }

	private void acquire()
	{
		assert(m_ctx, "Trying to acquire a closed TCP connection.");
		assert(m_ctx.readOwner == Task() && m_ctx.writeOwner == Task(), "Trying to acquire a TCP connection that is currently owned.");
		m_ctx.readOwner = m_ctx.writeOwner = Task.getThis();
	}

	private void release()
	{
		if( !m_ctx ) return;
		assert(m_ctx.readOwner != Task() && m_ctx.writeOwner != Task(), "Trying to release a TCP connection that is not owned.");
		assert(m_ctx.readOwner == Task.getThis() && m_ctx.readOwner == m_ctx.writeOwner, "Trying to release a foreign TCP connection.");
		m_ctx.readOwner = m_ctx.writeOwner = Task();
	}

	private bool amOwner()
	{
		return m_ctx !is null && m_ctx.readOwner != Task() && m_ctx.readOwner == Task.getThis() && m_ctx.readOwner == m_ctx.writeOwner;
	}
	
	/// Closes the connection.
	void close()
	{
		if (!m_ctx) return;
		acquire();

		scope (exit) {
			TCPContextAlloc.free(m_ctx);
			m_ctx = null;
		}

		if (m_ctx.event) {
			auto fd = m_ctx.socketfd;

			scope (exit) {
				version(Windows) shutdown(m_ctx.socketfd, SD_SEND);
				else shutdown(m_ctx.socketfd, SHUT_WR);
				if (m_ctx.event) bufferevent_free(m_ctx.event);
				logTrace("...socket %d closed.", fd);
			}

			m_ctx.shutdown = true;
			bufferevent_setwatermark(m_ctx.event, EV_WRITE, 1, 0);
			bufferevent_flush(m_ctx.event, EV_WRITE, bufferevent_flush_mode.BEV_FINISHED);
			logTrace("Closing socket %d...", fd);
			auto buf = bufferevent_get_output(m_ctx.event);
			while (m_ctx.event && evbuffer_get_length(buf) > 0)
				m_ctx.core.yieldForEvent();
		}
	}

	/// The 'connected' status of this connection
	@property bool connected() const { return m_ctx !is null && m_ctx.event !is null && !m_ctx.eof; }

	@property bool empty() { return leastSize == 0; }

	@property ulong leastSize()
	{
		if (!m_ctx || !m_ctx.event) return 0;
		acquireReader();
		scope(exit) releaseReader();
		auto inbuf = bufferevent_get_input(m_ctx.event);
		size_t len;
		while ((len = evbuffer_get_length(inbuf)) == 0) {
			if (!connected) {
				if (m_ctx) {
					if (m_ctx.event) bufferevent_free(m_ctx.event);
					TCPContextAlloc.free(m_ctx);
					m_ctx = null;
				}
				return 0;
			}
			logTrace("leastSize waiting for new data.");
			m_ctx.core.yieldForEvent();
		}
		return len;
	}

	@property bool dataAvailableForRead()
	{
		if (!m_ctx || !m_ctx.event) return false;
		acquireReader();
		scope(exit) releaseReader();
		auto inbuf = bufferevent_get_input(m_ctx.event);

		return evbuffer_get_length(inbuf) > 0;
	}

	@property string peerAddress() const { return m_peerAddress; }

	const(ubyte)[] peek()
	{
		if (!m_ctx || !m_ctx.event) return null;
		acquireReader();
		scope(exit) releaseReader();

		auto inbuf = bufferevent_get_input(m_ctx.event);
		evbuffer_iovec iovec;
		if (evbuffer_peek(inbuf, -1, null, &iovec, 1) == 0)
			return null;
		return (cast(ubyte*)iovec.iov_base)[0 .. iovec.iov_len];
	}

	/** Reads as many bytes as 'dst' can hold.
	*/
	void read(ubyte[] dst)
	{
		checkConnected(false);
		acquireReader();
		scope(exit) releaseReader();
		while (dst.length > 0) {
			checkConnected(false);
			logTrace("evbuffer_read %d bytes (fd %d)", dst.length, m_ctx.socketfd);
			auto nbytes = bufferevent_read(m_ctx.event, dst.ptr, dst.length);
			logTrace(" .. got %d bytes", nbytes);
			dst = dst[nbytes .. $];
			
			if( dst.length == 0 ) break;

			checkConnected(false);
			m_ctx.core.yieldForEvent();
		}
		logTrace("read data");
	}
	
	bool waitForData(Duration timeout)
	{
		if (!m_ctx || !m_ctx.event) return false;
		assert(m_ctx !is null);
		auto inbuf = bufferevent_get_input(m_ctx.event);
		if (evbuffer_get_length(inbuf) > 0) return true;
		if (m_ctx.eof) return false;
		
		acquireReader();
		scope(exit) releaseReader();
		m_timeout_triggered = false;
		event* evtmout = event_new(m_ctx.eventLoop, -1, 0, &onTimeout, cast(void*)this);
		timeval t;
		assert(timeout.total!"seconds"() <= int.max, "Timeouts must not be larger than int.max seconds!");
		t.tv_sec = cast(int)timeout.total!"seconds"();
		t.tv_usec = timeout.fracSec().usecs();
		logTrace("add timeout event with %d/%d", t.tv_sec, t.tv_usec);
		event_add(evtmout, &t);
		scope (exit) {
			event_del(evtmout);
			event_free(evtmout);
		}
		logTrace("wait for data");
		while (m_ctx && m_ctx.event) {
			if (evbuffer_get_length(inbuf) > 0) return true;
			if (m_timeout_triggered) {
				logTrace(" -> timeout = %s", m_timeout_triggered);
				return false;
			}
			try rawYield();
			catch (Exception e) {
				logDiagnostic("Connection error during waitForData: %s", e.toString());
			}
		}
		return false;
	}

	alias Stream.write write;

	/** Writes the given byte array.
	*/
	void write(in ubyte[] bytes)
	{
		checkConnected();
		acquireWriter();
		scope(exit) releaseWriter();

		if (!bytes.length) return;
		//logTrace("evbuffer_add (fd %d): %s", m_ctx.socketfd, bytes);
		//logTrace("evbuffer_add (fd %d): <%s>", m_ctx.socketfd, cast(string)bytes);
		logTrace("evbuffer_add (fd %d): %d B", m_ctx.socketfd, bytes.length);
		auto outbuf = bufferevent_get_output(m_ctx.event);
		if( bufferevent_write(m_ctx.event, cast(char*)bytes.ptr, bytes.length) != 0 )
			throw new Exception("Failed to write data to buffer");
		
		// wait for the data to be written up the the low watermark
		while (evbuffer_get_length(outbuf) > 4096) {
			rawYield();
			checkConnected();
		}
	}

	void write(InputStream stream, ulong nbytes = 0)
	{
		import vibe.core.drivers.threadedfile;
		version(none){ // causes a crash on Windows
			// special case sending of files
			if( auto fstream = cast(ThreadedFileStream)stream ){
				checkConnected();
				acquireWriter();
				scope(exit) releaseWriter();
				logInfo("Using sendfile! %s %s %s %s", fstream.fd, fstream.tell(), fstream.size, nbytes);
				fstream.takeOwnershipOfFD();
				auto buf = bufferevent_get_output(m_ctx.event);
				enforce(evbuffer_add_file(buf, fstream.fd, fstream.tell(), nbytes ? nbytes : fstream.size-fstream.tell()) == 0,
					"Failed to send file over TCP connection.");
				return;
			}
		}

		logTrace("writing stream %s %s", nbytes, stream.leastSize);
		writeDefault(stream, nbytes);
		logTrace("wrote stream %s", nbytes);
	}
		
	/** Causes any buffered data to be written.
	*/
	void flush()
	{
		checkConnected();
		acquireWriter();
		scope(exit) releaseWriter();
		logTrace("bufferevent_flush");
		bufferevent_flush(m_ctx.event, EV_WRITE, bufferevent_flush_mode.BEV_NORMAL);
	}

	void finalize()
	{
		flush();
	}

	private void acquireReader() { assert(m_ctx.readOwner == Task(), "Acquiring reader of already owned connection."); m_ctx.readOwner = Task.getThis(); }
	private void releaseReader() { if (!m_ctx) return; assert(m_ctx.readOwner == Task.getThis(), "Releasing reader of unowned connection."); m_ctx.readOwner = Task(); }

	private void acquireWriter() { assert(m_ctx.writeOwner == Task(), "Acquiring writer of already owned connection."); m_ctx.writeOwner = Task.getThis(); }
	private void releaseWriter() { if (!m_ctx) return; assert(m_ctx.writeOwner == Task.getThis(), "Releasing reader of already unowned connection."); m_ctx.writeOwner = Task(); }

	private void checkConnected(bool write = true)
	{
		enforce(m_ctx !is null, "Operating on closed TCPConnection.");
		if (m_ctx.event is null) {
			TCPContextAlloc.free(m_ctx);
			m_ctx = null;
			throw new Exception(format("Connection error while %s TCPConnection.", write ? "writing to" : "reading from"));
		}
		enforce (!write || !m_ctx.eof, "Remote hung up while writing to TCPConnection.");
		if (!write && m_ctx.eof) {
			auto buf = bufferevent_get_input(m_ctx.event);
			auto data_left = evbuffer_get_length(buf) > 0;
			enforce(data_left, "Remote hung up while reading from TCPConnection.");
		}
	}
}

final class Libevent2TCPListener : TCPListener {
	private {
		TCPContext*[] m_ctx;
	}

	void addContext(TCPContext* ctx)
	{
		synchronized(this) m_ctx ~= ctx;
	}

	void stopListening()
	{
		synchronized(this)
		{
			foreach (ctx; m_ctx) {
				event_free(ctx.listenEvent);
				evutil_closesocket(ctx.socketfd);
				TCPContextAlloc.free(ctx);
			}
			m_ctx = null;
		}
	}
}


/**************************************************************************************************/
/* Private types                                                                                  */
/**************************************************************************************************/

package struct TCPContext
{
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

	void checkForException() {
		if (auto ex = this.exception) {
			this.exception = null;
			throw ex;
		}
	}

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
	bool eof = false; // remomte has hung up
	Task readOwner;
	Task writeOwner;
	Exception exception; // set during onSocketEvent calls that were emitted synchronously
	TCPListenOptions listenOptions;
}
alias FreeListObjectAlloc!(TCPContext, false, true) TCPContextAlloc;


/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

package nothrow extern(C)
{
	version (VibeDebugCatchAll) alias UncaughtException = Throwable;
	else alias UncaughtException = Exception;

	void onConnect(evutil_socket_t listenfd, short evtype, void *arg)
	{
		logTrace("connect callback");
		auto ctx = cast(TCPContext*)arg;

		if( !(evtype & EV_READ) ){
			logError("Unknown event type in connect callback: 0x%hx", evtype);
			return;
		}

		static struct ClientTask {
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
					if (!(options & TCPListenOptions.disableAutoClose)) conn.close();
				}
			}
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
			catch {}
		}

		logTrace("handled incoming connections...");
	}

	void onSocketRead(bufferevent *buf_event, void *arg)
	{
		auto ctx = cast(TCPContext*)arg;
		logTrace("socket %d read event!", ctx.socketfd);

		auto f = ctx.readOwner;
		try {
			if (f && f.running)
				ctx.core.resumeTask(f);
		} catch (UncaughtException e) {
			logWarn("Got exception when resuming task onSocketRead: %s", e.msg);
		}
	}

	void onSocketWrite(bufferevent *buf_event, void *arg)
	{
		try {
			auto ctx = cast(TCPContext*)arg;
			assert(ctx.event is buf_event, "Write event on bufferevent that does not match the TCPContext");
			logTrace("socket %d write event (%s)!", ctx.socketfd, ctx.shutdown);
			if (ctx.writeOwner && ctx.writeOwner.running) {
				bufferevent_flush(buf_event, EV_WRITE, bufferevent_flush_mode.BEV_FLUSH);
			}
			if (ctx.writeOwner) ctx.core.resumeTask(ctx.writeOwner);
		} catch (UncaughtException e) {
			logWarn("Got exception when resuming task onSocketRead: %s", e.msg);
		}
	}
		
	void onSocketEvent(bufferevent *buf_event, short status, void *arg)
	{
		try {
			auto ctx = cast(TCPContext*)arg;
			ctx.status = status;
			logDebug("Socket event on fd %d: %d (%s vs %s)", ctx.socketfd, status, cast(void*)buf_event, cast(void*)ctx.event);
			assert(ctx.event is buf_event, "Status event on bufferevent that does not match the TCPContext");
	
			Exception ex;
			bool free_event = false;
			
			string errorMessage;
			if (status & BEV_EVENT_EOF) {
				logDebug("Connection was closed (fd %d).", ctx.socketfd);
				ctx.eof = true;
				evbuffer* buf = bufferevent_get_input(buf_event);
				if (evbuffer_get_length(buf) == 0) free_event = true;
			} else if (status & BEV_EVENT_TIMEOUT) {
				logDebug("Remote host on fd %d timed out.", ctx.socketfd);
				free_event = true;
			} else if (status & BEV_EVENT_ERROR) {
				auto msg = format("Error %s socket %s",
					(status & BEV_EVENT_READING) ? "reading from" : (status & BEV_EVENT_WRITING) ? "writing to" : "on",
					ctx.socketfd);
				ex = new SystemSocketException(msg);
				free_event = true;
			}

			if (free_event) {	
				bufferevent_free(buf_event);
				ctx.event = null;
			}

			ctx.core.eventException = ex;

			if (ctx.readOwner && ctx.readOwner.running) {
				logTrace("resuming corresponding task%s...", ex is null ? "" : " with exception");
				if (ctx.readOwner.fiber.state == Fiber.State.EXEC) ctx.exception = ex;
				else ctx.core.resumeTask(ctx.readOwner, ex);
			}
			if (ctx.writeOwner && ctx.writeOwner != ctx.readOwner && ctx.writeOwner.running) {
				logTrace("resuming corresponding task%s...", ex is null ? "" : " with exception");
				if (ctx.writeOwner.fiber.state == Fiber.State.EXEC) ctx.exception = ex;
				else ctx.core.resumeTask(ctx.writeOwner, ex);
			}
		} catch (UncaughtException e) {
			logWarn("Got exception when resuming task onSocketEvent: %s", e.msg);
			try logDiagnostic("Full error: %s", e.toString().sanitize); catch {}
		}
	}

	private extern(C) void onTimeout(evutil_socket_t, short events, void* userptr)
	{
		try {
			logTrace("data wait timeout");
			auto conn = cast(Libevent2TCPConnection)userptr;
			conn.m_timeout_triggered = true;
			if( conn.m_ctx ) conn.m_ctx.core.resumeTask(conn.m_ctx.readOwner);
			else logDebug("waitForData timeout after connection was closed!");
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
