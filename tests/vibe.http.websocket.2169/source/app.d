import vibe.core.core;
import vibe.core.log;
import vibe.inet.url;
import vibe.http.server;
import vibe.http.websockets;
import vibe.stream.tls;


void test(bool tls)
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	if (tls) {
		settings.tlsContext = createTLSContext(TLSContextKind.server);
		settings.tlsContext.useCertificateChainFile("../tls/server.crt");
		settings.tlsContext.usePrivateKeyFile("../tls/server.key");
	}
	auto listener = listenHTTP(settings, handleWebSockets((scope ws) {
		assert(ws.connected); // issue #2104
		assert(ws.receiveText() == "foo");
		ws.send("hello");
		assert(ws.receiveText() == "bar");
		ws.close();
	}));

	const serverAddr = listener.bindAddresses[0];
	const server_url = URL((tls ? "https://" : "http://") ~ serverAddr.toString);

	runTask({
		scope(exit) exitEventLoop(true);

		try {
			// issue #2169 - calling connectWebSocket twice
			auto ws1 = connectWebSocket(server_url);
			yield();
			auto ws2 = connectWebSocket(server_url);

			testWS(ws1);
			testWS(ws2);
			yield();
		} catch (Exception e) {
			assert(false, "Web sockets failed: "~e.msg);
		}
	}).join();

	listener.stopListening();
}

void main()
{
	test(false);
	test(true);
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
