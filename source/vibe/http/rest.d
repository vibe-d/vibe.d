/**
	Automatic REST interface and client code generation facilities.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/
module vibe.http.rest;

public import vibe.internal.meta.funcattr : before, after;

import vibe.core.log;
import vibe.http.router : URLRouter;
import vibe.http.common : HTTPMethod;
import vibe.http.server : HTTPServerRequestDelegate;

import std.array : startsWith, endsWith;

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
	
		RestInterfaceClient class for a seamless way to acces such a generated API

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
	enum uda = findFirstUDA!(RootPath, I);

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
			auto path = uda.value.data;
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

		version (none) {
			// PUT /api/greeting
			@property void greeting(string text);
		}

		// POST /api/users
		@path("/users")
		void addNewUser(string name);

		// GET /api/users
		@property string[] users();

		// GET /api/:id/name
		string getName(int id);
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
		
		@property string greeting()
		{
			return m_greeting;
		}

		version(none) {		
			@property void greeting(string text)
			{
				m_greeting = text;
			}
		}

		void addNewUser(string name)
		{
			m_users ~= name;
		}

		@property string[] users()
		{
			return m_users;
		}

		string getName(int id)
		{
			return m_users[id];
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
#line 1 "module imports"
	mixin(generateModuleImports!I());
#line 255

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
		enum uda = findFirstUDA!(RootPath, I);
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

#line 1 "subinterface instances"
		mixin (generateRestInterfaceSubInterfaceInstances!I());
#line 305
	}
	
	/**
		An optional request filter that allows to modify each request before it is made.
	*/
	@property RequestFilter requestFilter()
	{
		return m_requestFilter;
	}

	/// ditto
	@property void requestFilter(RequestFilter v) {
		m_requestFilter = v;
#line 1 "request filter"		
		mixin (generateRestInterfaceSubInterfaceRequestFilter!I());
#line 321
	}
	
	//pragma(msg, "subinterfaces:");
	//pragma(msg, generateRestInterfaceSubInterfaces!(I)());
#line 1 "subinterfaces"
	mixin (generateRestInterfaceSubInterfaces!I());
	
	//pragma(msg, "restinterface:");
	//pragma(msg, generateRestInterfaceMethods!(I)());
#line 1 "restinterface"
	mixin (generateRestInterfaceMethods!I());
#line 333 "source/vibe/http/rest.d"

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
			import std.string : appender;

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

				if (res.statusCode != HTTPStatus.OK) {
					if (ret.type == Json.Type.Object && ret.statusMessage.type == Json.Type.String) {
						throw new HTTPStatusException(res.statusCode, ret.statusMessage.get!string);
					}
					else {
						throw new HTTPStatusException(res.statusCode, httpStatusText(res.statusCode));
					}
				}
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
		version(none) {
			// PUT /greeting
			@property void greeting(string text);
		}
		
		// POST /new_user
		void addNewUser(string name);
		// GET /users
		@property string[] users();
		// GET /:id/name
		string getName(int id);
	}

	void application()
	{
		auto api = new RestInterfaceClient!IMyApi("http://127.0.0.1/api/");

		logInfo("Status: %s", api.getStatus());
		version(none)
			api.greeting = "Hello, World!";
		logInfo("Greeting message: %s", api.greeting);
		api.addNewUser("Peter");
		api.addNewUser("Igor");
		logInfo("Users: %s", api.users);
	}
}

/**
	Adjusts the naming convention for a given function name to the specified style.

	The input name is assumed to be in lowerCamelCase (D-style) or PascalCase. Acronyms
	(e.g. "HTML") should be written all caps
*/
string adjustMethodStyle(string name, MethodStyle style)
{
	if (!name.length) {
		return "";
	}

	import std.uni;

	final switch(style) {
		case MethodStyle.unaltered:
			return name;
		case MethodStyle.camelCase:
			size_t i = 0;
			foreach (idx, dchar ch; name) {
				if (isUpper(ch)) {
					i = idx;
				}
				else break;
			}
			if (i == 0) {
				std.utf.decode(name, i);
				return std.string.toLower(name[0 .. i]) ~ name[i .. $];
			} else {
				std.utf.decode(name, i);
				if (i < name.length) {
					return std.string.toLower(name[0 .. i-1]) ~ name[i-1 .. $];
				}
				else {
					return std.string.toLower(name);
				}
			}
		case MethodStyle.pascalCase:
			size_t idx = 0;
			std.utf.decode(name, idx);
			return std.string.toUpper(name[0 .. idx]) ~ name[idx .. $];
		case MethodStyle.lowerCase:
			return std.string.toLower(name);
		case MethodStyle.upperCase:
			return std.string.toUpper(name);
		case MethodStyle.lowerUnderscored:
		case MethodStyle.upperUnderscored:
			string ret;
			size_t start = 0, i = 0;
			while (i < name.length) {
				// skip acronyms
				while (i < name.length && (i+1 >= name.length || (name[i+1] >= 'A' && name[i+1] <= 'Z'))) {
					std.utf.decode(name, i);
				}

				// skip the main (lowercase) part of a word
				while (i < name.length && !(name[i] >= 'A' && name[i] <= 'Z')) {
					std.utf.decode(name, i);
				}

				// add a single word
				if( ret.length > 0 ) {
					ret ~= "_";
				}
				ret ~= name[start .. i];

				// quick skip the capital and remember the start of the next word
				start = i;
				if (i < name.length) {
					std.utf.decode(name, i);
				}
			}
			if (i < name.length) {
				ret ~= "_" ~ name[start .. $];
			}
			return style == MethodStyle.lowerUnderscored ? 
				std.string.toLower(ret) : std.string.toUpper(ret);
	}
}

unittest
{
	assert(adjustMethodStyle("methodNameTest", MethodStyle.unaltered) == "methodNameTest");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.camelCase) == "methodNameTest");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.pascalCase) == "MethodNameTest");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.lowerCase) == "methodnametest");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.upperCase) == "METHODNAMETEST");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.lowerUnderscored) == "method_name_test");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.upperUnderscored) == "METHOD_NAME_TEST");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.unaltered) == "MethodNameTest");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.camelCase) == "methodNameTest");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.pascalCase) == "MethodNameTest");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.lowerCase) == "methodnametest");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.upperCase) == "METHODNAMETEST");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.lowerUnderscored) == "method_name_test");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.upperUnderscored) == "METHOD_NAME_TEST");
	assert(adjustMethodStyle("Q", MethodStyle.lowerUnderscored) == "q");
	assert(adjustMethodStyle("getHTML", MethodStyle.lowerUnderscored) == "get_html");
	assert(adjustMethodStyle("getHTMLEntity", MethodStyle.lowerUnderscored) == "get_html_entity");
	assert(adjustMethodStyle("ID", MethodStyle.lowerUnderscored) == "id");
	assert(adjustMethodStyle("ID", MethodStyle.pascalCase) == "ID");
	assert(adjustMethodStyle("ID", MethodStyle.camelCase) == "id");
	assert(adjustMethodStyle("IDTest", MethodStyle.lowerUnderscored) == "id_test");
	assert(adjustMethodStyle("IDTest", MethodStyle.pascalCase) == "IDTest");
	assert(adjustMethodStyle("IDTest", MethodStyle.camelCase) == "idTest");
}

/**
	Determines the naming convention of an identifier.
*/
enum MethodStyle
{
	/// Special value for free-style conventions
	unaltered,
	/// camelCaseNaming
	camelCase,
	/// PascalCaseNaming
	pascalCase,
	/// lowercasenaming
	lowerCase,
	/// UPPERCASENAMING
	upperCase,
	/// lower_case_naming
	lowerUnderscored,
	/// UPPER_CASE_NAMING
	upperUnderscored,
	
	/// deprecated
	Unaltered = unaltered,
	/// deprecated
	CamelCase = camelCase,
	/// deprecated
	PascalCase = pascalCase,
	/// deprecated
	LowerCase = lowerCase,
	/// deprecated
	UpperCase = upperCase,
	/// deprecated
	LowerUnderscored = lowerUnderscored,
	/// deprecated
	UpperUnderscored = upperUnderscored,
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

// concatenates two URL parts avoiding any duplicate slashes
// in resulting URL. `trailing` defines of result URL must
// end with slash
private string concatURL(string prefix, string url, bool trailing = false)
{
	import std.algorithm : startsWith, endsWith;

	auto pre = prefix.endsWith("/");
	auto post = url.startsWith("/");

	if (!url.length) return trailing && !pre ? prefix ~ "/" : prefix;

	auto suffix = trailing && !url.endsWith("/") ? "/" : null;

	if (pre) {
		// "/" is ASCII, so can just slice
		if (post) return prefix ~ url[1 .. $] ~ suffix;
		else return prefix ~ url ~ suffix;
	} else {
		if (post) return prefix ~ url ~ suffix;
		else return prefix ~ "/" ~ url ~ suffix;
	}
}

unittest {
	assert(concatURL("/test/", "/it/", false) == "/test/it/");
	assert(concatURL("/test", "it/", false) == "/test/it/");
	assert(concatURL("/test", "it", false) == "/test/it");
	assert(concatURL("/test", "", false) == "/test");
	assert(concatURL("/test/", "", false) == "/test/");
	assert(concatURL("/test/", "/it/", true) == "/test/it/");
	assert(concatURL("/test", "it/", true) == "/test/it/");
	assert(concatURL("/test", "it", true) == "/test/it/");
	assert(concatURL("/test", "", true) == "/test/");
	assert(concatURL("/test/", "", true) == "/test/");
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
	static assert(imports == "static import vibe.http.rest;");
}

/**
	User Defined Attribute interface to force specific HTTP method in REST interface
	for function in question. Usual URL generation rules are still applied so if there
	are ny "get", "query" or similar prefixes, they are filtered out.

	Example:
	---
	interface IAPI
	{
		// Will be "POST /info" instead of default "GET /info"
		@method(HTTPMethod.POST) getInfo();
	}
	---	
 */
OverridenMethod method(HTTPMethod data)
{
	if (!__ctfe)
		assert(false);
	return OverridenMethod(data);
}

/// private
struct OverridenMethod
{
	HTTPMethod data;
	alias data this;
}

/**
	User Defined Attribute interface to force specific URL path n REST interface
	for function in question. Path attribute is relative though, not absolute.

	Example:
	---
	interface IAPI
	{
		@path("info2") getInfo();
	}
	
	// ...
	
	shared static this()
	{
		registerRestInterface!IAPI(new URLRouter(), new API(), "/root/");
		// now IAPI.getInfo is tied to "GET /root/info2"
	}
	---	
*/
OverridenPath path(string data)
{
	if (!__ctfe)
		assert(false);
	return OverridenPath(data);
}

/// private
struct OverridenPath
{
	string data;
	alias data this;
}

/**
	Uses given function symbol to determine what HTTP method and
	what URL path should be used to access it in REST API.

	Is designed for CTFE usage and will assert at run time.

	Returns:
		Tuple of three elements:
			* flag "was UDA used to override path"
			* HTTPMethod extracted
			* url path extracted
 */
private auto extractHTTPMethodAndName(alias Func)()
{   
	if (!__ctfe)
		assert(false);

	struct HandlerMeta
	{
		bool hadPathUDA;
		HTTPMethod method;
		string url;
	}

	import vibe.internal.meta.uda : findFirstUDA;
	import vibe.internal.meta.traits : isPropertySetter,
		isPropertyGetter;
	import std.algorithm : startsWith;
	import std.typecons : Nullable;
	
	immutable httpMethodPrefixes = [
		HTTPMethod.GET    : [ "get", "query" ],
		HTTPMethod.PUT    : [ "put", "set" ],
		HTTPMethod.PATCH  : [ "update", "patch" ],
		HTTPMethod.POST   : [ "add", "create", "post" ],
		HTTPMethod.DELETE : [ "remove", "erase", "delete" ],
	];
	
	string name = __traits(identifier, Func);
	alias typeof(&Func) T;

	Nullable!HTTPMethod udmethod;
	Nullable!string udurl;

	// Cases may conflict and are listed in order of priority

	// Workaround for Nullable incompetence
	enum uda1 = findFirstUDA!(vibe.http.rest.OverridenMethod, Func);
	enum uda2 = findFirstUDA!(vibe.http.rest.OverridenPath, Func);

	static if (uda1.found) {
		udmethod = uda1.value;
	}
	static if (uda2.found) {
		udurl = uda2.value;
	}

	// Everything is overriden, no further analysis needed
	if (!udmethod.isNull() && !udurl.isNull()) {
		return HandlerMeta(true, udmethod.get(), udurl.get());
	}
	
	// Anti-copy-paste delegate
	typeof(return) udaOverride( HTTPMethod method, string url ){
		return HandlerMeta(
			!udurl.isNull(),
			udmethod.isNull() ? method : udmethod.get(), 
			udurl.isNull() ? url : udurl.get()
		);
	}
	
	if (isPropertyGetter!T) {
		return udaOverride(HTTPMethod.GET, name);
	}
	else if(isPropertySetter!T) {
		return udaOverride(HTTPMethod.PUT, name);
	}
	else {
		foreach (method, prefixes; httpMethodPrefixes) {
			foreach (prefix; prefixes) {
				if (name.startsWith(prefix)) {
					string tmp = name[prefix.length..$];
					return udaOverride(method, tmp);
				}
			}
		}
		
		if (name == "index")
			return udaOverride(HTTPMethod.GET, "");
		else
			return udaOverride(HTTPMethod.POST, name);
	}
}

unittest
{
	interface Sample
	{
		string getInfo();
		string updateDescription();
		
		@method(HTTPMethod.DELETE)
		string putInfo();
		
		@path("matters")
		string getMattersnot();
		
		@path("compound/path") @method(HTTPMethod.POST)
		string mattersnot();
	}
	
	enum ret1 = extractHTTPMethodAndName!(Sample.getInfo);
	static assert (ret1.hadPathUDA == false);
	static assert (ret1.method == HTTPMethod.GET);
	static assert (ret1.url == "Info");
	enum ret2 = extractHTTPMethodAndName!(Sample.updateDescription);
	static assert (ret2.hadPathUDA == false);
	static assert (ret2.method == HTTPMethod.PATCH);
	static assert (ret2.url == "Description");
	enum ret3 = extractHTTPMethodAndName!(Sample.putInfo);
	static assert (ret3.hadPathUDA == false);
	static assert (ret3.method == HTTPMethod.DELETE);
	static assert (ret3.url == "Info");
	enum ret4 = extractHTTPMethodAndName!(Sample.getMattersnot);
	static assert (ret4.hadPathUDA == true);
	static assert (ret4.method == HTTPMethod.GET);
	static assert (ret4.url == "matters");
	enum ret5 = extractHTTPMethodAndName!(Sample.mattersnot);
	static assert (ret5.hadPathUDA == true);
	static assert (ret5.method == HTTPMethod.POST);
	static assert (ret5.url == "compound/path");
}

struct RootPath
{
	string data;
	alias data this;
}

/**
	UDA to define root URL prefix for annotated REST interface.
	Empty path means deducing prefix from interface type name (see also rootPathFromName)
 */
RootPath rootPath(string path)
{
	return RootPath(path);
}

///
unittest
{
	@rootPath("/oops")
	interface IAPI
	{
		int getFoo();
	}

	class API : IAPI
	{
		int getFoo()
		{
			return 42;
		}
	}

	auto router = new URLRouter();
	registerRestInterface(router, new API());
	auto routes= router.getAllRoutes();

	assert(routes[HTTPMethod.GET][0].pattern == "/oops/foo");
}

/**
	Convenience alias
 */
@property RootPath rootPathFromName()
{
	return RootPath("");
}

///
unittest
{
	@rootPathFromName
	interface IAPI
	{
		int getFoo();
	}

	class API : IAPI
	{
		int getFoo()
		{
			return 42;
		}
	}

	auto router = new URLRouter();
	registerRestInterface(router, new API());
	auto routes= router.getAllRoutes();

	assert(routes[HTTPMethod.GET][0].pattern == "/iapi/foo");
}
