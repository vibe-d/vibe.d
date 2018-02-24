/++ dub.sdl:
	dependency "vibe-d" path=".."
+/
import vibe.core.core;
import vibe.http.client;
import vibe.http.server;
import vibe.core.log;

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["0.0.0.0"];
	auto l = listenHTTP(settings, (req, res) {
		assert(req.fullURL.host == "::7f00:1");
		res.writeBody("Hello, World!");
	});

	auto url = URL("http", "::7f00:1", l.bindAddresses[0].port, InetPath("/"));

	runTask({
		try {
			auto res = requestHTTP(url);
			assert(res.statusCode == 200, res.toString);
			res.dropBody();
			exitEventLoop();
		} catch (Exception e) assert(false, e.msg);
	});
	runApplication();
}
