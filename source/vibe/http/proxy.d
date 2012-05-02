/**
	HTTP (reverse) proxy implementation

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.proxy;

import vibe.core.log;
import vibe.http.client;
import vibe.http.server;

import std.conv;
import std.exception;


/*
	TODO:
		- use a client pool
		- implement a path based reverse proxy
		- implement a forward proxy
*/

/**
	Transparently forwards all requests to the proxy to a destination_host.

	You can use the hostName field in the 'settings' to combine multiple internal HTTP servers
	into one public web server with multiple virtual hosts.
*/
void listenHttpReverseProxy(HttpServerSettings settings, string destination_host, ushort destination_port)
{
	// disable all advanced parsing in the server
	settings.options = HttpServerOption.None;
	listenHttp(settings, reverseProxyRequest(destination_host, destination_port));
}

/**
	Returns a HTTP request handler that forwards any request to the specified host/port.
*/
HttpServerRequestDelegate reverseProxyRequest(string destination_host, ushort destination_port)
{
	void handleRequest(HttpServerRequest req, HttpServerResponse res)
	{
		auto cli = new HttpClient;
		cli.connect(destination_host, destination_port);

		auto cres = cli.request((HttpClientRequest creq){
				creq.method = req.method;
				creq.url = req.url;
				creq.headers = req.headers.dup;
				creq.headers["Host"] = destination_host;
				while( !req.bodyReader.empty )
					creq.bodyWriter.write(req.bodyReader, req.bodyReader.leastSize);
			});
		
		// copy the response to the original requester
		res.statusCode = cres.statusCode;

		// copy all headers. the content-encoding and transfer-encoding headers must stay as they
		// were originally requested by the client
		static immutable string[] client_headers = [
				"Content-Encoding", "Transfer-Encoding"
			];
		StrMapCI saved_headers;
		foreach( h; client_headers )
			if( auto ph = h in res.headers )
				saved_headers[h] = *ph;
		res.headers = cres.headers.dup;
		foreach( h; client_headers )
			if( auto ph = h in saved_headers ){
				if( ph ) res.headers[h] = *ph;
				else if( h in res.headers ) res.headers.remove(h);
			}


		// copy the response body if any
		if( "Content-Length" !in res.headers && "Transfer-Encoding" !in res.headers ){
			res.writeVoidBody();
		} else {
			// enforce compatibility with HTTP/1.0 clients that do not support chunked encoding
			// (Squid and some other proxies)
			if( res.httpVersion == HttpVersion.HTTP_1_0 ){
				if( "Content-Length" !in res.headers ){
					if( "Transfer-Encoding" in res.headers ) res.headers.remove("Transfer-Encoding");
					auto content = cres.bodyReader.readAll(1024*1024);
					res.headers["Content-Length"] = to!string(content.length);
					res.bodyWriter.write(content);
					return;
				}
			}

			// by default, just forward the body using chunked encoding
			res.bodyWriter();
			while( !cres.bodyReader.empty )
				res.bodyWriter.write(cres.bodyReader, cres.bodyReader.leastSize);
		}
		assert(res.headerWritten);
	}

	return &handleRequest;
}
