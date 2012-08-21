import vibe.d;

void handleRequest(HttpServerRequest req, HttpServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, World!", "text/plain");
}

static this()
{
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	
	listenHttp(settings, &handleRequest);
}
