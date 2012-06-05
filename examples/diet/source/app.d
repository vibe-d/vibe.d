import vibe.d;

void handleRequest(HttpServerRequest req, HttpServerResponse res)
{
	string local_var = "Hello, World!";
	res.headers["Content-Type"] = "text/html";
	
	auto output = res.bodyWriter();
	parseDietFile!("diet.dt", req, local_var)(output);
}

static this()
{
	auto settings = new HttpServerSettings;
	settings.port = 8080;
	
	listenHttp(settings, &handleRequest);
}
