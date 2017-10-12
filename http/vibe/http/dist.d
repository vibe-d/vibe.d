/**
	Interface for the VibeDist load balancer

	Copyright: © 2012-2013 RejectedSoftware e.K.
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
import std.process;


/**
	Listens for HTTP connections on the specified load balancer using the given HTTP server settings.

	This function is usable as direct replacement of listenHTTP
*/
HTTPListener listenHTTPDist(HTTPServerSettings settings, HTTPServerRequestDelegate handler, string balancer_address, ushort balancer_port = 11000)
@safe {
	Json regmsg = Json.emptyObject;
	regmsg["host_name"] = settings.hostName;
	regmsg["port"] = settings.port;
	regmsg["ssl_settings"] = "";
	regmsg["pid"] = thisProcessID;
	//regmsg.sslContext = settings.sslContext; // TODO: send key/cert contents

	HTTPServerSettings local_settings = settings.dup;
	local_settings.bindAddresses = ["127.0.0.1"];
	local_settings.port = 0;
	local_settings.disableDistHost = true;
	auto ret = listenHTTP(local_settings, handler);

	requestHTTP(URL("http://"~balancer_address~":"~to!string(balancer_port)~"/register"), (scope req){
			logInfo("Listening for VibeDist connections on port %d", req.localAddress.port);
			regmsg["local_address"] = "127.0.0.1";
			regmsg["local_port"] = req.localAddress.port;
			req.method = HTTPMethod.POST;
			req.writeJsonBody(regmsg);
		}, (scope res){
			enforce(res.statusCode == HTTPStatus.ok, "Failed to register with load balancer.");
		});

	return ret;
}
