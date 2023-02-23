import vibe.d;

interface SimpleAPI
{
    @safe:

    void postData(string data);

    void postData2(@viaHeader("Content-Type") out string type, string data);
}

int main (string[] args)
{
    auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = [ "127.0.0.1" ];
	auto router = new URLRouter;
    router.post("/data", &handlePostData);
    router.post("/data2", &handlePostData2);
    auto listener = listenHTTP(settings, router);
	runTask(&doTest, listener.bindAddresses[0]);

    return runApplication(&args);
}

void handlePostData (scope HTTPServerRequest req, scope HTTPServerResponse res)
    @safe
{
    res.writeVoidBody();
}

void handlePostData2 (scope HTTPServerRequest req, scope HTTPServerResponse res)
    @safe
{
    res.headers["Content-Type"] = "text/html; charset=UTF-8";
    res.writeVoidBody();
}

void doTest (immutable NetworkAddress address)
nothrow {
    scope (exit) exitEventLoop();

    try {
    	string result;
	    scope client = new RestInterfaceClient!SimpleAPI("http://" ~ address.toString());
	    client.postData("Hello");
	    client.postData2(result, "World");
	    assert(result == "text/html; charset=UTF-8");
	} catch (Exception e) assert(false, e.msg);
}
