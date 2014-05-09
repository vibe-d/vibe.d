module app;

import vibe.d;
import index;


void showError(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error)
{
	res.render!("error.dt", req, error);
	//res.renderCompat!("error.dt",
	//	HTTPServerRequest, "req",
	//	HTTPServerErrorInfo, "error")(req, error);
}

shared static this()
{
	auto router = new URLRouter;
	router.get("/", &showHome);
	router.get("/about", staticTemplate!"about.dt");
	router.get("*", serveStaticFiles("public"));
	
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.errorPageHandler = toDelegate(&showError);

	listenHTTP(settings, router);
}
