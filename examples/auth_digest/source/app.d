import vibe.appmain;
import vibe.http.auth.digest_auth;
import vibe.http.router;
import vibe.http.server;
import std.functional : toDelegate;

string digestPassword(string realm, string user) @safe
{
	if (realm == "Site Realm" && user == "admin")
		return createDigestPassword(realm, user, "secret");
	return "";
}

shared static this()
{
	auto authinfo = new DigestAuthInfo;
	authinfo.realm = "Site Realm";

	auto router = new URLRouter;

	// the following routes are accessible without authentication:
	router.get("/", staticTemplate!"index.dt");

	// now any request is matched and checked for authentication:
	router.any("*", performDigestAuth(authinfo, toDelegate(&digestPassword)));

	// the following routes can only be reached if authenticated:
	router.get("/internal", staticTemplate!"internal.dt");

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	listenHTTP(settings, router);
}
