import vibe.d;

void handleRequest(HttpServerRequest req, HttpServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, World!", "text/plain");
}

static this()
{
	setLogLevel(LogLevel.Trace);

	auto settings = new HttpServerSettings;
	settings.port = 8080;
	settings.sslCertFile = "server.crt";
	settings.sslKeyFile = "server.key";
	
	listenHttp(settings, &handleRequest);
}
