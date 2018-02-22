import vibe.core.core;
import vibe.core.net;
import vibe.http.server;
import vibe.stream.operations;
import core.time : msecs;
import std.datetime : Clock, UTC;

void main()
{
	version (none) {
	auto s1 = new HTTPServerSettings;
	s1.port = 0;
	s1.bindAddresses = ["::1"];
	immutable serverAddr = listenHTTP(s1, &handler).bindAddresses[0];

	runTask({
		auto conn = connectTCP(serverAddr);
		conn.write("GET / HTTP/1.1\r\nHost: [::1]\r\n\r\n");
		string res = cast(string)conn.readLine();
		assert(res == "HTTP/1.1 200 OK", res);
		while (conn.readLine().length > 0) {}
		assert(cast(string)conn.readLine() == "success");

		conn.write("GET / HTTP/1.1\r\nHost: [::1]:11388\r\n\r\n");
		res = cast(string)conn.readLine();
		assert(res == "HTTP/1.1 200 OK", res);
		while (conn.readLine().length > 0) {}
		assert(cast(string)conn.readLine() == "success");

		conn.close();

		exitEventLoop();
	});
	runApplication();
	}

	import vibe.core.log : logWarn;
	logWarn("Test disabled due to missing IPv6 support (loopback) on Travis-CI");
}

void handler(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody("success\r\n");
}
