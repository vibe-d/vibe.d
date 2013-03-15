module tests.restclient;

import vibe.vibe;

interface ITestAPI
{
	@method(HttpMethod.POST) @path("other/path")
	string info();
	string getInfo();
	@path("getCheck/:param/:param2") @method(HttpMethod.GET)
	string customParameters(string _param, string _param2);
}

class TestAPI : ITestAPI
{
	string getInfo()
	{
		return "description";
	}

	string info()
	{
		return "description2";
	}

	string customParameters(string _param, string _param2)
	{
		return _param ~ _param2;
	}
}

void test_rest_client()
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
}
