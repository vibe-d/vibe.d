import vibe.d;

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, World!", "text/plain");
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.sslCertFile = "server.crt";
	settings.sslKeyFile = "server.key";
	
	listenHTTP(settings, &handleRequest);
}
