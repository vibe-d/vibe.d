import vibe.d;

shared static this()
{
	auto settings = new HttpServerSettings;
	settings.port = 8080;

	listenHttpReverseProxy(settings, "www.heise.de", 80);
}