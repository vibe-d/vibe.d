module app;

import vibe.d;
import index;


void showError(HttpServerRequest req, HttpServerResponse res, HttpServerErrorInfo error)
{
	res.render!("error.dt", req, error);
}

shared static this()
{
	auto router = new UrlRouter;
	router.get("/", &showHome);
	router.get("/about", staticTemplate!"about.dt");
	router.get("*", serveStaticFiles("public"));
	
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	settings.errorPageHandler = toDelegate(&showError);

	listenHttp(settings, router);
}
