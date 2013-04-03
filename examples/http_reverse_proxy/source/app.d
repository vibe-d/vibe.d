import vibe.appmain;
import vibe.http.proxy;
import vibe.http.server;


shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;

	listenHTTPReverseProxy(settings, "www.heise.de", 80);
}