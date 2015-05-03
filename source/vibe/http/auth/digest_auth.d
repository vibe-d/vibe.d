/**
	Implements HTTP Digest Authentication.

	This is a minimal implementation based on RFC 2069.

	Copyright: © 2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Kai Nacke
*/
module vibe.http.auth.digest_auth;

import vibe.http.server;
import vibe.core.log;

import std.base64;
import std.datetime;
import std.digest.md;
import std.exception;
import std.string;
import std.uuid;

enum NonceState { Valid, Expired, Invalid }

class DigestAuthInfo
{
	string realm;
	ubyte[] secret;
	ulong timeout;

	this()
	{
		secret = randomUUID().data.dup;
		timeout = 300;
	}

	string createNonce(in HTTPServerRequest req)
	{
		auto now = Clock.currTime(UTC()).stdTime();
		auto time = *cast(ubyte[now.sizeof]*)&now;
		MD5 md5;
		md5.put(time);
		md5.put(secret);
		auto data = md5.finish();
		return Base64.encode(time ~ data);
	}

	NonceState checkNonce(in string nonce, in HTTPServerRequest req)
	{
		auto now = Clock.currTime(UTC()).stdTime();
		ubyte[] decoded = Base64.decode(nonce);
		if (decoded.length != now.sizeof + secret.length) return NonceState.Invalid;
		auto time = decoded[0..now.sizeof];
		if (timeout + *cast(typeof(now)*)time.ptr > now) return NonceState.Expired;
		MD5 md5;
		md5.put(time);
		md5.put(secret);
		auto data = md5.finish();
		if (data[] != decoded[now.sizeof..$]) return NonceState.Invalid;
		return NonceState.Valid;
	}
}

private bool checkDigest(scope HTTPServerRequest req, DigestAuthInfo info, scope string delegate(string realm, string user) pwhash, out bool stale, out string username)
{
	stale = false;
	username = "";
	auto pauth = "Authorization" in req.headers;

	if (pauth && (*pauth).startsWith("Digest ")) {
		string realm, nonce, response, uri, algorithm;
		foreach (param; split((*pauth)[7 .. $], ",")) {
			auto kv = split(param, "=");
			switch (kv[0].strip().toLower()) {
				default: break;
				case "realm": realm = kv[1][1..$-1]; break;
				case "username": username = kv[1][1..$-1]; break;
				case "nonce": nonce = kv[1][1..$-1]; break;
				case "uri": uri = kv[1][1..$-1]; break;
				case "response": response = kv[1][1..$-1]; break;
				case "algorithm": algorithm = kv[1][1..$-1]; break;
			}
		}

		if (realm != info.realm)
			return false;
		if (algorithm !is null && algorithm != "MD5")
			return false;

		auto nonceState = info.checkNonce(nonce, req);
		if (nonceState != NonceState.Valid) {
			stale = nonceState == NonceState.Expired;
			return false;
		}

		auto ha1 = pwhash(realm, username);
		auto ha2 = toHexString!(LetterCase.lower)(md5Of(httpMethodString(req.method) ~ ":" ~ uri));
		auto calcresponse = toHexString!(LetterCase.lower)(md5Of(ha1 ~ ":" ~ nonce ~ ":" ~ ha2 ));
		if (response[] == calcresponse[])
			return true;
	}
	return false;
}

/**
	Returns a request handler that enforces request to be authenticated using HTTP Digest Auth.
*/
HTTPServerRequestDelegate performDigestAuth(DigestAuthInfo info, scope string delegate(string realm, string user) pwhash)
{
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		bool stale;
		string username;
		if (checkDigest(req, info, pwhash, stale, username)) {
			req.username = username;
			return ;
		}

		// else output an error page
		res.statusCode = HTTPStatus.unauthorized;
		res.contentType = "text/plain";
		res.headers["WWW-Authenticate"] = "Digest realm=\""~info.realm~"\", nonce=\""~info.createNonce(req)~"\", stale="~(stale?"true":"false");
		res.bodyWriter.write("Authorization required");
	}
	return &handleRequest;
}

/**
	Enforces HTTP Digest Auth authentication on the given req/res pair.

	Params:
		req = Request object that is to be checked
		res = Response object that will be used for authentication errors
		info = Digest authentication info object
		pwhash = A delegate queried for returning the digest password

	Returns: Returns the name of the authenticated user.

	Throws: Throws a HTTPStatusExeption in case of an authentication failure.
*/
string performDigestAuth(scope HTTPServerRequest req, scope HTTPServerResponse res, DigestAuthInfo info, scope string delegate(string realm, string user) pwhash)
{
	bool stale;
	string username;
	if (checkDigest(req, info, pwhash, stale, username))
		return username;

	res.headers["WWW-Authenticate"] = "Digest realm=\""~info.realm~"\", nonce=\""~info.createNonce(req)~"\", stale="~(stale?"true":"false");
	throw new HTTPStatusException(HTTPStatus.unauthorized);
}

/**
	Creates the digest password from the user name, realm and password.

	Params:
		realm = The realm
		user = The user name
		password = The plain text password

	Returns: Returns the digest password
*/
string createDigestPassword(string realm, string user, string password)
{
	return toHexString!(LetterCase.lower)(md5Of(user ~ ":" ~ realm ~ ":" ~ password)).dup;
}
