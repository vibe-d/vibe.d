import vibe.d;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;

	listenHTTPReverseProxy(settings, "www.heise.de", 80);
}