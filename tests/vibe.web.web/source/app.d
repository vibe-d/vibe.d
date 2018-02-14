module app;

import vibe.core.core;
import vibe.core.log;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.operations : readAllUTF8;
import vibe.web.web;
import std.format : format;

// TODO: test the various parameter and return type combinations, as well as all attributes

int main()
{
	runTask({
		scope (exit) exitEventLoop();

		auto settings = new HTTPServerSettings;
		settings.bindAddresses = ["127.0.0.1"];
		settings.port = 9132;

		auto router = new URLRouter;
		router.registerWebInterface(new Service);

		listenHTTP(settings, router);

		void test(string url, HTTPStatus expected, scope void delegate(HTTPClientResponse res) responseHandler = null) {
			requestHTTP("http://127.0.0.1:9132"~url,
				(scope req) {
				},
				(scope res) {
					assert(res.statusCode == expected, format("Unexpected status code for %s: %s", url, res.statusCode));
					if (responseHandler)
						responseHandler(res);
					res.dropBody();
				}
			);
		}
		test("/foo", HTTPStatus.notFound);
		test("/bar", HTTPStatus.ok);
		test("/user/5", HTTPStatus.ok, (scope res) {
			assert(res.bodyReader.readAllUTF8 == "User: 5");
		});
		logInfo("All web tests succeeded.");
	});
	return runEventLoop;
}

class Service {
	@noRoute void getFoo(HTTPServerResponse res) { res.writeBody("oops"); }
	void getBar(HTTPServerResponse res) { res.writeBody("ok"); }

	void getUser(string _id, HTTPServerResponse res) {
		res.writeBody("User: " ~ _id);
	}
}
