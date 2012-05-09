/**
	Automatic REST interface and client code generation facilities.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.rest;

import vibe.data.json;
import vibe.http.client;
import vibe.http.router;
import vibe.inet.url;

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
		<tr><td>set</td><td>PUT</td></tr>
		<tr><td>put</td><td>PUT</td></tr>
		<tr><td>update</td><td>PATCH</td></tr>
		<tr><td>patch</td><td>PATCH</td></tr>
		<tr><td>add</td><td>POST</td></tr>
		<tr><td>create</td><td>POST</td></tr>
		<tr><td>post</td><td>POST</td></tr>
	</table>

	Examples:

		The following example makes MyApi available using HTTP requests. Valid requests are:

		<ul>
		  $(LI GET /api/status &rarr; "OK")
		  $(LI GET /api/greeting &rarr; "&lt;current greeting&gt;")
		  $(LI PUT /api/greeting &larr; {"text": "&lt;new text&gt;"})
		  $(LI POST /api/new_user &larr; {"name": "&lt;new user name&gt;"})
		  $(LI GET /api/users &rarr; ["&lt;user 1&gt;", "&lt;user 2&gt;"])
		</ul>
		---
		import vibe.d;

		interface IMyApi {
			string getStatus();

			@property string greeting();
			@property void greeting(string text);

			void addNewUser(string name);
			@property string[] users();
		}

		class MyApiImpl : IMyApi {
			private string m_greeting;
			private string[] m_users;

			string getStatus() { return "OK"; }

			@property string greeting() { return m_greeting; }
			@property void greeting(string text) { m_greeting = text; }

			void addNewUser(string name) { m_users ~= name; }
			@property string[] users() { return m_users, }
		}

		static this()
		{
			auto routes = new UrlRouter;

			registerRestInterface(routes, new MyApi, "/api/", MethodStyle.LowerUnderscored);

			listenHttp(new HttpServerSettings, routes);
		}
		---

	See_Also:
	
		RestInterfaceClient class for a seemless way to acces such a generated API
*/
void registerRestInterface(T)(UrlRouter router, T instance, string url_prefix = "/",
		MethodStyle style = MethodStyle.Unaltered)
{
	string url(string name, size_t nskip){
		return url_prefix ~ adjustMethodStyle(name[nskip .. $], style);
	}

	foreach( method; __traits(allMembers, T) ){
		foreach( overload; MemberFunctionsTuple!(T, method) ){
			auto handler = jsonMethodHandler!(T, method, typeof(&overload))(instance);
			string http_verb, rest_name;
			getRestMethodName!(typeof(&overload))(method, http_verb, rest_name);
			router.addRoute(http_verb, url_prefix ~ adjustMethodStyle(rest_name, style), handler);
		}
	}
}

/**
	Generates a form based interface to the given instance.

	Each function is callable with either GET or POST using form encoded parameters. Complex
	parameters are encoded as JSON strings.

	Note that this function is currently not fully implemented.
*/
void registerFormInterface(I)(UrlRouter router, I instance, string url_prefix,
		MethodStyle style = MethodStyle.Unaltered)
{
	string url(string name){
		return url_prefix ~ adjustMethodStyle(name, style);
	}

	foreach( method; __traits(allMembers, T) ){
		foreach( overload; MemberFunctionsTuple!(T, method) ){
			auto handler = formMethodHandler(overload);
			router.get(url(method), handler);
			router.post(url(method), handler);
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
		}

		static this()
		{
			auto api = new RestInterfaceClient!IMyApi(Url.parse("http://127.0.0.1/api/"), MethodStyle.LowerUnderlined);

			logInfo("Status: ", api.getStatus());
			api.greeting = "Hello, World!";
			logInfo("Greeting message: %s", api.greeting);
			api.addUser("Peter");
			api.addUser("Igor");
			logInfo("Users: %s", api.users);
		}
		---
*/
class RestInterfaceClient(I) : I
{
	private {
		Url m_baseUrl;
		MethodStyle m_methodStyle;
	}

	this(Url base_url, MethodStyle style = MethodStyle.Unaltered)
	{
		m_baseUrl = base_url;
		m_methodStyle = style;
	}

	//pragma(msg, generateRestInterfaceMethods!(I)());
	mixin(generateRestInterfaceMethods!(I)());

	protected Json request(string verb, string name, Json params)
	const {
		Url url = m_baseUrl ~ PathEntry(adjustMethodStyle(name, m_methodStyle));
		auto res = requestHttp(url, (req){
				req.method = verb;
				if( verb == "GET" || verb == "HEAD" ){
					assert(params.length == 0, "Getter functions with parameters not yet supported");
					// TODO:
					//url.queryString = ...;
				} else {
					req.writeJsonBody(params);
				}
			});
		return res.readJson();
	}
}

/**
	Adjusts the naming convention for a given function name to the specified style.

	The function name must be in lowerCamelCase (D-style) for the adjustment to work correctly.
*/
string adjustMethodStyle(string name, MethodStyle style)
{
	final switch(style){
		case MethodStyle.Unaltered:
			return name;
		case MethodStyle.CamelCase:
			return toLower(name[0 .. 1]) ~ name[1 .. $];
		case MethodStyle.PascalCase:
			return toUpper(name[0 .. 1]) ~ name[1 .. $];
		case MethodStyle.LowerCase:
			return toLower(name);
		case MethodStyle.UpperCase:
			return toUpper(name);
		case MethodStyle.LowerUnderscored:
		case MethodStyle.UpperUnderscored:
			string ret;
			size_t start = 0, i = 1;
			while( i < name.length ){
				while( i < name.length && !(name[i] >= 'A' && name[i] <= 'Z') ) i++;
				if( ret.length > 0 ) ret ~= "_";
				ret ~= name[start .. i];
				start = i++;
			}
			if( i < name.length ) ret ~= "_" ~ name[start .. $];
			return style == MethodStyle.LowerUnderscored ? toLower(ret) : toUpper(ret);
	}
}

/**
	Determines the naming convention of an identifier.
*/
enum MethodStyle {
	Unaltered,        /// Special value for free-style conventions
	CamelCase,        /// camelCaseNaming
	PascalCase,       /// PascalCaseNaming
	LowerCase,        /// lowercasenaming
	UpperCase,        /// UPPERCASENAMING
	LowerUnderscored, /// lower_case_naming
	UpperUnderscored  /// UPPER_CASE_NAMING
}


/// private
private HttpServerRequestDelegate jsonMethodHandler(T, string method, FT)(T inst)
{
	alias ParameterTypeTuple!(FT) ParameterTypes;
	alias ReturnType!(FT) RetType;

	void handler(HttpServerRequest req, HttpServerResponse res)
	{
		auto jparams = req.json;
		ParameterTypes params;

		auto param_names = parameterNames!FT();
		foreach( i, P; ParameterTypes )
			deserializeJson(params[i], jparams[param_names[i]]);


		static if( is(RetType == void) ){
			__traits(getMember, inst, method)(params);
			res.writeJsonBody(Json.EmptyObject);
		} else {
			auto ret = __traits(getMember, inst, method)(params);
			res.writeJsonBody(serializeToJson(ret));
		}
	}

	return &handler;
}

/// private
private HttpServerRequestDelegate formMethodHandler(T)(T func)
{
	void handler(HttpServerRequest req, HttpServerResponse res)
	{
		assert(false, "TODO!");
	}

	return &handler;
}

/// private
private @property string generateRestInterfaceMethods(I)()
{
	string ret;

	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			alias typeof(&overload) FT;
			alias ParameterTypeTuple!FT PTypes;
			alias ReturnType!FT RT;

			auto param_names = parameterNames!FT();
			string http_verb, rest_name;
			getRestMethodName!FT(method, http_verb, rest_name);
			ret ~= "override "~RT.stringof~" "~method~"(";
			foreach( i, PT; PTypes ){
				if( i > 0 ) ret ~= ", ";
				ret ~= PT.stringof;
				ret ~= " " ~ param_names[i];
			}
			ret ~= ")";

			auto attribs = functionAttributes!FT;
			//if( is(FT == const) ) ret ~= " const"; // FIXME: do something that actually works here
			//if( is(FT == immutable) ) ret ~= " immutable";
			if( attribs & FunctionAttribute.property ) ret ~= " @property";

			ret ~= " {\n";
			ret ~= "\tJson jparams__ = Json.EmptyObject;\n";
			foreach( i, PT; PTypes )
				ret ~= "\tjparams__[\""~param_names[i]~"\"] = serializeToJson("~param_names[i]~");\n";
			ret ~= "\tauto jret__ = request(\""~http_verb~"\", \""~rest_name~"\", jparams__);\n";
			static if( !is(RT == void) ){
				ret ~= "\t"~RT.stringof~" ret__;\n";
				ret ~= "\tdeserializeJson(ret__, jret__);\n";
				ret ~= "\treturn ret__;\n";
			}
			ret ~= "}\n";
		}
	}

	return ret;
}

/// private
private void getRestMethodName(T)(string method, out string http_verb, out string rest_name)
{
	if( isPropertyGetter!T )               { http_verb = "GET"; rest_name = method; }
	else if( isPropertySetter!T )          { http_verb = "PUT"; rest_name = method; }
	else if( method.startsWith("get") )    { http_verb = "GET"; rest_name = method[3 .. $]; }
	else if( method.startsWith("set") )    { http_verb = "PUT"; rest_name = method[3 .. $]; }
	else if( method.startsWith("put") )    { http_verb = "PUT"; rest_name = method[3 .. $]; }
	else if( method.startsWith("update") ) { http_verb = "PATCH"; rest_name = method[6 .. $]; }
	else if( method.startsWith("patch") )  { http_verb = "PATCH"; rest_name = method[5 .. $]; }
	else if( method.startsWith("add") )    { http_verb = "POST"; rest_name = method[3 .. $]; }
	else if( method.startsWith("create") ) { http_verb = "POST"; rest_name = method[6 .. $]; }
	else if( method.startsWith("post") )   { http_verb = "POST"; rest_name = method[4 .. $]; }
	else { http_verb = "POST"; rest_name = method; }
}

/// private
private string[] parameterNames(T)()
{
	string funcStr = T.stringof;
	//pragma(msg, T.stringof);
 
	const firstPattern = ' ';
	const secondPattern = ',';
	
	while( funcStr[0] != '(' ) funcStr = funcStr[1 .. $];
	foreach( i; 0 .. funcStr.length )
		if( funcStr[i] == ')' ){
			funcStr = funcStr[0 .. i];
			break;
		}
       
	if( funcStr.length == 0 ) return null;
	
	funcStr ~= secondPattern;
       
	string token;
	string[] arr;
       
	foreach( c; funcStr )
	{
		if( c != firstPattern && c != secondPattern ) token ~= c;
		else {
			if( token ) arr ~= token;
			token = null;
		}
	}
	
	if( arr.length == 1 ) return arr;
	
	string[] result;
	bool skip = false;
       
	foreach( str; arr ){
		skip = !skip;
		if( skip ) continue;
		result ~= str;
	}
	
	return result;
}

/// private
private template isPropertyGetter(T)
{
	enum isPropertyGetter = (functionAttributes!(T) & FunctionAttribute.property) != 0
		&& !is(ReturnType!T == void);
}

/// private
private template isPropertySetter(T)
{
	enum isPropertySetter = (functionAttributes!(T) & FunctionAttribute.property) != 0
		&& is(ReturnType!T == void);
}
