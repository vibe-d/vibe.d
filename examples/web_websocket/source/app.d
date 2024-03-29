module app;

import vibe.core.core;
import vibe.core.log;
import vibe.http.fileserver : serveStaticFiles;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.web.web;
import vibe.http.websockets : WebSocket, handleWebSockets;

import core.time;
import std.conv : to;

class WebsocketService {
	@path("/") void getHome()
	{
		render!("index.dt");
	}

	@path("/ws") void getWebsocket(scope WebSocket socket){
		int counter = 0;
		logInfo("Got new web socket connection.");
		while (true) {
			sleep(1.seconds);
			if (!socket.connected) break;
			counter++;
			logInfo("Sending '%s'.", counter);
			socket.send(counter.to!string);
		}
		logInfo("Client disconnected.");
	}
}


int main(string[] args)
{
	auto router = new URLRouter;

	router.registerWebInterface(new WebsocketService);

	router.get("*", serveStaticFiles("public/"));

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	auto listener = listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
	return runApplication(&args);
}
