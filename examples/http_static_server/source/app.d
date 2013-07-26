import vibe.appmain;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;

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
	auto fileServerSettings = new HTTPFileServerSettings;
	fileServerSettings.encodingFileExtension = ["gzip" : ".gz"];
	router.get("/gzip/*", serveStaticFiles("./public/", fileServerSettings));
	router.get("*", serveStaticFiles("./public/",));
	
	listenHTTP(settings, router);
}
