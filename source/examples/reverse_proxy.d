import vibe.d;

static this()
{
	setLogLevel(LogLevel.Trace);
	auto settings = new HttpServerSettings;
	settings.port = 8080;

	listenHttpReverseProxy(settings, "www.heise.de", 80);
}