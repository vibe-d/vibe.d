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
import vibe.inet.url;

import std.base64;
import std.datetime;
import std.digest.md;
import std.exception;
import std.string;
import std.uuid;

@safe:

enum NonceState { Valid, Expired, Invalid }

class DigestAuthInfo
{
	@safe:

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
		auto time = () @trusted { return *cast(ubyte[now.sizeof]*)&now; } ();
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
		auto timebytes = decoded[0 .. now.sizeof];
		auto time = () @trusted { return (cast(typeof(now)[])timebytes)[0]; } ();
		if (timeout + time > now) return NonceState.Expired;
		MD5 md5;
		md5.put(timebytes);
		md5.put(secret);
		auto data = md5.finish();
		if (data[] != decoded[now.sizeof .. $]) return NonceState.Invalid;
		return NonceState.Valid;
	}
}

private bool checkDigest(scope HTTPServerRequest req, DigestAuthInfo info, scope DigestHashCallback pwhash, out bool stale, out string username)
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
				case "realm": realm = param.stripLeft()[7..$-1]; break;
				case "username": username = param.stripLeft()[10..$-1]; break;
				case "nonce": nonce = kv[1][1..$-1]; break;
				case "uri": uri = param.stripLeft()[5..$-1]; break;
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
HTTPServerRequestDelegate performDigestAuth(DigestAuthInfo info, scope DigestHashCallback pwhash)
{
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	@safe {
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
/// Scheduled for deprecation - use a `@safe` callback instead.
HTTPServerRequestDelegate performDigestAuth(DigestAuthInfo info, scope string delegate(string, string) @system pwhash)
@system {
	return performDigestAuth(info, (r, u) @trusted => pwhash(r, u));
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
string performDigestAuth(scope HTTPServerRequest req, scope HTTPServerResponse res, DigestAuthInfo info, scope DigestHashCallback pwhash)
{
	bool stale;
	string username;
	if (checkDigest(req, info, pwhash, stale, username))
		return username;

	res.headers["WWW-Authenticate"] = "Digest realm=\""~info.realm~"\", nonce=\""~info.createNonce(req)~"\", stale="~(stale?"true":"false");
	throw new HTTPStatusException(HTTPStatus.unauthorized);
}
/// Scheduled for deprecation - use a `@safe` callback instead.
string performDigestAuth(scope HTTPServerRequest req, scope HTTPServerResponse res, DigestAuthInfo info, scope string delegate(string, string) @system pwhash)
@system {
	return performDigestAuth(req, res, info, (r, u) @trusted => pwhash(r, u));
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

alias DigestHashCallback = string delegate(string realm, string user);

/// Structure which describes requirements of the digest authentication - see https://tools.ietf.org/html/rfc2617
struct DigestAuthParams {
	enum Qop { none = 0, auth = 1, auth_int = 2 }
	enum Algorithm { none = 0, md5 = 1, md5_sess = 2 }

	string realm, domain, nonce, opaque;
	Algorithm algorithm = Algorithm.md5;
	bool stale;
	Qop qop;

	/// Parses WWW-Authenticate header value with the digest parameters
	this(string auth) {
		import std.algorithm : splitter;

		assert(auth.startsWith("Digest "), "Correct Digest authentication request not provided");

		foreach (param; auth["Digest ".length..$].splitter(','))
		{
			auto idx = param.indexOf("=");
			if (idx <= 0) {
				logError("Invalid parameter in auth header: %s (%s)", param, auth);
				continue;
			}
			auto k = param[0..idx];
			auto v = param[idx+1..$];
			switch (k.strip().toLower()) {
				default: break;
				case "realm": realm = v[1..$-1]; break;
				case "domain": domain = v[1..$-1]; break;
				case "nonce": nonce = v[1..$-1]; break;
				case "opaque": opaque = v[1..$-1]; break;
				case "stale": stale = v.toLower() == "true"; break;
				case "algorithm":
					switch (v) {
						default: break;
						case "MD5": algorithm = Algorithm.md5; break;
						case "MD5-sess": algorithm = Algorithm.md5_sess; break;
					}
					break;
				case "qop":
					foreach (q; v[1..$-1].splitter(',')) {
						switch (q) {
							default: break;
							case "auth": qop |= Qop.auth; break;
							case "auth-int": qop |= Qop.auth_int; break;
						}
					}
					break;
			}
		}
	}
}

/**
	Creates the digest authorization request header.

	Params:
		username = user name
		password = user password
		url = requested url
		auth = value from the WWW-Authenticate response header
		cnonce = client generated unique data string (required only when some qop is requested)
		nc = the count of requests sent by the client (required only when some qop is requested)
		entityBody = request entity body required only if qop==auth-int
*/
auto createDigestAuthHeader(U)(HTTPMethod method, U url, string username, string password, DigestAuthParams auth,
	string cnonce = null, int nc = 0, in ubyte[] entityBody = null)
if (is(U == string) || is(U == URL)) {

	import std.array : appender;
	import std.format : formattedWrite;

	auto getHA1(string username, string password, string realm, string nonce = null, string cnonce = null) {

		assert((nonce is null && cnonce is null) || (nonce !is null && cnonce !is null));

		auto ha1 = toHexString!(LetterCase.lower)(md5Of(format("%s:%s:%s", username, realm, password))).dup;
		if (nonce !is null) ha1 = toHexString!(LetterCase.lower)(md5Of(format("%s:%s:%s", ha1, nonce, cnonce))).dup;
		return ha1;
	}

	auto getHA2(HTTPMethod method, string uri, in ubyte[] ebody = null) {
		return ebody is null
			? toHexString!(LetterCase.lower)(md5Of(format("%s:%s", method, uri))).dup
			: toHexString!(LetterCase.lower)(md5Of(format("%s:%s:%s", method, uri, toHexString!(LetterCase.lower)(md5Of(ebody)).dup))).dup;
	}

	static if (is(U == string)) auto uri = URL(url).pathString;
	else auto uri = url.pathString;

	auto dig = appender!string();
	dig ~= "Digest ";
	dig ~= `username="`; dig ~= username; dig ~= `", `;
	dig ~= `realm="`; dig ~= auth.realm; dig ~= `", `;
	dig ~= `nonce="`; dig ~= auth.nonce; dig ~= `", `;
	dig ~= `uri="`; dig ~= uri; dig ~= `", `;
	if (auth.opaque.length) { dig ~= `opaque="`; dig ~= auth.opaque; dig ~= `", `; }

	//choose one of provided qop
	DigestAuthParams.Qop qop;
	if ((auth.qop & DigestAuthParams.Qop.auth) == DigestAuthParams.Qop.auth) qop = DigestAuthParams.Qop.auth;
	else if ((auth.qop & DigestAuthParams.Qop.auth_int) == DigestAuthParams.Qop.auth_int) qop = DigestAuthParams.Qop.auth_int;

	if (qop != DigestAuthParams.Qop.none) {
		assert(cnonce !is null, "cnonce is required");
		assert(nc != 0, "nc is required");

		dig ~= `qop="`; dig ~= qop == DigestAuthParams.Qop.auth ? "auth" : "auth-int"; dig ~= `", `;
		dig ~= `cnonce="`; dig ~= cnonce; dig ~= `", `;
		dig ~= `nc="`; dig.formattedWrite("%08x", nc); dig ~= `", `;
	}

	auto ha1 = auth.algorithm == DigestAuthParams.Algorithm.md5_sess
		? getHA1(username, password, auth.realm, auth.nonce, cnonce)
		: getHA1(username, password, auth.realm);

	auto ha2 = qop != DigestAuthParams.Qop.auth_int
		? getHA2(method, uri)
		: getHA2(method, uri, entityBody);

	auto resp = qop == DigestAuthParams.Qop.none
		? toHexString!(LetterCase.lower)(md5Of(format("%s:%s:%s", ha1, auth.nonce, ha2))).dup
		: toHexString!(LetterCase.lower)(md5Of(format("%s:%s:%08x:%s:%s:%s", ha1, auth.nonce, nc, cnonce, qop == DigestAuthParams.Qop.auth ? "auth" : "auth-int" , ha2))).dup;

	dig ~= `response="`; dig ~= resp; dig ~= `"`;

	return dig.data;
}
