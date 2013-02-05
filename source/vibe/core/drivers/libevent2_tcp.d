/**
	libevent based driver

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libevent2_tcp;

public import vibe.core.core;

import vibe.core.log;
import vibe.core.drivers.libevent2;
import vibe.utils.memory;

import deimos.event2.buffer;
import deimos.event2.bufferevent;
import deimos.event2.bufferevent_ssl;
import deimos.event2.event;
import deimos.event2.util;

import std.algorithm;
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

package class Libevent2TcpConnection : TcpConnection {
	private {
		bufferevent* m_event;
		evbuffer* m_inputBuffer;
		bool m_timeout_triggered;
		TcpContext* m_ctx;
		string m_peerAddress;
		ubyte[64] m_peekBuffer;
		bool m_tcpNoDelay = false;
		Duration m_readTimeout;
	}
	
	this(TcpContext* ctx)
	{
		m_event = ctx.event;
		m_ctx = ctx;
		m_inputBuffer = bufferevent_get_input(m_event);

		assert(Fiber.getThis() is m_ctx.task);

		char buf[64];
		void* ptr;
		if( ctx.remote_addr.family == AF_INET ) ptr = &ctx.remote_addr.sockAddrInet4.sin_addr;
		else ptr = &ctx.remote_addr.sockAddrInet6.sin6_addr;
		evutil_inet_ntop(ctx.remote_addr.family, ptr, buf.ptr, buf.length);
		m_peerAddress = to!string(buf.ptr);
	}
	
	~this()
	{
		//assert(m_ctx is null, "Leaking TcpContext because it has not been cleaned up and we are not allowed to touch the GC in finalizers..");
	}
	
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
			bufferevent_set_timeouts(m_event, null, null);
		} else {
			assert(v.total!"seconds" <= int.max);
			timeval toread = {tv_sec: cast(int)v.total!"seconds", tv_usec: v.fracSec.usecs};
			bufferevent_set_timeouts(m_event, &toread, null);
		}
	}
	@property Duration readTimeout() const { return m_readTimeout; }

	void acquire()
	{
		assert(m_ctx, "Trying to acquire a closed TCP connection.");
		assert(m_ctx.task == Task(), "Trying to acquire a TCP connection that is currently owned.");
		m_ctx.task = Task.getThis();
	}

	void release()
	{
		if( !m_ctx ) return;
		assert(m_ctx.task != Task(), "Trying to release a TCP connection that is not owned.");
		assert(m_ctx.task == Task.getThis(), "Trying to release a foreign TCP connection.");
		m_ctx.task = Task();
	}

	bool isOwner()
	{
		return m_ctx !is null && m_ctx.task != Task() && m_ctx.task == Task.getThis();
	}
	
	/// Closes the connection.
	void close()
	{
		assert(m_ctx, "Closing an already closed TCP connection.");

		checkConnected();
		auto fd = m_ctx.socketfd;
		m_ctx.shutdown = true;
		bufferevent_setwatermark(m_event, EV_WRITE, 1, 0);
		bufferevent_flush(m_event, EV_WRITE, bufferevent_flush_mode.BEV_FLUSH);
		bufferevent_flush(m_event, EV_WRITE, bufferevent_flush_mode.BEV_FINISHED);
		logTrace("Closing socket %d...", fd);
		auto buf = bufferevent_get_output(m_ctx.event);
		while( m_ctx.event && evbuffer_get_length(buf) > 0 )
			m_ctx.core.yieldForEvent();

		version(Windows) shutdown(m_ctx.socketfd, SD_SEND);
		else shutdown(m_ctx.socketfd, SHUT_WR);
		if( m_ctx.event ) bufferevent_free(m_ctx.event);
		TcpContextAlloc.free(m_ctx);
		m_ctx = null;
		logTrace("...socket %d closed.", fd);
	}

	/// The 'connected' status of this connection
	@property bool connected() const { return m_ctx !is null && m_ctx.event !is null; }

	@property bool empty() { return leastSize == 0; }

	@property ulong leastSize()
	{
		size_t len;
		auto buf = m_inputBuffer;
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
		auto buf = m_inputBuffer;
		return evbuffer_get_length(buf) > 0;
	}

	@property string peerAddress() const { return m_peerAddress; }

	const(ubyte)[] peek()
	{
		auto buf = m_inputBuffer;
		evbuffer_iovec iovec;
		if( evbuffer_peek(buf, -1, null, &iovec, 1) == 0 )
			return null;
		return (cast(ubyte*)iovec.iov_base)[0 .. iovec.iov_len];
	}

	/** Reads as many bytes as 'dst' can hold.
	*/
	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			checkConnected();
			logTrace("evbuffer_read %d bytes (fd %d)", dst.length, m_ctx.socketfd);
			auto nbytes = bufferevent_read(m_event, dst.ptr, dst.length);
			logTrace(" .. got %d bytes", nbytes);
			dst = dst[nbytes .. $];
			
			if( dst.length == 0 ) break;

			m_ctx.core.yieldForEvent();
		}
		logTrace("read data");
	}
	
	bool waitForData(Duration timeout)
	{
		if( dataAvailableForRead ) return true;
		m_timeout_triggered = false;
		event* evtmout = event_new(m_ctx.eventLoop, -1, 0, &onTimeout, cast(void*)this);
		timeval t;
		assert(timeout.total!"seconds"() <= int.max, "Timeouts must not be larger than int.max seconds!");
		t.tv_sec = cast(int)timeout.total!"seconds"();
		t.tv_usec = timeout.fracSec().usecs();
		logTrace("add timeout event with %d/%d", t.tv_sec, t.tv_usec);
		event_add(evtmout, &t);
		scope(exit){
			event_del(evtmout);
			event_free(evtmout);
		}
		logTrace("wait for data");
		while( connected ) {
			if( dataAvailableForRead || m_timeout_triggered ) break;
			try rawYield();
			catch( Exception e ){
				logDebug("Connection error during waitForData: %s", e.toString());
			}
		}
		logTrace(" -> timeout = %s", m_timeout_triggered);
		return dataAvailableForRead;
	}

	alias Stream.write write;

	/** Writes the given byte array.
	*/
	void write(in ubyte[] bytes, bool do_flush = true)
	{	
		checkConnected();
		//logTrace("evbuffer_add (fd %d): %s", m_ctx.socketfd, bytes);
		//logTrace("evbuffer_add (fd %d): <%s>", m_ctx.socketfd, cast(string)bytes);
		logTrace("evbuffer_add (fd %d): %d B", m_ctx.socketfd, bytes.length);
		if( bufferevent_write(m_event, cast(char*)bytes.ptr, bytes.length) != 0 )
			throw new Exception("Failed to write data to buffer");
			
		if( do_flush ) flush();
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		import vibe.core.drivers.threadedfile;
		version(none){ // causes a crash on Windows
			// special case sending of files
			if( auto fstream = cast(ThreadedFileStream)stream ){
				logInfo("Using sendfile! %s %s %s %s", fstream.fd, fstream.tell(), fstream.size, nbytes);
				fstream.takeOwnershipOfFD();
				auto buf = bufferevent_get_output(m_event);
				enforce(evbuffer_add_file(buf, fstream.fd, fstream.tell(), nbytes ? nbytes : fstream.size-fstream.tell()) == 0,
					"Failed to send file over TCP connection.");
				if( do_flush ) flush();
				return;
			}
		}

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
		enforce(m_ctx !is null, "Operating on closed TCPConnection.");
		if( m_ctx.event is null ){
			TcpContextAlloc.free(m_ctx);
			m_ctx = null;
			enforce(false, "Remote hung up while operating on TCPConnection.");
		}
		enforce(m_ctx.task == Task.getThis(), "Operating on TcpConnection owned by a different fiber!");
	}
}

class LibeventTcpListener : TcpListener {
	private {
		TcpContext* m_ctx;
	}

	this(TcpContext* ctx)
	{
		m_ctx = ctx;
	}

	void stopListening()
	{
		if( !m_ctx ) return;

		event_free(m_ctx.listenEvent);
		evutil_closesocket(m_ctx.socketfd);
		TcpContextAlloc.free(m_ctx);
		m_ctx = null;
	}
}


/**************************************************************************************************/
/* Private types                                                                                  */
/**************************************************************************************************/

package struct TcpContext
{
	this(DriverCore c, event_base* evbase, int sock, bufferevent* evt, NetworkAddress peeraddr){
		core = c;
		eventLoop = evbase;
		socketfd = sock;
		event = evt;
		remote_addr = peeraddr;
	}

	this(DriverCore c, event_base* evbase, int sock, bufferevent* evt){
		core = c;
		eventLoop = evbase;
		socketfd = sock;
		event = evt;
	}

	DriverCore core;
	event_base* eventLoop;
	void delegate(TcpConnection conn) connectionCallback;
	bufferevent* event;
	deimos.event2.event_struct.event* listenEvent;
	NetworkAddress remote_addr;
	bool shutdown = false;
	int socketfd = -1;
	int status = 0;
	Task task;
	bool writeFinished;
}
alias FreeListObjectAlloc!(TcpContext, false, true) TcpContextAlloc;


/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

package nothrow extern(C)
{
	void onConnect(evutil_socket_t listenfd, short evtype, void *arg)
	{
		logTrace("connect callback");
		auto ctx = cast(TcpContext*)arg;

		if( !(evtype & EV_READ) ){
			logError("Unknown event type in connect callback: 0x%hx", evtype);
			return;
		}

		static struct ClientTask {
			TcpContext* listen_ctx;
			NetworkAddress remote_addr;
			int sockfd;

			void execute()
			{
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

				auto client_ctx = TcpContextAlloc.alloc(drivercore, eventloop, sockfd, buf_event, remote_addr);
				assert(client_ctx.event !is null, "event is null although it was just != null?");
				bufferevent_setcb(buf_event, &onSocketRead, &onSocketWrite, &onSocketEvent, client_ctx);
				if( bufferevent_enable(buf_event, EV_READ|EV_WRITE) ){
					bufferevent_free(buf_event);
					TcpContextAlloc.free(client_ctx);
					logError("Error enabling buffered I/O event for fd %d.", sockfd);
					return;
				}

				assert(client_ctx.event !is null, "Client task called without event!?");
				client_ctx.task = Task.getThis();
				auto conn = FreeListRef!Libevent2TcpConnection(client_ctx);
				assert(conn.connected, "Connection closed directly after accept?!");
				logDebug("start task (fd %d).", client_ctx.socketfd);
				try {
					listen_ctx.connectionCallback(conn);
					logDebug("task out (fd %d).", client_ctx.socketfd);
				} catch( Exception e ){
					logWarn("Handling of connection failed: %s", e.msg);
					logDebug("%s", e.toString());
				}
				if( conn.connected ) conn.close();

				FreeListObjectAlloc!ClientTask.free(&this);
				logDebug("task finished.");
			}
		}

		try {
			// Accept and configure incoming connections (up to 10 connections in one go)
			foreach( i; 0 .. 10 ){
				logTrace("accept");
				assert(listenfd < int.max, "Listen socket descriptor >= int.max?!");
				sockaddr_in6 remote_addr;
				socklen_t addrlen = remote_addr.sizeof;
				auto sockfd = accept(cast(int)listenfd, cast(sockaddr*)&remote_addr, &addrlen);
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

				auto task = FreeListObjectAlloc!ClientTask.alloc();
				task.listen_ctx = ctx;
				*cast(sockaddr_in6*)task.remote_addr.sockAddr = remote_addr;
				task.sockfd = sockfd;

				version(MultiThreadTest){
					runWorkerTask(&task.execute);
				} else {
					runTask(&task.execute);
				}
			}
		} catch( Throwable e ){
			logWarn("Got exception while accepting new connections: %s", e.msg);
		}

		logTrace("handled incoming connections...");
	}

	void onSocketRead(bufferevent *buf_event, void *arg)
	{
		auto ctx = cast(TcpContext*)arg;
		logTrace("socket %d read event!", ctx.socketfd);

		auto f = ctx.task;
		try {
			if( f && f.state != Fiber.State.TERM )
				ctx.core.resumeTask(f);
		} catch( Throwable e ){
			logWarn("Got exception when resuming task onSocketRead: %s", e.msg);
		}
	}

	void onSocketWrite(bufferevent *buf_event, void *arg)
	{
		try {
			auto ctx = cast(TcpContext*)arg;
			assert(ctx.event is buf_event, "Write event on bufferevent that does not match the TcpContext");
			logTrace("socket %d write event (%s)!", ctx.socketfd, ctx.shutdown);
			if( ctx.task && ctx.task.state != Fiber.State.TERM ){
				bufferevent_flush(buf_event, EV_WRITE, bufferevent_flush_mode.BEV_FLUSH);
			}
			ctx.writeFinished = true;
			if( ctx.task ) ctx.core.resumeTask(ctx.task);
		} catch( Throwable e ){
			logWarn("Got exception when resuming task onSocketRead: %s", e.msg);
		}
	}
		
	void onSocketEvent(bufferevent *buf_event, short status, void *arg)
	{
		try {
			auto ctx = cast(TcpContext*)arg;
			ctx.status = status;
			logDebug("Socket event on fd %d: %d (%s vs %s)", ctx.socketfd, status, cast(void*)buf_event, cast(void*)ctx.event);
			assert(ctx.event is buf_event, "Status event on bufferevent that does not match the TcpContext");
	
			bool free_event = false;
			
			string errorMessage;
			if( status & BEV_EVENT_EOF ){
				logDebug("Connection was closed (fd %d).", ctx.socketfd);
				free_event = true;
			} else if( status & BEV_EVENT_TIMEOUT ){
				logDebug("Remote host on fd %d timed out.", ctx.socketfd);
				free_event = true;
			} else if( status & BEV_EVENT_ERROR ){
				version(Windows){
					logDebug("A socket error occurred on fd %d: %d (%s)", ctx.socketfd, status, to!string(evutil_socket_error_to_string(status)));
				} else {
					logDebug("A socket error occurred on fd %d: %d", ctx.socketfd, status);
				}
				free_event = true;
				if( status & BEV_EVENT_READING ) errorMessage = "Error reading data from socket. Remote hung up?";
				else if( status & BEV_EVENT_WRITING ) errorMessage = "Error writing data to socket. Remote hung up?";
				else errorMessage = "Socket error: "~to!string(status);
			}

			if( free_event || (status & BEV_EVENT_ERROR) ){	
				bufferevent_free(buf_event);
				ctx.event = null;
			}

			if( ctx.task && ctx.task.running ){
				if( status & BEV_EVENT_ERROR ){
					logTrace("resuming corresponding task with exception...");
					ctx.core.resumeTask(ctx.task, new Exception(errorMessage));
				} else {
					logTrace("resuming corresponding task...");
					ctx.core.resumeTask(ctx.task);
				}
			}
		} catch( Throwable e ){
			logWarn("Got exception when resuming task onSocketEvent: %s", e.msg);
		}
	}

	private extern(C) void onTimeout(evutil_socket_t, short events, void* userptr)
	{
		try {
			logTrace("data wait timeout");
			auto conn = cast(Libevent2TcpConnection)userptr;
			conn.m_timeout_triggered = true;
			if( conn.m_ctx ) conn.m_ctx.core.resumeTask(conn.m_ctx.task);
			else logDebug("waitForData timeout after connection was closed!");
		} catch( Throwable e ){
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
