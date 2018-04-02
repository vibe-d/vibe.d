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

struct MyStruct
{
	int foo = 2;
}

class Service {
	@noRoute void getFoo(HTTPServerResponse res) { res.writeBody("oops"); }
	void getBar(HTTPServerResponse res) { res.writeBody("ok"); }
	// for POST/PUT requests: incoming objects are automatically serialized to Json
	// by default an unknown return type is serialized to Json
	auto postStruct(MyStruct st) { return st.foo + 3; }
}

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

		postJson("/struct", ["foo": 5], HTTPStatus.ok, (scope res) {
			auto j = res.readJson;
			assert(j.get!int == 8);
		});

		logInfo("All web tests succeeded.");
	});
}
