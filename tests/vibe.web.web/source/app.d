module app;

import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.web.web;
import std.format : format;

// TODO: test the various parameter and return type combinations, as well as all attributes

class Service {
	@noRoute void getFoo(HTTPServerResponse res) { res.writeBody("oops"); }
	void getBar(HTTPServerResponse res) { res.writeBody("ok"); }
	// you can work with Json objects directly
	auto postJson(Json _json) { return _json; }
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.bindAddresses = ["127.0.0.1"];
	settings.port = 9132;
	auto router = new URLRouter;
	router.registerWebInterface(new Service);

	listenHTTP(settings, router);

	runTask({
		scope (exit) exitEventLoop();
		void postJson(V)(string url, V[string] payload, HTTPStatus expected, scope void delegate(scope HTTPClientResponse res) expectedHandler) {
			requestHTTP("http://127.0.0.1:9132"~url,
				(scope req) {
					req.method = HTTPMethod.POST;
					req.writeJsonBody(payload);
				},
				(scope res) {
					assert(res.statusCode == expected, format("Unexpected status code for %s: %s", url, res.statusCode));
					expectedHandler(res);
				}
			);
		}
		void test(string url, HTTPStatus expected) {
			requestHTTP("http://127.0.0.1:9132"~url,
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

		postJson("/json", ["foo": "bar"], HTTPStatus.ok, (scope res) {
			auto j = res.readJson;
			assert(j["foo"].get!string == "bar");
		});

		logInfo("All web tests succeeded.");
	});
}
