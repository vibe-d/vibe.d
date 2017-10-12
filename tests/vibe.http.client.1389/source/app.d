import vibe.core.core;
import vibe.core.log;
import vibe.http.client;
import vibe.http.server;
import vibe.stream.operations : readAllUTF8;
import std.exception : assertThrown;

shared static this()
{
	// determine external network interface
	auto ec = connectTCP("vibed.org", 80);
	auto li = ec.localAddress;
	ec.close();
	li.port = 0;
	logInfo("External interface: %s", li.toString());

	auto settings = new HTTPServerSettings;
	// 10k + issue number -> Avoid bind errors
	settings.port = 11389;
	settings.bindAddresses = [li.toAddressString()];
	listenHTTP(settings, (req, res) {
		if (req.clientAddress.toAddressString() == "127.0.0.1")
			res.writeBody("local");
		else res.writeBody("remote");
	});

	runTask({
		scope(exit) exitEventLoop(true);

		auto url = "http://"~li.toAddressString~":11389/";

		auto cs = new HTTPClientSettings;
		cs.networkInterface = resolveHost("127.0.0.1");
		auto res = requestHTTP(url, null, cs).bodyReader.readAllUTF8();
		assert(res == "local", "Unexpected reply: "~res);

		auto cs2 = new HTTPClientSettings;
		cs2.networkInterface = li;
		res = requestHTTP(url, null, cs2).bodyReader.readAllUTF8();
		assert(res == "remote", "Unexpected reply: "~res);
    });
}
