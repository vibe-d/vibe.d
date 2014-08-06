module vibe.core.events.epoll;

version (linux):

import vibe.core.events.types;

import core.thread : Fiber;
import std.string : toStringz;
import std.container : Array;
import std.conv : to;
import std.datetime : Duration, msecs, seconds;
import std.algorithm : min, iota;
import std.traits : isIntegral;
import std.typecons : Tuple, tuple;
import std.utf : toUTFz;
import core.stdc.errno;

import vibe.core.events.events;

enum SOCKET_ERROR = -1;

import vibe.core.events.tcp;

alias fd_t = int;

struct EventLoopImpl {


package:
	alias error_t = EPosix;

nothrow:
private:

	EventLoop m_evLoop;
	bool m_started;
	fd_t m_epollfd; // epoll instance
	StatusInfo m_status;
	error_t m_error = EPosix.EOK;

	union EventObject {
		TCPAcceptHandler tcpAcceptHandler;
		TCPEventHandler tcpEvHandler;
	}

	enum EventType : char {
		TCPAccept,
		TCPTraffic
	}

	struct EventInfo {
		fd_t fd;
		bool connected;
		EventType evType;
		EventObject evObj;
	}

package:

	@property bool started() const {
		return m_started;
	}
	
	bool init(EventLoop evl) 
	in { assert(!m_started); }
	body
	{
		m_evLoop = evl;
		import core.sys.linux.epoll : epoll_create1;
		m_epollfd = epoll_create1(0);
		if (catchError!"epoll_create1"(m_epollfd))
			return false;
		return true;
	}

	void exit() {
		import core.sys.posix.unistd : close;
		close(m_epollfd);
	}

	@property const(StatusInfo) status() const {
		return m_status;
	}
	

	@property string error() const {
		string* ptr;
		return ((ptr = (m_error in EPosixMessages)) !is null) ? *ptr : string.init;
	}
	
	bool loop(Duration timeout = 0.seconds)
	in { assert(Fiber.getThis() is null); }
	body {
		import core.sys.linux.epoll : epoll_event, epoll_wait;
		bool success = true;
		static epoll_event[] events = new epoll_event[128];
		int timeout_ms;
		if (timeout == 0.seconds)
			timeout_ms = -1;
		else timeout_ms = cast(int)timeout.total!"msecs";

		int num = epoll_wait(m_epollfd, events.ptr, cast(int) events.length, timeout_ms);

		auto errors = 
		[	tuple(EINTR, Status.EVLOOP_TIMEOUT),
			tuple(EBADF, Status.EVLOOP_FAILURE),
			tuple(EFAULT, Status.EVLOOP_FAILURE),
			tuple(EINVAL, Status.EVLOOP_FAILURE) ];	

		if (catchErrors!"epoll_wait"(num, errors)) 
			return false; // everywhere in vibe.core.events, we must swim back to the surface by returning false or 0 anytime an error becomes current or we may drown in them...

		foreach(i; 0 .. num) {
			success = false;
			m_status = StatusInfo.init;
			epoll_event event = events[i];
			EventInfo info = *cast(EventInfo*)event.data.ptr;
			switch (info.evType) {
				default:
					try setInternalError!"wait.EventCategory"(Status.NOT_IMPLEMENTED, info.evType.to!string);
					catch (Exception e) {}
					return false;
				case EventType.TCPAccept:
					success = onTCPAccept(info.fd, info.evObj.tcpAcceptHandler, event.events);
					break;
				case EventType.TCPTraffic:
					assert(info.evObj.tcpEvHandler.conn !is null, "TCP Connection invalid");
					success = onTCPTraffic(info.fd, info.evObj.tcpEvHandler, event.events, &info.connected, info.evObj.tcpEvHandler.conn.inbound);
					if (!success && m_status.code == Status.ABORT) {
						import vibe.utils.memory : FreeListObjectAlloc;
						try info.evObj.tcpEvHandler(TCPEvent.ERROR);
						catch (Exception e) { assert(false, "Error in error handler"); }
						if (info.evObj.tcpEvHandler.conn.inbound) {
							try FreeListObjectAlloc!AsyncTCPConnection.free(info.evObj.tcpEvHandler.conn);
							catch (Exception e){ assert(false, "Error freeing resources"); }
						}
						closeSocket(info.fd, true);
						try FreeListObjectAlloc!EventInfo.free(&info);
						catch (Exception e){ assert(false, "Error freeing resources"); }

					}
					break;
			}

			if (!success && m_status.code == Status.EVLOOP_FAILURE)
				break;

		}
		return success;
	}
	
	fd_t run(AsyncTCPConnection ctxt, TCPEventHandler del)
	in { assert(ctxt.socket == fd_t.init); }
	body {
		import core.sys.posix.sys.socket : socket, SOCK_STREAM;
		fd_t fd = socket(cast(int)ctxt.peer.family, SOCK_STREAM, 0);

		if (catchError!("run AsyncTCPConnection")(fd)) 
			return 0;

		if (!setNonBlock(fd))
			return 0;


		if (ctxt.noDelay)
			setOption(fd, TCPOptions.NODELAY, true);
		
		initTCPConnection(fd, ctxt, del);
		
		return fd;
		
	}

	
	fd_t run(AsyncTCPListener ctxt, TCPAcceptHandler del)
	in { assert(ctxt.socket == fd_t.init); }
	body {
		import core.sys.posix.sys.socket : socket, SOCK_STREAM;
		fd_t fd = socket(cast(int)ctxt.local.family, SOCK_STREAM, 0);

		if (catchError!("run AsyncTCPAccept")(fd))
			return 0;

		if (!setNonBlock(fd))
			return 0;

		if (ctxt.noDelay)
			setOption(fd, TCPOptions.NODELAY, true);

		initTCPListener(fd, ctxt, del);
		
		return fd;
		
	}

	bool kill(AsyncTCPConnection ctxt, bool forced = false)
	{
		fd_t fd = ctxt.socket;
		return closeSocket(fd, true, forced);
	}
	
	bool kill(AsyncTCPListener ctxt)
	{
		fd_t fd = ctxt.socket;
		return closeSocket(fd, false, true);
	}

	bool setOption(T = int)(fd_t fd, TCPOptions option, T value) {
		import std.traits : isIntegral;

		import core.sys.posix.sys.socket : socklen_t, setsockopt, SO_KEEPALIVE, SO_RCVBUF, SO_SNDBUF, SO_RCVTIMEO, SO_SNDTIMEO, SO_LINGER, SOL_SOCKET;
		import std.c.linux.socket : IPPROTO_TCP, TCP_NODELAY, TCP_QUICKACK, TCP_KEEPCNT, TCP_KEEPINTVL, TCP_KEEPIDLE, TCP_CONGESTION, TCP_CORK, TCP_DEFER_ACCEPT;
		int err;

		final switch (option) {
			case TCPOptions.NODELAY: // true/false
				static if (!is(T == bool))
					assert(false, "NODELAY value type must be bool, not " ~ T.stringof);
				else {
					int val = value?1:0;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &val, len);
					break;
				}
			case TCPOptions.QUICK_ACK:
				static if (!is(T == bool))
					assert(false, "QUICK_ACK value type must be int, not " ~ T.stringof);
				else {
					int val = value?1:0;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, IPPROTO_TCP, TCP_QUICKACK, &val, len);
					break;
				}
			case TCPOptions.KEEPALIVE_ENABLE: // true/false
				static if (!is(T == bool))
					assert(false, "KEEPALIVE_ENABLE value type must be bool, not " ~ T.stringof);
				else
				{
					int val = value?1:0;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &val, len);
					break;
				}
			case TCPOptions.KEEPALIVE_COUNT: // ##
				static if (!isIntegral!T)
					assert(false, "KEEPALIVE_COUNT value type must be integral, not " ~ T.stringof);
				else {
					int val = value.total!"msecs".to!uint;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &val, len);
					break;
				}
			case TCPOptions.KEEPALIVE_INTERVAL: // wait ## seconds
				static if (!is(T == Duration))
					assert(false, "KEEPALIVE_INTERVAL value type must be Duration, not " ~ T.stringof);
				else {
					int val = value.total!"seconds".to!uint;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &val, len);
					break;
				}
			case TCPOptions.KEEPALIVE_DEFER: // wait ## seconds until start
				static if (!is(T == Duration))
					assert(false, "KEEPALIVE_DEFER value type must be Duration, not " ~ T.stringof);
				else {
					int val = value.total!"seconds".to!uint;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, IPPROTO_TCP, TCP_KEEPIDLE, &val, len);
					break;
				}
			case TCPOptions.BUFFER_RECV: // bytes
				static if (!isIntegral!T)
					assert(false, "BUFFER_RECV value type must be integral, not " ~ T.stringof);
				else {
					int val = value.to!int;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &val, len);
					break;
				}
			case TCPOptions.BUFFER_SEND: // bytes
				static if (!isIntegral!T)
					assert(false, "BUFFER_SEND value type must be integral, not " ~ T.stringof);
				else {
					int val = value.to!int;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &val, len);
					break;
				}
			case TCPOptions.TIMEOUT_RECV:
				static if (!is(T == Duration))
					assert(false, "TIMEOUT_RECV value type must be Duration, not " ~ T.stringof);
				else {
					time_t secs = value.total!"seconds".to!time_t;
					suseconds_t us = value.fracSec.usecs.to!suseconds_t;
					timeval t = timeval(secs, us);
					socklen_t len = t.sizeof;
					err = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, len);
					break;
				}
			case TCPOptions.TIMEOUT_SEND:
				static if (!is(T == Duration))
					assert(false, "TIMEOUT_SEND value type must be Duration, not " ~ T.stringof);
				else {
					time_t secs = value.total!"seconds".to!time_t;
					suseconds_t us = value.fracSec.usecs.to!suseconds_t;
					timeval t = timeval(secs, us);
					socklen_t len = t.sizeof;
					err = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &t, len);
					break;
				}
			case TCPOptions.TIMEOUT_HALFOPEN:
				static if (!is(T == Duration))
					assert(false, "TIMEOUT_SEND value type must be Duration, not " ~ T.stringof);
				else {
					uint val = value.total!"msecs".to!uint;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &val, len);
					break;
				}
			case TCPOptions.LINGER: // bool onOff, int seconds
				static if (!is(T == Tuple!(bool, int)))
					assert(false, "LINGER value type must be Tuple!(bool, int), not " ~ T.stringof);
				else {
					linger l = linger(val[0]?1:0, val[1]);
					socklen_t llen = l.sizeof;
					err = setsockopt(fd, SOL_SOCKET, SO_LINGER, &l, llen);
					break;
				}
			case TCPOptions.CONGESTION:
				static if (!isIntegral!T)
					assert(false, "CONGESTION value type must be integral, not " ~ T.stringof);
				else {
					int val = value.to!int;
					len = int.sizeof;
					err = setsockopt(fd, IPPROTO_TCP, TCP_CONGESTION, &val, len);
					break;
				}
			case TCPOptions.CORK:
				static if (!isIntegral!T)
					assert(false, "CORK value type must be int, not " ~ T.stringof);
				else {
					int val = value.to!int;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, IPPROTO_TCP, TCP_CORK, &val, len);
					break;
				}
			case TCPOptions.DEFER_ACCEPT: // seconds
				static if (!isIntegral!T)
					assert(false, "DEFER_ACCEPT value type must be integral, not " ~ T.stringof);
				else {
					int val = value.to!int;
					socklen_t len = val.sizeof;
					err = setsockopt(fd, IPPROTO_TCP, TCP_DEFER_ACCEPT, &val, len);
					break;
				}
		}

		if (catchSocketError!"setOption:"(fd, err)) {
			try m_status.text ~= option.to!string;
			catch (Exception e){ assert(false, "to!string conversion failure"); }
			return false;
		}
		return true;
	}

	uint recv(in fd_t fd, ref ubyte[] data)
	{
		import core.sys.posix.sys.socket : recv;
		int ret = cast(int) recv(fd, cast(void*) data.ptr, data.length, cast(int)0);
		
		static if (LOG) log(".recv " ~ ret.to!string ~ " bytes of " ~ data.length.to!string ~ " @ " ~ fd.to!string);
		if (catchSocketError!".recv"(fd, ret)) // ret == SOCKET_ERROR == -1 ?
			return 0; // TODO: handle some errors more specifically
		
		m_status.code = Status.OK;
		
		return cast(uint) ret;
	}
	
	uint send(in fd_t fd, in ubyte[] data)
	{
		import core.sys.posix.sys.socket : send;
		int ret = cast(int) send(fd, cast(const(void)*) data.ptr, data.length, cast(int)0);

		if (catchSocketError!"send"(fd, ret)) // ret == -1
			return 0; // TODO: handle some errors more specifically
		
		m_status.code = Status.ASYNC;
		return cast(uint) ret;
	}


	uint read(in fd_t fd, ref ubyte[] data)
	{
		return 0;
	}
	
	uint write(in fd_t fd, in ubyte[] data)
	{
		return 0;
	}

	private bool closeRemoteSocket(fd_t fd, bool forced) {
		
		int err;

		import core.sys.posix.sys.socket : shutdown, SHUT_WR, SHUT_RDWR;
		if (forced)
			err = shutdown(fd, SHUT_RDWR);
		else
			err = shutdown(fd, SHUT_WR);
		
		if (catchError!"shutdown"(err))
			return false;

		return true;
	}

	// for connected sockets
	bool closeSocket(fd_t fd, bool connected, bool forced = false)
	{

		if (connected && !closeRemoteSocket(fd, forced))
			return false;
		
		if (!connected || forced) {
			// todo: flush the socket here?

			import core.sys.posix.unistd : close;
			int err = close(fd);
			if (catchError!"closesocket"(err)) 
				return false;
		}
		return true;
	}

	
	NetworkAddress getAddressFromIP(in string ipAddr, in ushort port = 0, in bool ipv6 = false, in bool tcp = true) 
	in {
		import vibe.core.events.validator;
		assert( validateIPv4(ipAddr) || validateIPv6(ipAddr) );
	}
	body {
		import std.c.linux.socket : addrinfo, AI_NUMERICHOST, AI_NUMERICSERV;
		addrinfo hints;
		hints.ai_flags |= AI_NUMERICHOST | AI_NUMERICSERV; // Specific to an IP resolver!

		return getAddressInfo(ipAddr, port, ipv6, tcp, hints);
	}


	NetworkAddress getAddressFromDNS(in string host, in ushort port = 0, in bool ipv6 = true, in bool tcp = true)
	in { 
		import vibe.core.events.validator;	
		assert(validateHost(host)); 
	}
	body {
		import std.c.linux.socket : addrinfo;
		addrinfo hints;
		return getAddressInfo(host, port, ipv6, tcp, hints);
	}
	
	void setInternalError(string TRACE)(in Status s, in string details = "", in error_t error = EPosix.EACCES)
	{
		if (details.length > 0)
			m_status.text = TRACE ~ ": " ~ details;
		else m_status.text = TRACE;
		m_error = error;
		m_status.code = s;
		static if(LOG) log(m_status);
	}
private:	

	// socket must not be connected
	bool setNonBlock(fd_t fd) {
		import core.sys.posix.fcntl : fcntl, F_GETFL, F_SETFL, O_NONBLOCK;
		int flags = fcntl(fd, F_GETFL);
		flags |= O_NONBLOCK;
		int err = fcntl(fd, F_SETFL, flags);
		if (catchError!"F_SETFL O_NONBLOCK"(err)) {
			closeSocket(fd, false);
			return false;
		}
		return true;
	}
	
	bool onTCPAccept(fd_t fd, TCPAcceptHandler del, uint events)
	{
		import core.sys.linux.epoll : EPOLLIN, EPOLLERR;
		import core.sys.posix.sys.socket : AF_INET, AF_INET6, socklen_t, accept;
		if (events & EPOLLIN) { // accept incoming connection
			NetworkAddress addr;
			addr.family = AF_INET6;
			socklen_t addrlen = addr.sockAddrLen;
			fd_t csock = accept(fd, addr.sockAddr, &addrlen); // todo: use accept4 to set SOCK_NONBLOCK
			// make non-blocking
			if (!setNonBlock(csock))
				return false;

			if (addrlen < addr.sockAddrLen)
				addr.family = AF_INET;
			if (addrlen == addrlen.init) {
				setInternalError!"addrlen"(Status.ABORT);
				return false;
			}
			catchSocketError!".accept"(csock, SOCKET_ERROR);
			import vibe.utils.memory : FreeListObjectAlloc;
			AsyncTCPConnection conn;
			try conn = FreeListObjectAlloc!AsyncTCPConnection.alloc(m_evLoop);
			catch (Exception e){ assert(false, "Allocation failure"); }
			conn.peer = addr;
			conn.socket = csock;

			nothrow bool closeAll() {
				try FreeListObjectAlloc!AsyncTCPConnection.free(conn);
				catch (Exception e){ assert(false, "Free failure"); }
				closeSocket(csock, true, true);
				return false;
			}

			try {
				TCPEventHandler evh = del(conn);
				if (evh == TCPEventHandler.init || !initTCPConnection(csock, conn, evh, true)) {
					return closeAll();
				}
			}
			catch (Exception e) {
				return closeAll();
			}

		}
		
		if (events & EPOLLERR) { // socket failure
			catchSocketError!"EPOLLERR"(fd, SOCKET_ERROR);
			try del(null);
			catch(Exception e){ assert(false, "Failure calling TCPAcceptHandler(null)"); }
			closeSocket(fd, false);
			return false;
		}
		return true;
	}

	bool onTCPTraffic(fd_t fd, TCPEventHandler del, uint events, bool* connected, bool inbound) 
	{
		import core.sys.linux.epoll : EPOLLIN, EPOLLERR, EPOLLOUT, EPOLLRDHUP, EPOLLHUP;
		if (events & EPOLLIN) {
			
			try {
				if (!inbound && !connected) {
					*connected = true;
					del(TCPEvent.CONNECT);
					return true;
				}
				else
					del(TCPEvent.READ);
			}
			catch (Exception e) {
				setInternalError!"del@TCPEvent.READ"(Status.ABORT);
				return false;
			}
		}
		if (events & EPOLLOUT) { 
			try del(TCPEvent.WRITE);
			catch (Exception e) {
				setInternalError!"del@TCPEvent.WRITE"(Status.ABORT);
				return false;
			}
		}
		if (events & EPOLLRDHUP) { // peer shutdown (FIN)
			try del(TCPEvent.CLOSE);
			catch (Exception e) {
				setInternalError!"del@TCPEvent.CLOSE"(Status.ABORT);
				return false;
			}
			closeSocket(fd, true);
		}
		if (events & EPOLLHUP) { // possible connection reset (RST)
			try del(TCPEvent.CLOSE);
			catch (Exception e) {
				setInternalError!"del@TCPEvent.CLOSE"(Status.ABORT);
				return false;
			}
			closeSocket(fd, true);
		}
		if (events & EPOLLERR) { // socket failure
			import core.sys.posix.sys.socket : socklen_t, getsockopt, SOL_SOCKET, SO_ERROR;
			int error;
			socklen_t errlen = error.sizeof;
			getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &errlen);
			setInternalError!"EPOLLERR"(Status.ABORT, null, cast(error_t)error);
			closeSocket(fd, true, true);
			return false;
		}

		return true;
	}

	bool initTCPListener(fd_t fd, AsyncTCPListener ctxt, TCPAcceptHandler del)
	in {
		assert(ctxt.local !is NetworkAddress.init);
	}
	body {
		import core.sys.linux.epoll : epoll_event, epoll_ctl, EPOLL_CTL_ADD, EPOLLIN;
		import core.sys.posix.sys.socket : bind, listen, SOMAXCONN;
		int err;
		epoll_event event;
		EventObject eo;
		eo.tcpAcceptHandler = del;
		EventInfo* ev;
		import vibe.utils.memory : FreeListObjectAlloc;
		try ev = FreeListObjectAlloc!EventInfo.alloc(fd, false, EventType.TCPAccept, eo);
		catch (Exception e){ assert(false, "Allocation error"); }
		event.data.ptr = ev;
		event.events |= EPOLLIN;
		err = epoll_ctl(m_epollfd, EPOLL_CTL_ADD, fd, &event);

		nothrow bool closeAll() {
			try FreeListObjectAlloc!EventInfo.free(ev);
			catch(Exception e){ assert(false, "Failed free"); }
			closeSocket(fd, false);
			return false;
		}

		if (catchError!"epoll_ctl_add"(err))
			return closeAll();

		err = bind(fd, ctxt.local.sockAddr, ctxt.local.sockAddrLen);

		if (catchError!"bind"(err))
			return closeAll();

		err = listen(fd, SOMAXCONN);
		if (catchError!"listen"(err))
			return closeAll();

		return true;
	}
	
	bool initTCPConnection(fd_t fd, AsyncTCPConnection ctxt, TCPEventHandler del, bool inbound = false)
	in { 
		assert(ctxt.peer !is NetworkAddress.init);
		assert(ctxt.peer.port != 0, "Connecting to an invalid port");
	}
	body {
		import core.sys.linux.epoll : epoll_event, epoll_ctl, EPOLL_CTL_ADD, EPOLLIN, EPOLLOUT, EPOLLERR, EPOLLHUP, EPOLLRDHUP;
		import core.sys.posix.sys.socket : connect;
		int err;
		epoll_event event;
		// add to epoll
		EventObject eo;
		eo.tcpEvHandler = del;
		EventInfo* ev;

		import vibe.utils.memory : FreeListObjectAlloc;
		try ev = FreeListObjectAlloc!EventInfo.alloc(fd, false, EventType.TCPAccept, eo);
		catch (Exception e){ assert(false, "Allocation error"); }
		event.data.ptr = ev;
		event.events |= EPOLLIN | EPOLLOUT | EPOLLERR | EPOLLHUP | EPOLLRDHUP;
		err = epoll_ctl(m_epollfd, EPOLL_CTL_ADD, fd, &event);
		if (catchError!"epoll_ctl_add"(err)) { 
			closeSocket(fd, false);
			return false;
		}

		if (inbound) return true;

		// make non-blocking
		if (!setNonBlock(fd))
			return false;

		// connect
		err = connect(fd, ctxt.peer.sockAddr, ctxt.peer.sockAddrLen);
		if (catchErrorsEq!"connect"(err, [ tuple(cast(fd_t)SOCKET_ERROR, EPosix.EINPROGRESS, Status.ASYNC) ]))
			return true;

		if ( catchError!"connect"(err) ) {
			closeSocket(fd, false);
			return false;
		}

		return true;
	}

	bool catchError(string TRACE, T)(T val, T cmp = SOCKET_ERROR)
		if (isIntegral!T)
	{
		if (val == cmp) {
			m_status.text = TRACE;
			m_error = lastError();
			m_status.code = Status.ABORT;
			static if(LOG) log(m_status);
			return true;
		}
		return false;
	}

	bool catchSocketError(string TRACE, T)(fd_t fd, T val, T cmp = SOCKET_ERROR)
		if (isIntegral!T)
	{
		if (val == cmp) {
			m_status.text = TRACE;
			int err;
			import core.sys.posix.sys.socket : getsockopt, socklen_t, SOL_SOCKET, SO_ERROR;
			socklen_t len = int.sizeof;
			getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len);
			m_error = cast(error_t) err;
			m_status.code = Status.ABORT;
			static if(LOG) log(m_status);
			return true;
		}
		return false;
	}

	bool catchErrors(string TRACE, T)(T val, Tuple!(T, Status)[] cmp ...)
		if (isIntegral!T)
	{
		foreach (validator ; cmp) {
			if (val == validator[0]) {
				m_status.text = TRACE;
				m_error = lastError();
				m_status.code = validator[1];
				static if(LOG) log(m_status);
				return true;
			}
		}
		return false;
	}

	/**
	 * If the value at val matches the tuple first argument T, get the last error,
	 * and if the last error matches tuple second argument error_t, set the Status as
	 * tuple third argument Status.
	 * 
	 * Repeats for each comparison tuple until a match in which case returns true.
	*/
	bool catchErrorsEq(string TRACE, T)(T val, Tuple!(T, error_t, Status)[] cmp ...)
		if (isIntegral!T)
	{
		error_t err;
		foreach (validator ; cmp) {
			if (val == validator[0]) {
				if (err is EPosix.init) err = lastError();
				if (err == validator[1]) {
					m_status.text = TRACE;
					m_error = lastError();
					m_status.code = validator[2];
					static if(LOG) log(m_status);
					return true;
				}
			}
		}
		return false;
	}


	error_t lastError() {
		try {
			return cast(error_t) errno;
		} catch(Exception e) {
			return EPosix.EACCES;
		}

	}
	
	debug void log(StatusInfo val)
	{
		import std.stdio;
		try {
			writeln("Backtrace: ", m_status.text);
			writeln(" | Status:  ", m_status.code);
			writeln(" | Error: " , m_error);
			if ((m_error in EPosixMessages) !is null)
				writeln(" | Message: ", EPosixMessages[m_error]);
		} catch(Exception e) {
			return;
		}
	}

	debug void log(T)(T val)
	{
		import std.stdio;
		try {
			writeln(val);
		} catch(Exception e) {
			return;
		}
	}

	NetworkAddress getAddressInfo(addrinfo)(in string host, ushort port, bool ipv6, bool tcp, ref addrinfo hints) 
	{
		import core.sys.posix.sys.socket : AF_INET, AF_INET6, SOCK_DGRAM, SOCK_STREAM;
		import std.c.linux.socket : IPPROTO_TCP, IPPROTO_UDP, freeaddrinfo, getaddrinfo;

		NetworkAddress addr;
		addrinfo* infos;
		error_t err;
		if (ipv6) {
			addr.family = AF_INET6;
			hints.ai_family = AF_INET6;
		}
		else {
			addr.family = AF_INET;
			hints.ai_family = AF_INET;
		}
		if (tcp) {
			hints.ai_socktype = SOCK_STREAM;
			hints.ai_protocol = IPPROTO_TCP;
		}
		else {
			hints.ai_socktype = SOCK_DGRAM;
			hints.ai_protocol = IPPROTO_UDP;
		}

		static if (LOG) {
			log(host);
			log(port.to!string);
		}

		auto chost = host.toStringz();

		if ( port != 0 ) {
			addr.port = port;
			const(char)* cPort = cast(const(char)*) port.to!string.toStringz;


			err = cast(error_t) getaddrinfo(chost, cPort, &hints, &infos);
		}
		else {
			err = cast(error_t) getaddrinfo(chost, null, &hints, &infos);
		}

		if (err != EPosix.EOK) {
			setInternalError!"getAddressInfo"(Status.ERROR, string.init, err);
			return NetworkAddress.init;
		}
		ubyte* pAddr = cast(ubyte*) infos.ai_addr;
		ubyte* data = cast(ubyte*) addr.sockAddr;
		data[0 .. infos.ai_addrlen] = pAddr[0 .. infos.ai_addrlen]; // perform bit copy
		freeaddrinfo(infos);
		return addr;
	}

	
}

/**
		Represents a network/socket address. (taken from vibe.core.net)
*/
public struct NetworkAddress {
	import std.c.linux.socket : sockaddr, sockaddr_in, sockaddr_in6, AF_INET, AF_INET6;
	private union {
		sockaddr addr;
		sockaddr_in addr_ip4;
		sockaddr_in6 addr_ip6;
	}
	
	/** Family (AF_) of the socket address.
		*/
	@property ushort family() const pure nothrow { return addr.sa_family; }
	/// ditto
	@property void family(ushort val) pure nothrow { addr.sa_family = cast(ubyte)val; }
	
	/** The port in host byte order.
		*/
	@property ushort port()
	const pure nothrow {
		switch (this.family) {
			default: assert(false, "port() called for invalid address family.");
			case AF_INET: return ntoh(addr_ip4.sin_port);
			case AF_INET6: return ntoh(addr_ip6.sin6_port);
		}
	}
	/// ditto
	@property void port(ushort val)
	pure nothrow {
		switch (this.family) {
			default: assert(false, "port() called for invalid address family.");
			case AF_INET: addr_ip4.sin_port = hton(val); break;
			case AF_INET6: addr_ip6.sin6_port = hton(val); break;
		}
	}
	
	/** A pointer to a sockaddr struct suitable for passing to socket functions.
		*/
	@property inout(sockaddr)* sockAddr() inout pure nothrow { return &addr; }
	
	/** Size of the sockaddr struct that is returned by sockAddr().
		*/
	@property int sockAddrLen()
	const pure nothrow {
		switch (this.family) {
			default: assert(false, "sockAddrLen() called for invalid address family.");
			case AF_INET: return addr_ip4.sizeof;
			case AF_INET6: return addr_ip6.sizeof;
		}
	}
	
	@property inout(sockaddr_in)* sockAddrInet4() inout pure nothrow
	in { assert (family == AF_INET); }
	body { return &addr_ip4; }
	
	@property inout(sockaddr_in6)* sockAddrInet6() inout pure nothrow
	in { assert (family == AF_INET6); }
	body { return &addr_ip6; }
	
	/** Returns a string representation of the IP address
		*/
	string toAddressString()
	const {
		import std.array : appender;
		import std.string : format;
		import std.format : formattedWrite;
		
		switch (this.family) {
			default: assert(false, "toAddressString() called for invalid address family.");
			case AF_INET:
				ubyte[4] ip = (cast(ubyte*)&addr_ip4.sin_addr.s_addr)[0 .. 4];
				return format("%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
			case AF_INET6:
				ubyte[16] ip = addr_ip6.sin6_addr.s6_addr;
				auto ret = appender!string();
				ret.reserve(40);
				foreach (i; 0 .. 8) {
					if (i > 0) ret.put(':');
					ret.formattedWrite("%x", bigEndianToNative!ushort(cast(ubyte[2])ip[i*2 .. i*2+2]));
				}
				return ret.data;
		}
	}
	
	/** Returns a full string representation of the address, including the port number.
		*/
	string toString()
	const {
		
		import std.string : format;
		
		auto ret = toAddressString();
		switch (this.family) {
			default: assert(false, "toString() called for invalid address family.");
			case AF_INET: return ret ~ format(":%s", port);
			case AF_INET6: return format("[%s]:%s", ret, port);
		}
	}
	
}

private pure nothrow {
	import std.bitmanip;
	
	ushort ntoh(ushort val)
	{
		version (LittleEndian) return swapEndian(val);
		else version (BigEndian) return val;
		else static assert(false, "Unknown endianness.");
	}
	
	ushort hton(ushort val)
	{
		version (LittleEndian) return swapEndian(val);
		else version (BigEndian) return val;
		else static assert(false, "Unknown endianness.");
	}
}