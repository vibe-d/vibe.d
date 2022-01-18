module app;

import vibe.core.core;
import vibe.http.proxy;
import vibe.http.server;

int main(string[] args)
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	listenHTTPReverseProxy(settings, "vibed.org", 80);
	return runApplication(&args);
}
