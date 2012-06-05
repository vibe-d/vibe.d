import vibe.d;

void handleRequest(HttpServerRequest req, HttpServerResponse res)
{
	res.redirect("/index.html");
}

static this()
{
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	
	auto router = new UrlRouter;
	router.get("/", &handleRequest);
	router.get("*", serveStaticFiles("./public/"));
	
	listenHttp(settings, router);
}
