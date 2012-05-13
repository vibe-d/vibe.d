/**
	libevent based driver

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libevent2_tcp;

public import vibe.core.core;
public import vibe.crypto.ssl;
public import vibe.stream.stream;

import vibe.core.log;

import intf.event2.buffer;
import intf.event2.bufferevent;
import intf.event2.bufferevent_ssl;
import intf.event2.event;
import intf.event2.util;

import std.algorithm;
import std.exception;
import std.conv;
import std.string;

import core.stdc.errno;
import core.thread;
import core.sys.posix.netinet.tcp;


private {
	version(Windows){
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

package class Libevent2TcpConnection : TcpConnection {
	private {
		bufferevent* m_baseEvent;
		bufferevent* m_event;
		bufferevent* m_sslEvent;
		bool m_timeout_triggered;
		TcpContext* m_ctx;
		Fiber m_fiber;
		string m_peerAddress;
	}
	
	this(TcpContext* ctx)
	{
		m_baseEvent = ctx.event;
		m_event = ctx.event;
		m_fiber = Fiber.getThis();
		m_ctx = ctx;

		char buf[64];
		if( ctx.remote_addr4.sin_family == AF_INET )
			evutil_inet_ntop(AF_INET, &ctx.remote_addr4.sin_addr, buf.ptr, buf.length);
		else
			evutil_inet_ntop(AF_INET6, &ctx.remote_addr6.sin6_addr, buf.ptr, buf.length);
		m_peerAddress = to!string(buf.ptr).idup;
	}
	
	~this()
	{
		//evbuffer_free(m_buffer);
	}
	
	/// Enables/disables Nagle's algorithm for this connection (enabled by default).
	@property void tcpNoDelay(bool enabled)
	{
		auto fd = bufferevent_getfd(m_baseEvent);
		ubyte opt = enabled;
		assert(fd <= int.max);
		setsockopt(cast(int)fd, IPPROTO_TCP, TCP_NODELAY, &opt, opt.sizeof);
	}

	/**
		Makes the current task the sole owner of this connection.

		All events specific to this connection will go to the current task afterwards.
		Note that any other method of TcpConnection may only be called after
		acquire() has been called, if the connection was not already owned by the task.
	*/
	void acquire()
	{
		m_ctx.task = Fiber.getThis();
	}

	/// Makes this connection unowned so that no events are handled anymore.
	void release()
	{
		m_ctx.task = null;
	}
	
	/// Closes the connection.
	void close()
	{
		checkConnected();
		auto fd = bufferevent_getfd(m_baseEvent);
		m_ctx.shutdown = true;
		bufferevent_flush(m_event, EV_WRITE, bufferevent_flush_mode.BEV_FLUSH);
		bufferevent_flush(m_event, EV_WRITE, bufferevent_flush_mode.BEV_FINISHED);
		bufferevent_setwatermark(m_event, EV_WRITE, 1, 0);
		logTrace("Closing socket %d...", fd);
	}

	/// The 'connected' status of this connection
	@property bool connected() const { return m_ctx.event !is null; }

	@property bool empty() { return leastSize == 0; }

	@property ulong leastSize()
	{
		size_t len;
		auto buf = bufferevent_get_input(m_event);
		while( (len = evbuffer_get_length(buf)) == 0 ){
			if( !connected ) return 0;
			logTrace("leastSize waiting for new data.");
			m_ctx.core.yieldForEvent();
		}
		return len;
	}

	@property bool dataAvailableForRead()
	{
		size_t len;
		auto buf = bufferevent_get_input(m_event);
		return evbuffer_get_length(buf) > 0;
	}

	@property string peerAddress() const { return m_peerAddress; }

	/** Initiates an SSL encrypted connection.

		After this call, all subsequent reads/writes will be encrypted.
	*/
	void initiateSSL(SSLContext ctx)
	{
		checkConnected();
		assert(m_event is m_baseEvent);
		auto client_ctx = ctx.createClientCtx();
		int options = bufferevent_options.BEV_OPT_CLOSE_ON_FREE;
		auto state = bufferevent_ssl_state.BUFFEREVENT_SSL_CONNECTING;
		m_sslEvent = bufferevent_openssl_filter_new(m_ctx.eventLoop, m_baseEvent, client_ctx, state, options);
		assert(m_sslEvent !is null);
		bufferevent_setcb(m_sslEvent, &onSocketRead, null, null, m_ctx);
		bufferevent_enable(m_sslEvent, EV_READ|EV_WRITE);
		m_event = m_sslEvent;
	}

	/** Accepts an SSL intiation from the remote peer.

		After this call, all subsequent reads/writes will be encrypted.
	*/
	void acceptSSL(SSLContext ctx)
	{
		checkConnected();
		assert(m_event is m_baseEvent);
		auto client_ctx = ctx.createClientCtx();
		int options = bufferevent_options.BEV_OPT_CLOSE_ON_FREE;
		auto state = bufferevent_ssl_state.BUFFEREVENT_SSL_ACCEPTING;
		m_sslEvent = bufferevent_openssl_filter_new(m_ctx.eventLoop, m_baseEvent, client_ctx, state, options);
		assert(m_sslEvent !is null);
		bufferevent_setcb(m_sslEvent, &onSocketRead, null, null, m_ctx);
		bufferevent_enable(m_sslEvent, EV_READ|EV_WRITE);
		m_event = m_sslEvent;
	}
	

	/** Reads as many bytes as 'dst' can hold.
	*/
	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			checkConnected();
			logTrace("evbuffer_read %d bytes (fd %d)", dst.length, bufferevent_getfd(m_baseEvent));
			auto nbytes = bufferevent_read(m_event, dst.ptr, dst.length);
			logTrace(" .. got %d bytes", nbytes);
			dst = dst[nbytes .. $];
			
			if( dst.length == 0 ) break;

			m_ctx.core.yieldForEvent();
		}
		logTrace("read data");
	}
	
	/** Reads one line terminated by CRLF.
	*/
	ubyte[] readLine(size_t max_bytes = 0, string linesep = "\r\n")
	{
		import core.stdc.stdlib;

		evbuffer_eol_style style;
		switch( linesep ){
			default: assert(false, "Unsupported line style.");
			case "\r\n": style = evbuffer_eol_style.EVBUFFER_EOL_CRLF_STRICT; break;
			case "\n": style = evbuffer_eol_style.EVBUFFER_EOL_LF; break;
		}

		size_t nbytes;
		char* ln;
		while(true){
			checkConnected();
			logTrace("evbuffer_readln (fd %d)", bufferevent_getfd(m_baseEvent));
			ln = evbuffer_readln(bufferevent_get_input(m_event), &nbytes, style);
			if( ln ) break;
			
			enforce(!max_bytes || evbuffer_get_length(bufferevent_get_input(m_event)) < max_bytes,
				"Line is too long!");

			m_ctx.core.yieldForEvent();
		}
		
		auto ret = (cast(ubyte*)ln)[0 .. nbytes];
		logTrace("TCPConnection.readline return data (%d)", nbytes);
		return ret;
	}

	ubyte[] readAll(size_t max_bytes = 0) { return readAllDefault(max_bytes); }


	bool waitForData(int secs) {
		if( dataAvailableForRead ) return true;
		m_timeout_triggered = false;
		event* timeout = event_new(m_ctx.eventLoop, -1, 0, &onTimeout, cast(void*)this);
		timeval t;
		t.tv_sec = secs;
		event_add(timeout, &t);
		while( connected ) {
			if( dataAvailableForRead || m_timeout_triggered ) break;
			rawYield();
		}
		event_del(timeout);
		event_free(timeout);
		return !m_timeout_triggered;
	}

	alias Stream.write write;

	/** Writes the given byte array.
	*/
	void write(in ubyte[] bytes, bool do_flush = true)
	{	
		checkConnected();
		//logTrace("evbuffer_add (fd %d): %s", bufferevent_getfd(m_baseEvent), bytes);
		//logTrace("evbuffer_add (fd %d): <%s>", bufferevent_getfd(m_baseEvent), cast(string)bytes);
		logTrace("evbuffer_add (fd %d): %d B", bufferevent_getfd(m_baseEvent), bytes.length);
		if( bufferevent_write(m_event, cast(char*)bytes.ptr, bytes.length) != 0 )
			throw new Exception("Failed to write data to buffer");
			
		if( do_flush ) flush();
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}
		
	/** Causes any buffered data to be written.
	*/
	void flush()
	{
		checkConnected();
		logTrace("bufferevent_flush");
		bufferevent_flush(m_event, EV_WRITE, bufferevent_flush_mode.BEV_NORMAL);
	}

	void finalize()
	{
		flush();
	}

	private void checkConnected()
	{
		enforce(m_ctx.event !is null, "Operating on closed TCPConnection.");
		enforce(m_ctx.task is Fiber.getThis(), "Operating on TcpConnection owned by a different fiber!");
	}
}


/**************************************************************************************************/
/* Private types                                                                                  */
/**************************************************************************************************/

package struct TcpContext
{
	this(DriverCore c, event_base* evbase, void delegate(TcpConnection conn) cb, int sock, bufferevent* evt, sockaddr_in6 peeraddr){
		core = c;
		eventLoop = evbase;
		connectionCallback = cb;
		socketfd = sock;
		event = evt;
		remote_addr6 = peeraddr;
	}

	this(DriverCore c, event_base* evbase, void delegate(TcpConnection conn) cb, int sock, bufferevent* evt, sockaddr_in peeraddr){
		core = c;
		eventLoop = evbase;
		connectionCallback = cb;
		socketfd = sock;
		event = evt;
		remote_addr4 = peeraddr;
	}

	this(DriverCore c, event_base* evbase, void delegate(TcpConnection conn) cb, int sock, bufferevent* evt){
		core = c;
		eventLoop = evbase;
		connectionCallback = cb;
		socketfd = sock;
		event = evt;
	}

	DriverCore core;
	event_base* eventLoop;
	void delegate(TcpConnection conn) connectionCallback;
	bufferevent* event;
	union {
		sockaddr_in6 remote_addr6;
		sockaddr_in remote_addr4;
	}
	bool shutdown = false;
	int socketfd = -1;
	int status = 0;
	Fiber task;
}


/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

package extern(C)
{
	void onConnect(evutil_socket_t listenfd, short evtype, void *arg)
	{
		auto ctx = cast(TcpContext*)arg;

		sockaddr_in6 remote_addr;
		socklen_t addrlen = remote_addr.sizeof;
		int sockfd;
		int i;

		if( !(evtype & EV_READ) ){
			logError("Unknown event type in connect callback: 0x%hx", evtype);
			return;
		}

		// NOTE: we need to return the delegate from a function because
		//       otherwise multiple iterations of the for loop will share the
		//       same stack frame.
		static void delegate() client_task(TcpContext* listen_ctx, TcpContext* client_ctx)
		{
			return {
				client_ctx.task = Fiber.getThis();
				auto conn = new Libevent2TcpConnection(client_ctx);
				assert(conn.connected);
				logDebug("start task (fd %d).", client_ctx.socketfd);
				try {
					listen_ctx.connectionCallback(conn);
					logDebug("task out (fd %d).", client_ctx.socketfd);
				} catch( Exception e ){
					logWarn("Handling of connection failed: %s", e.msg);
					logDebug("%s", e.toString());
				}
				client_ctx.shutdown = true;
				if( client_ctx.event ){
					logTrace("initiate lazy active disconnect (fd %d)", client_ctx.socketfd);
					bufferevent_flush(client_ctx.event, EV_WRITE, bufferevent_flush_mode.BEV_FLUSH);
					bufferevent_flush(client_ctx.event, EV_WRITE, bufferevent_flush_mode.BEV_FINISHED);
					bufferevent_setwatermark(client_ctx.event, EV_WRITE, 1, 0);
				}
				logDebug("task finished.");
			};
		}


		// Accept and configure incoming connections (up to 10 connections in one go)
		for(i = 0; i < 10; i++) {
			logTrace("accept");
			assert(listenfd < int.max);
			sockfd = accept(cast(int)listenfd, cast(sockaddr*)&remote_addr, &addrlen);
			logTrace("accepted %d", sockfd);
			if(sockfd < 0) {
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

			if( evutil_make_socket_nonblocking(sockfd) ){
				logError("Error setting non-blocking I/O on an incoming connection.");
			}

			// Initialize a buffered I/O event
			auto buf_event = bufferevent_socket_new(ctx.eventLoop, sockfd, bufferevent_options.BEV_OPT_CLOSE_ON_FREE);
			if( !buf_event ){
				logError("Error initializing buffered I/O event for fd %d.", sockfd);
				return;
			}
			
			auto cctx = new TcpContext(ctx.core, ctx.eventLoop, null, sockfd, buf_event, remote_addr);
			bufferevent_setcb(buf_event, &onSocketRead, &onSocketWrite, &onSocketEvent, cctx);
			timeval toread = {tv_sec: 60, tv_usec: 0};
			bufferevent_set_timeouts(buf_event, &toread, null);
			if( bufferevent_enable(buf_event, EV_READ|EV_WRITE) ){
				logError("Error enabling buffered I/O event for fd %d.", sockfd);
				return;
			}
			
			runTask(client_task(ctx, cctx));
		}
		logTrace("handled incoming connections...");
	}

	void onSocketRead(bufferevent *buf_event, void *arg)
	{
		auto ctx = cast(TcpContext*)arg;
		logTrace("socket %d read event!", ctx.socketfd);

		auto f = ctx.task;
		if( f && f.state != Fiber.State.TERM )
			ctx.core.resumeTask(f);
	}

	void onSocketWrite(bufferevent *buf_event, void *arg)
	{
		auto ctx = cast(TcpContext*)arg;
		assert(ctx.event is buf_event);
		logTrace("socket %d write event (%s)!", ctx.socketfd, ctx.shutdown);
		if( ctx.shutdown ){
			version(Windows) shutdown(ctx.socketfd, SD_SEND);
			else shutdown(ctx.socketfd, SHUT_WR);
			bufferevent_free(buf_event);
			ctx.event = null;
		} else if( ctx.task && ctx.task.state != Fiber.State.TERM ){
			bufferevent_flush(buf_event, EV_WRITE, bufferevent_flush_mode.BEV_FLUSH);
			ctx.core.resumeTask(ctx.task);
		}
	}
		
	void onSocketEvent(bufferevent *buf_event, short status, void *arg)
	{
		auto ctx = cast(TcpContext*)arg;
		ctx.status = status;
		logDebug("Socket event on fd %d: %d", ctx.socketfd, status);
		assert(ctx.event is buf_event);
		
		bool free_event = false;
		
		if( status & BEV_EVENT_EOF ){
			logDebug("Connection was closed (fd %d).", ctx.socketfd);
			free_event = true;
		} else if( status & BEV_EVENT_TIMEOUT ){
			logDebug("Remote host on fd %d timed out.", ctx.socketfd);
			free_event = true;
		} else if( status & BEV_EVENT_ERROR ){
			version(Windows){
				logWarn("A socket error occurred on fd %d: %d (%s)", ctx.socketfd, status, to!string(evutil_socket_error_to_string(status)));
			} else {
				logWarn("A socket error occurred on fd %d: %d", ctx.socketfd, status);
			}
			free_event = true;
		}

		if( free_event || (status & BEV_EVENT_ERROR) ){	
			bufferevent_free(buf_event);
			ctx.event = null;
		}

		if( !ctx.shutdown && ctx.task && ctx.task.state != Fiber.State.TERM ){
			if( status & BEV_EVENT_ERROR ){
				logTrace("resuming corresponding task with exception...");
				ctx.core.resumeTask(ctx.task, new Exception("socket error "~to!string(status)));
			} else {
				logTrace("resuming corresponding task...");
				ctx.core.resumeTask(ctx.task);
			}
		}
	}

	private extern(C) void onTimeout(evutil_socket_t, short events, void* userptr)
	{
		auto conn = cast(Libevent2TcpConnection)userptr;
		conn.m_timeout_triggered = true;
		conn.m_ctx.core.resumeTask(conn.m_fiber);
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
