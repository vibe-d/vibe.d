import vibe.core.core : sleep;
import vibe.core.log;
import vibe.http.fileserver : serveStaticFiles;
import vibe.http.router : URLRouter;
import vibe.http.server;
import vibe.http.websockets : WebSocket, handleWebSockets;

import core.time;
import std.conv : to;


shared static this()
{
	auto router = new URLRouter;
	router.get("/", staticRedirect("/index.html"));
	router.get("/ws", handleWebSockets(&handleWebSocketConnection));
	router.get("*", serveStaticFiles("public/"));

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, router);
}

void handleWebSocketConnection(scope WebSocket socket)
{
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
