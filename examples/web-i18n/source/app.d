// This module shows the translation support of the vibe.web.web framework.
module app;

import vibe.core.log;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.web.web;
import vibe.web.i18n;

// A "traits" structure used to define the available translation files at
// compile time.
struct TranslationContext {
	import std.typetuple;
	// Throw an error when an translation string is missing/mistyped.
	enum enforceExistingKeys = true;
	// The list of supported languages (the same family of languages will
	// automatically be matched to the closest candidate, e.g. en_GB->en_US)
	alias languages = TypeTuple!("en_US", "de_DE");
	// The base name of the translation files - the full names will be
	// example.en_US.po and example.de_DE.po. Any number of these mixin
	// statements can be used.
	mixin translationModule!"example";
}

// perform some generic translation to see if things are working...
static assert(tr!(TranslationContext, "de_DE")("Welcome to the i18n example app!") == "Willkommen zum i18n-Beispiel!");

// Use the @translationContext attribute to make the translations defined
// above available to our web service
@translationContext!TranslationContext
class SampleService {
	// Just render a simple static page for "GET /" requests. Use the browser's
	// language preferences to control if the text is shown in English or in German.
	@path("/") void getHome()
	{
		render!"home.dt";
	}
}

shared static this()
{
	// Create the router that will map the incoming requests to request handlers
	auto router = new URLRouter;
	// Register SampleService as a web serive
	router.registerWebInterface(new SampleService);
	// Handle all other requests by searching for matching files in the public/ folder.
	router.get("*", serveStaticFiles("public/"));

	// Start up the HTTP server.
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.sessionStore = new MemorySessionStore;
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}
