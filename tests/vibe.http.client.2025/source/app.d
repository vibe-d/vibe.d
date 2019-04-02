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
	settings.bindAddresses = ["127.0.0.1"];
	auto l = listenHTTP(settings, (req, res) {
		res.headers.addField("Set-Cookie", "hello=world; Path=/path");
		// res.setCookie("hello", "world", "/path");
		res.writeBody("Hello, World!");
	});

	auto url = URL("http", "127.0.0.1", l.bindAddresses[0].port, InetPath("/"));

	runTask({
		try {
			auto res = requestHTTP(url);
			assert(res.statusCode == 200, res.toString);

			assert(res.cookies.length == 1);
			auto cookie = res.cookies.get("hello");
			assert(cookie !is null);
			assert(cookie.value == "world");
			assert(cookie.httpOnly == false);
			assert(cookie.secure == false);
			assert(cookie.expires == "");
			assert(cookie.maxAge == 0);
			assert(cookie.domain == "");
			assert(cookie.path == "/path");

			res.dropBody();
			exitEventLoop();
		} catch (Exception e) assert(false, e.msg);
	});
	runApplication();
}
