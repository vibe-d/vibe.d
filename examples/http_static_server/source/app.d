import vibe.d;

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	res.redirect("/index.html");
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	
	auto router = new URLRouter;
	router.get("/", &handleRequest);
	router.get("*", serveStaticFiles("./public/"));
	
	listenHTTP(settings, router);
}
