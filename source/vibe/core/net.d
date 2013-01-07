/**
	TCP/UDP connection and server handling.

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.net;

public import vibe.core.driver;

import core.sys.posix.netinet.in_;
import core.time;
import std.exception;
import std.functional;
version(Windows) import std.c.windows.winsock;


/**
	Resolves the given host name/IP address string.

	Setting use_dns to false will only allow IP address strings but also guarantees
	that the call will not block.
*/
NetworkAddress resolveHost(string host, ushort address_family = AF_UNSPEC, bool use_dns = true)
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
TcpListener[] listenTcp(ushort port, void delegate(TcpConnection stream) connection_callback)
{
	TcpListener[] ret;
	if( auto l = listenTcp(port, connection_callback, "::") ) ret ~= l;
	if( auto l = listenTcp(port, connection_callback, "0.0.0.0") ) ret ~= l;
	return ret;
}
/// ditto
TcpListener listenTcp(ushort port, void delegate(TcpConnection stream) connection_callback, string address)
{
	return getEventDriver().listenTcp(port, connection_callback, address);
}

/**
	Starts listening on the specified port.

	This function is the same as listenTcp but takes a function callback instead of a delegate.
*/
TcpListener[] listenTcpS(ushort port, void function(TcpConnection stream) connection_callback)
{
	return listenTcp(port, toDelegate(connection_callback));
}
/// ditto
TcpListener listenTcpS(ushort port, void function(TcpConnection stream) connection_callback, string address)
{
	return listenTcp(port, toDelegate(connection_callback), address);
}

/**
	Establishes a connection to the given host/port.
*/
TcpConnection connectTcp(string host, ushort port)
{
	return getEventDriver().connectTcp(host, port);
}


/**
	Creates a bound UDP socket suitable for sending and receiving packets.
*/
UdpConnection listenUdp(ushort port, string bind_address = "0.0.0.0")
{
	return getEventDriver().listenUdp(port, bind_address);
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
	@property ushort family() const nothrow { return addr.sa_family; }
	/// ditto
	@property void family(ushort val) nothrow { addr.sa_family = cast(ubyte)val; }

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

	/** A pointer to a sockaddr struct suitable for passing to socket functions.
	*/
	@property inout(sockaddr)* sockAddr() inout nothrow { return &addr; }

	/** Size of the sockaddr struct that is returned by sockAddr().
	*/
	@property int sockAddrLen() const nothrow {
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
	Represents a listening TCP socket.
*/
interface TcpListener /*: EventedObject*/ {
	/// Stops listening and closes the socket.
	void stopListening();
}


/**
	Represents a bound and possibly 'connected' UDP socket.
*/
interface UdpConnection : EventedObject {
	/** Returns the address to which the UDP socket is bound.
	*/
	@property string bindAddress() const;

	/** Determines if the socket is allowed to send to broadcast addresses.
	*/
	@property bool canBroadcast() const;
	/// ditto
	@property void canBroadcast(bool val);

	/** Locks the UDP connection to a certain peer.

		Once connected, the UdpConnection can only communicate with the specified peer.
		Otherwise communication with any reachable peer is possible.
	*/
	void connect(string host, ushort port);

	/** Sends a single packet.

		If peer_address is given, the packet is send to that address. Otherwise the packet
		will be sent to the address specified by a call to connect().
	*/
	void send(in ubyte[] data, in NetworkAddress* peer_address = null);

	/** Receives a single packet.

		If a buffer is given, it must be large enough to hold the full packet.
	*/
	ubyte[] recv(ubyte[] buf = null, NetworkAddress* peer_address = null);
}

