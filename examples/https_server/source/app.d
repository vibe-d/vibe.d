import vibe.appmain;
import vibe.http.server;
import vibe.stream.tls;

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, World!", "text/plain");
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.tlsContext = createTLSContext(TLSContextKind.server);
	settings.tlsContext.useCertificateChainFile("server.crt");
	settings.tlsContext.usePrivateKeyFile("server.key");

	listenHTTP(settings, &handleRequest);
}
