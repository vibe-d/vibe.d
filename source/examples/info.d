module examples.jade;

import vibe.d;


void handleRequest(HttpServerRequest req, HttpServerResponse res)
{
	res.headers["Content-Type"] = "text/html";	
	
	auto output = res.bodyWriter();
	parseDietFile!("info.dt", req)(output);
}

static this()
{
	auto settings = new HttpServerSettings;
	settings.sessionStore = new MemorySessionStore();
	settings.port = 8080;
	
	listenHttp(settings, &handleRequest);
}
