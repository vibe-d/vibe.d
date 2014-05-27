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

import std.algorithm : startsWith, endsWith;

/**
	Registers a REST interface and connects it the the given instance.

	Each method is mapped to the corresponing HTTP verb. Property methods are mapped to GET/PUT and
	all other methods are mapped according to their prefix verb. If the method has no known prefix,
	POST is used. The following table lists the mappings from prefix verb to HTTP verb:

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
	
	Any interface that you return from a getter will be made available with the base url and its name appended.

	See_Also:
	
		RestInterfaceClient class for a seamless way to access such a generated API

*/
void registerRestInterface(TImpl)(URLRouter router, TImpl instance, string url_prefix,
                              MethodStyle style = MethodStyle.lowerUnderscored)
{
	import vibe.internal.meta.traits : baseInterface;	
	import std.traits : MemberFunctionsTuple, ParameterIdentifierTuple,
		ParameterTypeTuple, ReturnType;	

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

	alias I = baseInterface!TImpl;

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

				string url = adjustMethodStyle(meta.url, style);
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
				auto handler = jsonMethodHandler!(I, method, overload)(instance);

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
void registerRestInterface(TImpl)(URLRouter router, TImpl instance, MethodStyle style = MethodStyle.lowerUnderscored)
{
	// this shorter overload tries to deduce root path automatically

	import vibe.internal.meta.uda : findFirstUDA;
	import vibe.internal.meta.traits : baseInterface;

	alias I = baseInterface!TImpl;
	enum uda = findFirstUDA!(RootPathAttribute, I);

	static if (!uda.found)
		registerRestInterface!I(router, instance, "/", style);
	else
	{
		static if (uda.value.data == "")
		{
			auto path = "/" ~ adjustMethodStyle(I.stringof, style);
			registerRestInterface!I(router, instance, path, style);
		}
		else
		{
			registerRestInterface!I(
				router,
				instance,
				concatURL("/", uda.value.data),
				style
			);
		}
	}
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
	}
	
	/**
		Creates a new REST implementation of I 
	*/
	this (string base_url, MethodStyle style = MethodStyle.lowerUnderscored)
	{
		import vibe.internal.meta.uda : findFirstUDA;
		
		URL url;
		enum uda = findFirstUDA!(RootPathAttribute, I);
		static if (!uda.found) {
			url = URL.parse(base_url);
		}
		else
		{
			static if (uda.value.data == "") {
				url = URL.parse(
					concatURL(base_url, adjustMethodStyle(I.stringof, style), true)
				);
			}
			else {
				url = URL.parse(
					concatURL(base_url, uda.value.data, true)
				);
			}
		}

		this(url, style);
	}

	/// ditto
	this(URL base_url, MethodStyle style = MethodStyle.lowerUnderscored)
	{
		m_baseURL = base_url;
		m_methodStyle = style;

		mixin (generateRestInterfaceSubInterfaceInstances!I());
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

				if (res.statusCode != HTTPStatus.OK)
					throw new RestException(res.statusCode, ret);
			};

			requestHTTP(url, reqdg, resdg);
			
			return ret;
		}
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
	}
}


/// private
private HTTPServerRequestDelegate jsonMethodHandler(T, string method, alias Func)(T inst)
{
	import std.traits : ParameterTypeTuple, ReturnType,
		ParameterDefaultValueTuple, ParameterIdentifierTuple;	
	import std.string : format;
	import std.algorithm : startsWith;
	import std.exception : enforce;

	import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
	import vibe.http.common : HTTPStatusException, HTTPStatus;
	import vibe.utils.string : sanitizeUTF8;
	import vibe.internal.meta.funcattr : IsAttributedParameter;

	alias PT = ParameterTypeTuple!Func;
	alias RT = ReturnType!Func;
	alias ParamDefaults = ParameterDefaultValueTuple!Func;
	enum ParamNames = [ ParameterIdentifierTuple!Func ];
	
	void handler(HTTPServerRequest req, HTTPServerResponse res)
	{
		PT params;
		
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
				static if (i == 0 && ParamNames[i] == "id") {
					// legacy special case for :id, backwards-compatibility
					logDebug("id %s", req.params["id"]);
					params[i] = fromRestString!P(req.params["id"]);
				} else static if (ParamNames[i].startsWith("_")) {
					// URL parameter
					static if (ParamNames[i] != "_dummy") {
						enforce(
							ParamNames[i][1 .. $] in req.params,
							format("req.param[%s] was not set!", ParamNames[i][1 .. $])
						);
						logDebug("param %s %s", ParamNames[i], req.params[ParamNames[i][1 .. $]]);
						params[i] = fromRestString!P(req.params[ParamNames[i][1 .. $]]);
					}
				} else {
					// normal parameter
					alias DefVal = ParamDefaults[i];
					if (req.method == HTTPMethod.GET) {
						logDebug("query %s of %s" ,ParamNames[i], req.query);
						
						static if (is (DefVal == void)) {
							enforce(
								ParamNames[i] in req.query,
								format("Missing query parameter '%s'", ParamNames[i])
							);
						} else {
							if (ParamNames[i] !in req.query) {
								params[i] = DefVal;
								continue;
							}
						}

						params[i] = fromRestString!P(req.query[ParamNames[i]]);
					} else {
						logDebug("%s %s", method, ParamNames[i]);

						enforce(
							req.contentType == "application/json",
							"The Content-Type header needs to be set to application/json."
						);
						enforce(
							req.json.type != Json.Type.Undefined,
							"The request body does not contain a valid JSON value."
						);
						enforce(
							req.json.type == Json.Type.Object,
							"The request body must contain a JSON object with an entry for each parameter."
						);

						static if (is(DefVal == void)) {
							enforce(
								req.json[ParamNames[i]].type != Json.Type.Undefined,
								format("Missing parameter %s", ParamNames[i])
							);
						} else {
							if (req.json[ParamNames[i]].type == Json.Type.Undefined) {
								params[i] = DefVal;
								continue;
							}
						}

						params[i] = deserializeJson!P(req.json[ParamNames[i]]);
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
			res.writeJsonBody([ "statusMessage": e.msg ], e.status);
		} catch (Exception e) {
			// TODO: better error description!
			res.writeJsonBody(
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
							if (%s)
								m_%s = new %s(m_baseURL.toString() ~ PathEntry("%s").toString() ~ "/", m_methodStyle);
							else
								m_%s = new %s(m_baseURL.toString() ~ adjustMethodStyle(PathEntry("%s").toString() ~ "/", m_methodStyle), m_methodStyle);
						},
						meta.hadPathUDA,
						implname, implname, meta.url,
						implname, implname, meta.url
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
								jparams__["%s"] = serializeToJson(%s);
								jparamsj__["%s"] = %s;
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
							url__ = %s ~ adjustMethodStyle(url__, m_methodStyle);
						},
						url_prefix
					);
				} else {
					auto parts = meta.url.split("/");
					request_str ~= `url__ = ""`;
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
		static if( is(T == bool) ) return value == "true";
		else static if( is(T : int) ) return to!T(value);
		else static if( is(T : double) ) return to!T(value); // FIXME: formattedWrite(dst, "%.16g", json.get!double);
		else static if( is(T : string) ) return value;
		else static if( __traits(compiles, T.fromString("hello")) ) return T.fromString(value);
		else return deserializeJson!T(parseJson(value));
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

