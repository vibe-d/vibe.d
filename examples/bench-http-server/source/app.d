import vibe.appmain;
import vibe.core.core;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;

import std.functional;


shared string data;

void empty(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody("");
}

void static_10(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 10]);
}

void static_1k(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 1000]);
}

void static_10k(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 10_000]);
}

void static_100k(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 100_000]);
}

void quit(HTTPServerRequest req, HTTPServerResponse res)
{
	res.writeBody("Exiting event loop...");
	exitEventLoop();
}

void staticAnswer(TCPConnection conn)
{
	conn.write("HTTP/1.0 200 OK\r\nContent-Length: 0\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n");
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

	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.options = HTTPServerOption.parseURL|HTTPServerOption.distribute;
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
	listenTCP(8081, toDelegate(&staticAnswer), "127.0.0.1");
}
