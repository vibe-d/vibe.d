/**
	HTTP (reverse) proxy implementation

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.proxy;

import vibe.core.log;
import vibe.http.client;
import vibe.http.server;
import vibe.stream.operations;

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
	static immutable string[] non_forward_headers = ["Content-Length", "Transfer-Encoding", "Content-Encoding"];
	static StrMapCI non_forward_headers_map;
	if( non_forward_headers_map.length == 0 )
		foreach( n; non_forward_headers )
			non_forward_headers_map[n] = "";

	Url url;
	url.schema = "http";
	url.host = destination_host;
	url.port = destination_port;

	void handleRequest(HttpServerRequest req, HttpServerResponse res)
	{
		auto rurl = url;
		rurl.localURI = req.url;
		auto cres = requestHttp(rurl, (HttpClientRequest creq){
				creq.method = req.method;
				creq.headers = req.headers.dup;
				creq.headers["Host"] = destination_host;
				if( auto pfh = "X-Forwarded-Host" in req.headers ) creq.headers["X-Forwarded-Host"] = *pfh;
				else creq.headers["X-Forwarded-Host"] = req.headers["Host"];
				if( auto pff = "X-Forwarded-For" in req.headers ) creq.headers["X-Forwarded-For"] = *pff ~ ", " ~ req.peer;
				else creq.headers["X-Forwarded-For"] = req.peer;
				creq.bodyWriter.write(req.bodyReader);
			});
		scope(exit) destroy(cres);
		
		// copy the response to the original requester
		res.statusCode = cres.statusCode;
		
		// copy all headers that may pass from upstream to client
		foreach( n, v; cres.headers ){
			if( n !in non_forward_headers_map )
				res.headers[n] = v;
		}

		// copy the response body if any
		if( "Content-Length" !in cres.headers && "Transfer-Encoding" !in cres.headers || req.method == HttpMethod.HEAD ){
			res.writeVoidBody();
		} else {
			// enforce compatibility with HTTP/1.0 clients that do not support chunked encoding
			// (Squid and some other proxies)
			if( res.httpVersion == HttpVersion.HTTP_1_0 ){
				if( "Transfer-Encoding" in res.headers ) res.headers.remove("Transfer-Encoding");
				auto content = cres.bodyReader.readAll(1024*1024);
				res.headers["Content-Length"] = to!string(content.length);
				res.bodyWriter.write(content);
				return;
			}

			// by default, just forward the body using chunked encoding
			res.bodyWriter().write(cres.bodyReader);
		}
		assert(res.headerWritten);
	}

	return &handleRequest;
}
