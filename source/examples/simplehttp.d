import vibe.d;

void handleRequest(HttpServerRequest req, HttpServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, World!", "text/plain");
}

static this()
{
	setLogLevel(LogLevel.Trace);

	auto settings = new HttpServerSettings;
	settings.port = 80;
	
	listenHttp(settings, &handleRequest);
}
