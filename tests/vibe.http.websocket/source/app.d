import vibe.core.core;
import vibe.core.log;
import vibe.inet.url;
import vibe.http.server;
import vibe.http.websockets;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	immutable serverAddr = listenHTTP(settings, handleWebSockets((scope ws) {
		assert(ws.connected); // issue #2104
		assert(ws.receiveText() == "foo");
		ws.send("hello");
		assert(ws.receiveText() == "bar");
		ws.close();
	})).bindAddresses[0];

	runTask({
		scope(exit) exitEventLoop(true);

		connectWebSocket(URL("http://" ~ serverAddr.toString), (scope ws) {
			assert(ws.connected);
			ws.send("foo");
			assert(ws.receiveText() == "hello");
			ws.send("bar");
			assert(!ws.waitForData);
			ws.close();
			logInfo("WebSocket test successful");
		});
    });
}
