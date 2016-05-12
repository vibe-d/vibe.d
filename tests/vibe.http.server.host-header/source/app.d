import vibe.core.core;
import vibe.core.log : logInfo;
import vibe.core.net;
import vibe.http.server;
import vibe.stream.operations;
import core.time : msecs, seconds;
import std.datetime : Clock, UTC;

shared static this()
{
	auto s1 = new HTTPServerSettings;
	s1.options &= ~HTTPServerOption.errorStackTraces;
	s1.bindAddresses = ["::1"];
	s1.port = 11388;
	listenHTTP(s1, &handler);

	runTask({
		scope (failure) assert(false);

		auto conn = connectTCP("::1", 11388);
		conn.write("GET / HTTP/1.1\r\nHost: [::1]\r\n\r\n");
		string res = cast(string)conn.readLine();
		assert(res == "HTTP/1.1 200 OK", res);
		while (conn.readLine().length > 0) {}
		assert(cast(string)conn.readLine() == "success");
		logInfo("1.1 with Host header OK.");

		conn.write("GET / HTTP/1.1\r\n\r\n");
		res = cast(string)conn.readLine();
		assert(res == "HTTP/1.1 400 Bad Request", res);
		while (conn.readLine().length > 0) {}
		ubyte[39] buf;
		conn.read(buf);
		assert(cast(string)buf == "400 - Bad Request\n\nMissing Host header.");
		conn.waitForData(1.seconds);
		assert(!conn.connected && conn.empty);
		logInfo("1.1 without Host header OK.");

		conn = connectTCP("::1", 11388);
		conn.write("GET / HTTP/1.0\r\n\r\n");
		res = cast(string)conn.readLine();
		assert(res == "HTTP/1.0 200 OK", res);
		while (conn.readLine().length > 0) {}
		assert(cast(string)conn.readLine() == "success");
		conn.waitForData(1.seconds);
		assert(!conn.connected && conn.empty);
		conn.waitForData(1.seconds);
		assert(!conn.connected && conn.empty);
		logInfo("1.0 without Host header OK.");

		scope (exit) exitEventLoop();
	});
}

void handler(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody("success\r\n");
}
