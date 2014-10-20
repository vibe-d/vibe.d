/**
	Automatic REST interface and client code generation facilities.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/
module vibe.web.rest;

public import vibe.internal.meta.funcattr : before, after;
public import vibe.web.common;

import vibe.core.log;
import vibe.http.router : URLRouter;
import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequestDelegate;
import vibe.http.status : isSuccessCode;
import vibe.internal.meta.uda : UDATuple;
import vibe.inet.url;

import std.algorithm : startsWith, endsWith;
import std.typetuple : anySatisfy, Filter;

/**
	Registers a REST interface and connects it the the given instance.

	Each method of the given class instance is mapped to the corresponing HTTP
	verb. Property methods are mapped to GET/PUT and all other methods are
	mapped according to their prefix verb. If the method has no known prefix,
	POST is used.

	The following table lists the mappings from prefix verb to HTTP verb:

	<table>
		<tr><th>Prefix</th><th>HTTP verb</th></tr>
		<tr><td>get</td><td>GET</td></tr>
		<tr><td>query</td><td>GET</td></tr>
		<tr><td>set</td><td>PUT</td></tr>
		<tr><td>put</td><td>PUT</td></tr>
		<tr><td>update</td><td>PATCH</td></tr>
		<tr><td>patch</td><td>PATCH</td></tr>
		<tr><td>add</td><td>POST</td></tr>
		<tr><td>create</td><td>POST</td></tr>
		<tr><td>post</td><td>POST</td></tr>
	</table>

	If a method has its first parameter named 'id', it will be mapped to ':id/method' and
    'id' is expected to be part of the URL instead of a JSON request. Parameters with default
    values will be optional in the corresponding JSON request.

	Any interface that you return from a getter will be made available with the
	base url and its name appended.

	Params:
		router = The HTTP router on which the interface will be registered
		instance = Class instance to use for the REST mapping - Note that TImpl
			must either be an interface type, or a class which derives from a
			single interface
		url_prefix = Optional path prefix to use when registering the HTTP routes
		style = The naming convention to use for the translation of method names
			to HTTP paths

	See_Also:
		$(D RestInterfaceClient) class for a seamless way to access such a generated API

*/
void registerRestInterface(TImpl)(URLRouter router, TImpl instance, RestInterfaceSettings settings = null)
{
	import vibe.internal.meta.traits : baseInterface;
	import vibe.internal.meta.uda : findFirstUDA;
	import std.traits : MemberFunctionsTuple, ParameterIdentifierTuple,
		ParameterTypeTuple, ReturnType;

	if (!settings) settings = new RestInterfaceSettings;

	string url_prefix = settings.baseURL.path.toString();

	alias I = baseInterface!TImpl;

	enum uda = findFirstUDA!(RootPathAttribute, I);
	static if (uda.found) {
		static if (uda.value.data == "") {
			auto path = "/" ~ adjustMethodStyle(I.stringof, settings.methodStyle);
			url_prefix = concatURL(url_prefix, path);
		} else {
			url_prefix = concatURL(url_prefix, uda.value.data);
		}
	}

	void addRoute(HTTPMethod httpVerb, string url, HTTPServerRequestDelegate handler, string[] params)
	{
		import std.algorithm : filter, startsWith;
		import std.array : array;

		router.match(httpVerb, url, handler);
		logDiagnostic(
			"REST route: %s %s %s",
			httpVerb,
			url,
			params.filter!(p => !p.startsWith("_") && p != "id")().array()
		);
	}

	string strip(string name) {
		if (settings.stripTrailingUnderscore && name.endsWith("_"))
			return name[0 .. $-1];
		else return name;
	}

	foreach (method; __traits(allMembers, I)) {
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			enum meta = extractHTTPMethodAndName!overload();

			static if (meta.hadPathUDA) {
				string url = meta.url;
			}
			else {
				static if (__traits(identifier, overload) == "index") {
					pragma(msg, "Processing interface " ~ T.stringof ~
						": please use @path(\"/\") to define '/' path" ~
						" instead of 'index' method. Special behavior will be removed" ~
						" in the next release.");
				}

				string url = adjustMethodStyle(strip(meta.url), settings.methodStyle);
			}

			alias RT = ReturnType!overload;

			static if (is(RT == interface)) {
				// nested API
				static assert(
					ParameterTypeTuple!overload.length == 0,
					"Interfaces may only be returned from parameter-less functions!"
				);
				registerRestInterface!RT(
					router,
					__traits(getMember, instance, method)(),
					concatURL(url_prefix, url, true)
				);
			} else {
				// normal handler
				auto handler = jsonMethodHandler!(I, method, overload)(instance, settings);

				string[] params = [ ParameterIdentifierTuple!overload ];

				// legacy special case for :id, left for backwards-compatibility reasons
				if (params.length && params[0] == "id") {
					auto combined_url = concatURL(
						concatURL(url_prefix, ":id", true),
						url);
					addRoute(meta.method, combined_url, handler, params);
				} else {
					addRoute(meta.method, concatURL(url_prefix, url), handler, params);
				}
			}
		}
	}
}

/// ditto
void registerRestInterface(TImpl)(URLRouter router, TImpl instance, MethodStyle style)
{
	registerRestInterface(router, instance, "/", style);
}

/// ditto
void registerRestInterface(TImpl)(URLRouter router, TImpl instance, string url_prefix,
	MethodStyle style = MethodStyle.lowerUnderscored)
{
	auto settings = new RestInterfaceSettings;
	if (!url_prefix.startsWith("/")) url_prefix = "/"~url_prefix;
	settings.baseURL = URL("http://127.0.0.1"~url_prefix);
	settings.methodStyle = style;
	registerRestInterface(router, instance, settings);
}


/**
	This is a very limited example of REST interface features. Please refer to
	the "rest" project in the "examples" folder for a full overview.

	All details related to HTTP are inferred from the interface declaration.
*/
unittest
{
	interface IMyAPI
	{
		// GET /api/greeting
		@property string greeting();

		// PUT /api/greeting
		@property void greeting(string text);

		// POST /api/users
		@path("/users")
		void addNewUser(string name);

		// GET /api/users
		@property string[] users();

		// GET /api/:id/name
		string getName(int id);

		// GET /some_custom_json
		Json getSomeCustomJson();
	}

	// vibe.d takes care of all JSON encoding/decoding
	// and actual API implementation can work directly
	// with native types

	class API : IMyAPI
	{
		private {
			string m_greeting;
			string[] m_users;
		}

		@property string greeting() { return m_greeting; }
		@property void greeting(string text) { m_greeting = text; }

		void addNewUser(string name) { m_users ~= name; }

		@property string[] users() { return m_users; }

		string getName(int id) { return m_users[id]; }

		Json getSomeCustomJson()
		{
			Json ret = Json.emptyObject;
			ret["somefield"] = "Hello, World!";
			return ret;
		}
	}

	// actual usage, this is usually done in app.d module
	// constructor

	void static_this()
	{
		import vibe.http.server, vibe.http.router;

		auto router = new URLRouter();
		registerRestInterface(router, new API());
		listenHTTP(new HTTPServerSettings(), router);
	}
}


/**
	Implements the given interface by forwarding all public methods to a REST server.

	The server must talk the same protocol as registerRestInterface() generates. Be sure to set
	the matching method style for this. The RestInterfaceClient class will derive from the
	interface that is passed as a template argument. It can be used as a drop-in replacement
	of the real implementation of the API this way.
*/
class RestInterfaceClient(I) : I
{
	//pragma(msg, "imports for "~I.stringof~":");
	//pragma(msg, generateModuleImports!(I)());
	mixin(generateModuleImports!I());

	import vibe.inet.url : URL, PathEntry;
	import vibe.http.client : HTTPClientRequest;

	alias RequestFilter = void delegate(HTTPClientRequest req);

	private {
		URL m_baseURL;
		MethodStyle m_methodStyle;
		RequestFilter m_requestFilter;
		RestInterfaceSettings m_settings;
	}

	/**
		Creates a new REST client implementation of $(D I).
	*/
	this(RestInterfaceSettings settings)
	{
		import vibe.internal.meta.uda : findFirstUDA;

		m_settings = settings.dup;

		if (!m_settings.baseURL.path.absolute) {
			assert(m_settings.baseURL.path.empty, "Base URL path must be absolute.");
			m_settings.baseURL.path = Path("/");
		}

		URL url = settings.baseURL;
		enum uda = findFirstUDA!(RootPathAttribute, I);
		static if (uda.found) {
			static if (uda.value.data == "") {
				url.path = Path(concatURL(url.path.toString(), adjustMethodStyle(I.stringof, settings.methodStyle), true));
			} else {
				url.path = Path(concatURL(url.path.toString(), uda.value.data, true));
			}
		}

		m_baseURL = url;
		m_methodStyle = settings.methodStyle;

		string strip(string name) {
			if (settings.stripTrailingUnderscore && name.endsWith("_"))
				return name[0 .. $-1];
			else return name;
		}

		mixin (generateRestInterfaceSubInterfaceInstances!I());
	}

	/// ditto
	this(string base_url, MethodStyle style = MethodStyle.lowerUnderscored)
	{
		this(URL(base_url), style);
	}

	/// ditto
	this(URL base_url, MethodStyle style = MethodStyle.lowerUnderscored)
	{
		scope settings = new RestInterfaceSettings;
		settings.baseURL = base_url;
		settings.methodStyle = style;
		this(settings);
	}

	/**
		An optional request filter that allows to modify each request before it is made.
	*/
	final @property RequestFilter requestFilter()
	{
		return m_requestFilter;
	}

	/// ditto
	final @property void requestFilter(RequestFilter v) {
		m_requestFilter = v;
		mixin (generateRestInterfaceSubInterfaceRequestFilter!I());
	}

	//pragma(msg, "subinterfaces:");
	//pragma(msg, generateRestInterfaceSubInterfaces!(I)());
	mixin (generateRestInterfaceSubInterfaces!I());

	//pragma(msg, "restinterface:");
	//pragma(msg, generateRestInterfaceMethods!(I)());
	mixin (generateRestInterfaceMethods!I());

	protected {
		import vibe.data.json : Json;
		import vibe.textfilter.urlencode;

		Json request(string verb, string name, Json params, bool[string] param_is_json) const
		{
			import vibe.http.client : HTTPClientRequest, HTTPClientResponse,
				requestHTTP;
			import vibe.http.common : HTTPStatusException, HTTPStatus,
				httpMethodFromString, httpStatusText;
			import vibe.inet.url : Path;
			import std.array : appender;

			URL url = m_baseURL;

			if (name.length) url ~= Path(name);

			if ((verb == "GET" || verb == "HEAD") && params.length > 0) {
				auto query = appender!string();
				bool first = true;

				foreach (string pname, p; params) {
					if (!first) {
						query.put('&');
					}
					else {
						first = false;
					}
					filterURLEncode(query, pname);
					query.put('=');
					filterURLEncode(query, param_is_json[pname] ? p.toString() : toRestString(p));
				}

				url.queryString = query.data();
			}

			Json ret;

			auto reqdg = (scope HTTPClientRequest req) {
				req.method = httpMethodFromString(verb);

				if (m_requestFilter) {
					m_requestFilter(req);
				}

				if (verb != "GET" && verb != "HEAD") {
					req.writeJsonBody(params);
				}
			};

			auto resdg = (scope HTTPClientResponse res) {
				ret = res.readJson();

				logDebug(
					"REST call: %s %s -> %d, %s",
					verb,
					url.toString(),
					res.statusCode,
					ret.toString()
				);

				if (!isSuccessCode(cast(HTTPStatus)res.statusCode))
					throw new RestException(res.statusCode, ret);
			};

			requestHTTP(url, reqdg, resdg);

			return ret;
		}
	}

	private string _stripName(string name)
	{
		if (m_settings.stripTrailingUnderscore && name.endsWith("_"))
			return name[0 .. $-1];
		else return name;
	}
}

///
unittest
{
	interface IMyApi
	{
		// GET /status
		string getStatus();

		// GET /greeting
		@property string greeting();
		// PUT /greeting
		@property void greeting(string text);

		// POST /new_user
		void addNewUser(string name);
		// GET /users
		@property string[] users();
		// GET /:id/name
		string getName(int id);

		Json getSomeCustomJson();
	}

	void application()
	{
		auto api = new RestInterfaceClient!IMyApi("http://127.0.0.1/api/");

		logInfo("Status: %s", api.getStatus());
		api.greeting = "Hello, World!";
		logInfo("Greeting message: %s", api.greeting);
		api.addNewUser("Peter");
		api.addNewUser("Igor");
		logInfo("Users: %s", api.users);
		logInfo("First user name: %s", api.getName(0));
	}
}


/**
	Encapsulates settings used to customize the generated REST interface.
*/
class RestInterfaceSettings {
	/** The public URL below which the REST interface is registered.
	*/
	URL baseURL;

	/** Naming convention used for the generated URLs.
	*/
	MethodStyle methodStyle = MethodStyle.lowerUnderscored;

	/** Ignores a trailing underscore in method and function names.

		With this setting set to $(D true), it's possible to use names in the
		REST interface that are reserved words in D.
	*/
	bool stripTrailingUnderscore = true;

	@property RestInterfaceSettings dup()
	const {
		auto ret = new RestInterfaceSettings;
		ret.baseURL = this.baseURL;
		ret.methodStyle = this.methodStyle;
		ret.stripTrailingUnderscore = this.stripTrailingUnderscore;
		return ret;
	}
}


/// private
private HTTPServerRequestDelegate jsonMethodHandler(T, string method, alias Func)(T inst, RestInterfaceSettings settings)
{
	import std.traits : ParameterTypeTuple, ReturnType, fullyQualifiedName,
		ParameterDefaultValueTuple, ParameterIdentifierTuple;
	import std.string : format;
	import std.algorithm : startsWith;

	import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
	import vibe.http.common : HTTPStatusException, HTTPStatus, enforceBadRequest;
	import vibe.utils.string : sanitizeUTF8;
	import vibe.internal.meta.funcattr : IsAttributedParameter;

	alias PT = ParameterTypeTuple!Func;
	alias RT = ReturnType!Func;
	alias ParamDefaults = ParameterDefaultValueTuple!Func;
	enum ParamNames = [ ParameterIdentifierTuple!Func ];
	enum FuncId = (fullyQualifiedName!T~ "." ~ __traits(identifier, Func));

	void handler(HTTPServerRequest req, HTTPServerResponse res)
	{
		PT params;

		string strip(string name) {
			if (settings.stripTrailingUnderscore && name.endsWith("_"))
				return name[0 .. $-1];
			else return name;
		}

		// Check if there is no orphan UDATuple (e.g. typo while writing the name of the parameter).
		static if (UDATuple!(WebParamAttribute, Func).length) {
			foreach (i, uda; UDATuple!(WebParamAttribute, Func)) {
				// Note: static foreach gets unrolled, generating multiple nested sub-scope.
				// The spec / DMD doesn't like when you have the same symbol in those,
				// leading to wrong codegen / wrong template being reused.
				// That's why those templates need different names.
				mixin(GenOrphan!(i).Decl);
				// template CmpOrphan(string name) { enum CmpOrphan = (uda.identifier == name); }
				static assert(anySatisfy!(mixin(GenOrphan!(i).Name), ParameterIdentifierTuple!Func),
				              format("No parameter '%s' on %s (referenced by attribute @from%s)",
				       uda.identifier, FuncId, uda.origin));
			}
		}

		foreach (i, P; PT) {
			static assert (
				ParamNames[i].length,
				format(
					"Parameter %s of %s has no name",
					i.stringof,
					method
				)
			);

			// will be re-written by UDA function anyway
			static if (!IsAttributedParameter!(Func, ParamNames[i])) {
				// Comparison template for anySatisfy
				//template Cmp(WebParamAttribute attr) { enum Cmp = (attr.identifier == ParamNames[i]); }
				mixin(GenCmp!("Loop", i, ParamNames[i]).Decl);
				// Find origin of parameter
				static if (i == 0 && ParamNames[i] == "id") {
					// legacy special case for :id, backwards-compatibility
					logDebug("id %s", req.params["id"]);
					params[i] = fromRestString!P(req.params["id"]);
				} else static if (anySatisfy!(mixin(GenCmp!("Loop", i, ParamNames[i]).Name), UDATuple!(WebParamAttribute, Func))) {
					// User anotated the origin of this parameter.
					enum PARAM = Filter!(mixin(GenCmp!("Loop", i, ParamNames[i]).Name), UDATuple!(WebParamAttribute, Func));
					static assert(PARAM.length == 1, "Parameter '"~ParamNames[i]~"' of "
					~FuncId~" has multiple origin (@from* attributes).");
					// @fromHeader.
					static if (PARAM[0].origin == WebParamAttribute.Origin.Header) {
						// If it has no default value
						static if (is (ParamDefaults[i] == void)) {
							auto fld = enforceBadRequest(PARAM[0].field in req.headers,
							format("Expected field '%s' in header", PARAM[0].field));
						} else {
							auto fld = PARAM[0].field in req.headers;
								if (fld is null) {
								params[i] = ParamDefaults[i];
								logDebug("No header param %s, using default value", PARAM[0].identifier);
								continue;
							}
						}
						logDebug("Header param: %s <- %s", PARAM[0].identifier, *fld);
						params[i] = fromRestString!P(*fld);
					} else static if (PARAM[0].origin == WebParamAttribute.Origin.Query) {
						static assert(0, "@fromQuery is not yet supported");
					} else static if (PARAM[0].origin == WebParamAttribute.Origin.Body) {
						static assert(0, "@fromBody is not yet supported");
					} else static assert (false, "Internal error: Origin "~PARAM[0].origin~" is not implemented.");
				} else static if (ParamNames[i].startsWith("_")) {
					// URL parameter
					static if (ParamNames[i] != "_dummy") {
						enforceBadRequest(
							ParamNames[i][1 .. $] in req.params,
							format("req.param[%s] was not set!", ParamNames[i][1 .. $])
						);
						logDebug("param %s %s", ParamNames[i], req.params[ParamNames[i][1 .. $]]);
						params[i] = fromRestString!P(req.params[ParamNames[i][1 .. $]]);
					}
				} else {
					// normal parameter
					alias DefVal = ParamDefaults[i];
					auto pname = strip(ParamNames[i]);

					if (req.method == HTTPMethod.GET) {
						logDebug("query %s of %s", pname, req.query);

						static if (is (DefVal == void)) {
							enforceBadRequest(
								pname in req.query,
								format("Missing query parameter '%s'", pname)
							);
						} else {
							if (pname !in req.query) {
								params[i] = DefVal;
								continue;
							}
						}

						params[i] = fromRestString!P(req.query[pname]);
					} else {
						logDebug("%s %s", method, pname);

						enforceBadRequest(
							req.contentType == "application/json",
							"The Content-Type header needs to be set to application/json."
						);
						enforceBadRequest(
							req.json.type != Json.Type.Undefined,
							"The request body does not contain a valid JSON value."
						);
						enforceBadRequest(
							req.json.type == Json.Type.Object,
							"The request body must contain a JSON object with an entry for each parameter."
						);

						static if (is(DefVal == void)) {
							enforceBadRequest(
								req.json[pname].type != Json.Type.Undefined,
								format("Missing parameter %s", pname)
							);
						} else {
							if (req.json[pname].type == Json.Type.Undefined) {
								params[i] = DefVal;
								continue;
							}
						}

						params[i] = deserializeJson!P(req.json[pname]);
					}
				}
			}
		}

		try {
			import vibe.internal.meta.funcattr;

			auto handler = createAttributedFunction!Func(req, res);

			static if (is(RT == void)) {
				handler(&__traits(getMember, inst, method), params);
				res.writeJsonBody(Json.emptyObject);
			} else {
				auto ret = handler(&__traits(getMember, inst, method), params);
				res.writeJsonBody(ret);
			}
		} catch (HTTPStatusException e) {
			if (res.headerWritten) logDebug("Response already started when a HTTPStatusException was thrown. Client will not receive the proper error code (%s)!", e.status);
			else res.writeJsonBody([ "statusMessage": e.msg ], e.status);
		} catch (Exception e) {
			// TODO: better error description!
			logDebug("REST handler exception: %s", e.toString());
			if (res.headerWritten) logDebug("Response already started. Client will not receive an error code!");
			else res.writeJsonBody(
				[ "statusMessage": e.msg, "statusDebugMessage": sanitizeUTF8(cast(ubyte[])e.toString()) ],
				HTTPStatus.internalServerError
			);
		}
	}

	return &handler;
}

/// private
private string generateRestInterfaceSubInterfaces(I)()
{
	if (!__ctfe)
		assert(false);

	import std.traits : MemberFunctionsTuple, FunctionTypeOf,
		ReturnType, ParameterTypeTuple, fullyQualifiedName;
	import std.algorithm : canFind;
	import std.string : format;

	string ret;
	string[] tps; // list of already processed interface types

	foreach (method; __traits(allMembers, I)) {
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			alias FT = FunctionTypeOf!overload;
			alias PTT = ParameterTypeTuple!FT;
			alias RT = ReturnType!FT;

			static if (is(RT == interface)) {
				static assert (
					PTT.length == 0,
					"Interface getters may not have parameters."
				);

				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof ~ "Impl";
					ret ~= format(
						q{
							alias RestInterfaceClient!(%s) %s;
						},
						fullyQualifiedName!RT,
						implname
					);
					ret ~= format(
						q{
							private %s m_%s;
						},
						implname,
						implname
					);
					ret ~= "\n";
				}
			}
		}
	}
	return ret;
}

/// private
private string generateRestInterfaceSubInterfaceInstances(I)()
{
	if (!__ctfe)
		assert(false);

	import std.traits : MemberFunctionsTuple, FunctionTypeOf,
		ReturnType, ParameterTypeTuple;
	import std.string : format;
	import std.algorithm : canFind;

	string ret;
	string[] tps; // list of of already processed interface types

	foreach (method; __traits(allMembers, I)) {
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			alias FT = FunctionTypeOf!overload;
			alias PTT = ParameterTypeTuple!FT;
			alias RT = ReturnType!FT;

			static if (is(RT == interface)) {
				static assert (
					PTT.length == 0,
					"Interface getters may not have parameters."
				);

				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof ~ "Impl";

					enum meta = extractHTTPMethodAndName!overload();

					ret ~= format(
						q{
							auto settings_%1$s = m_settings.dup;
							settings_%1$s.baseURL.path = m_baseURL.path ~
								(%3$s ? "%2$s/" : adjustMethodStyle(strip("%2$s"), m_methodStyle) ~ "/");
							m_%1$s = new %1$s(settings_%1$s);
						},
						implname, meta.url, meta.hadPathUDA
					);
					ret ~= "\n";
				}
			}
		}
	}

	return ret;
}

/// private
private string generateRestInterfaceSubInterfaceRequestFilter(I)()
{
	if (!__ctfe)
		assert(false);

	import std.traits : MemberFunctionsTuple, FunctionTypeOf,
		ReturnType, ParameterTypeTuple;
	import std.string : format;
	import std.algorithm : canFind;

	string ret;
	string[] tps; // list of already processed interface types

	foreach (method; __traits(allMembers, I)) {
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			alias FT = FunctionTypeOf!overload;
			alias PTT = ParameterTypeTuple!FT;
			alias RT = ReturnType!FT;

			static if (is(RT == interface)) {
				static assert (
					PTT.length == 0,
					"Interface getters may not have parameters."
				);

				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof ~ "Impl";

					ret ~= format(
						q{
							m_%s.requestFilter = m_requestFilter;
						},
						implname
					);
					ret ~= "\n";
				}
			}
		}
	}
	return ret;
}

/// private
private string generateRestInterfaceMethods(I)()
{
	if (!__ctfe)
		assert(false);

	import std.traits : MemberFunctionsTuple, FunctionTypeOf,
		ReturnType, ParameterTypeTuple, ParameterIdentifierTuple;
	import std.string : format;
	import std.algorithm : canFind, startsWith;
	import std.array : split;

	import vibe.internal.meta.codegen : cloneFunction;
	import vibe.internal.meta.funcattr : IsAttributedParameter;
	import vibe.http.server : httpMethodString;

	string ret;

	foreach (method; __traits(allMembers, I)) {
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			alias FT = FunctionTypeOf!overload;
			alias RT = ReturnType!FT;
			alias PTT = ParameterTypeTuple!overload;
			alias ParamNames = ParameterIdentifierTuple!overload;

			enum meta = extractHTTPMethodAndName!overload();

			// NB: block formatting is coded in dependency order, not in 1-to-1 code flow order

			static if (is(RT == interface)) {
				ret ~= format(
					q{
						override %s {
							return m_%sImpl;
						}
					},
					cloneFunction!overload,
					RT.stringof
				);
			} else {
				string param_handling_str;
				string url_prefix = `""`;

				// Block 2
				foreach (i, PT; PTT){
					static assert (
						ParamNames[i].length,
						format(
							"Parameter %s of %s has no name.",
							 i,
							 method
						)
					);

					// legacy :id special case, left for backwards-compatibility reasons
					static if (i == 0 && ParamNames[0] == "id") {
						static if (is(PT == Json))
							url_prefix = q{urlEncode(id.toString())~"/"};
						else
							url_prefix = q{urlEncode(toRestString(serializeToJson(id)))~"/"};
					}
					else static if (
						!ParamNames[i].startsWith("_") &&
						!IsAttributedParameter!(overload, ParamNames[i])
					) {
						// underscore parameters are sourced from the HTTPServerRequest.params map or from url itself
						param_handling_str ~= format(
							q{
								jparams__[_stripName("%s")] = serializeToJson(%s);
								jparamsj__[_stripName("%s")] = %s;
							},
							ParamNames[i],
							ParamNames[i],
							ParamNames[i],
							is(PT == Json) ? "true" : "false"
						);
					}
				}

				// Block 3
				string request_str;

				static if (!meta.hadPathUDA) {
					request_str = format(
						q{
							if (m_settings.stripTrailingUnderscore && url__.endsWith("_"))
								url__ = url__[0 .. $-1];
							url__ = %s ~ adjustMethodStyle(url__, m_methodStyle);
						},
						url_prefix
					);
				} else {
					auto parts = meta.url.split("/");
					request_str ~= `url__ = ` ~ url_prefix;
					foreach (i, p; parts) {
						if (i > 0) {
							request_str ~= `~ "/"`;
						}
						bool match = false;
						if (p.startsWith(":")) {
							foreach (pn; ParamNames) {
								if (pn.startsWith("_") && p[1 .. $] == pn[1 .. $]) {
									request_str ~= format(
										q{ ~ urlEncode(toRestString(serializeToJson(%s)))},
										pn
									);
									match = true;
									break;
								}
							}
						}

						if (!match) {
							request_str ~= `~ "` ~ p ~ `"`;
						}
					}

					request_str ~= ";\n";
				}

				request_str ~= format(
					q{
						auto jret__ = request("%s", url__ , jparams__, jparamsj__);
					},
					httpMethodString(meta.method)
				);

				static if (!is(ReturnType!overload == void)) {
					request_str ~= q{
						typeof(return) ret__;
						deserializeJson(ret__, jret__);
						return ret__;
					};
				}

				// Block 1
				ret ~= format(
					q{
						override %s {
							Json jparams__ = Json.emptyObject;
							bool[string] jparamsj__;
							string url__ = "%s";
							%s
								%s
						}
					},
					cloneFunction!overload,
					meta.url,
					param_handling_str,
					request_str
				);
			}
		}
	}

	return ret;
}

private {
	import vibe.data.json;
	import std.conv : to;

	string toRestString(Json value)
	{
		switch( value.type ){
			default: return value.toString();
			case Json.Type.Bool: return value.get!bool ? "true" : "false";
			case Json.Type.Int: return to!string(value.get!long);
			case Json.Type.Float: return to!string(value.get!double);
			case Json.Type.String: return value.get!string;
		}
	}

	T fromRestString(T)(string value)
	{
		import std.traits;
		import std.conv : ConvException;
		import vibe.web.common : HTTPStatusException, HTTPStatus;
		try {
			static if (isInstanceOf!(Nullable, T)) return T(fromRestString!(typeof(T.init.get()))(value));
			else static if( is(T == bool) ) return value == "true";
			else static if( is(T : int) ) return to!T(value);
			else static if( is(T : double) ) return to!T(value); // FIXME: formattedWrite(dst, "%.16g", json.get!double);
			else static if( is(T : string) ) return value;
			else static if( __traits(compiles, T.fromISOExtString("hello")) ) return T.fromISOExtString(value);
			else static if( __traits(compiles, T.fromString("hello")) ) return T.fromString(value);
			else return deserializeJson!T(parseJson(value));
		} catch(ConvException e) {
			throw new HTTPStatusException(HTTPStatus.badRequest, e.msg);
		}
	}
}

private string generateModuleImports(I)()
{
	if( !__ctfe )
		assert(false);

	import vibe.internal.meta.codegen : getRequiredImports;
	import std.algorithm : map;
	import std.array : join;

	auto modules = getRequiredImports!I();
	return join(map!(a => "static import " ~ a ~ ";")(modules), "\n");
}

version(unittest)
{
	private struct Aggregate { }
	private interface Interface
	{
		Aggregate[] foo();
	}
}

unittest
{
	enum imports = generateModuleImports!Interface;
	static assert(imports == "static import vibe.web.rest;");
}


// Workarounds @@DMD:9748@@, and maybe more
private template GenCmp(string name, int id, string cmpTo) {
	import std.string : format;
	import std.conv : to;
	enum Decl = q{
		template %1$s(alias uda) {
			enum %1$s = (uda.identifier == "%2$s");
		}
	}.format(Name, cmpTo);
	enum Name = name~to!string(id);
}

// Ditto
private template GenOrphan(int id) {
    import std.string : format;
    import std.conv : to;
    enum Decl = q{
        template %1$s(string name) {
            enum %1$s = (uda.identifier == name);
        }
    }.format(Name);
    enum Name = "OrphanCheck"~to!string(id);
}
