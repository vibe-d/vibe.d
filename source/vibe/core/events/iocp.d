module vibe.core.events.iocp;

version (Windows):

import core.atomic;
import core.thread : Fiber;
import vibe.core.events.types;
import vibe.utils.hashmap;
import vibe.utils.array;
import std.string : toStringz;
import std.conv : to;
import std.datetime : Duration, msecs, seconds;
import std.algorithm : min;
import std.c.windows.windows;
import std.c.windows.winsock;
import vibe.internal.win32;
import std.traits : isIntegral;
import std.typecons : Tuple, tuple;
import std.utf : toUTFz;
import vibe.core.events.tcp;
import vibe.core.events.events;
pragma(lib, "ws2_32");
alias fd_t = SIZE_T;
alias error_t = EWIN;


package struct EventLoopImpl {
	pragma(msg, "Using Windows IOCP for events");

private:
	HashMap!(fd_t, TCPAcceptHandler)* m_connHandlers;
	HashMap!(fd_t, TCPEventHandler)* m_evHandlers;

nothrow:
private:
	EventLoop m_evLoop;
	bool m_started;
	wstring m_window;
	HWND m_hwnd;
	DWORD m_threadId;
	HANDLE[] m_waitObjects;
	ushort m_instanceId;
	StatusInfo m_status;
	error_t m_error = EWIN.WSA_OK;

package:
	@property bool started() const {
		return m_started;
	}
	bool init(EventLoop evl) 
	in { assert(!m_started); }
	body
	{
		import vibe.utils.memory : defaultAllocator, FreeListObjectAlloc;
		try {
			m_connHandlers = FreeListObjectAlloc!(typeof(*m_connHandlers)).alloc(defaultAllocator());
			m_evHandlers = FreeListObjectAlloc!(typeof(*m_evHandlers)).alloc(defaultAllocator());
		} catch (Exception e) { assert(false, "failed to setup allocator strategy in HashMap"); }
		m_evLoop = evl;
		shared static ushort i;
		core.atomic.atomicOp!"+="(i, cast(ushort) 1);
		m_instanceId = i;
		wstring inststr;
		try { inststr = m_instanceId.to!wstring; }
		catch (Exception e) {
			return false;
		}
		m_window = "VibeWin32MessageWindow" ~ inststr;
		wstring classname = "VibeWin32MessageWindow" ~ inststr;
		
		LPCWSTR wnz;
		LPCWSTR clsn;
		try {
			wnz = cast(LPCWSTR) m_window.toUTFz!(immutable(wchar)*);
			clsn = cast(LPCWSTR) classname.toUTFz!(immutable(wchar)*);
		} catch (Exception e) {
			setInternalError!"toUTFz"(Status.ERROR, e.msg);
			return false;
		}
		
		m_threadId = GetCurrentThreadId();
		WNDCLASSW wc;
		wc.lpfnWndProc = &wndProc;
		wc.lpszClassName = clsn;
		RegisterClassW(&wc);
		m_hwnd = CreateWindowW(wnz, clsn, 0, 0, 0, 385, 375, HWND_MESSAGE,
		                       cast(HMENU) null, null, null);
		SetWindowLongPtrA(m_hwnd, GWLP_USERDATA, cast(ULONG_PTR)cast(void*)&this);
		assert( cast(EventLoopImpl*)cast(void*)GetWindowLongPtrA(m_hwnd, GWLP_USERDATA) is &this );
		WSADATA wd;
		m_error = cast(error_t) WSAStartup(0x0202, &wd);
		if (m_error == EWIN.WSA_OK)	
			m_status.code = Status.OK;
		else {
			m_status.code = Status.ABORT;
			static if(LOG) log(m_status);
			return false;
		}
		assert(wd.wVersion == 0x0202);
		m_started = true;
		return true;
	}

	// todo: find where to call this
	void exit() {
		PostThreadMessageW(m_threadId, WM_QUIT, 0, 0);
	}

	@property StatusInfo status() const {
		return m_status;
	}

	@property string error() const {
		string* ptr;
		string pv = ((ptr = (m_error in EWSAMessages)) !is null) ? *ptr : string.init;
		/* Todo: make windows return the message
		 * if (pv is string.init) {
			pv = new immutable(char)[128];
			fd_t sz;
			FormatMessageA( 
				FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
				null,
				m_error,
				MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), 
				cast(LPTSTR) pv.ptr,
				&sz,
				null
			);
			pv = m_error.to!string;
		}*/
		return pv;
	}

	bool loop(Duration timeout = 0.seconds)
	in { 
		assert(Fiber.getThis() is null); 
		assert(m_connHandlers !is null);
		assert(m_evHandlers !is null);
		assert(m_started);
	}
	body {
		DWORD msTimeout = cast(DWORD) min(timeout.total!"msecs", DWORD.max);
		/* 
		 * Waits until one or all of the specified objects are in the signaled state
		 * http://msdn.microsoft.com/en-us/library/windows/desktop/ms684245%28v=vs.85%29.aspx
		*/
		DWORD signal = MsgWaitForMultipleObjectsEx(
			cast(DWORD)m_waitObjects.length,
			m_waitObjects.ptr,
			msTimeout,
			QS_ALLEVENTS,								
			MWMO_ALERTABLE | MWMO_INPUTAVAILABLE		// MWMO_ALERTABLE: Wakes up to execute overlapped hEvent (i/o completion)
														// MWMO_INPUTAVAILABLE: Processes key/mouse input to avoid window ghosting
		);

		auto errors = 
			[	tuple(WAIT_TIMEOUT, Status.EVLOOP_TIMEOUT),		/* WAIT_TIMEOUT: Timeout was hit */
				tuple(WAIT_FAILED, Status.EVLOOP_FAILURE) ];	/* WAIT_FAILED: Failed to call MsgWait..() */

		if (catchErrors!"MsgWaitForMultipleObjectsEx"(signal, errors))
			return false; 
		
		MSG msg;
		while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE)) {
			TranslateMessage(&msg);
			DispatchMessageW(&msg);
			if (m_status.code == Status.ERROR)
				return false;
		}
		return true;
	}

	fd_t run(AsyncTCPListener ctxt, TCPAcceptHandler del)
	{
		fd_t fd = WSASocketW(cast(int)ctxt.local.family, SOCK_STREAM, IPPROTO_TCP, null, 0, WSA_FLAG_OVERLAPPED);
		
		if (catchSocketError!("run AsyncTCPConnection")(fd, INVALID_SOCKET))
			return 0;

		if (ctxt.noDelay) {
			BOOL eni = true;
			setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &eni, eni.sizeof);
		}

		if (initTCPListener(fd, ctxt))
		{
			try {
				(*m_connHandlers)[fd] = del;
			}
			catch (Exception e) {
				setInternalError!"m_connHandlers assign"(Status.ERROR, e.msg);
				closeSocket(fd, false);
				return 0;
			}
		}
		return fd;
	}

	fd_t run(AsyncTCPConnection ctxt, TCPEventHandler del)
	in { 
		assert(ctxt.socket == fd_t.init); 
		assert(ctxt.peer.family != AF_UNSPEC);
	}
	body {
		fd_t fd = WSASocketW(cast(int)ctxt.peer.family, SOCK_STREAM, IPPROTO_TCP, null, 0, WSA_FLAG_OVERLAPPED);

		log("Starting connection at: " ~ fd.to!string);
		if (catchSocketError!("run AsyncTCPConnection")(fd, INVALID_SOCKET))
			return 0;

		try {
			(*m_evHandlers)[fd] = del;
		}
		catch (Exception e) {
			setInternalError!"m_evHandlers assign"(Status.ERROR, e.msg);
			return 0;
		}
		debug {
			TCPEventHandler evh;
			try evh = m_evHandlers.get(fd);
			catch (Exception e) { log("Failed"); return 0; }
			assert( evh !is TCPEventHandler.init);
		}
		if (ctxt.noDelay) {
			BOOL eni = true;
			setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &eni, eni.sizeof);
		}

		if (!initTCPConnection(fd, ctxt)) {
			try {
				log("Remove event handler for " ~ fd.to!string);
				m_evHandlers.remove(fd);
			}
			catch (Exception e) {
				setInternalError!"m_evHandlers remove"(Status.ERROR, e.msg);
			}

			closeSocket(fd, false);
			return 0;
		}

		log("Got file descriptor: " ~  fd.to!string);

		return fd;
	}

	bool kill(AsyncTCPConnection ctxt, bool forced = false)
	{

		fd_t fd = ctxt.socket;

		log("Killing socket "~ fd.to!string);
		try { 
			if ((ctxt.socket in *m_evHandlers) !is null)
				return closeSocket(fd, true, forced);
			else // todo: review this, does it make sense?
				cast(void) closesocket(fd);
		} catch (Exception e) {
			setInternalError!"in m_evHandlers"(Status.ERROR, e.msg);
			return false;
		}

		return true;
	}

	bool kill(AsyncTCPListener ctxt)
	{
		fd_t fd = ctxt.socket;
		try { 
			if ((ctxt.socket in *m_connHandlers) !is null) {
				return closeSocket(fd, false, true);
			}
		} catch (Exception e) {
			setInternalError!"in m_connHandlers"(Status.ERROR, e.msg);
			return false;
		}

		return true;
	}

	bool setOption(T = int)(fd_t fd, TCPOptions option, T value) {
		return true;
	}

	uint read(in fd_t fd, ref ubyte[] data)
	{
		return 0;
	}

	uint write(in fd_t fd, in ubyte[] data)
	{
		return 0;
	}

	uint recv(in fd_t fd, ref ubyte[] data)
	{
		int ret = .recv(fd, cast(void*) data.ptr, cast(INT) data.length, 0);

		if (catchSocketError!".recv"(ret)) { // ret == -1
			if (m_error == WSAEWOULDBLOCK)
				m_status.code = Status.ASYNC;
			return 0; // TODO: handle some errors more specifically
		}
		m_status.code = Status.OK;

		return cast(uint) ret;
	}

	uint send(in fd_t fd, in ubyte[] data)
	{
		int ret = .send(fd, cast(const(void)*) data.ptr, cast(INT) data.length, 0);

		if (catchSocketError!"send"(ret)) // ret == -1
			return 0; // TODO: handle some errors more specifically

		m_status.code = Status.ASYNC;
		return cast(uint) ret;
	}

	void noDelay(in fd_t fd, bool b) {
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &b, b.sizeof);
	}

	bool notify(in fd_t fd) {

		return false;
	}

	private bool closeRemoteSocket(fd_t fd, bool forced) {

		INT err;

		if (forced)
			err = shutdown(fd, SD_BOTH);
		else
			err = shutdown(fd, SD_SEND);
		
		if (catchSocketError!"shutdown"(err))
			return false;
		if (forced) {
			try {
				TCPEventHandler* evh = fd in *m_evHandlers;
				if (evh) {
					import vibe.utils.memory : FreeListObjectAlloc;
					try FreeListObjectAlloc!AsyncTCPConnection.free(evh.conn);
					catch(Exception e) { assert(false, "Failed to free resources"); }
					log("Remove event handler for " ~ fd.to!string);
					m_evHandlers.remove(fd);
				}
			}
			catch (Exception e) {
				setInternalError!"m_evHandlers.remove"(Status.ERROR);
				return false;
			}
		}
		return true;
	}

	// for connected sockets
	bool closeSocket(fd_t fd, bool connected, bool forced = false)
	{

		if (!connected && forced) {
			try {
				if (fd in *m_connHandlers) {
					log("Removing connection handler for: " ~ fd.to!string);
					m_connHandlers.remove(fd);
				}
			}
			catch (Exception e) {
				setInternalError!"m_connHandlers.remove"(Status.ERROR);
				return false;
			}
		}
		else if (connected && !closeRemoteSocket(fd, forced))
			// invokes m_evHandlers.remove()
			return false;

		if (!connected || forced) {
			// todo: flush the socket here?
			INT err = closesocket(fd);
			if (catchSocketError!"closesocket"(err)) 
				return false;
		}
		return true;
	}

	bool closeConnection(fd_t fd) {
		return closeSocket(fd, true);
	}

	NetworkAddress getAddressFromIP(in string ipAddr, in ushort port = 0, in bool ipv6 = false, in bool tcp = true)
	in {
		import vibe.core.events.validator;
		assert( validateIPv4(ipAddr) || validateIPv6(ipAddr));
	}
	body {
		NetworkAddress addr;
		WSAPROTOCOL_INFO hints;
		import std.conv : to;
		if (ipv6) {
			hints.iAddressFamily = AF_INET6;
			addr.family = AF_INET6;
		}
		else {
			hints.iAddressFamily = AF_INET;
			addr.family = AF_INET;
		}
		if (tcp) {
			hints.iProtocol = IPPROTO_TCP;
			hints.iSocketType = SOCK_STREAM;
		}
		else {
			hints.iProtocol = IPPROTO_UDP;
			hints.iSocketType = SOCK_DGRAM;
		}

		if (port != 0) addr.port = port;

		INT addrlen = addr.sockAddrLen;
		LPTSTR str;
		try {
			str = cast(LPTSTR) toStringz(ipAddr);
		} catch (Exception e) {
			setInternalError!"toUTFz"(Status.ERROR, e.msg);
			return NetworkAddress.init;
		}

		INT err = WSAStringToAddressA(str, addr.family.to!int, &hints, addr.sockAddr, &addrlen); 
		if( catchSocketError!"getAddressFromIP"(err) )
			return NetworkAddress.init;
		else assert(addrlen == addr.sockAddrLen);
		return addr;
	}

	NetworkAddress getAddressFromDNS(in string host, in ushort port = 0, in bool ipv6 = true, in bool tcp = true, in bool force = true)
	in { 
		import vibe.core.events.validator;
		assert(validateHost(host));
	}
	body {
		import std.conv : to;
		NetworkAddress addr;
		ADDRINFOW hints;
		ADDRINFOW* infos;
		LPCWSTR wPort = port.to!(wchar[]).toUTFz!(const(wchar)*);
		if (ipv6) {
			hints.ai_family = AF_INET6;
			addr.family = AF_INET6;
		}
		else {
			hints.ai_family = AF_INET;
			addr.family = AF_INET;
		}
		
		if (tcp) {
			hints.ai_protocol = IPPROTO_TCP;
			hints.ai_socktype = SOCK_STREAM;
		}
		else {
			hints.ai_protocol = IPPROTO_UDP;
			hints.ai_socktype = SOCK_DGRAM;
		}
		if (port != 0) addr.port = port;
		
		LPCWSTR str;
		
		try {
			str = cast(LPCWSTR) toUTFz!(immutable(wchar)*)(host);
		} catch (Exception e) {
			setInternalError!"toUTFz"(Status.ERROR, e.msg);
			return NetworkAddress.init;
		}

		log("family: " ~ addr.family.to!string);

		log("protocol: " ~ hints.ai_protocol.to!string);
		log("family: " ~ hints.ai_family.to!string);
		log("socktype: " ~ hints.ai_socktype.to!string);

		error_t err = cast(error_t) GetAddrInfoW(str, cast(LPCWSTR) wPort, &hints, &infos);
		if (err != EWIN.WSA_OK) {
			setInternalError!"GetAddrInfoW"(Status.ABORT, string.init, err);
			return NetworkAddress.init;
		}

		ubyte* pAddr = cast(ubyte*) infos.ai_addr;
		ubyte* data = cast(ubyte*) addr.sockAddr;
		data[0 .. infos.ai_addrlen] = pAddr[0 .. infos.ai_addrlen]; // perform bit copy
		FreeAddrInfoW(infos);
		try log("GetAddrInfoW Successfully resolved DNS to: " ~ addr.toAddressString());
		catch (Exception e){}
		return addr;
	}

	void setInternalError(string TRACE)(in Status s, in string details = "", in error_t error = EWIN.ERROR_ACCESS_DENIED)
	{
		if (details.length > 0)
			m_status.text = TRACE ~ ": " ~ details;
		else
			m_status.text = TRACE;
		m_error = error;
		m_status.code = s;
		static if(LOG) log(m_status);
	}
private:
	bool onMessage(MSG msg) 
	in {
		assert(m_connHandlers !is null);
		assert(m_evHandlers !is null);
	}
	body {
		m_status = StatusInfo.init;
		switch (msg.message) {
			case WM_TCP_SOCKET:
				auto evt = LOWORD(msg.lParam);
				auto err = HIWORD(msg.lParam);
				return onTCPEvent(evt, err, cast(fd_t)msg.wParam);
			case WM_USER_SIGNAL:
				// Todo: implement a signaling mechanism
				break;
			default: return false; // not handled, sends to wndProc
		}
		return true;
	}

	bool onTCPEvent(WORD evt, WORD err, fd_t sock) {
		try{
			if (m_evHandlers.get(sock) == TCPEventHandler.init && m_connHandlers.get(sock) == TCPAcceptHandler.init)
			return false;
		}	catch {}
		if (sock == 0) { // highly unlikely...
			setInternalError!"onTCPEvent"(Status.EVLOOP_FAILURE, "no socket defined");
			return false;
		}
		if (err) {
			setInternalError!"onTCPEvent"(Status.EVLOOP_FAILURE, string.init, cast(error_t)err);
			// todo: figure out how to send this in the callbacks without operating on the socket
			return false;
		}

		TCPEventHandler cb;
		switch(evt) {
			default: break;
			case FD_ACCEPT:
				NetworkAddress addr;
				addr.family = AF_INET6;
				int addrlen = addr.sockAddrLen;
				fd_t csock = WSAAccept(sock, addr.sockAddr, &addrlen, null, 0);
				if (addrlen < addr.sockAddrLen)
					addr.family = AF_INET;
				if (addrlen == addrlen.init) {
					setInternalError!"addrlen"(Status.ABORT);
					return false;
				}
				catchSocketError!"WSAAccept"(csock, INVALID_SOCKET);
				import vibe.utils.memory : FreeListObjectAlloc;
				AsyncTCPConnection conn;
				try conn = FreeListObjectAlloc!AsyncTCPConnection.alloc(m_evLoop);
				catch (Exception e) { assert(false, "Failed allocation"); }
				conn.peer = addr;
				conn.socket = sock;
				try {
					cb = (*m_connHandlers)[sock](conn); 
				} 
				catch(Exception e) {	
					setInternalError!"onConnected"(Status.EVLOOP_FAILURE); 
					return false; 
				}
				try (*m_evHandlers)[csock] = cb;
				catch (Exception e) { 
					setInternalError!"m_evHandlers.opIndexAssign"(Status.ABORT); 
					return false; 
				}
				break;
			case FD_CONNECT:
				try {
					cb = m_evHandlers.get(sock);
					assert(cb != TCPEventHandler.init, "Socket " ~ sock.to!string ~ " could not yield a callback");
					cb(TCPEvent.CONNECT);
				} 
				catch(Exception e) {	
					setInternalError!"del@TCPEvent.CONNECT"(Status.ABORT);
					return false;
				}
				break;
			case FD_READ:
				try {
					cb = m_evHandlers.get(sock);
					assert(cb != TCPEventHandler.init, "Socket " ~ sock.to!string ~ " could not yield a callback");
					cb(TCPEvent.READ);
				}
				catch (Exception e) {
					setInternalError!"del@TCPEvent.READ"(Status.ABORT); 
					return false;
				}
				break;
			case FD_WRITE:
				try {
					cb = m_evHandlers.get(sock);
					assert(cb != TCPEventHandler.init, "Socket " ~ sock.to!string ~ " could not yield a callback");
					cb(TCPEvent.WRITE);
				}
				catch (Exception e) {
					setInternalError!"del@TCPEvent.WRITE"(Status.ABORT); 
					return false;
				}
				break;
			case FD_CLOSE:
				// called after shutdown()
				INT ret;
				bool connected = true;
				try {
					if (sock in *m_evHandlers)
						(*m_evHandlers)[sock](TCPEvent.CLOSE);
					else
						connected = false;
				}
				catch (Exception e) {
					setInternalError!"del@TCPEvent.CLOSE"(Status.ABORT); 
					return false;
				}

				closeSocket(sock, connected, true); // as necessary: invokes m_evHandlers.remove(fd), shutdown, closesocket

				break;
		}
		return true;
	}

	bool initTCPListener(fd_t fd, AsyncTCPListener ctxt)
	in { 
		assert(m_threadId == GetCurrentThreadId());
		assert(ctxt.local !is NetworkAddress.init);
	}
	body {
		INT err;
		err = bind(fd, ctxt.local.sockAddr, ctxt.local.sockAddrLen);
		if (catchSocketError!"bind"(err)) {
			closesocket(fd);
			return false;
		}
		err = listen(fd, 128);
		if (catchSocketError!"listen"(err)) {
			closesocket(fd);
			return false;
		}
		err = WSAAsyncSelect(fd, m_hwnd, WM_TCP_SOCKET, FD_ACCEPT);
		if (catchSocketError!"WSAAsyncSelect"(err)) {
			closesocket(fd);
			return false;
		}

		return true;
	}

	bool initTCPConnection(fd_t fd, AsyncTCPConnection ctxt)
	in { 
		assert(ctxt.peer !is NetworkAddress.init);
		assert(ctxt.peer.port != 0, "Connecting to an invalid port");
	}
	body {
		INT err;
		NetworkAddress bind_addr;
		bind_addr.family = ctxt.peer.family;

		if (ctxt.peer.family == AF_INET) 
			bind_addr.sockAddrInet4.sin_addr.s_addr = 0;
		else if (ctxt.peer.family == AF_INET6) 
			bind_addr.sockAddrInet6.sin6_addr.s6_addr[] = 0;
		else assert(false, "Invalid NetworkAddress.family " ~ ctxt.peer.family.to!string);

		err = .bind(fd, bind_addr.sockAddr, bind_addr.sockAddrLen);
		if ( catchSocketError!"bind"(err) ) 
			return false;
		err = WSAAsyncSelect(fd, m_hwnd, WM_TCP_SOCKET, FD_CONNECT|FD_READ|FD_WRITE|FD_CLOSE);
		if ( catchSocketError!"WSAAsyncSelect"(err) ) 
			return false;
		err = .connect(fd, ctxt.peer.sockAddr, ctxt.peer.sockAddrLen);

		auto errors = [	tuple(cast(size_t) SOCKET_ERROR, EWIN.WSAEWOULDBLOCK, Status.ASYNC) ];		

		if (catchSocketErrorsEq!"connectEQ"(err, errors))
			return true;
		else if (catchSocketError!"connect"(err))
			return false;

		return true;
	}

	bool catchErrors(string TRACE, T)(T val, Tuple!(T, Status)[] cmp ...)
		if (isIntegral!T)
	{
		foreach (validator ; cmp) {
			if (val == validator[0]) {
				m_status.text = TRACE;
				m_error = GetLastErrorSafe();
				m_status.code = validator[1];
				static if(LOG) log(m_status);
				return true;
			}
		}
		return false;
	}

	bool catchSocketErrors(string TRACE, T)(T val, Tuple!(T, Status)[] cmp ...)
		if (isIntegral!T)
	{
		foreach (validator ; cmp) {
			if (val == validator[0]) {
				m_status.text = TRACE;
				m_error = WSAGetLastErrorSafe();
				m_status.status = validator[1];
				static if(LOG) log(m_status);
				return true;
			}
		}
		return false;
	}

	bool catchSocketErrorsEq(string TRACE, T)(T val, Tuple!(T, error_t, Status)[] cmp ...)
		if (isIntegral!T)
	{
		error_t err;
		foreach (validator ; cmp) {
			if (val == validator[0]) {
				if (err is EWIN.init) err = WSAGetLastErrorSafe();
				if (err == validator[1]) {
					m_status.text = TRACE;
					m_error = WSAGetLastErrorSafe();
					m_status.code = validator[2];
					static if(LOG) log(m_status);
					return true;
				}
			}
		}
		return false;
	}

	
	bool catchSocketError(string TRACE, T)(T val, T cmp = SOCKET_ERROR)
		if (isIntegral!T)
	{
		if (val == cmp) {
			m_status.text = TRACE;
			m_error = WSAGetLastErrorSafe();
			m_status.code = Status.ABORT;
			static if(LOG) log(m_status);
			return true;
		}
		return false;
	}

	error_t WSAGetLastErrorSafe() {
		try {
			return cast(error_t) WSAGetLastError();
		} catch(Exception e) {
			return EWIN.ERROR_ACCESS_DENIED;
		}
	}

	error_t GetLastErrorSafe() {
		try {
			return cast(error_t) GetLastError();
		} catch(Exception e) {
			return EWIN.ERROR_ACCESS_DENIED;
		}
	}

	debug void log(StatusInfo val)
	{
		import std.stdio;
		try {
			writeln("Backtrace: ", m_status.text);
			writeln(" | Status:  ", m_status.code);
			writeln(" | Error: " , m_error);
			if ((m_error in EWSAMessages) !is null)
				writeln(" | Message: ", EWSAMessages[m_error]);
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

}
/**
		Represents a network/socket address. (taken from vibe.core.net)
*/
public struct NetworkAddress {
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
enum WM_USER_SIGNAL = WM_USER+101;
enum WM_TCP_SOCKET = WM_USER+102;

nothrow:
private:

extern(System) LRESULT wndProc(HWND wnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
	auto ptr = cast(void*)GetWindowLongPtrA(wnd, GWLP_USERDATA);
	if (ptr is null) 
		return DefWindowProcA(wnd, msg, wparam, lparam);
	auto appl = cast(EventLoopImpl*)ptr;
	MSG obj = MSG(wnd, msg, wparam, lparam, DWORD.init, POINT.init);
	if (appl.onMessage(obj)) return 0;
	else return DefWindowProcA(wnd, msg, wparam, lparam);
}

extern (Windows) void FreeAddrInfoW(ADDRINFOW* pAddrInfo);
extern (Windows) int GetAddrInfoW(LPCWSTR pName, LPCWSTR pServiceName, const ADDRINFOW *pHints, ADDRINFOW **ppResult);
extern (Windows) INT WSAStringToAddressA(in LPTSTR AddressString, INT AddressFamily, in WSAPROTOCOL_INFO* lpProtocolInfo, SOCKADDR* lpAddress, INT* lpAddressLength);

extern (Windows) struct WSAPROTOCOL_INFO {
	DWORD            dwServiceFlags1;
	DWORD            dwServiceFlags2;
	DWORD            dwServiceFlags3;
	DWORD            dwServiceFlags4;
	DWORD            dwProviderFlags;
	GUID             ProviderId;
	DWORD            dwCatalogEntryId;
	WSAPROTOCOLCHAIN ProtocolChain;
	int              iVersion;
	int              iAddressFamily;
	int              iMaxSockAddr;
	int              iMinSockAddr;
	int              iSocketType;
	int              iProtocol;
	int              iProtocolMaxOffset;
	int              iNetworkByteOrder;
	int              iSecurityScheme;
	DWORD            dwMessageSize;
	DWORD            dwProviderReserved;
	CHAR            szProtocol[WSAPROTOCOL_LEN+1];
}