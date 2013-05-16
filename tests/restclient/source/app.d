module app;

import vibe.vibe;

interface ITestAPI
{
	@method(HttpMethod.POST) @path("other/path")
	string info();
	string getInfo();
	@path("getCheck/:param/:param2") @method(HttpMethod.GET)
	string customParameters(string _param, string _param2);
	@path("getCheck2/:param/:param2") @method(HttpMethod.GET)
	int customParameters2(int _param, bool _param2);
}

class TestAPI : ITestAPI
{
	string getInfo() { return "description"; }
	string info() { return "description2"; }
	string customParameters(string _param, string _param2) { return _param ~ _param2; }
	int customParameters2(int _param, bool _param2) { return _param2 ? _param : -_param; }
}

void runTest()
{
	auto router = new UrlRouter;
	registerRestInterface!ITestAPI(router, new TestAPI, "/root/");

	auto settings = new HttpServerSettings;
	settings.disableDistHost = true;
	settings.port = 8000;
	listenHttp(settings, router);

	auto api = new RestInterfaceClient!ITestAPI("http://127.0.0.1:8000/root/");
	assert(api.getInfo() == "description");
	assert(api.info() == "description2");
	assert(api.customParameters("one", "two") == "onetwo");
	assert(api.customParameters2(10, false) == -10);
	assert(api.customParameters2(10, true) == 10);
}

int main()
{
	setLogLevel(LogLevel.Debug);
	runTask(toDelegate(&runTest));
	return runEventLoop();
}
