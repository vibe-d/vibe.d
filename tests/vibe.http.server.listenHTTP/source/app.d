import vibe.core.core;
import vibe.core.core;
import vibe.core.log;
import vibe.http.client;
import vibe.http.server;
import vibe.stream.operations : readAllUTF8;

shared static this()
{
	listenHTTP(":11721", (scope req, scope res) {
		res.writeBody("Hello world.");
	});

	runTask({
		scope (exit) exitEventLoop();

		auto res = requestHTTP("http://0.0.0.0:11721");
		assert(res.statusCode == HTTPStatus.ok);
		assert(res.bodyReader.readAllUTF8 == "Hello world.");
		logInfo("All web tests succeeded.");
	});
}
