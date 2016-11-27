import vibe.http.server;
import vibe.http.router;
import vibe.http.client;
import vibe.core.core;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 11628;
	auto router = new URLRouter;
	router.get("/tag/:tag", &handler);
	listenHTTP(settings, router);

	runTask({
		auto conn = connectHTTP("127.0.0.1", 11628);
		conn.request((scope req) {
			req.requestURL = "/tag/foo%2Fbar";
		}, (scope res) {
			assert(res.statusCode == 200);
			auto tag = res.readJson().get!string;
			assert(tag == "foo/bar", tag);
		});
		conn.request((scope req) {
			req.requestURL = "/tag/foo/bar";
		}, (scope res) {
			assert(res.statusCode != 200);
		});
		conn.request((scope req) {
			req.requestURL = "/tag/foo%252Fbar";
		}, (scope res) {
			assert(res.statusCode == 200);
			auto tag = res.readJson().get!string;
			assert(tag == "foo%2Fbar", tag);
		});
		conn.disconnect();

		exitEventLoop();
	});
}

void handler(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeJsonBody(req.params["tag"]);
}
