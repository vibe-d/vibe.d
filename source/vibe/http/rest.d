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
void registerRestInterface(T)(UrlRouter router, T instance, string url_prefix = "/",
		MethodStyle style = MethodStyle.lowerUnderscored)
{
	void addRoute(HttpMethod http_verb, string url, HttpServerRequestDelegate handler, string[] params)
	{
		router.addRoute(http_verb, url, handler);
		logDebug("REST route: %s %s %s", http_verb, url, params.filter!(p => !p.startsWith("_") && p != "id")().array());
	}

	foreach( method; __traits(allMembers, T) ){
		foreach( overload; MemberFunctionsTuple!(T, method) ){
			alias ReturnType!overload RetType;
			string[] param_names = [ParameterIdentifierTuple!overload];

			enum meta = extractHttpMethodAndName!(overload)();
			enum pathOverriden = meta[0];
			HttpMethod httpVerb = meta[1];
			static if (pathOverriden)
				string url = meta[2];
			else
				string url = adjustMethodStyle(meta[2], style);

			static if( is(RetType == interface) ){
				static assert(ParameterTypeTuple!overload.length == 0, "Interfaces may only be returned from parameter-less functions!");
				registerRestInterface!RetType(router, __traits(getMember, instance, method)(), url_prefix ~ url ~ "/");
			} else {
				auto handler = jsonMethodHandler!(T, method, overload)(instance);
				string id_supplement;
				size_t skip = 0;
				string url;
				if( param_names.length && param_names[0] == "id" ){
					addRoute(httpVerb, url_prefix ~ ":id/" ~ url, handler, param_names);
					if( rest_name_adj.length == 0 )
						addRoute(httpVerb, url_prefix ~ ":id", handler, param_names);
				} else addRoute(httpVerb, url_prefix ~ url, handler, param_names);
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
    mixin(generateModuleImports!I);

	alias void delegate(HttpClientRequest req) RequestFilter;
	private {
		Url m_baseUrl;
		MethodStyle m_methodStyle;
		RequestFilter m_requestFilter;
	}

	alias I BaseInterface;

	/** Creates a new REST implementation of I
	*/
	this(string base_url, MethodStyle style = MethodStyle.lowerUnderscored)
	{
		m_baseUrl = Url.parse(base_url);
		m_methodStyle = style;
		mixin(generateRestInterfaceSubInterfaceInstances!I);
	}
	/// ditto
	this(Url base_url, MethodStyle style = MethodStyle.lowerUnderscored)
	{
		m_baseUrl = base_url;
		m_methodStyle = style;
		mixin(generateRestInterfaceSubInterfaceInstances!I);
	}

	/** An optional request filter that allows to modify each request before it is made.
	*/
	@property RequestFilter requestFilter() { return m_requestFilter; }
	/// ditto
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

	#line 254 "source/vibe/http/rest.d"
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
		scope(exit) destroy(res);
		auto ret = res.readJson();
		logDebug("REST call: %s %s -> %d, %s", verb, url.toString(), res.statusCode, ret.toString());
		if( res.statusCode != HttpStatus.OK ){
			if( ret.type == Json.Type.Object && ret.statusMessage.type == Json.Type.String )
				throw new HttpStatusException(res.statusCode, ret.statusMessage.get!string);
			else throw new HttpStatusException(res.statusCode, httpStatusText(res.statusCode));
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
			size_t start = 0, i = 1;
			while( i < name.length ){
				while( i < name.length && !(name[i] >= 'A' && name[i] <= 'Z') ) i++;
				if( ret.length > 0 ) ret ~= "_";
				ret ~= name[start .. i];
				start = i++;
			}
			if( i < name.length ) ret ~= "_" ~ name[start .. $];
			return style == MethodStyle.lowerUnderscored ? toLower(ret) : toUpper(ret);
	}
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
private HttpServerRequestDelegate jsonMethodHandler(T, string method, alias FUNC)(T inst)
{
	alias ParameterTypeTuple!FUNC ParameterTypes;
	alias ReturnType!FUNC RetType;
	alias ParameterDefaultValueTuple!FUNC DefaultValues;
	enum param_names = [ParameterIdentifierTuple!FUNC];

	void handler(HttpServerRequest req, HttpServerResponse res)
	{
		ParameterTypes params;

		foreach( i, P; ParameterTypes ){
			static assert(param_names[i].length, "Parameter "~i.stringof~" of "~method~" has no name");
			static if( i == 0 && param_names[i] == "id" ){
				logDebug("id %s", req.params["id"]);
				params[i] = fromRestString!P(req.params["id"]);
			} else static if( param_names[i].startsWith("_") ){
				static if( param_names[i] != "_dummy"){
					enforce(param_names[i][1 .. $] in req.params, "req.param[\""~param_names[i][1 .. $]~"\"] was not set!");
					logDebug("param %s %s", param_names[i], req.params[param_names[i][1 .. $]]);
					params[i] = fromRestString!P(req.params[param_names[i][1 .. $]]);
				}
			} else {
				alias DefaultValues[i] DefVal;
				if( req.method == HttpMethod.GET ){
					logDebug("query %s of %s" ,param_names[i], req.query);
					static if( is(DefVal == void) ){
						enforce(param_names[i] in req.query, "Missing query parameter '"~param_names[i]~"'");
					} else {
						if( param_names[i] !in req.query ){
							params[i] = DefVal;
							continue;
						}
					}
					params[i] = fromRestString!P(req.query[param_names[i]]);
				} else {
					logDebug("%s %s", method, param_names[i]);
					enforce(req.contentType == "application/json", "The Content-Type header needs to be set to application/json.");
					enforce(req.json.type != Json.Type.Undefined, "The request body does not contain a valid JSON value.");
					enforce(req.json.type == Json.Type.Object, "The request body must contain a JSON object with an entry for each parameter.");
					static if( is(DefVal == void) ){
						enforce(req.json[param_names[i]].type != Json.Type.Undefined, "Missing parameter "~param_names[i]~".");
					} else {
						if( req.json[param_names[i]].type == Json.Type.Undefined ){
							params[i] = DefVal;
							continue;
						}
					}
					params[i] = deserializeJson!P(req.json[param_names[i]]);
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

/// private
private @property string generateModuleImports(I)()
{
	bool[string] visited;
	string ret;

	void addModule(string mod){
		if( mod !in visited ){
			ret ~= "static import "~mod~";\n";
			visited[mod] = true;
		}
	}

	foreach( method; __traits(allMembers, I) )
		foreach( overload; MemberFunctionsTuple!(I, method) ){
            foreach( symbol; getSymbols!(ReturnType!overload))
            {
                static if( __traits(compiles, moduleName!(symbol)))
                    addModule(moduleName!symbol);
            }
			foreach( P; ParameterTypeTuple!overload )
            {
                foreach( symbol; getSymbols!P )
                {
		            static if( __traits(compiles, moduleName!(symbol)))
                        addModule(moduleName!(symbol));
                }
            }
		}

	return ret;
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

					enum meta = extractHttpMethodAndName!(FT)();
					string url = meta[2];

					ret ~= "m_"~implname~" = new "~implname~"(m_baseUrl~PathEntry(\""~url~"\"), m_methodStyle);\n";
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
					ret ~= "m_"~implname~".requestFilter = m_requestFilter;\n";
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
				bool regexNeeded = false;
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
								jparams__["%s"] = serializeToJson("%s");
								jparamsj__["%s"] = %s;
							},
							ParamNames[i],
							ParamNames[i],
							ParamNames[i],
							is(PT == Json) ? "true" : "false"
							);
					}
					else {
						regexNeeded = true;
						paramHandlingStr ~= format(
							q{
								url__ = replace(url__, regex("(^|/)(:%s)($|/)"), "$1" ~ %s ~ "$3");
							},
							ParamNames[i][1..$],
							ParamNames[i]
							);
					}
				}
				
				if( regexNeeded )
					paramHandlingStr = format(
						q{
							import std.regex;
							%s
						},
						paramHandlingStr
						);
				
				// Block 3
				string requestStr;
				
				static if( !pathOverriden ){
					requestStr = format(
						q{
							url__ = %s ~ adjustMethodStyle(url__, m_methodStyle);
						},
						urlPrefix
						);
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
		return "ref " ~ fullyQualifiedTypeName!T;
	else
		return fullyQualifiedTypeName!T;
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

	return prefix ~ fullyQualifiedTypeName!(T[i]);
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
    
    static if (isBasicType!T || is(T == enum))
    {   
        enum fullyQualifiedTypeNameImpl = chain!((Unqual!T).stringof);
    }   
    else static if (isAggregateType!T)
    {   
        enum fullyQualifiedTypeNameImpl = chain!(fullyQualifiedName!T);
    }  
    else static if (isStaticArray!T)
    {
        enum fullyQualifiedTypeNameImpl = chain!(
            fullyQualifiedTypeNameImpl!(typeof(T.init[0]), qualifiers) ~ "["~to!string(T.length)~"]"
        );
    }
    else static if (isArray!T)
    {   
        enum fullyQualifiedTypeNameImpl = chain!(
            fullyQualifiedTypeNameImpl!(typeof(T.init[0]), qualifiers) ~ "[]"
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
    else static if (isPointer!T)
    {
    	enum fullyQualifiedTypeNameImpl = chain!(
            fullyQualifiedTypeNameImpl!(PointerTarget!T, qualifiers)
            ~ "*"
    	);
    }
    else
        // In case something is forgotten
        static assert(0, "Unrecognized type " ~ T.stringof ~ ", can't convert to fully qualified string");
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

        Inner[] array;
        Inner[16] sarray;
        Inner[Inner] aarray;

        Json external_type;
        Json[] ext_array;
        Json[16] ext_sarray;
        Json[Json] ext_aarray;
    }
}

/// private
template getSymbols(T)
{
    import std.typetuple;

    static if (isAggregateType!T || is(T == enum))
    {   
        alias TypeTuple!T getSymbols;
    }  
    else static if (isStaticArray!T || isArray!T)
    {
        alias getSymbols!(typeof(T.init[0])) getSymbols;
    }
    else static if (isAssociativeArray!T)
    {   
        alias TypeTuple!( getSymbols!(ValueType!T) , getSymbols!(KeyType!T) ) getSymbols;
    }   
    else static if (isPointer!T)
    {
    	alias getSymbols!(PointerTarget!T) getSymbols;
    }
    else
        alias TypeTuple!() getSymbols;
}

unittest
{   
    import std.typetuple;
    alias QualifiedNameTests.Inner symbol;
    enum target1 = TypeTuple!(symbol).stringof;
    enum target2 = TypeTuple!(symbol, symbol).stringof;
    static assert(getSymbols!(symbol[10]).stringof == target1);
    static assert(getSymbols!(symbol[]).stringof == target1);
    static assert(getSymbols!(symbol).stringof == target1);
    static assert(getSymbols!(symbol[symbol]).stringof == target2);
    static assert(getSymbols!(int).stringof == TypeTuple!().stringof);
}

unittest
{
    static assert(fullyQualifiedTypeName!(string) == "immutable(char)[]");
    static assert(fullyQualifiedTypeName!(Json)
		== "vibe.data.json.Json");
    static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.ext_array))
        == "vibe.data.json.Json[]");
    static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.ext_sarray))
    	== "vibe.data.json.Json[16]");
    static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.ext_aarray))
    	== "vibe.data.json.Json[vibe.data.json.Json]");

	// the following tests fail on DMD < 2.061 - instanceOf was added in 2.061 and we
	// use this fact to avoid failing on DMD 2.060
	static if( __traits(compiles, { assert(isInstanceOf!(Appender, Appender!string)); }) ){
		static assert(fullyQualifiedTypeName!(QualifiedNameTests.Inner)
			== "vibe.http.rest.QualifiedNameTests.Inner");
		/*static assert(fullyQualifiedTypeName!(ReturnType!(QualifiedNameTests.func))
			== "const(vibe.http.rest.QualifiedNameTests.Inner[immutable(char)[]])");
		static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.func))
			== "const(vibe.http.rest.QualifiedNameTests.Inner[immutable(char)[]])(vibe.http.rest.QualifiedNameTests.Inner, immutable(char)[])");
		static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.data))
			== "shared(const(vibe.http.rest.QualifiedNameTests.Inner[immutable(char)[]])[])");*/
		static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.deleg))
			== "vibe.http.rest.QualifiedNameTests.Inner(double, immutable(char)[])");
		static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.array))
			== "vibe.http.rest.QualifiedNameTests.Inner[]");
		static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.sarray))
			== "vibe.http.rest.QualifiedNameTests.Inner[16]");
		static assert(fullyQualifiedTypeName!(typeof(QualifiedNameTests.aarray))
			== "vibe.http.rest.QualifiedNameTests.Inner[vibe.http.rest.QualifiedNameTests.Inner]");
	}
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
	foreach( uda; udas ){
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
	else if (isPropertySetter!T)
		return udaOverride(HttpMethod.PUT, name);
	
	foreach( method, prefixes; httpMethodPrefixes ){
		foreach( prefix; prefixes ){
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
	else return deserializeJson!T(parseJson(value));
}
