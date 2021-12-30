module app;

import vibe.core.core;
import vibe.http.server;

void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
@safe {
	string local_var = "Hello, World!";
	bool is_admin = false;
	res.headers["Content-Type"] = "text/html";

	res.render!("diet.dt", req, local_var, is_admin);
}

int main(string[] args)
{
	auto settings = new HTTPServerSettings;
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	auto listener = listenHTTP(settings, &handleRequest);
	return runApplication(&args);
}
