import vibe.d;
import std.datetime;

shared static this()
{
	auto settings = new HTTPServerSettings;
    // 10k + issue number -> Avoid bind errors
	settings.port = 11125;
	settings.bindAddresses = ["::1", "127.0.0.1"];
    auto router = new URLRouter;
    router.registerRestInterface(new Llama);
    listenHTTP(settings, router);

    // Client
    setTimer(1.seconds, {
            scope(exit) exitEventLoop(true);

            auto api = new RestInterfaceClient!ILlama("http://127.0.0.1:11125/");
            auto r = api.updateLlama("llama");
            assert(r == "llama", "[vibe.web.rest.1125.Client] Expected llama, got: " ~ r);
        });
}

interface ILlama {
    @bodyParam("llama", "llama")
    string updateLlama(string llama = null);
}

class Llama : ILlama {
    string updateLlama(string llama) {
        assert(llama == "llama", "[vibe.web.rest.1125.Server] Expected llama, got: " ~ llama);
        return llama;
    }
}
