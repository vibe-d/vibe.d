import std;
import vibe.core.core;
import vibe.core.stream;
import vibe.data.bson;
import vibe.data.json;
import vibe.data.serialization;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;
import vibe.stream.memory;
import vibe.stream.operations;
import vibe.web.rest;

void main()
@safe {
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
    router.registerRestInterface(new Server);
    router.post("/api/error1", &handleError1);
    router.post("/api/error2", &handleError2);
	auto listener = listenHTTP(settings, router);
	scope (exit) listener.stopListening();
	immutable addr = listener.bindAddresses[0];

	auto api = new RestInterfaceClient!API("http://"~addr.toString);

    // Test that regular exception lead to JSON error
    try {
        api.getError();
        assert(0);
    } catch (RestException exc) {
        assert(exc.message() == "Something very bad happened");
        assert(exc.jsonResult["statusDebugMessage"].get!string.canFind("object.Exception@source"));
    }

    // Test that `text/plain` is properly handled
    try {
        api.postError1();
        assert(0);
    } catch (RestException exc)
        assert(exc.message() == "No name was provided");

    // Test that no content-type is properly handled
    try {
        api.postError2();
        assert(0);
    } catch (RestException exc) {
        debug writeln(exc.jsonResult);
        assert(exc.message() == "Internal Server Error");
        // Base64 encoding of 'Invalid name'
        assert(exc.jsonResult["data"].get!string == "SW52YWxpZCBuYW1lCg==");
    }
}

@path("/api")
interface ServerAPI {
@safe:
    string getError();
}

@path("/api")
interface API : ServerAPI {
    @safe:
    string postError1();
    string postError2();
}

// We split the API because `Server` shouldn't implement `postError` - we need
// to control exactly how the response is sent for the test to be useful.
class Server : ServerAPI {
    string getError() {
        throw new Exception("Something very bad happened");
    }
}

private void handleError1 (scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
    assert(req.method == HTTPMethod.POST, "Unexpected method");
    res.writeBody("No name was provided", 400, "text/plain");
}

private void handleError2 (scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
    assert(req.method == HTTPMethod.POST, "Unexpected method");
    res.headers["Content-Type"] = null;
    res.writeBody("Invalid name\n", 500);
}
