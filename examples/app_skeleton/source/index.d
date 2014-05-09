module index;

import vibe.d;


void showHome(HTTPServerRequest req, HTTPServerResponse res)
{
	string username = "Tester Test";
	res.render!("home.dt", req, username);
	//res.renderCompat!("home.dt",
	//	HTTPServerRequest, "req",
	//	string, "username")(req, username);
}