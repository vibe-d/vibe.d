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
import vibe.internal.meta.uda;
import vibe.inet.url;
import vibe.inet.message : InetHeaderMap;

import vibe.web.internal.rest;
import vibe.web.internal.routes;
import vibe.web.internal.rest_client;
import vibe.web.internal.rest_server;

import std.algorithm : startsWith, endsWith;
import std.typetuple : anySatisfy, Filter;
import std.traits;

/**
	Registers a REST interface and connects it the the given instance.

	Each method of the given class instance is mapped to the corresponing HTTP
	verb. Property methods are mapped to GET/PUT and all other methods are
	mapped according to their prefix verb. If the method has no known prefix,
	POST is used.

	The following table lists the mappings from prefix verb to HTTP verb:

	$(TABLE
		$(TR $(TH Prefix) $(TH HTTP verb))
		$(TR $(TD get)	  $(TD GET))
		$(TR $(TD query)  $(TD GET))
		$(TR $(TD set)    $(TD PUT))
		$(TR $(TD put)    $(TD PUT))
		$(TR $(TD update) $(TD PATCH))
		$(TR $(TD patch)  $(TD PATCH))
		$(TR $(TD add)    $(TD POST))
		$(TR $(TD create) $(TD POST))
		$(TR $(TD post)   $(TD POST))
	)

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
		settings = Additional settings, such as the $(D MethodStyle), or the prefix.
			See $(D RestInterfaceSettings) for more details.

	See_Also:
		$(D RestInterfaceClient) class for a seamless way to access such a generated API

*/
void registerRestInterface(TImpl)(URLRouter router, TImpl instance, RestInterfaceSettings settings = null)
{
	import std.traits : InterfacesTuple;
	import vibe.internal.meta.uda : findFirstUDA;

	alias IT = InterfacesTuple!TImpl;
	static assert (IT.length > 0 || is (TImpl == interface),
		       "Cannot registerRestInterface type '" ~ TImpl.stringof
		       ~ "' because it doesn't implement an interface");
	static if (IT.length > 1)
		pragma(msg, "Type '" ~ TImpl.stringof ~ "' implements more than one interface: make sure the one describing the REST server is the first one");
	static if (is(TImpl == interface))
		alias I = TImpl;
	else
		alias I = IT[0];

	static assert(getInterfaceValidationError!(I) is null, getInterfaceValidationError!(I));

	if (!settings) settings = new RestInterfaceSettings;

	string url_prefix = settings.baseURL.path.toString();

	enum uda = findFirstUDA!(PathAttribute, I);
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

	foreach (method; __traits(allMembers, I)) {
		// WORKAROUND #1045 / @@BUG14375@@
		static if (method.length != 0)
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			enum meta = extractHTTPMethodAndName!(overload, false)();

			static if (meta.hadPathUDA) {
				string url = meta.url;
			}
			else {
				string url = adjustMethodStyle(stripTUnderscore(meta.url, settings), settings.methodStyle);
			}

			alias RT = ReturnType!overload;

			static if (is(RT == interface)) {
				// nested API
				static assert (
					ParameterTypeTuple!overload.length == 0,
					"Interfaces may only be returned from parameter-less functions!"
				);
				auto subSettings = settings.dup;
				subSettings.baseURL = URL(concatURL(url_prefix, url, true));
				registerRestInterface!RT(
					router,
					__traits(getMember, instance, method)(),
					subSettings
				);
			} else {
				// normal handler
				auto handler = jsonMethodHandler!(I, overload)(instance, settings);

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
	import vibe.data.json;

	@path("/")
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
	static assert(getInterfaceValidationError!(I) is null, getInterfaceValidationError!(I));

	import vibe.data.json;

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
			assert (m_settings.baseURL.path.empty, "Base URL path must be absolute.");
			m_settings.baseURL.path = Path("/");
		}

		URL url = settings.baseURL;
		enum uda = findFirstUDA!(PathAttribute, I);
		static if (uda.found) {
			static if (uda.value.data == "") {
				url.path = Path(concatURL(url.path.toString(), adjustMethodStyle(I.stringof, settings.methodStyle), true));
			} else {
				url.path = Path(concatURL(url.path.toString(), uda.value.data, true));
			}
		}

		m_baseURL = url;
		m_methodStyle = settings.methodStyle;

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
	mixin RestClientMethods!I;

	protected {
		import vibe.data.json : Json;
		import vibe.textfilter.urlencode;

		/**
		 * Perform a request to the interface using the given parameters.
		 *
		 * Params:
		 * verb = Kind of request (See $(D HTTPMethod) enum).
		 * name = Location to request. For a request on https://github.com/rejectedsoftware/vibe.d/issues?q=author%3ASantaClaus,
		 *		it will be '/rejectedsoftware/vibe.d/issues'.
		 * hdrs = The headers to send. Some field might be overriden (such as Content-Length). However, Content-Type will NOT be overriden.
		 * query = The $(B encoded) query string. For a request on https://github.com/rejectedsoftware/vibe.d/issues?q=author%3ASantaClaus,
		 *		it will be 'author%3ASantaClaus'.
		 * body_ = The body to send, as a string. If a Content-Type is present in $(D hdrs), it will be used, otherwise it will default to
		 *		the generic type "application/json".
		 */
		Json request(HTTPMethod verb, string name, in ref InetHeaderMap hdrs, string query, string body_) const
		{
			import vibe.http.client : HTTPClientRequest, HTTPClientResponse, requestHTTP;
			import vibe.http.common : HTTPStatusException, HTTPStatus, httpMethodString, httpStatusText;
			import vibe.inet.url : Path;

			URL url = m_baseURL;

			if (name.length) url ~= Path(name);
			if (query.length) url.queryString = query;

			Json ret;

			auto reqdg = (scope HTTPClientRequest req) {
				req.method = verb;
				foreach (k, v; hdrs)
					req.headers[k] = v;

				if (m_requestFilter) {
					m_requestFilter(req);
				}

				if (body_ != "")
					req.writeBody(cast(ubyte[])body_, hdrs.get("Content-Type", "application/json"));
			};

			auto resdg = (scope HTTPClientResponse res) {
				ret = res.readJson();

				logDebug(
					 "REST call: %s %s -> %d, %s",
					 httpMethodString(verb),
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

	/// Params are passed in a deterministic order: [Name, value]*
	private string genQuery(Ts...)(Ts params) {
		import std.array : appender;

		static assert(!(params.length % 2), "Internal error ("~__FUNCTION__~"): Expected [Name, value] pairs.");
		static if (!params.length)
			return null;
		else {
			auto query = appender!string();

			foreach (idx, p; params) {
				static if (!(idx % 2)) {
					// Parameter name
					static assert(is(typeof(p) == string), "Internal error ("~__FUNCTION__~"): Parameter name is not string.");
					query.put('&');
					filterURLEncode(query, p);
				} else {
					// Parameter value
					query.put('=');
					static if (is(typeof(p) == Json))
						filterURLEncode(query, p.toString());
					else // Note: CTFE triggers compiler bug here (think we are returning Json, not string).
						filterURLEncode(query, toRestString(serializeToJson(p)));
				}
			}
			return query.data();
		}
	}

	/// Params are passed in a deterministic order: [Name, value]*
	private string genBody(Ts...)(Ts params) {
		import std.array : appender;
		import vibe.data.json;

		static assert(!(params.length % 2), "Internal error ("~__FUNCTION__~"): Expected [Name, value] pairs.");
		static if (!params.length)
			return null;
		else {
			auto jsonBody = Json.emptyObject;

			string nextName;
			foreach (idx, p; params) {
				static if (!(idx % 2)) {
					// Parameter name
					static assert(is(typeof(p) == string), "Internal error ("~__FUNCTION__~"): Parameter name is not string.");
					nextName = p;
				} else {
					// Parameter value
					jsonBody[nextName] = serializeToJson(p);
				}
			}
			debug return jsonBody.toPrettyString();
			else return jsonBody.toString();
		}
	}
}

///
unittest
{
	import vibe.data.json;

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

	void test()
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

// Workaround for issue #1045 / DMD bug 14375
// Also, an example of policy-based design using this module.
unittest {
	import std.traits, std.typetuple;
	import vibe.internal.meta.codegen;
	import vibe.internal.meta.typetuple;

	interface Policies {
		@headerParam("auth", "Authorization")
		string BasicAuth(string auth, ulong expiry);
	}

	@path("/keys/")
	interface IKeys(alias AuthenticationPolicy = Policies.BasicAuth) {
		static assert(is(FunctionTypeOf!AuthenticationPolicy == function),
			      "Policies needs to be functions");
		@path("/") @method(HTTPMethod.POST)
		mixin CloneFunctionDecl!(AuthenticationPolicy, true, "create");
	}

	class KeysImpl : IKeys!() {
	override:
		string create(string auth, ulong expiry) {
			return "4242-4242";
		}
	}

	// Some sanity checks
        // Note: order is most likely implementation dependent.
	// Good thing we only have one frontend...
	alias WPA = WebParamAttribute;
	static assert(Compare!(
			      Group!(__traits(getAttributes, IKeys!().create)),
			      Group!(PathAttribute("/"),
				     MethodAttribute(HTTPMethod.POST),
				     WPA(WPA.Origin.Header, "auth", "Authorization"))));

	static if (__VERSION__ > 2065) {
		void register() {
			auto router = new URLRouter();
			router.registerRestInterface(new KeysImpl());
		}

		void query() {
			auto client = new RestInterfaceClient!(IKeys!())("http://127.0.0.1:8080");
			assert(client.create("Hello", 0) == "4242-4242");
		}
	}
}
