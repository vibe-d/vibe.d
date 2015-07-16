module app;

import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.web.web;
import vibe.web.i18n;

struct TranslationContext {
	import std.typetuple;
	enum enforceExistingKeys = true;
	alias languages = TypeTuple!("en_US", "de_DE");
	mixin translationModule!"example";
}

static assert(tr!(TranslationContext, "de_DE")("Welcome to the i18n example app!") == "Willkommen zum i18n-Beispiel!");

@translationContext!TranslationContext
class SampleService {
	@path("/") void getHome()
	{
		render!"home.dt";
	}
}

shared static this()
{
	auto router = new URLRouter;
	router.registerWebInterface(new SampleService);
	router.get("*", serveStaticFiles("public/"));

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}
