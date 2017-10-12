import vibe.appmain;
import vibe.http.proxy;
import vibe.http.server;


shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	listenHTTPReverseProxy(settings, "vibed.org", 80);
}
