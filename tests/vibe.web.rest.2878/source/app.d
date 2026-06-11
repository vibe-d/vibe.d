import vibe.core.core;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.web.rest;

void main()
@safe {
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
    router.get("/api/error", &handleError);
    router.get("/api/ok", &handleOk);
	auto listener = listenHTTP(settings, router);
	scope (exit) listener.stopListening();
	immutable addr = listener.bindAddresses[0];

	auto api = new RestInterfaceClient!API("http://"~addr.toString);

	int status;
    api.getOk(status);
	assert(status == 200);
    api.getError(status);
	assert(status == 500);
}

@path("/api")
interface API {
@safe:
	@method(HTTPMethod.HEAD)
	@path("/error")
    void getError(out @viaStatus int status);

	@method(HTTPMethod.HEAD)
	@path("/ok")
    void getOk(out @viaStatus int status);
}

private void handleOk (scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
    res.writeBody("OK", 200);
}

private void handleError (scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
    res.writeBody("Error", 500);
}
