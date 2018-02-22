import vibe.core.core;
import vibe.core.core;
import vibe.core.log;
import vibe.http.client;
import vibe.http.server;
import vibe.stream.operations : readAllUTF8;
import std.algorithm : find;
import std.socket : AddressFamily;

shared static this()
{
	immutable serverAddr = listenHTTP(":0", (scope req, scope res) {
		res.writeBody("Hello world.");
	}).bindAddresses.find!(addr => addr.family == AddressFamily.INET).front;

	runTask({
		scope (exit) exitEventLoop();

		auto res = requestHTTP("http://" ~ serverAddr.toString);
		assert(res.statusCode == HTTPStatus.ok);
		assert(res.bodyReader.readAllUTF8 == "Hello world.");
		logInfo("All web tests succeeded.");
	});
}
