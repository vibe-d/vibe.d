/**
	TCP connection and server handling.

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.tcp;

public import vibe.core.driver;

import vibe.core.core;


/**
	Starts listening on the specified port.

	'connection_callback' will be called for each client that connects to the
	server socket. The 'stream' parameter then allows to perform pseudo-blocking
	i/o on the client socket.
	
	The 'ip4_addr' or 'ip6_addr' parameters can be used to specify the network
	interface on which the server socket is supposed to listen for connections.
	By default, all IPv4 and IPv6 interfaces will be used.
*/
void listenTcpS(ushort port, void function(TcpConnection stream) connection_callback)
{
	listenTcp(port, (TcpConnection conn){ connection_callback(conn); });
}

/// ditto
void listenTcpS(ushort port, void function(TcpConnection conn) connection_callback, string address)
{
	listenTcp(port, (TcpConnection conn){ connection_callback(conn); }, address);
}

/// ditto
void listenTcp(ushort port, void delegate(TcpConnection stream) connection_callback)
{
	listenTcp(port, connection_callback, "0.0.0.0");
	listenTcp(port, connection_callback, "::");
}

/// ditto
void listenTcp(ushort port, void delegate(TcpConnection conn) connection_callback, string address)
{
	getEventDriver().listenTcp(port, connection_callback, address);
}


/** Establishes a connection to the given host/port.
*/
TcpConnection connectTcp(string host, ushort port)
{
	return getEventDriver().connectTcp(host, port);
}
