/**
	HTTP (reverse) proxy implementation

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.proxy;

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

		string encoding;
		if( auto ptce = "Transfer-Encoding" in req.headers )
			encoding = *ptce;
		ulong req_length = 0;
		if( auto pcl = "Content-Length" in req.headers )
			req_length = to!ulong(*pcl);

		auto cres = cli.request((HttpClientRequest creq){
				creq.method = req.method;
				creq.url = req.url;
				creq.headers = req.headers;
				creq.headers["Host"] = destination_host;
				while( !req.bodyReader.empty )
					creq.bodyWriter.write(req.bodyReader, req.bodyReader.leastSize);
			});
		
		res.httpVersion = cres.httpVersion;
		res.statusCode = cres.statusCode;
		res.headers = cres.headers;

		if( "Content-Length" !in res.headers && "Transfer-Encoding" !in res.headers ){
			res.writeVoidBody();
		} else {
			res.bodyWriter();
			while( !cres.bodyReader.empty )
				res.bodyWriter.write(cres.bodyReader, cres.bodyReader.leastSize);
		}
		assert(res.headerWritten);
	}

	return &handleRequest;
}
