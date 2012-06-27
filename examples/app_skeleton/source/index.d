module index;

import vibe.d;


void showHome(HttpServerRequest req, HttpServerResponse res)
{
	string username = "Tester Test";
	res.render!("home.dt", req, username);
}