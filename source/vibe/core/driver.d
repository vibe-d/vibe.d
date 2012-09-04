/**
	Contains interfaces and enums for evented I/O drivers.

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.driver;

public import vibe.stream.stream;

import vibe.inet.url;

import core.sys.posix.netinet.in_;
import core.thread;
version(Windows) import std.c.windows.winsock;
import std.exception;


/**
	Interface for all evented I/O implementations
*/
interface EventDriver {
	/** Starts the event loop.

		The loop will continue to run until either no more event listeners are active or until
		exitEventLoop() is called.
	*/
	int runEventLoop();

	/* Processes all outstanding events, potentially blocking to wait for the first event.
	*/
	int runEventLoopOnce();

	/** Processes all outstanding events if any, does not block.
	*/
	int processEvents();

	/** Exits any running event loop.
	*/
	void exitEventLoop();

	/** Opens a file on disk with the speficied file mode.
	*/
	FileStream openFile(string path, FileMode mode);

	/** Resolves the given host name or IP address string.
	*/
	NetworkAddress resolveHost(string host, ushort family = AF_UNSPEC, bool no_dns = false);

	/** Establiches a tcp connection on the specified host/port.

		'host' can be a DNS name or an IPv4 or IPv6 address string.
	*/
	TcpConnection connectTcp(string host, ushort port);

	/** Listens on the specified port and interface for TCP connections.

		'bind_address' must be an IPv4 or IPv6 address string corresponding to a local network
		interface.
	*/
	void listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string bind_address);

	/** Creates a new UDP socket and sets the specified address/port as the destination for packets.

		If a bind port is specified, the socket will be able to receive UDP packets on that port.
		Otherwise, a random bind port is chosen.
	*/
	UdpConnection listenUdp(ushort port, string bind_address = "0.0.0.0");

	/** Creates a new signal (a single-threaded condition variable).
	*/
	Signal createSignal();

	/** Creates a new timer.

		The timer can be started by calling rearm() with a timeout.
	*/
	Timer createTimer(void delegate() callback);
}

/**
	Provides an event driver with core functions for task/fiber control.
*/
interface DriverCore {
	void yieldForEvent();
	void resumeTask(Task f, Exception event_exception = null);
	void notifyIdle();
}

class Task : Fiber {
	protected this(void delegate() fun, size_t stack_size)
	{
		super(fun, stack_size);
	}

	static Task getThis(){ return cast(Task)Fiber.getThis(); }
}


/**
	Base interface for all evented objects.

	Evented objects are owned by the fiber/task that created them and may only be used inside this
	specific fiber. By using release(), a fiber can drop the ownership of an object so that 
	another fiber can gain ownership using acquire(). This way it becomes possible to share
	connections and files across fibers.
*/
interface EventedObject {
	/// Releases the ownership of the object.
	void release();

	/// Acquires the ownership of an unowned object.
	void acquire();

	/// Returns true if the calling fiber owns this object
	bool isOwner();
}

/**
	Represents a network/socket address.
*/
struct NetworkAddress {
	private union {
		sockaddr addr;
		sockaddr_in addr_ip4;
		sockaddr_in6 addr_ip6;
	}

	/** Family (AF_) of the socket address.
	*/
	@property ushort family() const { return addr.sa_family; }
	/// ditto
	@property void family(ushort val) { addr.sa_family = val; }

	/** The port in host byte order.
	*/
	@property ushort port()
	const {
		switch(this.family){
			default: assert(false, "port() called for invalid address family.");
			case AF_INET: return ntohs(addr_ip4.sin_port);
			case AF_INET6: return ntohs(addr_ip6.sin6_port);
		}
	}
	/// ditto
	@property void port(ushort val)
	{
		switch(this.family){
			default: assert(false, "port() called for invalid address family.");
			case AF_INET: addr_ip4.sin_port = htons(val); break;
			case AF_INET6: addr_ip6.sin6_port = htons(val); break;
		}
	}

	/** A poiter to a sockaddr struct suitable for passing to socket functions.
	*/
	@property inout(sockaddr)* sockAddr() inout { return &addr; }

	/** Size of the sockaddr struct that is returned by sockAddr().
	*/
	@property size_t sockAddrLen() const {
		switch(this.family){
			default: assert(false, "sockAddrLen() called for invalid address family.");
			case AF_INET: return addr_ip4.sizeof;
			case AF_INET6: return addr_ip6.sizeof;
		}
	}

	@property inout(sockaddr_in)* sockAddrInet4() inout { enforce(family == AF_INET); return &addr_ip4; }
	@property inout(sockaddr_in6)* sockAddrInet6() inout { enforce(family == AF_INET6); return &addr_ip6; }
}

/**
	Represents a single TCP connection.
*/
interface TcpConnection : Stream, EventedObject {
	/// Used to disable Nagle's algorithm
	@property void tcpNoDelay(bool enabled);
	/// ditto
	@property bool tcpNoDelay() const;

	/// Controls the read time out after which the connection is closed automatically
	@property void readTimeout(Duration duration)
		in { assert(duration >= dur!"seconds"(0)); }
	/// ditto
	@property Duration readTimeout() const;

	/// The current connection status
	@property bool connected() const;

	/// Returns the IP address of the connected peer.
	@property string peerAddress() const;

	/// Actively closes the connection.
	void close();

	/// Sets a timeout until data has to be availabe for read. Returns false on timeout.
	bool waitForData(Duration timeout);
}

/**
	Represents a bound and possibly 'connected' UDP socket.
*/
interface UdpConnection : EventedObject {
	/** Returns the address to which the UDP socket is bound.
	*/
	@property string bindAddress() const;

	/** Locks the UDP connection to a certain peer.

		Once connected, the UdpConnection can only communicate with the specified peer.
		Otherwise communication with any reachable peer is possible.
	*/
	void connect(string host, ushort port);

	/** Sends a single packet.
	*/
	void send(in ubyte[] data);

	/** Receives a single packet.

		If a buffer is given, it must be large enough to hold the full packet.
	*/
	ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null);
}

/**
	Specifies how a file is manipulated on disk.
*/
enum FileMode {
	Read,
	ReadWrite,
	CreateTrunc,
	Append
}

/**
	Accesses the contents of a file as a stream.
*/
interface FileStream : Stream, EventedObject {
	/// The path of the file.
	@property Path path() const;

	/// Returns the total size of the file.
	@property ulong size() const;

	/// Determines if this stream is readable.
	@property bool readable() const;

	/// Determines if this stream is writable.
	@property bool writable() const;

	/// Closes the file handle.
	void close();

	/// Seeks to a specific position in the file if supported by the stream.
	void seek(ulong offset);

	/// Returns the current offset of the file pointer
	ulong tell();
}

/** A cross-fiber signal

	Note: the ownership can be shared between multiple fibers.
*/
interface Signal : EventedObject {
	@property int emitCount() const;
	void emit();
	void wait();
	void wait(int reference_emit_count);
}

/**
*/
interface Timer : EventedObject {
	@property bool pending();

	void rearm(Duration dur, bool periodic = false);
	void stop();
	void wait();
}
