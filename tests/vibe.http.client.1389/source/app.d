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
	auto externalAddr = ec.localAddress;
	ec.close();
	logInfo("External interface: %s", externalAddr.toString());

	auto settings = new HTTPServerSettings;
	settings.port = 0;
	settings.bindAddresses = [externalAddr.toAddressString()];
	immutable serverAddr = listenHTTP(settings, (req, res) {
		if (req.clientAddress.toAddressString() == "127.0.0.1")
			res.writeBody("local");
		else res.writeBody("remote");
	}).bindAddresses[0];

	runTask({
		scope(exit) exitEventLoop(true);

		auto url = "http://"~serverAddr.toString;
		logInfo(url);

		auto cs = new HTTPClientSettings;
		cs.networkInterface = resolveHost("127.0.0.1");
		auto res = requestHTTP(url, null, cs).bodyReader.readAllUTF8();
		assert(res == "local", "Unexpected reply: "~res);

		auto cs2 = new HTTPClientSettings;
		cs2.networkInterface = resolveHost(externalAddr.toAddressString());
		res = requestHTTP(url, null, cs2).bodyReader.readAllUTF8();
		assert(res == "remote", "Unexpected reply: "~res);
    });
}
