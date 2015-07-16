import vibe.appmain;
import vibe.http.auth.basic_auth;
import vibe.http.router;
import vibe.http.server;
import std.functional : toDelegate;

bool checkPassword(string user, string password)
{
	return user == "admin" && password == "secret";
}

shared static this()
{
	auto router = new URLRouter;

	// the following routes are accessible without authentication:
	router.get("/", staticTemplate!"index.dt");

	// now any request is matched and checked for authentication:
	router.any("*", performBasicAuth("Site Realm", toDelegate(&checkPassword)));

	// the following routes can only be reached if authenticated:
	router.get("/internal", staticTemplate!"internal.dt");

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	listenHTTP(settings, router);
}
