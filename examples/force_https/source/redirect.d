// Libs needed for MVC
import vibe.d;
import std.stdio;

// The handler for redirecting
void handler(HTTPServerRequest req, HTTPServerResponse res) {
	res.redirect("https://URL.DOMAIN/");
}

/* Function to handle the inbounds on port
 * 80 and redirect it to port 443 for HTTPS
 */
void forward() {
	
	// Router configuration
	auto router = new URLRouter;
	router.any("*", serveStaticFiles("public/"));
	router.any("/*", &handler);

	// Connection settings
	auto settings = new HTTPServerSettings;
	settings.port = 80;
	settings.bindAddresses = ["127.0.0.1"];
	
	// Start & run application
	listenHTTP(settings, router);
}
