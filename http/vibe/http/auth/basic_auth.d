/**
	Implements HTTP Basic Auth.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.auth.basic_auth;

import vibe.http.server;
import vibe.core.log;

import std.base64;
import std.exception;
import std.string;

@safe:


/**
	Returns a request handler that enforces request to be authenticated using HTTP Basic Auth.
*/
HTTPServerRequestDelegateS performBasicAuth(string realm, PasswordVerifyCallback pwcheck)
{
	void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res)
	@safe {
		if (!checkBasicAuth(req, pwcheck)) {
			res.statusCode = HTTPStatus.unauthorized;
			res.contentType = "text/plain";
			res.headers["WWW-Authenticate"] = "Basic realm=\""~realm~"\"";
			res.bodyWriter.write("Authorization required");
		}
	}
	return &handleRequest;
}
/// Scheduled for deprecation - use a `@safe` callback instead.
HTTPServerRequestDelegateS performBasicAuth(string realm, bool delegate(string, string) @system pwcheck)
@system {
	return performBasicAuth(realm, (u, p) @trusted => pwcheck(u, p));
}


/**
	Enforces HTTP Basic Auth authentication on the given req/res pair.

	Params:
		req = Request object that is to be checked
		res = Response object that will be used for authentication errors
		realm = HTTP Basic Auth realm reported to the client
		pwcheck = A delegate queried for validating user/password pairs

	Returns: Returns the name of the authenticated user.

	Throws: Throws a HTTPStatusExeption in case of an authentication failure.
*/
string performBasicAuth(scope HTTPServerRequest req, scope HTTPServerResponse res, string realm, scope PasswordVerifyCallback pwcheck)
{
	if (checkBasicAuth(req, pwcheck))
		return req.username;

	res.headers["WWW-Authenticate"] = "Basic realm=\""~realm~"\"";
	throw new HTTPStatusException(HTTPStatus.unauthorized);
}
/// Scheduled for deprecation - use a `@safe` callback instead.
string performBasicAuth(scope HTTPServerRequest req, scope HTTPServerResponse res, string realm, scope bool delegate(string, string) @system pwcheck)
@system {
	return performBasicAuth(req, res, realm, (u, p) @trusted => pwcheck(u, p));
}


/**
	Checks for valid HTTP Basic Auth authentication on the given request.

	Upon successful authorization, the name of the authorized user will
	be stored in `req.username`.

	Params:
		req = Request object that is to be checked
		pwcheck = A delegate queried for validating user/password pairs

	Returns: Returns `true` $(I iff) a valid Basic Auth header is present
		and the credentials were verified successfully by the validation
		callback.

	Throws: Throws a `HTTPStatusExeption` with `HTTPStatusCode.badRequest`
		if the "Authorization" header is malformed.
*/
bool checkBasicAuth(scope HTTPServerRequest req, scope PasswordVerifyCallback pwcheck)
{
	auto pauth = "Authorization" in req.headers;
	if (pauth && (*pauth).startsWith("Basic ")) {
		string user_pw = () @trusted { return cast(string)Base64.decode((*pauth)[6 .. $]); } ();

		auto idx = user_pw.indexOf(":");
		enforceBadRequest(idx >= 0, "Invalid auth string format!");
		string user = user_pw[0 .. idx];
		string password = user_pw[idx+1 .. $];

		if (pwcheck(user, password)) {
			req.username = user;
			return true;
		}
	}

	return false;
}


/**
	Augments the given HTTP request with an HTTP Basic Auth header.
*/
void addBasicAuth(scope HTTPRequest req, string user, string password)
{
	string pwstr = user ~ ":" ~ password;
	string authstr = () @trusted { return cast(string)Base64.encode(cast(ubyte[])pwstr); } ();
	req.headers["Authorization"] = "Basic " ~ authstr;
}

alias PasswordVerifyCallback = bool delegate(string user, string password);
