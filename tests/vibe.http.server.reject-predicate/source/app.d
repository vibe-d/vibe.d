module app;

import core.time;
import vibe.core.log;
import vibe.core.core : exitEventLoop, runApplication, runTask, sleep;
import vibe.http.client;
import vibe.http.server;
import vibe.stream.operations : readAllUTF8;

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.statusCode = HTTPStatus.ok;
	res.writeBody("Hello, World!", "text/plain");
}

void main()
{
	immutable string xforward_addr = "127.0.0.2";
	immutable string xforward_addrs = xforward_addr ~ ", 127.0.0.3";

	bool delegate (in NetworkAddress address) @safe nothrow rejectDg = (in address) @safe nothrow {
		return (address.toAddressString == xforward_addr);
    };

	auto settings = new HTTPServerSettings;
	settings.port = 8099;
	settings.rejectConnectionPredicate = rejectDg;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	auto l = listenHTTP(settings, &handleRequest);
	scope (exit) l.stopListening();

	runTask({
		bool got403, got403_multiple, got200;
		scope (exit) exitEventLoop();

		try {
			requestHTTP("http://127.0.0.1:8099/",
				(scope req) {
					req.headers["X-Forwarded-For"] = xforward_addr;
				},
				(scope res) {
					got403 = (res.statusCode == HTTPStatus.forbidden);
				}
			);
			requestHTTP("http://127.0.0.1:8099/",
				(scope req) {
					req.headers["X-Forwarded-For"] = xforward_addrs;
				},
				(scope res) {
					got403_multiple = (res.statusCode == HTTPStatus.forbidden);
				}
			);
			requestHTTP("http://127.0.0.1:8099/", null,
				(scope res) {
					got200 = (res.statusCode == HTTPStatus.ok);
				}
			);
		} catch (Exception e) assert(false, e.msg);
		assert(got403, "Status 403 wasn't received");
		assert(got403_multiple, "Status 403 wasn't received for multiple addresses");
		assert(got200, "Status 200 wasn't received");
		logInfo("All web tests succeeded.");
	});

	runApplication();
}
