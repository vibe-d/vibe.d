import vibe.d;
import std.stdio;
// redirect.d
import redirect;

// Function to render index page
void index(HTTPServerRequest req, HTTPServerResponse res) {
	res.writeBody("Hello, world!");
}

void main() {
	
	// Router configuration
	auto router = new URLRouter;
	router.any("*", serveStaticFiles("public/"));
	router.get("/", &index);

	// Connection settings
	auto settings = new HTTPServerSettings;
	settings.port = 443;
	settings.bindAddresses = ["127.0.0.1"];

	// Settings for TLS
	settings.tlsContext = createTLSContext(TLSContextKind.server);
	settings.tlsContext.useCertificateChainFile("certificate.crt");
	settings.tlsContext.usePrivateKeyFile("private.key");
	
	// Start & run application
	listenHTTP(settings, router);
	forward();
	runApplication();
}
