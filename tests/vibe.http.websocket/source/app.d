import vibe.core.core;
import vibe.core.log;
import vibe.http.server;
import vibe.http.websockets;

shared static this()
{
	auto settings = new HTTPServerSettings;
	// 10k + issue number -> Avoid bind errors
	settings.port = 11332;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, handleWebSockets(&onWS));

	runTask({
		scope(exit) exitEventLoop(true);

		auto ws = connectWebSocket(URL("http://127.0.0.1:11332/"));
		ws.send("foo");
		assert(ws.receiveText() == "hello");
		ws.send("bar");
		assert(!ws.waitForData);
		ws.close();
		logInfo("WebSocket test successful");
        });
}

void onWS(scope WebSocket ws)
{
	assert(ws.receiveText() == "foo");
	ws.send("hello");
	assert(ws.receiveText() == "bar");
	ws.close();
}

