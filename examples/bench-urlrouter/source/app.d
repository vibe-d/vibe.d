import vibe.core.log;
import vibe.http.router;
import vibe.http.server;
import vibe.inet.url;
static if (__VERSION__ >= 2076)
	import std.datetime.stopwatch;
else
	import std.datetime;
import std.string : format;


void req(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	if (!res.headerWritten)
		res.writeVoidBody();
}

Duration runTimed(scope void delegate() del)
{
	StopWatch sw;
	sw.start();
	del();
	sw.stop();
	static if (__VERSION__ >= 2076)
		return sw.peek;
	else
		return cast(Duration) sw.peek;
}

void main()
{
	enum nroutes = 1_000;
	enum nrequests = 1_000_000;

	auto router = new URLRouter;

	logInfo("Setting up routes...");
	auto duradd = runTimed({
		foreach (i; 0 .. nroutes)
			router.get(format("/%s/:test1/%s/:test2", i/100, i), &req);
	});

	import std.random;
	foreach (i; 0 .. nroutes)
		router.get(format("/%s%s", uniform!uint(), uniform!uint()), &req);

	logInfo("Performing first request...");
	auto req = createTestHTTPServerRequest(URL("http://localhost/0/test/0/test"), HTTPMethod.GET);
	auto res = createTestHTTPServerResponse();
	auto durfirst = runTimed({
		router.handleRequest(req, res);
	});

	logInfo("Performing first match requests...");
	auto durfirstmatch = runTimed({
		foreach (i; 0 .. nrequests)
			router.handleRequest(req, res);
	});

	logInfo("Performing last match requests...");
	req = createTestHTTPServerRequest(URL(format("http://localhost/%s/test/%s/test", (nroutes-1)/100, nroutes-1)), HTTPMethod.GET);
	auto durlastmatch = runTimed({
		foreach (i; 0 .. nrequests)
			router.handleRequest(req, res);
	});

	logInfo("Performing non-match requests...");
	req = createTestHTTPServerRequest(URL("http://localhost/test/x/test"), HTTPMethod.GET);
	auto durnonmatch = runTimed({
		foreach (i; 0 .. nrequests)
			router.handleRequest(req, res);
	});

	version (VibeRouterTreeMatch) enum method = "tree match";
	else enum method = "linear probe";

	logInfo("Results (%s):", method);
	logInfo("  Add %s routes: %s", nroutes, duradd);
	logInfo("  First request: %s", durfirst);
	logInfo("  %s first match requests: %s", nrequests, durfirstmatch);
	logInfo("  %s last match requests: %s", nrequests, durlastmatch);
	logInfo("  %s non-match requests: %s", nrequests, durnonmatch);
}
