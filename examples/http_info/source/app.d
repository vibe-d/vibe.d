import vibe.d;

shared static this()
{
	auto settings = new HttpServerSettings;
	settings.sessionStore = new MemorySessionStore();
	settings.port = 8080;
	
	listenHttp(settings, staticTemplate!("info.dt"));
}
