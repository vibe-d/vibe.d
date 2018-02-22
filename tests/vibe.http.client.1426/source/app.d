import vibe.core.core;
import vibe.core.net;
import vibe.http.client;
import vibe.stream.operations;

shared static this()
{
	immutable serverAddr = listenTCP(0, (TCPConnection c) {
		c.write("HTTP/1.1 200 OK\r\nConnection: Close\r\n\r\nqwerty");
	}, "127.0.0.1").bindAddress;

	runTask({
		requestHTTP("http://" ~ serverAddr.toString,
			(scope req) {},
			(scope res) {
				assert(res.bodyReader.readAllUTF8() == "qwerty");
			}
		);
		exitEventLoop();
	});
}
