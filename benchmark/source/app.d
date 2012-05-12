import vibe.d;

import vibe.http.rest;

char[] data;

void empty(HttpServerRequest req, HttpServerResponse res)
{
	res.writeBody("");
}

void static_10(HttpServerRequest req, HttpServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 10]);
}

void static_1k(HttpServerRequest req, HttpServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 1000]);
}

void static_10k(HttpServerRequest req, HttpServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 10_000]);
}

void static_100k(HttpServerRequest req, HttpServerResponse res)
{
	res.writeBody(cast(string)data[0 .. 100_000]);
}

void staticAnswer(TcpConnection conn)
{
	conn.write("HTTP/1.0 200 OK\r\nContent-Length: 0\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n");
}

static this()
{
	//setLogLevel(LogLevel.Debug);

	data.length = 100_000;
	foreach( i; 0 .. data.length ){
		data[i] = (i % 10) + '0';
		if( i % 100 == 99 ) data[i] = '\n';
	}

	auto settings = new HttpServerSettings;
	settings.port = 8080;
//	settings.options = HttpServerOption.None;
	//settings.accessLogToConsole = true;

	auto fsettings = new HttpFileServerSettings;
	fsettings.serverPathPrefix = "/file";

	auto routes = new UrlRouter;
	routes.get("/", staticTemplate!"home.dt");
	routes.get("/empty", &empty);
	routes.get("/static/10", &static_10);
	routes.get("/static/1k", &static_1k);
	routes.get("/static/10k", &static_10k);
	routes.get("/static/100k", &static_100k);
	routes.get("/file/*", serveStaticFiles("./public", fsettings));

	listenHttp(settings, routes);
	listenTcp(8081, toDelegate(&staticAnswer), "127.0.0.1");
}
