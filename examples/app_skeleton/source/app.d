module app;

import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import index;
import std.functional : toDelegate;


void showError(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error)
{
	res.render!("error.dt", req, error);
}

shared static this()
{
	auto router = new URLRouter;
	router.get("/", &showHome);
	router.get("/about", staticTemplate!"about.dt");
	router.get("*", serveStaticFiles("public"));

	auto settings = new HTTPServerSettings;
	settings.bindAddresses = ["127.0.0.1"];
	settings.port = 8080;
	settings.errorPageHandler = toDelegate(&showError);

	listenHTTP(settings, router);
}
