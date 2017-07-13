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


@safe:


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

	Using a `@system` callback is scheduled for deprecation. Use a `@safe`
	callback instead.
*/
TCPListener[] listenTCP(ushort port, void delegate(TCPConnection stream) @safe connection_callback, TCPListenOptions options = TCPListenOptions.defaults)
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
TCPListener listenTCP(ushort port, void delegate(TCPConnection stream) @safe connection_callback, string address, TCPListenOptions options = TCPListenOptions.defaults)
{
	return getEventDriver().listenTCP(port, connection_callback, address, options);
}
/// ditto
TCPListener[] listenTCP(ushort port, void delegate(TCPConnection stream) @system connection_callback, TCPListenOptions options = TCPListenOptions.defaults)
@system {
	return listenTCP(port, (s) @trusted => connection_callback(s), options);
}
/// ditto
TCPListener listenTCP(ushort port, void delegate(TCPConnection stream) @system connection_callback, string address, TCPListenOptions options = TCPListenOptions.defaults)
@system {
	return listenTCP(port, (s) @trusted => connection_callback(s), address, options);
}


/**
	Starts listening on the specified port.

	This function is the same as listenTCP but takes a function callback instead of a delegate.
*/
TCPListener[] listenTCP_s(ushort port, void function(TCPConnection stream) @safe connection_callback, TCPListenOptions options = TCPListenOptions.defaults)
{
	return listenTCP(port, () @trusted { return toDelegate(connection_callback); } (), options);
}
/// ditto
TCPListener listenTCP_s(ushort port, void function(TCPConnection stream) @safe connection_callback, string address, TCPListenOptions options = TCPListenOptions.defaults)
{
	return listenTCP(port, () @trusted { return toDelegate(connection_callback); } (), address, options);
}

/**
	Establishes a connection to the given host/port.
*/
TCPConnection connectTCP(string host, ushort port, string bind_interface = null, ushort bind_port = 0)
{
	NetworkAddress addr = resolveHost(host);
	if (addr.family != AddressFamily.UNIX)
		addr.port = port;
	NetworkAddress bind_address;
	if (bind_interface.length) bind_address = resolveHost(bind_interface, addr.family);
	else {
		bind_address.family = addr.family;
		if (bind_address.family == AddressFamily.INET) bind_address.sockAddrInet4.sin_addr.s_addr = 0;
		else if (bind_address.family != AddressFamily.UNIX) bind_address.sockAddrInet6.sin6_addr.s6_addr[] = 0;
	}
	if (addr.family != AddressFamily.UNIX)
		bind_address.port = bind_port;
	return getEventDriver().connectTCP(addr, bind_address);
}
/// ditto
TCPConnection connectTCP(NetworkAddress addr, NetworkAddress bind_address = anyAddress)
{
	if (bind_address.family == AddressFamily.UNSPEC) {
		bind_address.family = addr.family;
		if (bind_address.family == AddressFamily.INET) bind_address.sockAddrInet4.sin_addr.s_addr = 0;
		else if (bind_address.family != AddressFamily.UNIX) bind_address.sockAddrInet6.sin6_addr.s6_addr[] = 0;
		if (bind_address.family != AddressFamily.UNIX)
			bind_address.port = 0;
	}
	enforce(addr.family == bind_address.family, "Destination address and bind address have different address families.");
	return getEventDriver().connectTCP(addr, bind_address);
}


/**
	Creates a bound UDP socket suitable for sending and receiving packets.
*/
UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0")
{
	return getEventDriver().listenUDP(port, bind_address);
}

NetworkAddress anyAddress()
{
	NetworkAddress ret;
	ret.family = AddressFamily.UNSPEC;
	return ret;
}

/**
	Represents a network/socket address.

	To construct a `NetworkAddress`, use either `resolveHost` or set the
	`family` property accordingly, followed by setting the fields of
	`sockAddrInet4`/`sockAddrInet6`/`sockAddrUnix`.
*/
struct NetworkAddress {
	version(Windows) {
		import core.sys.windows.winsock2 : sockaddr, sockaddr_in, sockaddr_in6;
	}
	version(Posix)
	{
		import core.sys.posix.sys.un : sockaddr_un;
	}

	@safe:

	private union {
		sockaddr addr;
		version (Posix) sockaddr_un addr_unix;
		sockaddr_in addr_ip4;
		sockaddr_in6 addr_ip6;
	}

	version(VibeLibasyncDriver) {
		static import libasync.events;
		this(libasync.events.NetworkAddress addr)
		@trusted {
			this.family = addr.family;
			switch (addr.family) {
				default: assert(false, "Got unsupported address family from libasync.");
				case AddressFamily.INET: this.addr_ip4 = *addr.sockAddrInet4; break;
				case AddressFamily.INET6: this.addr_ip6 = *addr.sockAddrInet6; break;
			}
		}

		T opCast(T)() @trusted
			if (is(T == libasync.events.NetworkAddress))
		{
			T ret;
			ret.family = this.family;
			(cast(ubyte*)ret.sockAddr)[0 .. this.sockAddrLen] = (cast(ubyte*)this.sockAddr)[0 .. this.sockAddrLen];
			return ret;
		}
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
			case AddressFamily.INET: nport = addr_ip4.sin_port; break;
			case AddressFamily.INET6: nport = addr_ip6.sin6_port; break;
		}
		return () @trusted { return ntoh(nport); } ();
	}
	/// ditto
	@property void port(ushort val)
	pure nothrow {
		auto nport = () @trusted { return hton(val); } ();
		switch (this.family) {
			default: assert(false, "port() called for invalid address family.");
			case AddressFamily.INET: addr_ip4.sin_port = nport; break;
			case AddressFamily.INET6: addr_ip6.sin6_port = nport; break;
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
			version (Posix) {
				case AddressFamily.UNIX: return addr_unix.sizeof;
			}
			case AddressFamily.INET: return addr_ip4.sizeof;
			case AddressFamily.INET6: return addr_ip6.sizeof;
		}
	}

	@property inout(sockaddr_in)* sockAddrInet4() inout pure nothrow
		in { assert (family == AddressFamily.INET); }
		body { return &addr_ip4; }

	@property inout(sockaddr_in6)* sockAddrInet6() inout pure nothrow
		in { assert (family == AddressFamily.INET6); }
		body { return &addr_ip6; }

	version (Posix) {
		@property inout(sockaddr_un)* sockAddrUnix() inout pure nothrow
			in { assert (family == AddressFamily.UNIX); }
			body { return &addr_unix; }
	}

	/** Returns a string representation of the IP address
	*/
	string toAddressString()
	const {
		import std.array : appender;
		auto ret = appender!string();
		ret.reserve(40);
		toAddressString(str => ret.put(str));
		return ret.data;
	}
	/// ditto
	void toAddressString(scope void delegate(const(char)[]) @safe sink)
	const {
		import std.array : appender;
		import std.format : formattedWrite;
		ubyte[2] _dummy = void; // Workaround for DMD regression in master

		switch (this.family) {
			default: assert(false, "toAddressString() called for invalid address family.");
			case AddressFamily.INET: {
				ubyte[4] ip = () @trusted { return (cast(ubyte*)&addr_ip4.sin_addr.s_addr)[0 .. 4]; } ();
				sink.formattedWrite("%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
				} break;
			case AddressFamily.INET6: {
				ubyte[16] ip = addr_ip6.sin6_addr.s6_addr;
				foreach (i; 0 .. 8) {
					if (i > 0) sink(":");
					_dummy[] = ip[i*2 .. i*2+2];
					sink.formattedWrite("%x", bigEndianToNative!ushort(_dummy));
				}
				} break;
			version (Posix) {
				case AddressFamily.UNIX:
					import std.traits : hasMember;
					static if (hasMember!(sockaddr_un, "sun_len"))
						sink.formattedWrite("%s",() @trusted { return cast(char[])addr_unix.sun_path[0..addr_unix.sun_len]; } ());
					else
						sink.formattedWrite("%s",() @trusted { return (cast(char*)addr_unix.sun_path.ptr).fromStringz; } ());
					break;
			}
		}
	}

	/** Returns a full string representation of the address, including the port number.
	*/
	string toString()
	const {
		import std.array : appender;
		auto ret = appender!string();
		toString(str => ret.put(str));
		return ret.data;
	}
	/// ditto
	void toString(scope void delegate(const(char)[]) @safe sink)
	const {
		import std.format : formattedWrite;
		switch (this.family) {
			default: assert(false, "toString() called for invalid address family.");
			case AddressFamily.INET:
				toAddressString(sink);
				sink.formattedWrite(":%s", port);
				break;
			case AddressFamily.INET6:
				sink("[");
				toAddressString(sink);
				sink.formattedWrite("]:%s", port);
				break;
			case AddressFamily.UNIX:
				toAddressString(sink);
				break;
		}
	}

	unittest {
		void test(string ip) {
			auto res = () @trusted { return resolveHost(ip, AddressFamily.UNSPEC, false); } ().toAddressString();
			assert(res == ip,
				   "IP "~ip~" yielded wrong string representation: "~res);
		}
		test("1.2.3.4");
		test("102:304:506:708:90a:b0c:d0e:f10");
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
	/// The local address at which TCP connections are accepted.
	@property NetworkAddress bindAddress();

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

	/** Become member of IP multicast group

		The multiaddr parameter should be in the range 239.0.0.0-239.255.255.255.
		See https://www.iana.org/assignments/multicast-addresses/multicast-addresses.xml#multicast-addresses-12
		and https://www.iana.org/assignments/ipv6-multicast-addresses/ipv6-multicast-addresses.xhtml
	*/
	void addMembership(ref NetworkAddress multiaddr);

	/** Set IP multicast loopback

		This is on by default.
		All packets send will also loopback if enabled.
		Useful if more than one application is running on same host and both need each other's packets.
	*/
	@property void multicastLoopback(bool loop);
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
