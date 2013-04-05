import vibe.appmain;
import vibe.http.server;

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, World!", "text/plain");
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	
	listenHTTP(settings, &handleRequest);
}
