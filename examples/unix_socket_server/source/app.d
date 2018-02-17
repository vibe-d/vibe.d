import vibe.inet.url;
import vibe.http.server;
import vibe.http.router;
import std.stdio;

void handleHelloRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
    res.writeBody("Hello, World!", "text/plain");
}

shared static this()
{
	auto router = new URLRouter;
	router.get("/hello", &handleHelloRequest);

	auto settings = new HTTPServerSettings;
	settings.bindAddresses = ["/tmp/vibe.sock"];

	listenHTTP(settings, router);
}
