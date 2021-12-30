module app;

import vibe.core.core;
import vibe.http.server;

int main (string[] args)
{
	auto settings = new HTTPServerSettings;
	settings.sessionStore = new MemorySessionStore();
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	auto listener = listenHTTP(settings, staticTemplate!("info.dt"));
	return runApplication(&args);
}
