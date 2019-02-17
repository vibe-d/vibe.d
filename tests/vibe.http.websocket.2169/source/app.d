import vibe.core.core;
import vibe.core.log;
import vibe.inet.url;
import vibe.http.server;
import vibe.http.websockets;

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto listener = listenHTTP(settings, handleWebSockets((scope ws) {
		assert(ws.connected); // issue #2104
		assert(ws.receiveText() == "foo");
		ws.send("hello");
		assert(ws.receiveText() == "bar");
		ws.close();
	}));

	const serverAddr = listener.bindAddresses[0];

	runTask({
		scope(exit) exitEventLoop(true);

		try {
			// issue #2169 - calling connectWebSocket twice
			auto ws1 = connectWebSocket(URL("http://" ~ serverAddr.toString));
			yield();
			auto ws2 = connectWebSocket(URL("http://" ~ serverAddr.toString));

			testWS(ws1);
			testWS(ws2);
		} catch (Exception e) {
			assert(false, "Web sockets failed: "~e.msg);
		}
    });

    runApplication();

    listener.stopListening();
}


void testWS(scope WebSocket ws)
{
	assert(ws.connected);
	ws.send("foo");
	assert(ws.receiveText() == "hello");
	ws.send("bar");
	assert(!ws.waitForData);
	ws.close();
	logInfo("WebSocket test successful");
}
