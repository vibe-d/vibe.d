import vibe.appmain;
import vibe.core.core;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;
import vibe.core.stream : pipe, nullSink;

import std.functional : toDelegate;


shared string data;

void empty(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody("");
}

void static_10(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 10]);
}

void static_1k(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 1000]);
}

void static_10k(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 10_000]);
}

void static_100k(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 100_000]);
}

void quit(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	res.writeBody("Exiting event loop...");
	exitEventLoop();
}

void staticAnswer(TCPConnection conn)
@safe nothrow {
	try {
		conn.write("HTTP/1.0 200 OK\r\nContent-Length: 0\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n");
		conn.close();
	} catch (Exception e) {
		// increment error counter
	}
}

pure char[] generateData()
{
	char[] data;
	data.length = 100_000;
	foreach (i; 0 .. data.length) {
		data[i] = (i % 10) + '0';
		if (i % 100 == 99) data[i] = '\n';
	}
	return data;
}


shared static this()
{
	//setLogLevel(LogLevel.Trace);
	data = generateData();

	runWorkerTaskDist({
		auto settings = new HTTPServerSettings;
		settings.port = 8080;
		settings.bindAddresses = ["127.0.0.1"];
		settings.options = HTTPServerOption.parseURL|HTTPServerOption.reusePort;
		//settings.accessLogToConsole = true;

		auto fsettings = new HTTPFileServerSettings;
		fsettings.serverPathPrefix = "/file";

		auto routes = new URLRouter;
		routes.get("/", staticTemplate!"home.dt");
		routes.get("/empty", &empty);
		routes.get("/static/10", &static_10);
		routes.get("/static/1k", &static_1k);
		routes.get("/static/10k", &static_10k);
		routes.get("/static/100k", &static_100k);
		routes.get("/quit", &quit);
		routes.get("/file/*", serveStaticFiles("./public", fsettings));
		routes.rebuild();

		listenHTTP(settings, routes);
		listenTCP(8081, toDelegate(&staticAnswer), "127.0.0.1", TCPListenOptions.reusePort);
	});
}
