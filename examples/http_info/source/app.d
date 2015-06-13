import vibe.appmain;
import vibe.http.server;

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.sessionStore = new MemorySessionStore();
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	listenHTTP(settings, staticTemplate!("info.dt"));
}
