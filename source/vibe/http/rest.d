/**
	Automatic REST interface and client code generation facilities.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/
module vibe.http.rest;

import vibe.http.restutil;

import vibe.core.log;
import vibe.data.json;
import vibe.http.client;
import vibe.http.router;
import vibe.inet.url;
import vibe.textfilter.urlencode;
import vibe.utils.string;

import std.algorithm : filter;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.traits;

/**
	Generates registers a REST interface and connects it the the given instance.

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

	A method named 'index' is mapped to the root URL (e.g. GET /api/). If a method has its first
	parameter named 'id', it will be mapped to ':id/method' and 'id' is expected to be part of the
	URL instead of a JSON request. Parameters with default values will be optional in the
	corresponding JSON request.
	
	Any interface that you return from a getter will be made available with the base url and its name appended.

	Examples:

		The following example makes MyApi available using HTTP requests. Valid requests are:

		<ul>
		  $(LI GET /api/status &rarr; "OK")
		  $(LI GET /api/greeting &rarr; "&lt;current greeting&gt;")
		  $(LI PUT /api/greeting &larr; {"text": "&lt;new text&gt;"})
		  $(LI POST /api/new_user &larr; {"name": "&lt;new user name&gt;"})
		  $(LI GET /api/users &rarr; ["&lt;user 1&gt;", "&lt;user 2&gt;"])
		  $(LI GET /api/ &rarr; ["&lt;user 1&gt;", "&lt;user 2&gt;"])
		  $(LI GET /api/:id/name &rarr; ["&lt;user name for id&gt;"])
		  $(LI GET /api/items/text &rarr; "Hello, World")
		  $(LI GET /api/items/:id/index &rarr; &lt;item index&gt;)
		</ul>
		---
		import vibe.d;
		
		interface IMyItemsApi {
			string getText();
			int getIndex(int id);
		}

		interface IMyApi {
			string getStatus();

			@property string greeting();
			@property void greeting(string text);

			void addNewUser(string name);
			@property string[] users();
			string[] index();
			string getName(int id);
			
			@property IMyItemsApi items();
		}
		
		class MyItemsApiImpl : IMyItemsApi {
			string getText() { return "Hello, World"; }
			int getIndex(int id) { return id; }
		}

		class MyApiImpl : IMyApi {
			private string m_greeting;
			private string[] m_users;
			private MyItemsApiImpl m_items;
			
			this() { m_items = new MyItemsApiImpl; }

			string getStatus() { return "OK"; }

			@property string greeting() { return m_greeting; }
			@property void greeting(string text) { m_greeting = text; }

			void addNewUser(string name) { m_users ~= name; }
			@property string[] users() { return m_users; }
			string[] index() { return m_users; }
			string getName(int id) { return m_users[id]; }
			
			@property MyItemsApiImpl items() { return m_items; }
		}

		static this()
		{
			auto routes = new UrlRouter;

			registerRestInterface(routes, new MyApiImpl, "/api/");

			listenHttp(new HttpServerSettings, routes);
		}
		---

	See_Also:
	
		RestInterfaceClient class for a seamless way to acces such a generated API
*/
void registerRestInterface(T)(UrlRouter router, T instance, string urlPrefix = "/",
                              MethodStyle style = MethodStyle.lowerUnderscored)
{
	void addRoute(HttpMethod httpVerb, string url, HttpServerRequestDelegate handler, string[] params)
	{
		router.addRoute(httpVerb, url, handler);
		logDebug("REST route: %s %s %s", httpVerb, url, params.filter!(p => !p.startsWith("_") && p != "id")().array());
	}       
	
	foreach( method; __traits(allMembers, T) ) {
		foreach( overload; MemberFunctionsTuple!(T, method) ) {
			alias ReturnType!overload RetType;
			string[] paramNames = [ParameterIdentifierTuple!overload];
			
			enum meta = extractHttpMethodAndName!(overload)();
			enum pathOverriden = meta[0];
			HttpMethod httpVerb = meta[1];
			static if (pathOverriden)
				string url = meta[2];
			else
				string url = adjustMethodStyle(meta[2], style);
			
			static if( is(RetType == interface) ) {
				static assert(ParameterTypeTuple!overload.length == 0, "Interfaces may only be returned from parameter-less functions!");
				registerRestInterface!RetType(router, __traits(getMember, instance, method)(), urlPrefix ~ url ~ "/");
			} else {
				auto handler = jsonMethodHandler!(T, method, overload)(instance);
				string id_supplement;
				size_t skip = 0;
				// legacy special case for :id, left for backwards-compatibility reasons
				if( paramNames.length && paramNames[0] == "id" ) {
					addRoute(httpVerb, urlPrefix ~ ":id/" ~ url, handler, paramNames);
					if( url.length == 0 )
						addRoute(httpVerb, urlPrefix ~ ":id", handler, paramNames);
				} else
					addRoute(httpVerb, urlPrefix ~ url, handler, paramNames);
			}
		}
	}
}

/**
	Implements the given interface by forwarding all public methods to a REST server.

	The server must talk the same protocol as registerRestInterface() generates. Be sure to set
	the matching method style for this. The RestInterfaceClient class will derive from the
	interface that is passed as a template argument. It can be used as a drop-in replacement
	of the real implementation of the API this way.

	Examples:
	
		An example client that accesses the API defined in the registerRestInterface() example:

		---
		import vibe.d;

		interface IMyApi {
			string getStatus();

			@property string greeting();
			@property void greeting(string text);
			
			void addNewUser(string name);
			@property string[] users();
			string[] index();
			string getName(int id);
		}

		static this()
		{
			auto api = new RestInterfaceClient!IMyApi("http://127.0.0.1/api/");

			logInfo("Status: %s", api.getStatus());
			api.greeting = "Hello, World!";
			logInfo("Greeting message: %s", api.greeting);
			api.addNewUser("Peter");
			api.addNewUser("Igor");
			logInfo("Users: %s", api.users);
		}
		---
*/
class RestInterfaceClient(I) : I
{
	//pragma(msg, "imports for "~I.stringof~":");
	//pragma(msg, generateModuleImports!(I)());
	mixin(generateModuleImports!I());
	
	alias void delegate(HttpClientRequest req) RequestFilter;
	private {
		Url m_baseUrl;
		MethodStyle m_methodStyle;
		RequestFilter m_requestFilter;
	}
	
	alias I BaseInterface;
	
	/** Creates a new REST implementation of I
	*/
	this(string baseUrl, MethodStyle style = MethodStyle.lowerUnderscored)
	{
		m_baseUrl = Url.parse(baseUrl);
		m_methodStyle = style;
		mixin(generateRestInterfaceSubInterfaceInstances!I());
	}
	/// ditto
	this(Url baseUrl, MethodStyle style = MethodStyle.lowerUnderscored)
	{
		m_baseUrl = baseUrl;
		m_methodStyle = style;
		mixin(generateRestInterfaceSubInterfaceInstances!I());
	}
	
	/** An optional request filter that allows to modify each request before it is made.
	*/
	@property RequestFilter requestFilter() { return m_requestFilter; }
	/// ditto
	@property void requestFilter(RequestFilter v) {
		m_requestFilter = v;
		mixin(generateRestInterfaceSubInterfaceRequestFilter!I());
	}
	
	//pragma(msg, generateRestInterfaceSubInterfaces!(I)());
#line 1 "subinterfaces"
	mixin(generateRestInterfaceSubInterfaces!I());
	
	//pragma(msg, "restinterface:");
	//pragma(msg, generateRestInterfaceMethods!(I)());
#line 1 "restinterface"
	mixin(generateRestInterfaceMethods!I());
	
#line 261 "source/vibe/http/rest.d"
	protected Json request(string verb, string name, Json params, bool[string] paramIsJson)
	const {
		Url url = m_baseUrl;
		if( name.length ) url ~= Path(name);
		else if( !url.path.endsWithSlash ){
			auto p = url.path;
			p.endsWithSlash = true;
			url.path = p;
		}
		
		if( (verb == "GET" || verb == "HEAD") && params.length > 0 ){
			auto queryString = appender!string();
			bool first = true;
			foreach( string pname, p; params ){
				if( !first ) queryString.put('&');
				else first = false;
				filterUrlEncode(queryString, pname);
				queryString.put('=');
				filterUrlEncode(queryString, paramIsJson[pname] ? p.toString() : toRestString(p));
			}
			url.queryString = queryString.data();
		}
		
		Json ret;

		requestHttp(url,
			(scope req){
				req.method = httpMethodFromString(verb);
				if( m_requestFilter ) m_requestFilter(req);
				if( verb != "GET" && verb != "HEAD" )
					req.writeJsonBody(params);
			},
			(scope res){
				ret = res.readJson();
				logDebug("REST call: %s %s -> %d, %s", verb, url.toString(), res.statusCode, ret.toString());
				if( res.statusCode != HttpStatus.OK ){
					if( ret.type == Json.Type.Object && ret.statusMessage.type == Json.Type.String )
						throw new HttpStatusException(res.statusCode, ret.statusMessage.get!string);
					else throw new HttpStatusException(res.statusCode, httpStatusText(res.statusCode));
				}
			}
		);
		
		return ret;
	}
}

unittest
{
	// checking that rest client actually instantiates
	interface TestAPI
	{	
		string getInfo();
		
		@method(HttpMethod.DELETE)
		double[] setSomething(int num);
		
		@path("/process/:param/:param2/please")
		void readOnly(string _param, string _param2);
	}
	
	auto api = new RestInterfaceClient!TestAPI("http://127.0.0.1");
	assert(api);
}

/**
	Adjusts the naming convention for a given function name to the specified style.

	The input name is assumed to be in lowerCamelCase (D-style) or PascalCase. Acronyms
	(e.g. "HTML") should be written all caps
*/
string adjustMethodStyle(string name, MethodStyle style)
{
	final switch(style){
		case MethodStyle.unaltered:
			return name;
		case MethodStyle.camelCase:
			return toLower(name[0 .. 1]) ~ name[1 .. $];
		case MethodStyle.pascalCase:
			return toUpper(name[0 .. 1]) ~ name[1 .. $];
		case MethodStyle.lowerCase:
			return toLower(name);
		case MethodStyle.upperCase:
			return toUpper(name);
		case MethodStyle.lowerUnderscored:
		case MethodStyle.upperUnderscored:
			string ret;
			size_t start = 0, i = 0;
			while( i <= name.length ){
				// skip acronyms
				while (i < name.length && (i+1 >= name.length || (name[i+1] >= 'A' && name[i+1] <= 'Z'))) i++;

				// skip the main (lowercase) part of a word
				while (i < name.length && !(name[i] >= 'A' && name[i] <= 'Z')) i++;

				// add a single word
				if( ret.length > 0 ) ret ~= "_";
				ret ~= name[start .. i];

				// quick skip the capital and remember the start of the next word
				start = i++;
			}
			if( i < name.length ) ret ~= "_" ~ name[start .. $];
			return style == MethodStyle.lowerUnderscored ? toLower(ret) : toUpper(ret);
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
}


/**
	Determines the naming convention of an identifier.
*/
enum MethodStyle {
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
private HttpServerRequestDelegate jsonMethodHandler(T, string method, alias Func)(T inst)
{
	alias ParameterTypeTuple!Func ParameterTypes;
	alias ReturnType!Func RetType;
	alias ParameterDefaultValueTuple!Func DefaultValues;
	enum paramNames = [ParameterIdentifierTuple!Func];
	
	void handler(HttpServerRequest req, HttpServerResponse res)
	{
		ParameterTypes params;
		
		foreach( i, P; ParameterTypes ){
			static assert(paramNames[i].length, "Parameter "~i.stringof~" of "~method~" has no name");
			static if( i == 0 && paramNames[i] == "id" ){
				logDebug("id %s", req.params["id"]);
				params[i] = fromRestString!P(req.params["id"]);
			} else static if( paramNames[i].startsWith("_") ){
				static if( paramNames[i] != "_dummy"){
					enforce(paramNames[i][1 .. $] in req.params, "req.param[\""~paramNames[i][1 .. $]~"\"] was not set!");
					logDebug("param %s %s", paramNames[i], req.params[paramNames[i][1 .. $]]);
					params[i] = fromRestString!P(req.params[paramNames[i][1 .. $]]);
				}
			} else {
				alias DefaultValues[i] DefVal;
				if( req.method == HttpMethod.GET ){
					logDebug("query %s of %s" ,paramNames[i], req.query);
					static if( is(DefVal == void) ){
						enforce(paramNames[i] in req.query, "Missing query parameter '"~paramNames[i]~"'");
					} else {
						if( paramNames[i] !in req.query ){
							params[i] = DefVal;
							continue;
						}
					}
					params[i] = fromRestString!P(req.query[paramNames[i]]);
				} else {
					logDebug("%s %s", method, paramNames[i]);
					enforce(req.contentType == "application/json", "The Content-Type header needs to be set to application/json.");
					enforce(req.json.type != Json.Type.Undefined, "The request body does not contain a valid JSON value.");
					enforce(req.json.type == Json.Type.Object, "The request body must contain a JSON object with an entry for each parameter.");
					static if( is(DefVal == void) ){
						enforce(req.json[paramNames[i]].type != Json.Type.Undefined, "Missing parameter "~paramNames[i]~".");
					} else {
						if( req.json[paramNames[i]].type == Json.Type.Undefined ){
							params[i] = DefVal;
							continue;
						}
					}
					params[i] = deserializeJson!P(req.json[paramNames[i]]);
				}
			}
		}
		
		try {
			static if( is(RetType == void) ){
				__traits(getMember, inst, method)(params);
				res.writeJsonBody(Json.EmptyObject);
			} else {
				auto ret = __traits(getMember, inst, method)(params);
				res.writeJsonBody(serializeToJson(ret));
			}
		} catch( HttpStatusException e) {
			res.writeJsonBody(["statusMessage": e.msg], e.status);
		} catch( Exception e ){
			// TODO: better error description!
			res.writeJsonBody(["statusMessage": e.msg, "statusDebugMessage": sanitizeUTF8(cast(ubyte[])e.toString())], HttpStatus.InternalServerError);
		}
	}
	
	return &handler;
}

/// For a given interface, finds all user-defined types
/// used in its method signatures and generates list of
/// static imports with modules they originate from.
private string generateModuleImports(I)()
	if( is(I == interface) )
{
	if( !__ctfe )
		assert(false);
	
	bool[string] visited;
	string ret;
	
	void addModule( string mod ){
		if( mod !in visited ){
			ret ~= "static import "~mod~";\n";
			visited[mod] = true;
		}
	}
	
	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			foreach( symbol; getSymbols!(ReturnType!overload) ){
				static if( __traits(compiles, temporary_moduleName!(symbol)) )
					addModule(temporary_moduleName!symbol);
			}
			foreach( P; ParameterTypeTuple!overload ){
				foreach( symbol; getSymbols!P ){
					static if( __traits(compiles, temporary_moduleName!(symbol)) )
						addModule(temporary_moduleName!(symbol));
				}
			}
		}
	}
	
	return ret;
}

/// private
private string generateRestInterfaceSubInterfaces(I)()
{
	if (!__ctfe)
		assert(false);
	
	string ret;
	string[] tps;
	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			alias FunctionTypeOf!overload FT;
			alias ParameterTypeTuple!FT PTypes;
			alias ReturnType!FT RT;
			static if( is(RT == interface) ){
				static assert(PTypes.length == 0, "Interface getters may not have parameters.");
				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof~"Impl";
					ret ~= format(
						q{alias RestInterfaceClient!(%s) %s;},
						ReturnTypeString!(overload),
						implname
					);
					ret ~= "\n";
					ret ~= format(
						q{private %s m_%s;},
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
	
	string ret;
	string[] tps;
	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			alias FunctionTypeOf!overload FT;
			alias ParameterTypeTuple!FT PTypes;
			alias ReturnType!FT RT;
			static if( is(RT == interface) ){
				static assert(PTypes.length == 0, "Interface getters may not have parameters.");
				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof~"Impl";
					
					enum meta = extractHttpMethodAndName!overload();
					HttpMethod http_verb = meta[1];
					string url = meta[2];
					
					ret ~= format(
						q{m_%s = new %s(m_baseUrl~PathEntry("%s"), m_methodStyle);},
						implname,
						implname,
						url
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
	
	string ret;
	string[] tps;
	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			alias FunctionTypeOf!overload FT;
			alias ParameterTypeTuple!FT PTypes;
			alias ReturnType!FT RT;
			static if( is(RT == interface) ){
				static assert(PTypes.length == 0, "Interface getters may not have parameters.");
				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof~"Impl";
					
					ret ~= format(
						q{m_%s.requestFilter = m_requestFilter;},
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
	
	string ret;
	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			alias FunctionTypeOf!overload FT;
			alias ReturnType!FT RT;
			alias ParameterTypeTuple!overload PTypes;
			alias ParameterIdentifierTuple!overload ParamNames;
			
			enum meta = extractHttpMethodAndName!(overload)();
			enum pathOverriden = meta[0];
			HttpMethod httpVerb = meta[1];
			string url = meta[2];
			
			// NB: block formatting is coded in dependency order, not in 1-to-1 code flow order
			
			static if( is(RT == interface) ){
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
				string paramHandlingStr;
				string urlPrefix = `""`;
				
				// Block 2
				foreach( i, PT; PTypes ){
					static assert(ParamNames[i].length, format("Parameter %s of %s has no name.", i, method));
					
					// legacy :id special case, left for backwards-compatibility reasons
					static if( i == 0 && ParamNames[0] == "id" ){
						static if( is(PT == Json) )
							urlPrefix = q{urlEncode(id.toString())~"/"};
						else
							urlPrefix = q{urlEncode(toRestString(serializeToJson(id)))~"/"};
					}
					else static if( !ParamNames[i].startsWith("_") ){
						// underscore parameters are sourced from the HttpServerRequest.params map or from url itself
						paramHandlingStr ~= format(
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
				string requestStr;
				
				static if( !pathOverriden ){
					requestStr = format(
						q{
							url__ = %s ~ adjustMethodStyle(url__, m_methodStyle);
						},
						urlPrefix
					);
				} else {
					auto parts = url.split("/");
					requestStr ~= `url__ = ""`;
					foreach (i, p; parts) {
						if (i > 0) requestStr ~= `~"/"`;
						bool match = false;
						if( p.startsWith(":") ){
							foreach (pn; ParamNames) {
								if (pn.startsWith("_") && p[1 .. $] == pn[1 .. $]) {
									requestStr ~= `~urlEncode(toRestString(serializeToJson(`~pn~`)))`;
									match = true;
									break;
								}
							}
						}
						if (!match) requestStr ~= `~"`~p~`"`;
					}

					requestStr ~= ";\n";
				}
				
				requestStr ~= format(
					q{
						auto jret__ = request("%s", url__ , jparams__, jparamsj__);
					},
					httpMethodString(httpVerb)
				);
				
				static if (!is(ReturnType!overload == void)){
					requestStr ~= q{
						typeof(return) ret__;
						deserializeJson(ret__, jret__);
						return ret__;
					};
				}
				
				// Block 1
				ret ~= format(
					q{
						override %s {
							Json jparams__ = Json.EmptyObject;
							bool[string] jparamsj__;
							string url__ = "%s";
							%s
								%s
						}
					},
					cloneFunction!overload,
					url,
					paramHandlingStr,
					requestStr
				);
			}
		}
	}
	
	return ret;
}

private string toRestString(Json value)
{
	switch( value.type ){
		default: return value.toString();
		case Json.Type.Bool: return value.get!bool ? "true" : "false";
		case Json.Type.Int: return to!string(value.get!long);
		case Json.Type.Float: return to!string(value.get!double);
		case Json.Type.String: return value.get!string;
	}
}

private T fromRestString(T)(string value)
{
	static if( is(T == bool) ) return value == "true";
	else static if( is(T : int) ) return to!T(value);
	else static if( is(T : double) ) return to!T(value); // FIXME: formattedWrite(dst, "%.16g", json.get!double);
	else static if( is(T : string) ) return value;
	else static if( __traits(compiles, T.fromString("hello")) ) return T.fromString(value);
	else return deserializeJson!T(parseJson(value));
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
		@method(HttpMethod.POST) getInfo();
	}
	---	
 */
OverridenMethod method(HttpMethod data)
{
	if (!__ctfe)
		assert(false);
	return OverridenMethod(data);
}

/// private
struct OverridenMethod
{
	HttpMethod data;
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
		registerRestInterface!IAPI(new UrlRouter(), new API(), "/root/");
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
			* HttpMethod extracted
			* url path extracted
 */
private Tuple!(bool, HttpMethod, string) extractHttpMethodAndName(alias Func)()
{   
	if (!__ctfe)
		assert(false);
	
	immutable httpMethodPrefixes = [
		HttpMethod.GET    : [ "get", "query" ],
		HttpMethod.PUT    : [ "put", "set" ],
		HttpMethod.PATCH  : [ "update", "patch" ],
		HttpMethod.POST   : [ "add", "create", "post" ],
		HttpMethod.DELETE : [ "remove", "erase", "delete" ],
	];
	
	string name = __traits(identifier, Func);
	alias typeof(&Func) T;
	alias TypeTuple!(__traits(getAttributes, Func)) udas;
	
	Nullable!HttpMethod udmethod;
	Nullable!string udurl;
	
	// Cases may conflict and are listed in order of priority
	foreach ( uda; udas ){
		static if (is(typeof(uda) == vibe.http.rest.OverridenMethod))
			udmethod = uda.data;
		else if (is(typeof(uda) == vibe.http.rest.OverridenPath))
			udurl = uda.data;
	}
	
	// Everything is overriden, no further analysis needed
	if (!udmethod.isNull() && !udurl.isNull())
		return tuple(true, udmethod.get(), udurl.get());
	
	// Anti-copy-paste delegate
	typeof(return) udaOverride( HttpMethod method, string url ){
		return tuple(
			!udurl.isNull(),
			udmethod.isNull() ? method : udmethod.get(), 
			udurl.isNull() ? url : udurl.get()
		);
	}
	
	if (isPropertyGetter!T)
		return udaOverride(HttpMethod.GET, name);
	else if(isPropertySetter!T)
		return udaOverride(HttpMethod.PUT, name);
	else {
		foreach( method, prefixes; httpMethodPrefixes ){
			foreach (prefix; prefixes){
				if( name.startsWith(prefix) ){
					string tmp = name[prefix.length..$];
					return udaOverride(method, tmp);
				}
			}
		}
		
		if (name == "index")
			return udaOverride(HttpMethod.GET, "");
		else
			return udaOverride(HttpMethod.POST, name);
	}
}

unittest
{
	interface Sample
	{
		string getInfo();
		string updateDescription();
		
		@method(HttpMethod.DELETE)
		string putInfo();
		
		@path("matters")
		string getMattersnot();
		
		@path("compound/path") @method(HttpMethod.POST)
		string mattersnot();
	}
	
	enum ret1 = extractHttpMethodAndName!(Sample.getInfo);
	static assert (ret1[0] == false);
	static assert (ret1[1] == HttpMethod.GET);
	static assert (ret1[2] == "Info");
	enum ret2 = extractHttpMethodAndName!(Sample.updateDescription);
	static assert (ret2[0] == false);
	static assert (ret2[1] == HttpMethod.PATCH);
	static assert (ret2[2] == "Description");
	enum ret3 = extractHttpMethodAndName!(Sample.putInfo);
	static assert (ret3[0] == false);
	static assert (ret3[1] == HttpMethod.DELETE);
	static assert (ret3[2] == "Info");
	enum ret4 = extractHttpMethodAndName!(Sample.getMattersnot);
	static assert (ret4[0] == true);
	static assert (ret4[1] == HttpMethod.GET);
	static assert (ret4[2] == "matters");
	enum ret5 = extractHttpMethodAndName!(Sample.mattersnot);
	static assert (ret5[0] == true);
	static assert (ret5[1] == HttpMethod.POST);
	static assert (ret5[2] == "compound/path");
}
