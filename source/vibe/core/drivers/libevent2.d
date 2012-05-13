/**
	libevent based driver

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.libevent2;

import vibe.core.driver;
import vibe.core.drivers.libevent2_tcp;
import vibe.core.drivers.threadedfile;
import vibe.core.log;

import intf.event2.bufferevent;
import intf.event2.dns;
import intf.event2.event;
import intf.event2.util;

import core.memory;
import core.sys.posix.netinet.tcp;
import core.thread;
import std.conv;
import std.exception;
import std.string;

private extern(C){
	void* myalloc(size_t size){ return GC.malloc(size); }
	void* myrealloc(void* p, size_t newsize){ return GC.realloc(p, newsize); }
	void myfree(void* p){ GC.free(p); }
}


class Libevent2Driver : EventDriver {
	private {
		DriverCore m_core;
		event_base* m_eventLoop;
		evdns_base* m_dnsBase;
	}

	this(DriverCore core)
	{
		m_core = core;

		// set the malloc/free versions of our runtime so we don't run into trouble
		// because the libevent DLL uses a different one.
		event_set_mem_functions(&myalloc, &myrealloc, &myfree);

		// initialize libevent
		logDebug("libevent version: %s", to!string(event_get_version()));
		m_eventLoop = event_base_new();
		logDebug("libevent is using %s for events.", to!string(event_base_get_method(m_eventLoop)));
		
		m_dnsBase = evdns_base_new(m_eventLoop, 1);
		if( !m_dnsBase ) logError("Failed to initialize DNS lookup.");
	}

	@property event_base* eventLoop() { return m_eventLoop; }
	@property evdns_base* dnsEngine() { return m_dnsBase; }

	int runEventLoop()
	{
		return event_base_loop(m_eventLoop, 0);
	}

	int processEvents()
	{
		return event_base_loop(m_eventLoop, EVLOOP_ONCE);
	}

	void exitEventLoop()
	{
		enforce(event_base_loopbreak(m_eventLoop) == 0, "Failed to exit libevent event loop.");
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
		auto af = AF_INET;
		auto sockfd = socket(af, SOCK_STREAM, 0);
		enforce(sockfd != -1, "Failed to create socket.");
		
		if( evutil_make_socket_nonblocking(sockfd) )
			throw new Exception("Failed to make socket non-blocking.");
			
		auto buf_event = bufferevent_socket_new(m_eventLoop, sockfd, bufferevent_options.BEV_OPT_CLOSE_ON_FREE);
		if( !buf_event ) throw new Exception("Failed to create buffer event for socket.");

		auto cctx = new TcpContext(m_core, m_eventLoop, null, sockfd, buf_event);
		cctx.task = Fiber.getThis();
		bufferevent_setcb(buf_event, &onSocketRead, &onSocketWrite, &onSocketEvent, cctx);
		timeval toread = {tv_sec: 60, tv_usec: 0};
		bufferevent_set_timeouts(buf_event, &toread, null);
		if( bufferevent_enable(buf_event, EV_READ|EV_WRITE) )
			throw new Exception("Error enabling buffered I/O event for socket.");

		if( bufferevent_socket_connect_hostname(buf_event, m_dnsBase, af, toStringz(host), port) )
			throw new Exception("Failed to connect to host "~host~" on port "~to!string(port));

	// TODO: cctx.remove_addr6 = ...;
			
		while( cctx.status == 0 )
			m_core.yieldForEvent();
			
		logTrace("Connect result status: %d", cctx.status);
		
		if( cctx.status != BEV_EVENT_CONNECTED )
			throw new Exception("Failed to connect to host "~host~" on port "~to!string(port)~": "~to!string(cctx.status));

		return new Libevent2TcpConnection(cctx);
	}

	void listenTcp(ushort port, void delegate(TcpConnection conn) connection_callback, string address)
	{
		sockaddr_in addr_ip4;
		addr_ip4.sin_family = AF_INET;
		addr_ip4.sin_port = htons(port);
		auto ret = evutil_inet_pton(AF_INET, toStringz(address), &addr_ip4.sin_addr);
		if( ret == 1 ){
			auto rc = listenTcpGeneric(AF_INET, &addr_ip4, port, connection_callback);
			logInfo("Listening on %s port %d %s", address, port, (rc==0?"succeeded":"failed"));
			return;
		}

		sockaddr_in6 addr_ip6;
		addr_ip6.sin6_family = AF_INET6;
		addr_ip6.sin6_port = htons(port);
		ret = evutil_inet_pton(AF_INET6, toStringz(address), &addr_ip6.sin6_addr);
		if( ret == 1 ){
			auto rc = listenTcpGeneric(AF_INET6, &addr_ip6, port, connection_callback);
			logInfo("Listening on %s port %d %s", address, port, (rc==0?"succeeded":"failed"));
			return;
		}

		enforce(false, "Invalid IP address string: '"~address~"'");
	}

	Libevent2Signal createSignal()
	{
		return new Libevent2Signal(this);
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
		if( evutil_make_socket_nonblocking(listenfd) ){
			logError("Error setting listening socket to non-blocking I/O.");
			return -1;
		}
		
		version(Windows){} else evutil_make_listen_socket_reuseable(listenfd);

		// Add an event to wait for connections
		auto ctx = new TcpContext(m_core, m_eventLoop, connection_callback, listenfd, null, *sock_addr);
		auto connect_event = event_new(m_eventLoop, listenfd, EV_READ | EV_PERSIST, &onConnect, ctx);
		if( event_add(connect_event, null) ){
			logError("Error scheduling connection event on the event loop.");
		}
		
		// TODO: do something with connect_event (at least store somewhere for clean up)
		
		return 0;
	}
}

class Libevent2Signal : Signal {
	private {
		Libevent2Driver m_driver;
		event* m_event;
		bool[Fiber] m_listeners;
		int m_emitCount = 0;
	}

	this(Libevent2Driver driver)
	{
		m_driver = driver;
		m_event = event_new(m_driver.eventLoop, -1, EV_PERSIST, &onSignalTriggered, cast(void*)this);
		event_add(m_event, null);
	}

	~this()
	{
		event_free(m_event);
	}

	void emit()
	{
		event_active(m_event, 0, 0);
	}

	void wait()
	{
		assert(!isSelfRegistered());
		auto self = Fiber.getThis();
		registerSelf();
		auto start_count = m_emitCount;
		while( m_emitCount == start_count )
			m_driver.m_core.yieldForEvent();
		unregisterSelf();
	}

	void registerSelf()
	{
		m_listeners[Fiber.getThis()] = true;
	}

	void unregisterSelf()
	{
		auto self = Fiber.getThis();
		if( isSelfRegistered() )
			m_listeners.remove(self);
	}

	bool isSelfRegistered()
	{
		return (Fiber.getThis() in m_listeners) !is null;
	}

	@property int emitCount() const { return m_emitCount; }
}

private extern(C) void onSignalTriggered(evutil_socket_t, short events, void* userptr)
{
	auto sig = cast(Libevent2Signal)userptr;

	sig.m_emitCount++;

	auto lst = sig.m_listeners.dup;
	
	foreach( l, _; lst )
		sig.m_driver.m_core.resumeTask(l);
}
