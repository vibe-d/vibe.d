/**
	Implements a descriptive framework for building web interfaces.

	Copyright: © 2013-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.web;

public import vibe.internal.meta.funcattr : before, after;
public import vibe.web.common;
public import vibe.web.i18n;

import vibe.core.core;
import vibe.http.common;
import vibe.http.router;
import vibe.http.server;

/*
	TODO:
		- conversion errors of path place holder parameters should result in 404
		- support format patterns for redirect()
		- add a way to specify response headers without explicit access to "res"
		- support class/interface getter properties and register their methods as well
		- support authentication somehow nicely
		- support UDA based parameter validation
*/


/**
	Registers a HTTP/web interface based on a class instance.

	Each public method corresponds to one or multiple request URLs.

	Supported types...

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


/**
	Gives an overview of the basic features. For more advanced use, see the
	example in the "examples/web/" directory.
*/
unittest {
	import vibe.http.router;
	import vibe.http.server;
	import vibe.web.web;

	class WebService {
		private {
			SessionVar!(string, "login_user") m_loginUser;
		}

		@path("/")
		void getIndex(string _error = null)
		{
			//render!("index.dt", _error);
		}

		// automatically mapped to: POST /login
		@errorDisplay!getIndex
		void postLogin(string username, string password)
		{
			enforceHTTP(username.length > 0, HTTPStatus.forbidden,
				"User name must not be empty.");
			enforceHTTP(password == "secret", HTTPStatus.forbidden,
				"Invalid password.");
			m_loginUser = username;
			redirect("/profile");
		}

		// automatically mapped to: POST /logout
		void postLogout()
		{
			terminateSession();
			redirect("/");
		}

		// automatically mapped to: GET /profile
		void getProfile()
		{
			enforceHTTP(m_loginUser.length > 0, HTTPStatus.forbidden,
				"Must be logged in to access the profile.");
			//render!("profile.dt")
		}
	}

	void run()
	{
		auto router = new URLRouter;
		router.registerWebInterface(new WebService);

		auto settings = new HTTPServerSettings;
		settings.port = 8080;
		listenHTTP(settings, router);
	}
}


/**
	Renders a Diet template file to the current HTTP response.

	This function is equivalent to vibe.http.server.render, but implicitly
	writes the result to the response object of the currently processed
	request.

	Note that this may only be called from a function/method
	registered using registerWebInterface.
*/
template render(string diet_file, ALIASES...) {
	void render(string MODULE = __MODULE__, string FUNCTION = __FUNCTION__)()
	{
		import vibe.web.i18n;
		import vibe.internal.meta.uda : findFirstUDA;
		mixin("static import "~MODULE~";");

		alias PARENT = typeof(__traits(parent, mixin(FUNCTION)).init);
		enum FUNCTRANS = findFirstUDA!(TranslationContextAttribute, mixin(FUNCTION));
		enum PARENTTRANS = findFirstUDA!(TranslationContextAttribute, PARENT);
		static if (FUNCTRANS.found) alias TranslateContext = FUNCTRANS.value.Context;
		else static if (PARENTTRANS.found) alias TranslateContext = PARENTTRANS.value.Context;

		assert(s_requestContext.req !is null, "render() used outside of a web interface request!");
		auto req = s_requestContext.req;

		static if (is(TranslateContext) && TranslateContext.languages.length) {
			static if (TranslateContext.languages.length > 1) {
				switch (s_requestContext.language) {
					default: {
						static string diet_translate__(string key) { return tr!(TranslateContext, TranslateContext.languages[0])(key); }
						vibe.http.server.render!(diet_file, req, ALIASES, diet_translate__)(s_requestContext.res);
						return;
						}
					foreach (lang; TranslateContext.languages[1 .. $])
						case lang: {
							mixin("struct "~lang~" { static string diet_translate__(string key) { return tr!(TranslateContext, lang)(key); } void render() { vibe.http.server.render!(diet_file, req, ALIASES, diet_translate__)(s_requestContext.res); } }");
							mixin(lang~" renderctx;");
							renderctx.render();
							return;
							}
				}
			} else {
				static string diet_translate__(string key) { return tr!(TranslateContext, TranslateContext.languages[0])(key); }
				vibe.http.server.render!(diet_file, req, ALIASES, diet_translate__)(s_requestContext.res);
			}
		} else {
			vibe.http.server.render!(diet_file, req, ALIASES)(s_requestContext.res);
		}
	}
}


/**
	Redirects to the given URL.

	The URL may either be a full URL, including the protocol and server
	portion, or it may be the local part of the URI (the path and an
	optional query string). Finally, it may also be a relative path that is
	combined with the path of the current request to yield an absolute
	path.

	Note that this may only be called from a function/method
	registered using registerWebInterface.
*/
void redirect(string url)
{
	import std.algorithm : canFind, startsWith;

	assert(s_requestContext.req !is null, "redirect() used outside of a web interface request!");
	alias ctx = s_requestContext;
	URL fullurl;
	if (url.startsWith("/")) {
		fullurl = ctx.req.fullURL;
		fullurl.localURI = url;
	} else if (url.canFind(":")) { // TODO: better URL recognition
		fullurl = URL(url);
	} else {
		if (ctx.req.fullURL.path.endsWithSlash) fullurl = ctx.req.fullURL ~ Path(url);
		else fullurl = ctx.req.fullURL.parentURL ~ Path(url);
	}
	ctx.res.redirect(fullurl);
}


/**
	Terminates the currently active session (if any).

	Note that this may only be called from a function/method
	registered using registerWebInterface.
*/
void terminateSession()
{
	alias ctx = s_requestContext;
	if (ctx.req.session) {
		ctx.res.terminateSession();
		ctx.req.session = Session.init;
	}
}


/**
	Attribute to customize error display of an interface method.



	The first template parameter takes a function that maps an exception and an
	optional field name to a single error type. The result of this function
	will then be passed as the $(D _error) parameter to the method referenced
	by the second template parameter.

	The field parameter, if present, will be set to null if the exception was
	thrown after the field validation has finished.
*/
@property errorDisplay(alias DISPLAY_METHOD)()
{
	return ErrorDisplayAttribute!DISPLAY_METHOD.init;
}

/// Simple error message display
unittest {
	void getForm(string _error = null)
	{
		//render!("form.dt", _error);
	}

	@errorDisplay!getForm
	void postForm(string name)
	{
		if (name.length == 0)
			throw new Exception("Name must not be empty");
		redirect("/");
	}
}

/// Error message display with a matching
unittest {
	struct FormError {
		string error;
		string field;
	}

	void getForm(FormError _error = FormError.init)
	{
		//render!("form.dt", _error);
	}

	// throws an error if the submitted form value is not a valid integer
	@errorDisplay!getForm
	void postForm(int ingeter)
	{
		redirect("/");
	}
}


/**
	Encapsulates settings used to customize the generated web interface.
*/
class WebInterfaceSettings {
	string urlPrefix = "/";
}


/**
	Maps a web interface member variable to a session field.

	Setting a SessionVar variable will implicitly start a session, if none
	has been started, yet. The content of the variable will be stored in
	the session store and is automatically serialized and deserialized.

	Note that variables of type SessionVar must always be normal members of a
	class that was registered using registerWebInterface.
*/
struct SessionVar(T, string name) {
	private {
		T m_initValue;
	}

	/** Initializes a session var with a constant value.
	*/
	this(T init_val) { m_initValue = init_val; }
	///
	unittest {
		class MyService {
			SessionVar!(int, "someInt") m_someInt = 42;
		
			void index() {
				assert(m_someInt == 42);
			}
		}
	}

	/** Accesses the current value of the session variable.

		Any access will automatically start a new session and set the
		initializer value, if necessary.
	*/
	@property const(T) value()
	{
		assert(s_requestContext.req !is null, "SessionVar used outside of a web interface request!");
		alias ctx = s_requestContext;
		if (!ctx.req.session) ctx.req.session = ctx.res.startSession();

		if (ctx.req.session.isKeySet(name))
			return ctx.req.session.get!T(name);

		ctx.req.session.set!T(name, m_initValue);
		return m_initValue;
	}
	/// ditto
	@property void value(T new_value)
	{
		assert(s_requestContext.req !is null, "SessionVar used outside of a web interface request!");
		alias ctx = s_requestContext;
		if (!ctx.req.session) ctx.req.session = ctx.res.startSession();
		ctx.req.session.set(name, new_value);
	}

	void opAssign(T new_value) { this.value = new_value; }

	alias value this;
}


struct ErrorDisplayAttribute(alias DISPLAY_METHOD) {
	import std.traits : ParameterTypeTuple, ParameterIdentifierTuple;

	alias displayMethod = DISPLAY_METHOD;
	enum displayMethodName = __traits(identifier, DISPLAY_METHOD);

	private template GetErrorParamType(size_t idx) {
		static assert(idx < ParameterIdentifierTuple!DISPLAY_METHOD.length,
			"Error display method "~displayMethodName~" is missing the _error parameter.");
		static if (ParameterIdentifierTuple!DISPLAY_METHOD[idx] == "_error")
			alias GetErrorParamType = ParameterTypeTuple!DISPLAY_METHOD[idx];
		else alias GetErrorParamType = GetErrorParamType!(idx+1);
	}
	
	alias ErrorParamType = GetErrorParamType!0;

	ErrorParamType getError(Exception ex, string field)
	{
		static if (is(ErrorParamType == bool)) return true;
		else static if (is(ErrorParamType == string)) return ex.msg;
		else static if (is(ErrorParamType == Exception)) return ex;
		else static if (is(typeof(ErrorParamType(ex, field)))) return ErrorParamType(ex, field);
		else static if (is(typeof(ErrorParamType(ex.msg, field)))) return ErrorParamType(ex.msg, field);
		else static if (is(typeof(ErrorParamType(ex.msg)))) return ErrorParamType(ex.msg);
		else static assert(false, "Error parameter type %s does not have the required constructor.");
	}
}


private {
	TaskLocal!RequestContext s_requestContext;
}

private struct RequestContext {
	HTTPServerRequest req;
	HTTPServerResponse res;
	string language;
}

private void handleRequest(string M, alias overload, C, ERROR...)(HTTPServerRequest req, HTTPServerResponse res, C instance, WebInterfaceSettings settings, ERROR error)
	if (ERROR.length <= 1)
{
	import std.array : startsWith;
	import std.traits;
	import vibe.internal.meta.uda : findFirstUDA;

	alias RET = ReturnType!overload;
	alias PARAMS = ParameterTypeTuple!overload;
	alias default_values = ParameterDefaultValueTuple!overload;
	enum param_names = [ParameterIdentifierTuple!overload];
	enum erruda = findFirstUDA!(ErrorDisplayAttribute, overload);

	s_requestContext = RequestContext(req, res, determineLanguage!overload(req));
	PARAMS params;
	foreach (i, PT; PARAMS) {
		try {
			static if (param_names[i] == "_error" && ERROR.length == 1) params[i] = error[0];
			else static if (is(PT == InputStream)) params[i] = req.bodyReader;
			else static if (is(PT == HTTPServerRequest) || is(PT == HTTPRequest)) params[i] = req;
			else static if (is(PT == HTTPServerResponse) || is(PT == HTTPResponse)) params[i] = res;
			else static if (param_names[i].startsWith("_")) {
				if (auto pv = param_names[i][1 .. $] in req.params) params[i] = (*pv).convTo!PT;
				else static if (!is(default_values[i] == void)) params[i] = default_values[i];
				else enforceHTTP(false, HTTPStatus.badRequest, "Missing request parameter for "~param_names[i]);
			} else static if (is(PT == bool)) {
				params[i] = param_names[i] in req.form || param_names[i] in req.query;
			} else {
				static if (!is(default_values[i] == void)) {
					if (!readParamRec(req, params[i], param_names[i], false))
						params[i] = default_values[i];
				} else {
					readParamRec(req, params[i], param_names[i], true);
				}
			}
		} catch (Exception ex) {
			static if (erruda.found && ERROR.length == 0) {
				auto err = erruda.value.getError(ex, param_names[i]);
				handleRequest!(erruda.value.displayMethodName, erruda.value.displayMethod)(req, res, instance, settings, err);
			} else {
				throw new HTTPStatusException(HTTPStatus.badRequest, ex.msg);
			}
		}
	}

	try {
		static if (is(RET : InputStream)) {
			res.writeBody(__traits(getMember, instance, M)(params));
		} else {
			static assert(is(RET == void), "Only InputStream and void are supported as return types.");
			__traits(getMember, instance, M)(params);
		}
	} catch (Exception ex) {
		static if (erruda.found && ERROR.length == 0) {
			auto err = erruda.value.getError(ex, null);
			handleRequest!(erruda.value.displayMethodName, erruda.value.displayMethod)(req, res, instance, settings, err);
		} else throw ex;
	}
}

private bool readParamRec(T)(HTTPServerRequest req, ref T dst, string fieldname, bool required)
{
	import std.string;
	import std.traits;
	import std.typecons;
	import vibe.data.serialization;

	static if (isDynamicArray!T && !isSomeString!T) {
		alias EL = typeof(T.init[0]);
		size_t idx = 0;
		while (true) {
			EL el;
			if (!readParamRec(req, el, format("%s_%s", fieldname, idx), false))
				break;
			dst ~= el;
			idx++;
		}
	} else static if (isInstanceOf!(Nullable, T)) {
		typeof(dst.get()) el;
		if (readParamRec(req, el, fieldname, false))
			dst = el;
	} else static if (is(T == struct) && !isStringSerializable!T) {
		foreach (m; __traits(allMembers, T))
			if (!readParamRec(req, __traits(getMember, dst, m), fieldname~"_"~m, required))
				return false;
	} else if (auto pv = fieldname in req.form) dst = (*pv).convTo!T;
	else if (auto pv = fieldname in req.query) dst = (*pv).convTo!T;
	else if (required) throw new HTTPStatusException(HTTPStatus.badRequest, "Missing parameter "~fieldname);
	else return false;
	return true;
}

private T convTo(T)(string str)
{
	import std.conv;
	static if (is(typeof(T.fromString(str)) == T)) return T.fromString(str);
	else return str.to!T();
}
