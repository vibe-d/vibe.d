import vibe.appmain;
import vibe.http.server;
import vibe.stream.ssl;

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, World!", "text/plain");
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.sslContext = new SSLContext("server.crt", "server.key");
	
	listenHTTP(settings, &handleRequest);
}
