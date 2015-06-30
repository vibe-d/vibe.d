import vibe.appmain;
import vibe.http.server;
import vibe.stream.tls;
import vibe.stream.botan;
import vibe.core.log;
import vibe.core.core;
import libasync.threads;
import std.datetime;

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	if (req.path == "/")
		res.writeBody("Hello, World!", "text/plain");
}

shared static this()
{
	setLogLevel(LogLevel.trace);
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	version(Botan) settings.tlsContext = new BotanTLSContext(TLSContextKind.server/*, createCreds()*/); // see stream/botan for more options
	settings.tlsContext.useCertificateChainFile("server_insecure.crt");
	settings.tlsContext.usePrivateKeyFile("server_insecure.key");

	listenHTTP(settings, &handleRequest);
}
