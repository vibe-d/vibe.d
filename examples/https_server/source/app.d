import vibe.core.core : runApplication;
import vibe.http.server;
import vibe.stream.tls;

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, World!", "text/plain");
}

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	settings.tlsContext = createTLSContext(TLSContextKind.server);
	settings.tlsContext.useCertificateChainFile("server.crt");
	settings.tlsContext.usePrivateKeyFile("server.key");

	auto l = listenHTTP(settings, &handleRequest);
	scope (exit) l.stopListening();

	runApplication();
}
