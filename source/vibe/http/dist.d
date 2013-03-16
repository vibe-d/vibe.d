/**
	Interface for the VibeDist load balancer

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.dist;

import vibe.core.log;
import vibe.data.json;
import vibe.inet.url;
import vibe.http.client;
import vibe.http.server;

import std.conv;
import std.exception;


/**
	Listens for HTTP connections on the spefified load balancer using the given HTTP server settings.

	This function is usable as direct replacement of 
*/
void listenHttpDist(HttpServerSettings settings, HttpServerRequestDelegate handler, string balancer_address, ushort balancer_port = 11000)
{
	Json regmsg = Json.EmptyObject;
	regmsg.hostName = settings.hostName;
	regmsg.port = settings.port;
	regmsg.sslCertFile = settings.sslCertFile;
	regmsg.sslKeyFile = settings.sslKeyFile;

	HttpServerSettings local_settings = settings.dup;
	local_settings.port = 0;
	local_settings.disableDistHost = true;
	listenHttp(local_settings, handler);

	regmsg.localPort = local_settings.port;

	logInfo("Listening for VibeDist connections on port %d", local_settings.port);

	auto res = requestHttp(Url.parse("http://"~balancer_address~":"~to!string(balancer_port)~"/register"), (scope req){
			req.writeJsonBody(regmsg);
		});
	scope(exit) destroy(res);
	enforce(res.statusCode == HttpStatus.OK, "Failed to register with load balancer.");
}

