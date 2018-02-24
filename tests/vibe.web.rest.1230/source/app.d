import std.datetime;
import vibe.d;

interface ITestAPI {
    string postDefault(int value, bool check = true);
}

class Test : ITestAPI {
    string postDefault(int value, bool check = true) {
        import std.format;
        return format("Value: %s, Check: %s", value, check);
    }
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];

	auto router = new URLRouter;
	router.registerRestInterface(new Test);
	immutable serverAddr = listenHTTP(settings, router).bindAddresses[0];

	runTask({
		scope (exit) exitEventLoop(true);
		auto api = new RestInterfaceClient!ITestAPI(
			"http://" ~ serverAddr.toString);
		assert(api.postDefault(42, true) == "Value: 42, Check: true");
		assert(api.postDefault(42, false) == "Value: 42, Check: false");
		assert(api.postDefault(42) == "Value: 42, Check: true");
		requestHTTP("http://" ~ serverAddr.toString ~ "/default",
			(scope req) {
				req.method = HTTPMethod.POST;
				req.writeBody(cast(const(ubyte)[])`{"value":42}`, "application/json");
			},
			(scope res) {
				assert(res.statusCode == HTTPStatus.ok);
				assert(res.readJson.get!string == "Value: 42, Check: true");
			}
		);
		requestHTTP("http://" ~ serverAddr.toString ~ "/default",
			(scope req) {
				req.method = HTTPMethod.POST;
				req.writeBody(cast(const(ubyte)[])`{"value":42,"check":true}`, "application/json");
			},
			(scope res) {
				assert(res.statusCode == HTTPStatus.ok);
				assert(res.readJson.get!string == "Value: 42, Check: true");
			}
		);
		logInfo("Tests passed.");
	});
}
