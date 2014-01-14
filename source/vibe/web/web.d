/**
	Implements a descriptive framework for building web interfaces.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.web;

public import vibe.internal.meta.funcattr : before, after;
public import vibe.web.common;

import vibe.core.core;
import vibe.http.common;
import vibe.http.router;
import vibe.http.server;

/*
	TODO:
		- conversion errors of path place holder parameters should result in 404
		- support arrays and composite types as parameters by splitting them up into multiple form/query parameters
		- support format patterns for redirect()
		- add a way to specify response headers without explicit access to "res"
		- support class/interface getter properties and register their methods as well
		- support authentication somehow nicely
*/


/** Registers a HTTP/web interface based on a class instance.

	Each method corresponds to one or multiple request URLs.

	...
*/
void registerWebInterface(C : Object, MethodStyle method_style = MethodStyle.lowerUnderscored)(URLRouter router, C instance, WebInterfaceSettings settings = null)
{
	import std.traits;

	if (!settings) settings = new WebInterfaceSettings;

	foreach (M; __traits(allMembers, C)) {
		/*static if (isInstanceOf!(SessionVar, __traits(getMember, instance, M))) {
			__traits(getMember, instance, M).m_getContext = toDelegate({ return s_requestContext; });
		}*/
		static if (!is(typeof(__traits(getMember, Object, M)))) { // exclude Object's default methods and field
			foreach (overload; MemberFunctionsTuple!(C, M)) {
				enum minfo = extractHTTPMethodAndName!overload();
				enum url = minfo.hadPathUDA ? minfo.url : adjustMethodStyle(minfo.url, method_style);

				router.match(minfo.method, concatURL(settings.urlPrefix, url), (req, res) {
					handleRequest!(M, overload)(req, res, instance, settings);
				});
			}
		}
	}
}

void render(string diet_file, ALIASES...)()
{
	assert(s_requestContext.req !is null, "render() used outside of a web interface request!");
	auto req = s_requestContext.req;
	vibe.http.server.render!(diet_file, req, ALIASES)(s_requestContext.res);
}

void redirect(string path_or_url)
{
	import std.array : startsWith;

	assert(s_requestContext.req !is null, "redirect() used outside of a web interface request!");
	alias ctx = s_requestContext;
	URL url;
	if (path_or_url.startsWith("/")) {
		url = ctx.req.fullURL;
		url.path = Path(path_or_url);
	} else if (path_or_url.canFind(":")) { // TODO: better URL recognition
		url = URL(path_or_url);
	} else {
		if (ctx.req.fullURL.path.endsWithSlash) url = ctx.req.fullURL ~ Path(path_or_url);
		else url = ctx.req.fullURL.parentURL ~ Path(path_or_url);
	}
	ctx.res.redirect(url);
}

class WebInterfaceSettings {
	string urlPrefix = "/";
}


/**
	Maps a web interface member variable to a session field.
*/
struct SessionVar(T, string name) {
	private {
		T m_initValue;
	}

	this(T init_val) { m_initValue = init_val; }

	void opAssign(T new_value) { this.value = new_value; }

	@property T value()
	{
		assert(s_requestContext.req !is null, "SessionVar used outside of a web interface request!");
		alias ctx = s_requestContext;
		if (ctx.req.session && ctx.req.session.isKeySet(name))
			return ctx.req.session.get!T(name);

		return m_initValue;
	}

	@property void value(T new_value)
	{
		assert(s_requestContext.req !is null, "SessionVar used outside of a web interface request!");
		alias ctx = s_requestContext;
		if (!ctx.req.session) ctx.req.session = ctx.res.startSession();
		ctx.req.session.set(name, new_value);
	}

	alias value this;
}

private {
	TaskLocal!RequestContext s_requestContext;
}

private struct RequestContext {
	HTTPServerRequest req;
	HTTPServerResponse res;
}

private void handleRequest(string M, alias overload, C)(HTTPServerRequest req, HTTPServerResponse res, C instance, WebInterfaceSettings settings)
{
	import std.array : startsWith;
	import std.traits;

	alias RET = ReturnType!overload;
	alias PARAMS = ParameterTypeTuple!overload;
	alias default_values = ParameterDefaultValueTuple!overload;
	enum param_names = [ParameterIdentifierTuple!overload];

	s_requestContext = RequestContext(req, res);
	PARAMS params;
	foreach (i, PT; PARAMS) {
		static if (is(PT == InputStream)) params[i] = req.bodyReader;
		else static if (is(PT == HTTPServerRequest) || is(PT == HTTPRequest)) params[i] = req;
		else static if (is(PT == HTTPServerResponse) || is(PT == HTTPResponse)) params[i] = res;
		else static if (param_names[i].startsWith("_")) {
			if (auto pv = param_names[i][1 .. $] in req.params) params[i] = (*pv).convTo!PT;
			else static if (!is(default_values[i] == void)) params[i] = default_values[i];
			else enforceHTTP(false, HTTPStatus.badRequest, "Missing request parameter for "~param_names[i]);
		} else static if (is(PT == bool)) {
			params[i] = param_names[i] in req.form || param_names[i] in req.query;
		} else {
			if (auto pv = param_names[i] in req.form) params[i] = (*pv).convTo!PT;
			else if (auto pv = param_names[i] in req.query) params[i] = (*pv).convTo!PT;
			else static if (!is(default_values[i] == void)) params[i] = default_values[i];
			else enforceHTTP(false, HTTPStatus.badRequest, "Missing form/query field "~param_names[i]);
		}
	}

	static if (is(RET : InputStream)) {
		res.writeBody(__traits(getMember, instance, M)(params));
	} else {
		static assert(is(RET == void), "Only InputStream and void are supported as return types.");
		__traits(getMember, instance, M)(params);
	}
}

private T convTo(T)(string str)
{
	import std.conv;
	static if (is(typeof(T.fromString(str)) == T)) return T.fromString(str);
	else return str.to!T();
}
