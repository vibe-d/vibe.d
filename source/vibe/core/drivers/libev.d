/**
	libev based driver implementation

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libev;

version(VibeLibevDriver)
{

import vibe.core.core;
import vibe.core.driver;
import vibe.core.drivers.threadedfile;
import vibe.core.log;

import deimos.ev;

import std.algorithm : min;
import std.array;
import std.exception;
import std.conv;
import std.string;

import core.memory;
import core.sys.posix.netinet.tcp;
import core.thread;

version(Windows){
	import std.c.windows.winsock;
} else {
	import core.sys.posix.sys.socket;
	import core.sys.posix.sys.time;
 	import core.sys.posix.fcntl;
	import core.sys.posix.netdb;
	import core.sys.posix.netinet.in_;
	import core.sys.posix.unistd;
	import core.stdc.errno;
}


private extern(C){
	void* myrealloc(void* p, int newsize){ return GC.realloc(p, newsize); }
}


class LibevDriver : EventDriver {
	private {
		DriverCore m_core;
		ev_loop_t* m_loop;
		bool m_break = false;
	}

	this(DriverCore core)
	{
		m_core = core;
		ev_set_allocator(&myrealloc);
		m_loop = ev_loop_new(EVFLAG_AUTO);
		enforce(m_loop !is null, "Failed to create libev loop");
		logInfo("Got libev backend: %d", ev_backend(m_loop));
	}

	int runEventLoop()
	{
		while(!m_break){
			ev_run(m_loop, EVRUN_ONCE);
			m_core.notifyIdle();
		}
		m_break = false;
		logInfo("Event loop exit", m_break);
		return 0;
	}
	
	int runEventLoopOnce()
	{
		ev_run(m_loop, EVRUN_ONCE);
		m_core.notifyIdle();
		return 0;
	}

	int processEvents()
	{
		ev_run(m_loop, EVRUN_NOWAIT);
		m_core.notifyIdle();
		return 0;
	}
	
	void exitEventLoop()
	{
		logInfo("Exiting (%s)", m_break);
		m_break = true;
		ev_break(m_loop, EVBREAK_ALL);
	}
	
	FileStream openFile(Path path, FileMode mode)
	{
		return new ThreadedFileStream(path, mode);
	}
	
	DirectoryWatcher watchDirectory(Path path, bool recursive)
	{
		assert(false);
	}

	/** Resolves the given host name or IP address string.
	*/
	NetworkAddress resolveHost(string host, ushort family, bool no_dns)
	{
		assert(false);
	}

	TcpConnection connectTcp(string host, ushort port)
	{
		assert(false);
	}
	
	LibevTcpListener listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string address)
	{
		sockaddr_in addr_ip4;
		addr_ip4.sin_family = AF_INET;
		addr_ip4.sin_port = htons(port);
		int ret;
		version(Windows){
			ret = 1;
			addr_ip4.sin_addr.s_addr = inet_addr(toStringz(address));
			// FIXME: support IPv6
			if( addr_ip4.sin_addr.s_addr  == INADDR_NONE ){
				logError("Not an IPv4 address: '%s'", address);
				return null;
			}
		} else {
			ret = inet_pton(AF_INET, toStringz(address), &addr_ip4.sin_addr);
		}
		if( ret == 1 ){
			auto rc = listenTcpGeneric(AF_INET, &addr_ip4, port, conn_callback);
			logInfo("Listening on %s port %d %s", address, port, (rc?"succeeded":"failed"));
			return rc;
		}

		version(Windows){}
		else {
			sockaddr_in6 addr_ip6;
			addr_ip6.sin6_family = AF_INET6;
			addr_ip6.sin6_port = htons(port);
			ret = inet_pton(AF_INET6, toStringz(address), &addr_ip6.sin6_addr);
			if( ret == 1 ){
				auto rc = listenTcpGeneric(AF_INET6, &addr_ip6, port, conn_callback);
				logInfo("Listening on %s port %d %s", address, port, (rc?"succeeded":"failed"));
				return rc;
			}
		}

		enforce(false, "Invalid IP address string: '"~address~"'");
		assert(false);
	}
	
	UdpConnection listenUdp(ushort port, string bind_address = "0.0.0.0")
	{
		assert(false);
	}

	Signal createSignal()
	{
		assert(false);
	}

	Timer createTimer(void delegate() callback)
	{
		assert(false);
	}

	private LibevTcpListener listenTcpGeneric(SOCKADDR)(int af, SOCKADDR* sock_addr, ushort port, void delegate(TcpConnection conn) connection_callback)
	{
		auto listenfd = socket(af, SOCK_STREAM, 0);
		if( listenfd == -1 ){
			logError("Error creating listening socket> %s", af);
			return null;
		}
		int tmp_reuse = 1; 
		if( setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof) ){
			logError("Error enabling socket address reuse on listening socket");
			return null;
		}
		if( bind(listenfd, cast(
sockaddr*)sock_addr, SOCKADDR.sizeof) ){
			logError("Error binding listening socket");
			return null;
		}
		if( listen(listenfd, 128) ){
			logError("Error listening to listening socket");
			return null;
		}

		// Set socket for non-blocking I/O
		setNonBlocking(listenfd);
		
		auto w_accept = new ev_io;
		ev_io_init(w_accept, &accept_cb, listenfd, EV_READ);
		ev_io_start(m_loop, w_accept);
		
		w_accept.data = cast(void*)this;
		//addEventReceiver(m_core, listenfd, new LibevTcpListener(connection_callback));

		return new LibevTcpListener(listenfd, w_accept, connection_callback);
	}
}

class LibevTcpListener : TcpListener {
	private {
		int m_socket;
		ev_io* m_io;
		void delegate(TcpConnection conn) m_connectionCallback;
	}

	this(int sock, ev_io* io, void delegate(TcpConnection conn) connection_callback)
	{
		m_socket = sock;
		m_io = io;
		m_connectionCallback = connection_callback;
	}
	
	@property void delegate(TcpConnection conn) connectionCallback() { return m_connectionCallback; }

	void stopListening()
	{
		// TODO!
	}
}

class LibevTcpConnection : TcpConnection {
	private {
		LibevDriver m_driver;
		int m_socket;
		ubyte[64*1024] m_readBuffer;
		ubyte[] m_readBufferContent;
		ev_io* m_readWatcher;
		ev_io* m_writeWatcher;
		int m_eventsExpected = 0;
		Appender!(ubyte[]) m_writeBuffer;
		bool m_tcpNoDelay = false;
		Duration m_readTimeout;
	}
	
	this(LibevDriver driver, int fd, ev_io* read_watcher, ev_io* write_watcher)
	{
		assert(fd >= 0);
		m_driver = driver;
		m_socket = fd;
		m_readWatcher = read_watcher;
		m_writeWatcher = write_watcher;
		//logInfo("fd %d %d", fd, watcher.fd);
	}
	
	@property void tcpNoDelay(bool enabled)
	{
		m_tcpNoDelay = enabled;
		ubyte opt = enabled;
		setsockopt(m_socket, IPPROTO_TCP, TCP_NODELAY, &opt, opt.sizeof);
	}
	@property bool tcpNoDelay() const { return m_tcpNoDelay; }

	@property void readTimeout(Duration v)
	{
		m_readTimeout = v;
		if( v == dur!"seconds"(0) ){
			// ...
		} else {
			assert(false);
		}
	}
	@property Duration readTimeout() const { return m_readTimeout; }
	
	void close()
	{
		//logTrace("closing");
		enforce(m_socket >= 0);
		//logInfo("shut %d", m_socket);
		shutdown(m_socket, SHUT_WR);
		while(true){
			ubyte[1024] buffer;
		//logInfo("shutrecv %d", m_socket);
			auto ret = recv(m_socket, buffer.ptr, buffer.length, 0);
			if( ret == 0 ) break;
			int err = errno;
			//logInfo("shutrecv %d: %d %d", m_socket, ret, err);
			if( err != EWOULDBLOCK && err != EAGAIN ){
				//logInfo("Socket error on shutdown: %d", err);
				break;
			}
			//logInfo("shutyield %d", m_socket);
			yieldFor(EV_READ);
		}
		stopYield();
		//logInfo("close %d", m_socket);
		.close(m_socket);
		m_socket = -1;

	}
	
	@property bool connected() const { return m_socket >= 0; }
	
	@property bool dataAvailableForRead(){ return m_readBufferContent.length > 0; }
	
	@property string peerAddress() const
	{
		return "xxx";
	}
	
	bool waitForData(Duration secs)
	{
		//ev_timer timer;
		//ev_timer_set(&timer, tst, rtst);
		//eventsExpected = EV_READ;
		assert(false);
	}
	
	void release()
	{
		assert(false);
	}
	
	void acquire()
	{
		assert(false);
	}

	bool isOwner()
	{
		assert(false);
	}
	
	@property bool empty() { return leastSize == 0; }
	
	@property ulong leastSize()
	{
		if( m_readBufferContent.length == 0 ){
			readChunk();
			//assert(m_readBufferContent.length > 0);
		}
		return m_readBufferContent.length;
	}
	
	const(ubyte)[] peek()
	{
		return null;
	}

	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			checkConnected();
			if( !m_readBufferContent.length ) readChunk();
			enforce(m_readBufferContent.length > 0, "Remote end hung up during read.");
			size_t n = min(dst.length, m_readBufferContent.length);
			dst[0 .. n] = m_readBufferContent[0 .. n];
			dst = dst[n .. $];
			m_readBufferContent = m_readBufferContent[n .. $];
		}
	}
	
	const(ubyte)[] peek(size_t nbytes = 0)
	{
		if( !m_readBufferContent.length ) readChunk();
		return m_readBufferContent;
	}
	
	void drain(size_t nbytes){
		while( nbytes > 0 ){
			if( m_readBufferContent.length == 0 ) readChunk();
			size_t amt = min(nbytes, m_readBufferContent.length);
			m_readBufferContent = m_readBufferContent[amt .. $];
			nbytes -= amt;
		}
	}
		
	void write(in ubyte[] bytes_, bool do_flush = true)
	{
		m_writeBuffer.put(bytes_);
		
		/*if( do_flush )*/ flush();
	}
	
	void flush()
	{
		const(ubyte)[] bytes = m_writeBuffer.data();//bytes_;
		scope(exit) m_writeBuffer.clear();
		scope(exit) stopYield();
		while( bytes.length > 0 ){
			checkConnected();
			logTrace("send %d: %s", bytes.length,cast(string)bytes);
			auto nbytes = send(m_socket, bytes.ptr, bytes.length, 0);
			logTrace(" .. got %d", nbytes);
			if( nbytes == bytes.length ) break;
			if( nbytes < 0 ){
				int err = errno;
				enforce(err != EPIPE, "Remote end hung before all data was sent.");
				enforce(err == EAGAIN || err == EWOULDBLOCK, "Error sending data: "~to!string(errno));
			} else bytes = bytes[nbytes .. $];
			if( bytes.length > 0 ) yieldFor(EV_WRITE);
		}
	}
	
	void finalize()
	{
		flush();
	}
	
	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}
	
	private void readChunk()
	{
		checkConnected();
		logTrace("Reading next chunk!");
		assert(m_readBufferContent.length == 0);
		ptrdiff_t nbytes;
		scope(exit) stopYield();
		while(true){
			nbytes = recv(m_socket, m_readBuffer.ptr, m_readBuffer.length, 0);
			logTrace(" .. got %d, %d", nbytes, errno);
			if( nbytes >= 0 ) break;
			int err = errno;
			enforce(err == EWOULDBLOCK || err == EAGAIN, "Socket error on read: "~to!string(err));
			yieldFor(EV_READ);
		}
		
		logTrace(" <%s>", cast(string)m_readBuffer[0 .. nbytes]);
		if( nbytes == 0 ){
			logInfo("detected connection close during read!");
			/*close();
			return;*/
		}
		m_readBufferContent = m_readBuffer[0 .. nbytes];
	}
	
	private void checkConnected()
	{
		enforce(m_socket >= 0, "Operating on closed connection.");
	}
	
	private void yieldFor(int events)
	{
		if( m_eventsExpected != events ){
			if( events & EV_READ ) ev_io_start(m_driver.m_loop, m_readWatcher);
			if( events & EV_WRITE ) ev_io_start(m_driver.m_loop, m_writeWatcher);
			m_eventsExpected = events;
		}
		m_driver.m_core.yieldForEvent();
	}
	
	private void stopYield()
	{
		if( m_eventsExpected ){
			if( m_eventsExpected & EV_READ ) ev_io_stop(m_driver.m_loop, m_readWatcher);
			if( m_eventsExpected & EV_WRITE ) ev_io_stop(m_driver.m_loop, m_writeWatcher);
			m_eventsExpected = 0;
		}
	}
}

private {
	class EventSlot {
		private {
			DriverCore m_core;
			long m_fd;
			Task[] m_tasks;
			EventedObject m_object;
		}

		this(DriverCore core, long fd, EventedObject object)
		{
			m_core = core;
			m_fd = fd;
			m_object = object;
			auto self = Task.getThis();
			if( self ) m_tasks ~= self;
		}
		
		void wakeUpTasks(Exception e = null)
		{
			foreach( t; m_tasks )
				m_core.resumeTask(t, e);
		}
		
		@property EventedObject eventObject() { return m_object; }
	}
	EventSlot[long] m_eventReceivers;
	
	void addEventReceiver(DriverCore core, long fd, EventedObject object)
	{
		m_eventReceivers[fd] = new EventSlot(core, fd, object);
	}
	
	void removeEventReceiver(long fd)
	{
		m_eventReceivers.remove(fd);
	}
	
	EventedObject getEventedObjectForFd(long fd)
	{
		auto sl = fd in m_eventReceivers;
		return sl ? sl.m_object : null;
	}
}

private extern(C){
	void accept_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		auto driver = cast(LibevDriver)watcher.data;
	
		sockaddr_in client_addr;
		socklen_t client_len = client_addr.sizeof;
		enforce((EV_ERROR & revents) == 0);

		auto client_sd = accept(watcher.fd, cast(sockaddr*)&client_addr, &client_len);
		
		setNonBlocking(client_sd);

		enforce(client_sd >= 0);

		logDebug("client %d connected.", client_sd);

		/*ev_io* w_client = new ev_io;
		ev_io_init(w_client, &write_cb, client_sd, EV_WRITE);
		ev_io_start(loop, w_client);*/
		
		auto obj = cast(LibevTcpListener)getEventedObjectForFd(watcher.fd);
		
		void client_task()
		{
			ev_io* r_client = new ev_io;
			ev_io* w_client = new ev_io;
			ev_io_init(r_client, &read_cb, client_sd, EV_READ);
			ev_io_init(w_client, &read_cb, client_sd, EV_WRITE);

			auto conn = new LibevTcpConnection(driver, client_sd, r_client, w_client);
			logTrace("client task in");
			addEventReceiver(driver.m_core, client_sd, conn);
			logTrace("calling connection callback");
			try {
				obj.m_connectionCallback(conn);
			} catch( Exception e ){
				logWarn("Unhandled exception in connection handler: %s", e.toString());
			}
			logTrace("client task out");
			if( conn.connected ) conn.close();
			removeEventReceiver(client_sd);
		}
		
		runTask(&client_task);
	}
	
	void read_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		logTrace("i/o event on %d: %d", watcher.fd, revents);
		auto rec = watcher.fd in m_eventReceivers;
		//assert(rec !is null);
		if( rec is null ) return;
		
		if( ((cast(LibevTcpConnection)rec.eventObject).m_eventsExpected & revents) != 0 )
			rec.wakeUpTasks();
	}

	void write_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		logTrace("write event on %d: %d", watcher.fd, revents);
		auto rec = watcher.fd in m_eventReceivers;
		assert(rec !is null);
		rec.wakeUpTasks();
	}
}

private void setNonBlocking(int fd)
{
	version(Windows){
		uint p = 1;
		ioctlsocket(fd, FIONBIO, &p);
	} else {
		int flags;
		flags = fcntl(fd, F_GETFL);
		flags |= O_NONBLOCK;
		fcntl(fd, F_SETFL, flags);
	}
}

} // version(VibeLibevDriver)
