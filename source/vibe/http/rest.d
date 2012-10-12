/**
	Automatic REST interface and client code generation facilities.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.rest;

import vibe.core.log;
import vibe.data.json;
import vibe.http.client;
import vibe.http.router;
import vibe.inet.url;
import vibe.textfilter.urlencode;
import vibe.utils.string;

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
	URL instead of a JSON request.
	
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
	
		RestInterfaceClient class for a seemless way to acces such a generated API
*/
void registerRestInterface(T)(UrlRouter router, T instance, string url_prefix = "/",
		MethodStyle style = MethodStyle.LowerUnderscored)
{
	void addRoute(HttpMethod http_verb, string url, HttpServerRequestDelegate handler)
	{
		router.addRoute(http_verb, url, handler);
		logDebug("REST route: %s %s", http_verb, url);
	}

	foreach( method; __traits(allMembers, T) ){
		foreach( overload; MemberFunctionsTuple!(T, method) ){
			alias ReturnType!overload RetType;
			auto param_names = parameterNames!(typeof(&overload))();
			HttpMethod http_verb;
			string rest_name;
			getRestMethodName!(typeof(&overload))(method, http_verb, rest_name);
			string rest_name_adj = adjustMethodStyle(rest_name, style);
			static if( is(RetType == interface) ){
				static assert(ParameterTypeTuple!overload.length == 0, "Interfaces may only be returned from parameter-less functions!");
				registerRestInterface!RetType(router, __traits(getMember, instance, method)(), url_prefix ~ rest_name_adj ~ "/");
			} else {
				auto handler = jsonMethodHandler!(T, method, typeof(&overload))(instance);
				string id_supplement;
				size_t skip = 0;
				string url;
				if( param_names.length && param_names[0] == "id" ){
					addRoute(http_verb, url_prefix ~ ":id/" ~ rest_name_adj, handler);
					if( rest_name_adj.length == 0 )
						addRoute(http_verb, url_prefix ~ ":id", handler);
				} else addRoute	(http_verb, url_prefix ~ rest_name_adj, handler);
			}
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
    mixin("static import "~(moduleName!I)~";");

	alias void delegate(HttpClientRequest req) RequestFilter;
	private {
		Url m_baseUrl;
		MethodStyle m_methodStyle;
		RequestFilter m_requestFilter;
	}

	alias I BaseInterface;

	this(string base_url, MethodStyle style = MethodStyle.LowerUnderscored)
	{
		m_baseUrl = Url.parse(base_url);
		m_methodStyle = style;
		mixin(generateRestInterfaceSubInterfaceInstances!I);
	}

	this(Url base_url, MethodStyle style = MethodStyle.LowerUnderscored)
	{
		m_baseUrl = base_url;
		m_methodStyle = style;
		mixin(generateRestInterfaceSubInterfaceInstances!I);
	}

	@property RequestFilter requestFilter() { return m_requestFilter; }
	@property void requestFilter(RequestFilter v) {
		m_requestFilter = v;
		mixin(generateRestInterfaceSubInterfaceRequestFilter!I);
	}

	//pragma(msg, generateRestInterfaceSubInterfaces!(I)());
	#line 1 "subinterfaces"
	mixin(generateRestInterfaceSubInterfaces!(I));

	//pragma(msg, "restinterface:");
	//pragma(msg, generateRestInterfaceMethods!(I)());
	#line 1 "restinterface"
	mixin(generateRestInterfaceMethods!(I));

	#line 268 "rest.d"
	protected Json request(string verb, string name, Json params, bool[string] param_is_json)
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
				filterUrlEncode(queryString, param_is_json[pname] ? p.toString() : toRestString(p));
			}
			url.queryString = queryString.data();
		}

		auto res = requestHttp(url, (req){
				req.method = httpMethodFromString(verb);
				if( m_requestFilter ) m_requestFilter(req);
				if( verb != "GET" && verb != "HEAD" )
					req.writeJsonBody(params);
			});
		auto ret = res.readJson();
		logDebug("REST call: %s %s -> %d, %s", verb, url.toString(), res.statusCode, ret.toString());
		if( res.statusCode != HttpStatus.OK ){
			if( ret.type == Json.Type.Object && ret.statusMessage.type == Json.Type.String )
				throw new Exception(ret.statusMessage.get!string);
			else throw new Exception(httpStatusText(res.statusCode));
		}
		return ret;
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
		ParameterTypes params;

		static immutable param_names = parameterNames!FT();
		foreach( i, P; ParameterTypes ){
			static if( i == 0 && param_names[i] == "id" ){
				params[i] = fromRestString!P(req.params["id"]);
			} else static if( param_names[i].startsWith("_") ){
				static if( param_names[i] != "_dummy"){
					params[i] = fromRestString!P(req.params[param_names[i][1 .. $]]);
				}
			} else {
				if( req.method == HttpMethod.GET ){
					logDebug("query %s of %s" ,param_names[i], req.query);
					enforce(param_names[i] in req.query, "Missing query parameter '"~param_names[i]~"'");
					params[i] = fromRestString!P(req.query[param_names[i]]);
				} else {
					logDebug("%s %s", method, param_names[i]);
					enforce(req.headers["Content-Type"] == "application/json", "The Content-Type header needs to be set to application/json.");
					enforce(req.json.type != Json.Type.Undefined, "The request body does not contain a valid JSON value.");
					enforce(req.json.type == Json.Type.Object, "The request body must contain a JSON object with an entry for each parameter.");
					enforce(req.json[param_names[i]].type != Json.Type.Undefined, "Missing parameter "~param_names[i]~".");
					deserializeJson(params[i], req.json[param_names[i]]);
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
		} catch( Exception e ){
			// TODO: better error description!
			res.writeJsonBody(["statusMessage": e.msg, "statusDebugMessage": sanitizeUTF8(cast(ubyte[])e.toString())], HttpStatus.InternalServerError);
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
private @property string generateRestInterfaceSubInterfaces(I)()
{
	string ret;
	string[] tps;
	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			alias typeof(&overload) FT;
			alias ParameterTypeTuple!FT PTypes;
			alias ReturnType!FT RT;
			static if( is(RT == interface) ){
				static assert(PTypes.length == 0, "Interface getters may not have parameters.");
				if( tps.countUntil(RT.stringof) < 0 ){
					tps ~= RT.stringof;
					string implname = RT.stringof~"Impl";
					ret ~= "alias RestInterfaceClient!("~getReturnTypeString!(overload)~") "
							~implname~";\n";
					ret ~= "private "~implname~" m_"~implname~";\n";
				}
			}
		}
	}
	return ret;
}

/// private
private @property string generateRestInterfaceSubInterfaceInstances(I)()
{
	string ret;
	string[] tps;
	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			alias typeof(&overload) FT;
			alias ParameterTypeTuple!FT PTypes;
			alias ReturnType!FT RT;
			static if( is(RT == interface) ){
				static assert(PTypes.length == 0, "Interface getters may not have parameters.");
				if( tps.countUntil(RT.stringof) < 0 ){
					tps ~= RT.stringof;
					string implname = RT.stringof~"Impl";
					HttpMethod http_verb;
					string rest_name;
					getRestMethodName!FT(method, http_verb, rest_name);
					ret ~= "m_"~implname~" = new "~implname~"(m_baseUrl~PathEntry(\""~rest_name~"\"), m_methodStyle);\n";
				}
			}
		}
	}
	return ret;
}

/// private
private @property string generateRestInterfaceSubInterfaceRequestFilter(I)()
{
	string ret;
	string[] tps;
	foreach( method; __traits(allMembers, I) ){
		foreach( overload; MemberFunctionsTuple!(I, method) ){
			alias typeof(&overload) FT;
			alias ParameterTypeTuple!FT PTypes;
			alias ReturnType!FT RT;
			static if( is(RT == interface) ){
				static assert(PTypes.length == 0, "Interface getters may not have parameters.");
				if( tps.countUntil(RT.stringof) < 0 ){
					tps ~= RT.stringof;
					string implname = RT.stringof~"Impl";
					HttpMethod http_verb;
					string rest_name;
					getRestMethodName!FT(method, http_verb, rest_name);
					ret ~= "m_"~implname~".requestFilter = m_requestFilter;\n";
				}
			}
		}
	}
	return ret;
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
			HttpMethod http_verb; 
			string rest_name;
			getRestMethodName!FT(method, http_verb, rest_name);
			ret ~= "override "~getReturnTypeString!(overload)~" "~method~"(";
			foreach( i, PT; PTypes ){
				if( i > 0 ) ret ~= ", ";
				ret ~= getParameterTypeString!(overload, i);
				ret ~= " " ~ param_names[i];
			}
			ret ~= ")";

			auto attribs = functionAttributes!FT;
			//if( is(FT == const) ) ret ~= " const"; // FIXME: do something that actually works here
			//if( is(FT == immutable) ) ret ~= " immutable";
			if( attribs & FunctionAttribute.property ) ret ~= " @property";

			static if( is(RT == interface) ){
				ret ~= "{ return m_"~RT.stringof~"Impl; }\n";
			} else {
				ret ~= " {\n";
				ret ~= "\tJson jparams__ = Json.EmptyObject;\n";
				ret ~= "\tbool[string] jparamsj__;\n";

				// serialize all parameters
				string path_supplement;
				foreach( i, PT; PTypes ){
					if( i == 0 && param_names[0] == "id" ){
						static if( is(PT == Json) ) path_supplement = "urlEncode(id.toString())~\"/\"~";
						else path_supplement = "urlEncode(toRestString(serializeToJson(id)))~\"/\"~";
						continue;
					}
					// underscore parameters are sourced from the HttpServerRequest.params map
					if( param_names[i].startsWith("_") ) continue;

					ret ~= "\tjparams__[\""~param_names[i]~"\"] = serializeToJson("~param_names[i]~");\n";
					ret ~= "\tjparamsj__[\""~param_names[i]~"\"] = "~(is(PT == Json) ? "true" : "false")~";\n";
				}

				ret ~= "\tauto jret__ = request(\""~ httpMethodString(http_verb)~"\", "~path_supplement~"adjustMethodStyle(\""~rest_name~"\", m_methodStyle), jparams__, jparamsj__);\n";
				static if( !is(RT == void) ){
					ret ~= "\t"~getReturnTypeString!(overload)~" ret__;\n";
					ret ~= "\tdeserializeJson(ret__, jret__);\n";
					ret ~= "\treturn ret__;\n";
				}
				ret ~= "}\n";
			}
		}
	}

	return ret;
}

/// private
// https://github.com/D-Programming-Language/phobos/pull/862
private template returnsRef(alias f)
{
	enum bool returnsRef = is(typeof(
	{
		ParameterTypeTuple!f param;
		auto ptr = &f(param);
	}));
}

/// private
private @property string getReturnTypeString(alias F)()
{   
	alias ReturnType!F T;
	static if (returnsRef!F)	
		return "ref " ~ fullyQualifiedTypename!T;
	else
		return fullyQualifiedTypename!T;
}

/// private
private @property string getParameterTypeString(alias F, int i)()
{
	alias ParameterTypeTuple!(F) T;
	alias ParameterStorageClassTuple!(F) storage_classes;
	static assert(T.length > i);
	static assert(storage_classes.length > i);

	enum is_ref = (storage_classes[i] & ParameterStorageClass.ref_);
	enum is_out = (storage_classes[i] & ParameterStorageClass.out_);
	enum is_lazy = (storage_classes[i] & ParameterStorageClass.lazy_);
	enum is_scope = (storage_classes[i] & ParameterStorageClass.scope_);

	string prefix = "";
	if (is_ref)
		prefix = "ref " ~ prefix;
	if (is_out)
		prefix = "out " ~ prefix;
	if (is_lazy)
		prefix = "lazy " ~ prefix;
	if (is_scope)
		prefix = "scope " ~ prefix;

	return prefix ~ fullyQualifiedTypename!(T[i]);
}

/// private
private template fullyQualifiedTypeNameImpl(T,
    bool already_const, bool already_immutable, bool already_shared)
{
	import std.typetuple;
	
    // Convinience tags
    enum {
        _const = 0,
        _immutable = 1,
        _shared = 2
    }
    
    alias TypeTuple!(is(T == const), is(T == immutable), is(T == shared)) qualifiers;
    alias TypeTuple!(false, false, false) no_qualifiers;

    template parametersTypeString(T)
    {
        import std.array;
        import std.algorithm;

        alias ParameterTypeTuple!(T) parameters;
        enum parametersTypeString = join([staticMap!(fullyQualifiedTypeName, parameters)], ", ");
    }

    template addQualifiers(string type_string,
        bool add_const, bool add_immutable, bool add_shared)
    {
        static if (add_const)
            enum addQualifiers = addQualifiers!("const(" ~ type_string ~ ")",
                false, add_immutable, add_shared);
        else static if (add_immutable)
            enum addQualifiers = addQualifiers!("immutable(" ~ type_string ~ ")",
                add_const, false, add_shared);
        else static if (add_shared)
            enum addQualifiers = addQualifiers!("shared(" ~ type_string ~ ")",
                add_const, add_immutable, false);
        else
            enum addQualifiers = type_string;
    }

    // Convenience template to avoid copy-paste
    template chain(string current)
    {
        enum chain = addQualifiers!(current,
            qualifiers[_const]     && !already_const,
            qualifiers[_immutable] && !already_immutable,
            qualifiers[_shared]    && !already_shared);
    }
    
    static if (isBasicType!T)
    {   
        enum fullyQualifiedTypeNameImpl = chain!((Unqual!T).stringof);
    }   
    else static if (isAggregateType!T)
    {   
        enum fullyQualifiedTypeNameImpl = chain!(fullyQualifiedName!T);
    }   
    else static if (isArray!T)
    {   
        enum fullyQualifiedTypeNameImpl = chain!(
            fullyQualifiedTypeNameImpl!(typeof(T.init[0]), qualifiers ) ~ "[]"
        );
    }   
    else static if (isAssociativeArray!T)
    {   
        enum fullyQualifiedTypeNameImpl = chain!(
            fullyQualifiedTypeNameImpl!(ValueType!T, qualifiers) 
            ~ "["
            ~ fullyQualifiedTypeNameImpl!(KeyType!T, qualifiers)
            ~ "]"
        );
    }   
    else static if (isSomeFunction!T)
    {   
        enum fullyQualifiedTypeNameImpl = chain!(
            fullyQualifiedTypeNameImpl!(ReturnType!T, no_qualifiers)
            ~ "("
            ~ parametersTypeString!(T)
            ~ ")"
        );
    }   
    else
        // In case something is forgotten
        static assert(0, "Unrecognized type" ~ T.stringof ~ ", can't convert to fully qualified string");
}

/// private
// https://github.com/D-Programming-Language/phobos/pull/863
private template fullyQualifiedTypeName(T)
{
    static assert(is(T), "Template parameter must be a type");
    enum fullyQualifiedTypeName = fullyQualifiedTypeNameImpl!(T, false, false, false);
}
	
version(unittest)
{
    struct QualifiedNameTests
    {
        struct Inner
        {
        }

        ref const(Inner[string]) func( ref Inner var1, lazy scope string var2 );        

        shared(const(Inner[string])[]) data;
        
        Inner delegate(double, string) deleg;
    }
}

unittest
{   
    static assert(fullyQualifiedTypeName!(string) == "immutable(char)[]");
    static assert(fullyQualifiedTypeName!(QualifiedNameTests.Inner)
		== "vibe.http.rest.QualifiedNameTests.Inner");
    static assert(fullyQualifiedTypeName!(ReturnType!(QualifiedNameTests.func))
		== "const(vibe.http.rest.QualifiedNameTests.Inner[immutable(char)[]])");
    static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.func))
		== "const(vibe.http.rest.QualifiedNameTests.Inner[immutable(char)[]])(vibe.http.rest.QualifiedNameTests.Inner, immutable(char)[])");
    static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.data))
		== "shared(const(vibe.http.rest.QualifiedNameTests.Inner[immutable(char)[]])[])");
    static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.deleg))
		== "vibe.http.rest.QualifiedNameTests.Inner(double, immutable(char)[])");
}

/// private
private void getRestMethodName(T)(string method, out HttpMethod http_verb, out string rest_name)
{
	if( isPropertyGetter!T )               { http_verb = HttpMethod.GET; rest_name = method; }
	else if( isPropertySetter!T )          { http_verb = HttpMethod.PUT; rest_name = method; }
	else if( method.startsWith("get") )    { http_verb = HttpMethod.GET; rest_name = method[3 .. $]; }
	else if( method.startsWith("query") )  { http_verb = HttpMethod.GET; rest_name = method[5 .. $]; }
	else if( method.startsWith("set") )    { http_verb = HttpMethod.PUT; rest_name = method[3 .. $]; }
	else if( method.startsWith("put") )    { http_verb = HttpMethod.PUT; rest_name = method[3 .. $]; }
	else if( method.startsWith("update") ) { http_verb = HttpMethod.PATCH; rest_name = method[6 .. $]; }
	else if( method.startsWith("patch") )  { http_verb = HttpMethod.PATCH; rest_name = method[5 .. $]; }
	else if( method.startsWith("add") )    { http_verb = HttpMethod.POST; rest_name = method[3 .. $]; }
	else if( method.startsWith("create") ) { http_verb = HttpMethod.POST; rest_name = method[6 .. $]; }
	else if( method.startsWith("post") )   { http_verb = HttpMethod.POST; rest_name = method[4 .. $]; }
	else if( method.startsWith("remove") ) { http_verb = HttpMethod.DELETE; rest_name = method[6 .. $]; }
	else if( method.startsWith("erase") )  { http_verb = HttpMethod.DELETE; rest_name = method[5 .. $]; }
	else if( method.startsWith("delete") ) { http_verb = HttpMethod.DELETE; rest_name = method[6 .. $]; }
	else if( method == "index" )           { http_verb = HttpMethod.GET; rest_name = ""; }
	else { http_verb = HttpMethod.POST; rest_name = method; }
}

/// private
private string[] parameterNames(T)()
{
	auto str = extractParameters(T.stringof);
	//pragma(msg, T.stringof);

	string[] ret;
	for( size_t i = 0; i < str.length; ){
		skipWhitespace(str, i);
		skipType(str, i);
		skipWhitespace(str, i);
		ret ~= skipIdent(str, i);
		skipWhitespace(str, i);
		if( i >= str.length ) break;
		if( str[i] == '=' ){
			i++;
			skipWhitespace(str, i);
			skipBalancedUntil(",", str, i);
			if( i >= str.length ) break;
		}
		assert(str[i] == ',');
		i++;
	}

	return ret;
}

/// private
private string[] parameterDefaultValues(T)()
{
	auto str = extractParameters(T.stringof);
	//pragma(msg, T.stringof);

	string[] ret;
	for( size_t i = 0; i < str.length; ){
		skipWhitespace(str, i);
		skipType(str, i);
		skipWhitespace(str, i);
		skipIdent(str, i);
		skipWhitespace(str, i);
		if( i >= str.length ) break;
		if( str[i] == '=' ){
			i++;
			skipWhitespace(str, i);
			ret ~= skipBalancedUntil(",", str, i);
			if( i >= str.length ) break;
		}
		assert(str[i] == ',');
		i++;
	}

	return ret;
}

private string extractParameters(string str)
{
	auto i1 = str.countUntil("function");
	auto i2 = str.countUntil("delegate");
	assert(i1 >= 0 || i2 >= 0);
	size_t start;
	if( i1 >= 0 && i2 >= 0) start = min(i1, i2);
	else if( i1 >= 0 ) start = i1;
	else start = i2;
	size_t end = str.length-1;
	while( str[start] != '(' ) start++;
	while( str[end] != ')' ) end--;
	return str[start+1 .. end];
}

private void skipWhitespace(string str, ref size_t i)
{
	while( i < str.length && str[i] == ' ' ) i++;
}

private string skipIdent(string str, ref size_t i)
{
	size_t start = i;
	while( i < str.length ){
		switch( str[i] ){
			default:
				i++;
				break;
			case ' ',  ',', '(', ')', '=', '[', ']':
				return str[start .. i];
		}
	}
	return str[start .. $];
}

private void skipType(string str, ref size_t i)
{
	if (str[i..$].startsWith("ref")) {
		i += 3;
		skipWhitespace(str, i);
	}
	skipIdent(str, i);
	if( i < str.length && (str[i] == '(' || str[i] == '[') ){
		int depth = 1;
		for( ++i; i < str.length && depth > 0; i++ ){
			if( str[i] == '(' || str[i] == '[' ) depth++;
			else if( str[i] == ')' || str[i] == ']' ) depth--;
		}
	}
}

private string skipBalancedUntil(string chars, string str, ref size_t i)
{
	int depth = 0;
	size_t start = i;
	while( i < str.length && (depth > 0 || chars.countUntil(str[i]) < 0) ){
		if( str[i] == '(' || str[i] == '[' ) depth++;
		else if( str[i] == ')' || str[i] == ']' ) depth--;
		i++;
	}
	return str[start .. i];
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

/// private
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

/// private
private T fromRestString(T)(string value)
{
	static if( is(T == bool) ) return value == "true";
	else static if( is(T : int) ) return to!T(value);
	else static if( is(T : double) ) return to!T(value); // FIXME: formattedWrite(dst, "%.16g", json.get!double);
	else static if( is(T : string) ) return value;
	else static if( __traits(compiles, T.fromString("hello")) ) return T.fromString(value);
	else {
		T ret;
		deserializeJson(ret, parseJson(value));
		return ret;
	}
}
