module tests.restclient;

import vibe.vibe;
import vibe.http.rest : Path, Method;

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
    override:
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
    auto router = new UrlRouter();
    auto settings = new HttpServerSettings();
    settings.port = 8000;
	
    registerRestInterface!ITestAPI(router, new TestAPI(), "/root/");
    listenHttp(settings, router);

    setTimer(dur!"seconds"(1), {
        auto api = new RestInterfaceClient!ITestAPI("http://127.0.0.1:8000/root/");
        assert(api.getInfo() == "description");
	    assert(api.info() == "description2");
	    assert(api.customParameters("one", "two") == "onetwo");
    });
}
