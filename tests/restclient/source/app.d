module app;

import vibe.vibe;

interface ITestAPI
{
	@property ISub sub();

	@method(HTTPMethod.POST) @path("other/path")
	string info();
	string getInfo();
	@path("getCheck/:param/:param2") @method(HTTPMethod.GET)
	string customParameters(string _param, string _param2);
	@path("getCheck2/:param/:param2") @method(HTTPMethod.GET)
	int customParameters2(int _param, bool _param2);
	@path(":id/idtest1")
	int testID1(int _id);
	@path("idtest2")
	int testID2(int id); // the special "id" parameter
	int get(int id); // the special "id" parameter on "/"" path
	int testKeyword(int body_, int const_);
}

interface ISub {
	int get(int id);
}

class TestAPI : ITestAPI
{
	SubAPI m_sub;

	this() { m_sub = new SubAPI; }

	@property SubAPI sub() { return m_sub; }

	string getInfo() { return "description"; }
	string info() { return "description2"; }
	string customParameters(string _param, string _param2) { return _param ~ _param2; }
	int customParameters2(int _param, bool _param2) { return _param2 ? _param : -_param; }
	int testID1(int _id) { return _id; }
	int testID2(int id) { return id; }
	int get(int id) { return id; }
	int testKeyword(int body_, int const_) { return body_ + const_; }
}

class SubAPI : ISub {
	int get(int id) { return id; }
}

interface ITestAPICors
{
	string getFoo();
	string setFoo();
	string addFoo();
	@path("bar/:param3") string addBar(int _param3);
	@path("bar/:param4") string removeBar(int _param4);
	@path("bar/:param5") string updateBar(int _param5);
	string setFoo(int id);
	string addFoo(int id);
	string removeFoo(int id);
}

class TestAPICors : ITestAPICors
{
	string getFoo() { return "foo"; };
	string setFoo() { return "foo"; };
	string addFoo() { return "foo"; };
	string addBar(int _param3) { return "bar"; };
	string removeBar(int _param4) { return "bar"; };
	string updateBar(int _param5) { return "bar"; };
	string setFoo(int id) { return "foo"; };
	string addFoo(int id) { return "foo"; };
	string removeFoo(int id) { return "foo"; };
}

enum ShouldFail
{
	Yes,
	No
}

void assertHeader(ref InetHeaderMap headers, ShouldFail shouldFail, string header, string value)
{
	import std.algorithm : equal;
	auto h = header in headers;
	if (shouldFail == ShouldFail.Yes)
	{
		assert(h is null);
		return;
	}
	assert(h !is null);
	assert(equal((*h),value));
}

void assertCorsHeaders(string url, HTTPMethod method, ShouldFail shouldFail)
{
	// preflight request
	requestHTTP(url, 
		(scope HTTPClientRequest req) {
			req.method = HTTPMethod.OPTIONS;
			req.headers["Origin"] = "www.example.com";
			req.headers["Access-Control-Request-Method"] = method.to!string;
			req.headers["Access-Control-Request-Headers"] = "Authorization";
		}, 
		(scope HTTPClientResponse res) {
			res.headers.assertHeader(shouldFail,"Access-Control-Allow-Origin","www.example.com");
			res.headers.assertHeader(shouldFail,"Access-Control-Allow-Credentials","true");
			res.headers.assertHeader(shouldFail,"Access-Control-Allow-Methods",method.to!string);
			res.headers.assertHeader(shouldFail,"Access-Control-Allow-Headers","Authorization");
			res.dropBody();
		});

	// normal request
	requestHTTP(url, 
		(scope HTTPClientRequest req) {
			req.method = method;
			req.headers["Origin"] = "www.example.com";
		}, 
		(scope HTTPClientResponse res) {
			res.headers.assertHeader(shouldFail,"Access-Control-Allow-Origin","www.example.com");
			res.headers.assertHeader(shouldFail,"Access-Control-Allow-Credentials","true");
			res.dropBody();
		});
}

void assertCorsPasses(string url, HTTPMethod method)
{
	assertCorsHeaders(url, method, ShouldFail.No);
}

void assertCorsFails(string url, HTTPMethod method)
{
	assertCorsHeaders(url, method, ShouldFail.Yes);
}

void testAllowedOrigins(string url, HTTPMethod method, RestInterfaceSettings settings)
{
	// all tests use the www.example.com as origin, so this should fail
	settings.allowedOrigins = ["non-existent.com"];
	assertCorsFails(url, method);

	// all these should pass
	settings.allowedOrigins = [];
	assertCorsPasses(url, method);

	//settings.allowedOrigins = ["WWW.EXAMPLE.COM"];
	//assertCorsPasses(url, method);

	settings.allowedOrigins = ["www.example.com"];
	assertCorsPasses(url, method);
}

// According to specs, when a resource is requested with the OPTIONS method the server should
// return the Allow header that specifies all methods available on that resource.
// Since a CORS preflight also uses the OPTIONS method, we implemented the Allow header as well.
void testAllowHeader(string url, HTTPMethod[] methods)
{
	import std.algorithm : joiner;
	import std.conv : text;
	string allow = methods.map!(m=>m.to!string).joiner(",").text;
	requestHTTP(url, 
		(scope HTTPClientRequest req) {
			req.method = HTTPMethod.OPTIONS;
		}, 
		(scope HTTPClientResponse res) {
			res.headers.assertHeader(ShouldFail.No,"Allow",allow);
			res.dropBody();
		});
}

void testCors(string url, HTTPMethod[] methods)
{
	foreach(method; methods)
		assertCorsPasses(url, method);
}

void runTest()
{
	auto router = new URLRouter;
	registerRestInterface!ITestAPI(router, new TestAPI, "/root/");

	auto corsRestSettings = new RestInterfaceSettings();
	corsRestSettings.baseURL = URL("http://127.0.0.1/cors/");
	corsRestSettings.methodStyle = MethodStyle.lowerUnderscored;
	registerRestInterface!ITestAPICors(router, new TestAPICors, corsRestSettings);

	auto settings = new HTTPServerSettings;
	settings.disableDistHost = true;
	settings.port = 8000;
	listenHTTP(settings, router);

	auto api = new RestInterfaceClient!ITestAPI("http://127.0.0.1:8000/root/");
	assert(api.getInfo() == "description");
	assert(api.info() == "description2");
	assert(api.customParameters("one", "two") == "onetwo");
	assert(api.customParameters2(10, false) == -10);
	assert(api.customParameters2(10, true) == 10);
	assert(api.testID1(2) == 2);
	assert(api.testID2(3) == 3);
	assert(api.get(4) == 4);
	assert(api.sub.get(5) == 5);
	assert(api.testKeyword(3, 4) == 7);

	testAllowedOrigins("http://127.0.0.1:8000/cors/foo", HTTPMethod.GET, corsRestSettings);
	testAllowHeader("http://127.0.0.1:8000/cors/foo",   [HTTPMethod.GET,HTTPMethod.PUT,HTTPMethod.POST]);
	testAllowHeader("http://127.0.0.1:8000/cors/bar/6", [HTTPMethod.POST,HTTPMethod.DELETE,HTTPMethod.PATCH]);
	testAllowHeader("http://127.0.0.1:8000/cors/7/foo", [HTTPMethod.PUT,HTTPMethod.POST,HTTPMethod.DELETE]);
	testCors("http://127.0.0.1:8000/cors/foo", 			[HTTPMethod.GET,HTTPMethod.PUT,HTTPMethod.POST]);
	testCors("http://127.0.0.1:8000/cors/bar/6", 		[HTTPMethod.POST,HTTPMethod.DELETE,HTTPMethod.PATCH]);
	testCors("http://127.0.0.1:8000/cors/7/foo", 		[HTTPMethod.PUT,HTTPMethod.POST,HTTPMethod.DELETE]);

	exitEventLoop(true);
}

int main()
{
	setLogLevel(LogLevel.debug_);
	runTask(toDelegate(&runTest));
	return runEventLoop();
}
