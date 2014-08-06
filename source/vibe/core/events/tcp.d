module vibe.core.events.tcp;
import std.traits : isPointer;
import vibe.core.events.types;
import vibe.core.events.events;


final class AsyncTCPConnection
{
package:

	EventLoop m_evLoop;

private:
	NetworkAddress m_peer;
	fd_t m_socket;
	bool m_inbound;
	bool m_noDelay;
	void* m_ctxt;

nothrow:
public:
	this(EventLoop evl) { m_evLoop = evl; }

	@property T context(T)() 
		if (isPointer!T)
	{
		return cast(T*) m_ctxt;
	}

	@property void context(T)(T ctxt)
		if (isPointer!T)
	{
		m_ctxt = cast(void*) ctxt;
	}

	@property void noDelay(bool b)
	in { assert(m_socket != fd_t.init, "Method can only be used before connection"); }
	body {
		m_noDelay = true;
	}

	bool setOption(T)(TCPOptions op, in T val) 
	in { assert(m_socket != fd_t.init, "No socket to operate on"); }
	body {
		return m_evLoop.setOption(m_socket, op, val);
	}

	@property NetworkAddress peer() const 
	{
		return m_peer;
	}

	@property void peer(NetworkAddress addr)
	in { 
		assert(m_socket == fd_t.init, "Cannot change remote address on a connected socket"); 
		assert(addr != NetworkAddress.init);
	}
	body {
		m_peer = addr;
	}

	uint recv(ref ubyte[] ub)
	in { assert(m_socket != fd_t.init); }
	body {
		return m_evLoop.recv(m_socket, ub);
	}

	uint send(in ubyte[] ub)
	in { assert(m_socket != fd_t.init); }
	body {
		return m_evLoop.send(m_socket, ub);
	}

	bool run(TCPEventHandler del)
	in { assert(m_socket == fd_t.init); }
	body {
		m_socket = m_evLoop.run(this, del);
		if (m_socket == 0)
			return false;
		else
			return true;

	}

	bool kill()
	in { assert(m_socket != fd_t.init); }
	body {
		return m_evLoop.kill(this);
	}

package:

	@property bool noDelay() const
	{
		return m_noDelay;
	}

	@property bool inbound() const {
		return m_inbound;
	}

	@property fd_t socket() const {
		return m_socket;
	}

	@property void socket(fd_t sock) {
		m_socket = sock;
		m_inbound = true;
	}

}

final class AsyncTCPListener
{
private:
nothrow:
	EventLoop m_evLoop;
	fd_t m_socket;
	NetworkAddress m_local;
	bool m_noDelay;

public:

	this(EventLoop evl) { m_evLoop = evl; }

	@property bool noDelay() const
	{
		return m_noDelay;
	}
	
	@property void noDelay(bool b) {
		if (m_socket == fd_t.init)
			m_noDelay = b;
		else
			assert(false, "Not implemented");
	}

	@property NetworkAddress local() const
	{
		return m_local;
	}
	
	@property void local(NetworkAddress addr)
	in { assert(m_socket == fd_t.init, "Cannot change binding address on a listening socket"); }
	body {
		m_local = addr;
	}

	bool run(TCPAcceptHandler del)
	in { assert(m_socket == fd_t.init); }
	body {
		m_socket = m_evLoop.run(this, del);
		if (m_socket == fd_t.init)
			return false;
		else
			return true;
	}
	
	bool kill()
	in { assert(m_socket != 0); }
	body {
		return m_evLoop.kill(this);
	}

package:
	@property fd_t socket() const {
		return m_socket;
	}
}

struct TCPEventHandler {
	AsyncTCPConnection conn;
	void function(AsyncTCPConnection, TCPEvent) fct;
	void opCall(TCPEvent code){
		assert(conn !is null);
		fct(conn, code);
		assert(conn !is null);
		return;
	}
}

struct TCPAcceptHandler {
	void* ctxt;
	TCPEventHandler function(void*, AsyncTCPConnection) fct;
	TCPEventHandler opCall(AsyncTCPConnection conn){ // conn is null = error!
		return fct(ctxt, conn);
	}
}


