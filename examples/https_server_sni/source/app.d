import vibe.appmain;
import vibe.core.log;
import vibe.http.server;
import vibe.stream.tls;


shared static this()
{
	{
		auto settings = new HTTPServerSettings;
		settings.port = 8080;
		settings.hostName = "hosta";
		settings.bindAddresses = ["::1", "127.0.0.1"];
		settings.tlsContext = createTLSContext(TLSContextKind.server);
		settings.tlsContext.useCertificateChainFile("hosta.crt");
		settings.tlsContext.usePrivateKeyFile("hosta.key");
		listenHTTP(settings, &handleRequestA);
	}

	{
		auto settings = new HTTPServerSettings;
		settings.port = 8080;
		settings.hostName = "hostb";
		settings.bindAddresses = ["::1", "127.0.0.1"];
		settings.tlsContext = createTLSContext(TLSContextKind.server);
		settings.tlsContext.useCertificateChainFile("hostb.crt");
		settings.tlsContext.usePrivateKeyFile("hostb.key");
		listenHTTP(settings, &handleRequestB);
	}

	logInfo(
`This example shows how to run multiple HTTPS virtual hosts on the same port.
For this to work, you need to add the following two lines to your /etc/hosts
file:

  127.0.0.1 hosta
  127.0.0.1 hostb

You can then navigate to either https://hosta:8080/ or https://hostb:8080/
and should be presented with a different certificate each time, matching the
host name entered.
`);
}

void handleRequestA(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, this is host A!", "text/plain");
}

void handleRequestB(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(cast(ubyte[])"Hello, this is host B!", "text/plain");
}
