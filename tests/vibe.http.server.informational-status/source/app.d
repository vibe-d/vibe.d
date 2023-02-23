import core.time;
import vibe.core.log;
import vibe.core.core : exitEventLoop, runApplication, runTask, sleep;
import vibe.http.client;
import vibe.http.server;
import vibe.stream.operations : readAllUTF8;

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.statusCode = HTTPStatus.processing;
	res.writeVoidBody();

	sleep(100.msecs);
	res.statusCode = HTTPStatus.ok;
	res.writeBody("Hello, World!", "text/plain");
}

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8099;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	auto l = listenHTTP(settings, &handleRequest);
	scope (exit) l.stopListening();

	runTask({
		bool got102, got200;
		scope (exit) exitEventLoop();

		try requestHTTP("http://127.0.0.1:8099/", null,
			(scope res) {
				if (res.statusCode == HTTPStatus.processing) {
					assert(!got200, "Status 200 received first");
					got102 = true;
				}
				else if (res.statusCode == HTTPStatus.ok) {
					got200 = true;
					assert(res.bodyReader.readAllUTF8() == "Hello, World!");
				}
			}
		);
		catch (Exception e) assert(false, e.msg);
		assert(got102, "Status 102 wasn't received");
		assert(got200, "Status 200 wasn't received");
		logInfo("All web tests succeeded.");
	});

	runApplication();
}
