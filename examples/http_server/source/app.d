import vibe.core.core : runApplication;
import vibe.http.server;

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	if (req.path == "/")
		res.writeBody("Hello, World!", "text/plain");
}

void main()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	auto l = listenHTTP(settings, &handleRequest);
	scope (exit) l.stopListening();

	runApplication();
}
