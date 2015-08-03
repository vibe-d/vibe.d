import vibe.web.rest;


// Defines a simple RESTful API
interface ITest {
	// GET /compute_sum?a=...&b=...
	@method(HTTPMethod.GET)
	float computeSum(float a, float b);

	// POST /to_console {"text": ...}
	void postToConsole(string text);
}

// Local implementation that will be provided by the server
class Test : ITest {
	import std.stdio;
	float computeSum(float a, float b) { return a + b; }
	void postToConsole(string text) { writeln(text); }
}

shared static this()
{
	import vibe.core.log : logInfo;
	import vibe.inet.url : URL;
	import vibe.http.router : URLRouter;
	import vibe.http.server : HTTPServerSettings, listenHTTP, staticTemplate;

	// Set up the proper base URL, so that the JavaScript client
	// will find our REST service
	auto restsettings = new RestInterfaceSettings;
	restsettings.baseURL = URL("http://127.0.0.1:8080/");

	auto router = new URLRouter;
	// Serve the generated JavaScript client at /test.js
	router.get("/test.js", serveRestJSClient!ITest(restsettings));
	// Serve an example page at /
	// The page will use the test.js script to issue calls to the
	// REST service.
	router.get("/", staticTemplate!"index.dt");
	// Finally register the REST interface defined above
	router.registerRestInterface(new Test, restsettings);

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, router);

	logInfo("Please open http://127.0.0.1:8080/ in your browser.");
}
