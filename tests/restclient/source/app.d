module app;

import vibe.vibe;

interface ITestAPI
{
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
	int testKeyword(int body_, int const_);
}

class TestAPI : ITestAPI
{
	string getInfo() { return "description"; }
	string info() { return "description2"; }
	string customParameters(string _param, string _param2) { return _param ~ _param2; }
	int customParameters2(int _param, bool _param2) { return _param2 ? _param : -_param; }
	int testID1(int _id) { return _id; }
	int testID2(int id) { return id; }
	int testKeyword(int body_, int const_) { return body_ + const_; }
}

void runTest()
{
	auto router = new URLRouter;
	registerRestInterface!ITestAPI(router, new TestAPI, "/root/");

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
	assert(api.testKeyword(3, 4) == 7);
	exitEventLoop(true);
}

int main()
{
	setLogLevel(LogLevel.debug_);
	runTask(toDelegate(&runTest));
	return runEventLoop();
}
