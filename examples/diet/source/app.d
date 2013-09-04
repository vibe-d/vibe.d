import vibe.appmain;
import vibe.http.server;

void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
{
	string local_var = "Hello, World!";
	res.headers["Content-Type"] = "text/html";
	
	auto output = res.bodyWriter();
	//parseDietFile!("diet.dt", req, local_var)(output);
	res.renderCompat!("diet.dt",
		HTTPServerRequest, "req",
		string, "local_var")(req, local_var);
}

shared static this()
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	
	listenHTTP(settings, &handleRequest);
}
