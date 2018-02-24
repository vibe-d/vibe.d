import vibe.core.core;
import vibe.core.net;
import vibe.http.server;
import vibe.stream.operations;
import std.algorithm.searching : startsWith;
import std.string : toLower;
import core.time : seconds;


shared static this()
{
	auto s1 = new HTTPServerSettings;
	s1.options &= ~HTTPServerOption.errorStackTraces;
	s1.port = 0;
	s1.bindAddresses = ["127.0.0.1"];
	immutable serverAddr = listenHTTP(s1, &handler).bindAddresses[0];

	runTask({
		scope (exit) exitEventLoop();

		try {
			auto conn = connectTCP(serverAddr);
			conn.write("GET / HTTP/1.0\r\n\r\n");
			string res = cast(string)conn.readLine();
			assert(res == "HTTP/1.0 200 OK", res);
			while (true) {
				auto ln = conn.readLine();
				if (!ln.length) break;
				assert(!(cast(const(char)[])ln).toLower().startsWith("transfer-encoding:"), "Server sent transfer encoding on HTTP/1.0 connection.");
			}
			assert(cast(string)conn.readLine() == "Hello, World!");
			assert(!conn.waitForData(1.seconds), "Connection not closed by server after response was written.");
			assert(conn.empty);
		} catch (Exception e) {
			assert(false, e.msg);
		}
	});
}

void handler(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.bodyWriter.write("Hello, ");
	res.bodyWriter.write("World!\r\n");
}
