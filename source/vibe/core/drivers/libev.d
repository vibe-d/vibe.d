/**
	libev based driver implementation

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libev;

import vibe.core.driver;
import vibe.core.drivers.threadedfile;
import vibe.core.log;

import intf.libev;

import std.algorithm : min;
import std.exception;
import std.string;

import core.memory;
import core.sys.posix.netinet.tcp;
import core.thread;

version(Windows){
  public import std.c.windows.winsock;
} else {
  public import core.sys.posix.sys.socket;
  public import core.sys.posix.sys.time;
  public import core.sys.posix.netdb;
  public import core.sys.posix.netinet.in_;
}


private extern(C){
	void* myrealloc(void* p, int newsize);//{ return GC.realloc(p, newsize); }
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
	}

	int runEventLoop()
	{
		while(!m_break)
			ev_run(m_loop, 0);
		return 0;
	}
	
	int processEvents()
	{
		ev_run(m_loop, EVRUN_ONCE);
		return 0;
	}
	
	void exitEventLoop()
	{
		ev_break(m_loop, EVBREAK_ALL);
	}
	
	void sleep(double seconds)
	{
		assert(false);
	}
	
	FileStream openFile(string path, FileMode mode)
	{
		return new ThreadedFileStream(path, mode);
	}
	
	TcpConnection connectTcp(string host, ushort port)
	{
		assert(false);
	}
	
	void listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string address)
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
				return;
			}
		} else {
			ret = inet_pton(AF_INET, toStringz(address), &addr_ip4.sin_addr);
		}
		if( ret == 1 ){
			auto rc = listenTcpGeneric(AF_INET, &addr_ip4, port, conn_callback);
			logInfo("Listening on %s port %d %s", address, port, (rc==0?"succeeded":"failed"));
			return;
		}

		version(Windows){}
		else {
			sockaddr_in6 addr_ip6;
			addr_ip6.sin6_family = AF_INET6;
			addr_ip6.sin6_port = htons(port);
			ret = inet_pton(AF_INET6, toStringz(address), &addr_ip6.sin6_addr);
			if( ret == 1 ){
				auto rc = listenTcpGeneric(AF_INET6, &addr_ip6, port, conn_callback);
				logInfo("Listening on %s port %d %s", address, port, (rc==0?"succeeded":"failed"));
				return;
			}
		}

		enforce(false, "Invalid IP address string: '"~address~"'");
	}
	
	Signal createSignal()
	{
		return null;
	}

	private int listenTcpGeneric(SOCKADDR)(int af, SOCKADDR* sock_addr, ushort port, void delegate(TcpConnection conn) connection_callback)
	{
		auto listenfd = socket(af, SOCK_STREAM, 0);
		if( listenfd == -1 ){
			logError("Error creating listening socket> %s", af);
			return -1;
		}
		int tmp_reuse = 1; 
		if( setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, &tmp_reuse, tmp_reuse.sizeof) ){
			logError("Error enabling socket address reuse on listening socket");
			return -1;
		}
		if( bind(listenfd, cast(sockaddr*)sock_addr, SOCKADDR.sizeof) ){
			logError("Error binding listening socket");
			return -1;
		}
		if( listen(listenfd, 128) ){
			logError("Error listening to listening socket");
			return -1;
		}

		// Set socket for non-blocking I/O
		setNonBlocking(listenfd);
		
		auto w_accept = new ev_io;
		ev_io_init(w_accept, &accept_cb, listenfd, EV_READ);
		ev_io_start(m_loop, w_accept);

		return 0;
	}
}

class LibevTcpConnection : TcpConnection {
	private {
		LibevDriver m_driver;
		int m_socket;
		ubyte[64*1024] m_readBuffer;
		ubyte[] m_readBufferContent;
	}
	
	this(LibevDriver driver, int fd)
	{
		assert(fd >= 0);
		m_driver = driver;
		m_socket = fd;
	}
	
	@property void tcpNoDelay(bool enabled)
	{
		ubyte opt = enabled;
		setsockopt(m_socket, IPPROTO_TCP, TCP_NODELAY, &opt, opt.sizeof);
	}
	
	void close()
	{
	}
	
	@property bool connected() const { return m_socket >= 0; }
	
	@property bool dataAvailableForRead(){ return m_readBufferContent.length > 0; }
	
	@property string peerAddress() const
	{
		return "xxx";
	}
	
	void initiateSSL(SSLContext ctx)
	{
		assert(false);
	}
	
	void acceptSSL(SSLContext ctx)
	{
		assert(false);
	}
	
	bool waitForData(int secs)
	{
		//ev_timer timer;
		//ev_timer_set(&timer, tst, rtst);
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
	
	@property bool empty() { return leastSize == 0; }
	
	@property ulong leastSize()
	{
		if( m_readBufferContent.length == 0 ){
			readChunk();
			assert(m_readBufferContent.length > 0);
		}
		return m_readBufferContent.length;
	}
	
	void read(ubyte[] dst)
	{
		while( dst.length > 0 ){
			if( !m_readBufferContent.length )
				readChunk();
			size_t n = min(dst.length, m_readBufferContent.length);
			dst[0 .. n] = m_readBufferContent[0 .. n];
			dst = dst[n .. $];
			m_readBufferContent = m_readBufferContent[n .. $];
		}
	}
	
	ubyte[] readLine(size_t max_bytes = 0, string linesep = "\r\n")
	{
		return readLineDefault(max_bytes, linesep);
	}
	
	ubyte[] readAll(size_t max_bytes = 0)
	{
		return readAllDefault(max_bytes);
	}
	
	void write(in ubyte[] bytes_, bool do_flush = true)
	{
		const(ubyte)[] bytes = bytes_;
		while( bytes.length > 0 ){
			size_t nbytes = send(m_socket, bytes.ptr, bytes.length, 0);
			enforce(nbytes >= 0, "Error sending data");
			enforce(nbytes > 0, "Conn closed while sending?");
			bytes = bytes[nbytes .. $];
			m_driver.m_core.yieldForEvent();
		}
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
	
	private void readChunk()
	{
		assert(m_readBufferContent.length == 0);
		auto nbytes = recv(m_socket, m_readBuffer.ptr, m_readBuffer.length, 0);
		enforce(nbytes >= 0, "Socket error on read");
		enforce(nbytes == 0, "Socket closed by peer on read");
		m_readBufferContent = m_readBuffer[0 .. nbytes];
	}
}

private {
	class EventSlot {
		private {
			DriverCore m_core;
			long m_fd;
			Fiber[] m_tasks;
			EventedObject m_object;
		}
		
		void wakeUpTasks(Exception e = null)
		{
			foreach( t; m_tasks )
				m_core.resumeTask(t, e);
		}
		
		EventedObject eventObject() { return m_object; }
	}
	EventSlot[long] m_eventReceivers;
}

private extern(C){
	void accept_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		sockaddr_in client_addr;
		socklen_t client_len = client_addr.sizeof;
		enforce((EV_ERROR & revents) == 0);

		auto client_sd = accept(watcher.fd, cast(sockaddr*)&client_addr, &client_len);
		
		setNonBlocking(client_sd);

		enforce(client_sd >= 0);

		logDebug("client %d connected.", client_sd);

		ev_io* r_client = new ev_io;
		ev_io_init(r_client, &read_cb, client_sd, EV_READ);
		ev_io_start(loop, r_client);

		ev_io* w_client = new ev_io;
		ev_io_init(w_client, &write_cb, client_sd, EV_WRITE);
		ev_io_start(loop, w_client);
	}
	
	void read_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		auto rec = watcher.fd in m_eventReceivers;
		rec.wakeUpTasks();
	}

	void write_cb(ev_loop_t *loop, ev_io *watcher, int revents)
	{
		auto rec = watcher.fd in m_eventReceivers;
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
