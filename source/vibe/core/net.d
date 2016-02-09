/**
	TCP/UDP connection and server handling.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.net;

public import vibe.core.stream;
public import std.socket : AddressFamily;

import vibe.core.driver;
import vibe.core.log;

import core.sys.posix.netinet.in_;
import core.time;
import std.exception;
import std.functional;
import std.string;
version(Windows) {
	static if (__VERSION__ >= 2070)
		import std.c.windows.winsock;
	else
		import core.sys.windows.winsock2;
}


/**
	Resolves the given host name/IP address string.

	Setting use_dns to false will only allow IP address strings but also guarantees
	that the call will not block.
*/
NetworkAddress resolveHost(string host, AddressFamily address_family = AddressFamily.UNSPEC, bool use_dns = true)
{
	return resolveHost(host, cast(ushort)address_family, use_dns);
}
/// ditto
NetworkAddress resolveHost(string host, ushort address_family, bool use_dns = true)
{
	return getEventDriver().resolveHost(host, address_family, use_dns);
}


/**
	Starts listening on the specified port.

	'connection_callback' will be called for each client that connects to the
	server socket. Each new connection gets its own fiber. The stream parameter
	then allows to perform blocking I/O on the client socket.

	The address parameter can be used to specify the network
	interface on which the server socket is supposed to listen for connections.
	By default, all IPv4 and IPv6 interfaces will be used.
*/
TCPListener[] listenTCP(ushort port, void delegate(TCPConnection stream) connection_callback, TCPListenOptions options = TCPListenOptions.defaults)
{
	TCPListener[] ret;
	try ret ~= listenTCP(port, connection_callback, "::", options);
	catch (Exception e) logDiagnostic("Failed to listen on \"::\": %s", e.msg);
	try ret ~= listenTCP(port, connection_callback, "0.0.0.0", options);
	catch (Exception e) logDiagnostic("Failed to listen on \"0.0.0.0\": %s", e.msg);
	enforce(ret.length > 0, format("Failed to listen on all interfaces on port %s", port));
	return ret;
}
/// ditto
TCPListener listenTCP(ushort port, void delegate(TCPConnection stream) connection_callback, string address, TCPListenOptions options = TCPListenOptions.defaults)
{
	return getEventDriver().listenTCP(port, connection_callback, address, options);
}

/**
	Starts listening on the specified port.

	This function is the same as listenTCP but takes a function callback instead of a delegate.
*/
TCPListener[] listenTCP_s(ushort port, void function(TCPConnection stream) connection_callback, TCPListenOptions options = TCPListenOptions.defaults)
{
	return listenTCP(port, toDelegate(connection_callback), options);
}
/// ditto
TCPListener listenTCP_s(ushort port, void function(TCPConnection stream) connection_callback, string address, TCPListenOptions options = TCPListenOptions.defaults)
{
	return listenTCP(port, toDelegate(connection_callback), address, options);
}

/**
	Establishes a connection to the given host/port.
*/
TCPConnection connectTCP(string host, ushort port)
{
	NetworkAddress addr = resolveHost(host);
	addr.port = port;
	return connectTCP(addr);
}
/// ditto
TCPConnection connectTCP(NetworkAddress addr) {
	return getEventDriver().connectTCP(addr);
}


/**
	Creates a bound UDP socket suitable for sending and receiving packets.
*/
UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
{
	return getEventDriver().listenUDP(port, bind_address);
}

version(VibeLibasyncDriver) {
	public import libasync.events : NetworkAddress;
} else {
/**
	Represents a network/socket address.
*/
struct NetworkAddress {
	@safe:

	private union {
		sockaddr addr;
		sockaddr_in addr_ip4;
		sockaddr_in6 addr_ip6;
	}

	/** Family of the socket address.
	*/
	@property ushort family() const pure nothrow { return addr.sa_family; }
	/// ditto
	@property void family(AddressFamily val) pure nothrow { addr.sa_family = cast(ubyte)val; }
	/// ditto
	@property void family(ushort val) pure nothrow { addr.sa_family = cast(ubyte)val; }

	/** The port in host byte order.
	*/
	@property ushort port()
	const pure nothrow {
		ushort nport;
		switch (this.family) {
			default: assert(false, "port() called for invalid address family.");
			case AF_INET: nport = addr_ip4.sin_port; break;
			case AF_INET6: nport = addr_ip6.sin6_port; break;
		}
		return () @trusted { return ntoh(nport); } ();
	}
	/// ditto
	@property void port(ushort val)
	pure nothrow {
		auto nport = () @trusted { return hton(val); } ();
		switch (this.family) {
			default: assert(false, "port() called for invalid address family.");
			case AF_INET: addr_ip4.sin_port = nport; break;
			case AF_INET6: addr_ip6.sin6_port = nport; break;
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
		ubyte[2] _dummy = void; // Workaround for DMD regression in master

		switch (this.family) {
			default: assert(false, "toAddressString() called for invalid address family.");
			case AF_INET:
				ubyte[4] ip = () @trusted { return (cast(ubyte*)&addr_ip4.sin_addr.s_addr)[0 .. 4]; } ();
				return format("%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
			case AF_INET6:
				ubyte[16] ip = addr_ip6.sin6_addr.s6_addr;
				auto ret = appender!string();
				ret.reserve(40);
				foreach (i; 0 .. 8) {
					if (i > 0) ret.put(':');
					_dummy[] = ip[i*2 .. i*2+2];
					ret.formattedWrite("%x", bigEndianToNative!ushort(_dummy));
				}
				return ret.data;
		}
	}

	/** Returns a full string representation of the address, including the port number.
	*/
	string toString()
	const {
		auto ret = toAddressString();
		switch (this.family) {
			default: assert(false, "toString() called for invalid address family.");
			case AF_INET: return ret ~ format(":%s", port);
			case AF_INET6: return format("[%s]:%s", ret, port);
		}
	}

	version(Have_libev) {}
	else {
		unittest {
			void test(string ip) {
				auto res = () @trusted { return resolveHost(ip, AF_UNSPEC, false); } ().toAddressString();
				assert(res == ip,
					   "IP "~ip~" yielded wrong string representation: "~res);
			}
			test("1.2.3.4");
			test("102:304:506:708:90a:b0c:d0e:f10");
		}
	}
}
}

/**
	Represents a single TCP connection.
*/
interface TCPConnection : ConnectionStream {
	/// Used to disable Nagle's algorithm.
	@property void tcpNoDelay(bool enabled);
	/// ditto
	@property bool tcpNoDelay() const;


	/// Enables TCP keep-alive packets.
	@property void keepAlive(bool enable);
	/// ditto
	@property bool keepAlive() const;

	/// Controls the read time out after which the connection is closed automatically.
	@property void readTimeout(Duration duration);
	/// ditto
	@property Duration readTimeout() const;

	/// Returns the IP address of the connected peer.
	@property string peerAddress() const;

	/// The local/bind address of the underlying socket.
	@property NetworkAddress localAddress() const;

	/// The address of the connected peer.
	@property NetworkAddress remoteAddress() const;
}


/**
	Represents a listening TCP socket.
*/
interface TCPListener {
	/// Stops listening and closes the socket.
	void stopListening();
}


/**
	Represents a bound and possibly 'connected' UDP socket.
*/
interface UDPConnection {
	/** Returns the address to which the UDP socket is bound.
	*/
	@property string bindAddress() const;

	/** Determines if the socket is allowed to send to broadcast addresses.
	*/
	@property bool canBroadcast() const;
	/// ditto
	@property void canBroadcast(bool val);

	/// The local/bind address of the underlying socket.
	@property NetworkAddress localAddress() const;

	/** Stops listening for datagrams and frees all resources.
	*/
	void close();

	/** Locks the UDP connection to a certain peer.

		Once connected, the UDPConnection can only communicate with the specified peer.
		Otherwise communication with any reachable peer is possible.
	*/
	void connect(string host, ushort port);
	/// ditto
	void connect(NetworkAddress address);

	/** Sends a single packet.

		If peer_address is given, the packet is send to that address. Otherwise the packet
		will be sent to the address specified by a call to connect().
	*/
	void send(in ubyte[] data, in NetworkAddress* peer_address = null);

	/** Receives a single packet.

		If a buffer is given, it must be large enough to hold the full packet.

		The timeout overload will throw an Exception if no data arrives before the
		specified duration has elapsed.
	*/
	ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null);
	/// ditto
	ubyte[] recv(Duration timeout, ubyte[] buf = null, NetworkAddress* peer_address = null);
}


/**
	Flags to control the behavior of listenTCP.
*/
enum TCPListenOptions {
	/// Don't enable any particular option
	defaults = 0,
	/// Causes incoming connections to be distributed across the thread pool
	distribute = 1<<0,
	/// Disables automatic closing of the connection when the connection callback exits
	disableAutoClose = 1<<1,
	/** Enable port reuse on linux kernel version >=3.9, do nothing on other OS
	    Does not affect libasync driver because it is always enabled by libasync.
	*/
	reusePort = 1<<2,
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
