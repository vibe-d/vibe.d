module app;

import vibe.core.core;
import vibe.core.log;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.web.web;
import std.format : format;

// TODO: test the various parameter and return type combinations, as well as all attributes

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
	router.registerWebInterface(new Service);
	immutable serverAddr = listenHTTP(settings, router).bindAddresses[0];

	runTask({
		scope (exit) exitEventLoop();

		void test(string url, HTTPStatus expected) {
			requestHTTP("http://" ~ serverAddr.toString ~ url,
				(scope req) {
				},
				(scope res) {
					res.dropBody();
					assert(res.statusCode == expected, format("Unexpected status code for %s: %s", url, res.statusCode));
				}
			);
		}
		test("/foo", HTTPStatus.notFound);
		test("/bar", HTTPStatus.ok);
		logInfo("All web tests succeeded.");
	});
}

class Service {
	@noRoute void getFoo(HTTPServerResponse res) { res.writeBody("oops"); }
	void getBar(HTTPServerResponse res) { res.writeBody("ok"); }
}
