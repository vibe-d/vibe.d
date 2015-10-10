module app;

import vibe.core.core;
import vibe.core.log;
import vibe.core.net;
import vibe.stream.operations;
import std.exception;
import std.string;
import core.time;


void testProtocol(TCPConnection server, bool terminate)
{
	foreach (i; 0 .. 1) {
		foreach (j; 0 .. 1) {
			auto str = format("Hello, World #%s", i*100+j);
			server.write(str);
			server.write("\r\n");
			auto reply = server.readLine();
			assert(reply == format("Hash: %08X", typeid(string).getHash(&str)));
		}
		sleep(10.msecs);
	}

	assert(!server.dataAvailableForRead);

	if (terminate) {
		// forcefully close connection
		server.close();
	} else {
		server.write("quit\r\n");
		enforce(server.readLine() == "Bye bye!");
		// should have closed within 500 ms
		enforce(!server.waitForData(500.msecs));
		assert(!server.connected);
	}
}

void runTest()
{
	// server for a simple line based protocol
	listenTCP(11001, (client) {
		while (!client.empty) {
			auto ln = client.readLine();
			if (ln == "quit") {
				client.write("Bye bye!\r\n");
				client.close();
				break;
			}

			client.write(format("Hash: %08X\r\n", typeid(string).getHash(&ln)));
		}
	});

	// proxy server
	listenTCP(11002, (client) {
		auto server = connectTCP("127.0.0.1", 11001);

		// pipe server to client as long as the server connection is alive
		auto t = runTask({
			scope (exit) client.close();
			client.write(server);
		});

		// pipe client to server as long as the client connection is alive
		scope (exit) {
			server.close();
			t.join();
		}
		server.write(client);
	});

	// test server
	logInfo("Test protocol implementation on server");
	testProtocol(connectTCP("127.0.0.1", 11001), false);
	logInfo("Test protocol implementation on server with forced disconnect");
	testProtocol(connectTCP("127.0.0.1", 11001), true);

	// test proxy
	logInfo("Test protocol implementation on proxy");
	testProtocol(connectTCP("127.0.0.1", 11002), false);
	logInfo("Test protocol implementation on proxy with forced disconnect");
	testProtocol(connectTCP("127.0.0.1", 11002), true);
}

int main()
{
	int ret = 0;
	runTask({
		try runTest();
		catch (Throwable th) {
			logError("Test failed: %s", th.msg);
			logDiagnostic("Full error: %s", th);
			ret = 1;
		} finally exitEventLoop(true);
	});
	runEventLoop();
	return ret;
}
