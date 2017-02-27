/* This example module consists from several small example REST interfaces.
 * Features are not grouped by topic but by common their are needed. Each example
 * introduces few new more advanced features. Sometimes registration code in module constructor
 * is also important, it is then mentioned in example comment explicitly.
 */

import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.router;
import vibe.http.server;
import vibe.web.rest;

import core.time;
import std.typecons : Nullable;


/* --------- EXAMPLE 1 ---------- */

/* Very simple REST API interface. No additional configurations is used,
 * all HTTP-specific information is generated based on few conventions.
 *
 * All types are serialized and deserialized automatically by vibe.d framework using JSON.
 */
@rootPathFromName
interface Example1API
{
	/* Default convention is based on camelCase
	 */

	/* Used HTTP method is "GET" because function name start with "get".
	 * Remaining part is converted to lower case with words separated by _
	 *
	 * Resulting matching request: "GET /some_info"
	 */
	string getSomeInfo();

	/* Parameters are supported in a similar fashion.
	 * Despite this is only an interface, make sure parameter names are not omitted, those are used for serialization.
	 * If it is a GET request, parameters are embedded into query URL.
	 * Stored in POST data for POST, of course.
	 */
	int postSum(int a, int b);

	/* @property getters are always GET. @property setters are always PUT.
	 * All supported convention prefixes are documentated : http://vibed.org/api/vibe.web.rest/registerRestInterface
	 * Rather obvious and thus omitted in this example interface.
	 */
	@property string getter();
}

class Example1 : Example1API
{
	override: // usage of this handy D feature is highly recommended
		string getSomeInfo()
		{
			return "Some Info!";
		}

		int postSum(int a, int b)
		{
			return a + b;
		}

		@property
		string getter()
		{
			return "Getter";
		}
}

unittest
{
	auto router = new URLRouter;
	registerRestInterface(router, new Example1());
	auto routes = router.getAllRoutes();

	assert (routes[0].method == HTTPMethod.GET && routes[0].pattern == "/example1_api/some_info");
	assert (routes[1].method == HTTPMethod.POST && routes[1].pattern == "/example1_api/sum");
	assert (routes[2].method == HTTPMethod.GET && routes[2].pattern == "/example1_api/getter");
}

/* --------- EXAMPLE 2 ---------- */

/* Step forward. Using some compound types and query parameters.
 * Shows example usage of non-default naming convention, please check module constructor for details on this.
 * UpperUnderscore method style will be used.
 */
@rootPathFromName
interface Example2API
{
	// Any D data type may be here. Serializer is not configurable and will send all declared fields.
	// This should be an API-specified type and may or may not be the same as data type used by other application code.
	struct Aggregate
	{
		string name;
		uint count;

		enum Type
		{
			Type1,
			Type2,
			Type3
		}

		Type type;
	}

	/* As you may see, using aggregate types in parameters is just as easy.
	 * Matching request for this function will be "GET /ACCUMULATE_ALL?input=<encoded json data>"
	 * Answer will be of "application/json" type.
	 */
	Aggregate queryAccumulateAll(Aggregate[] input);
}

class Example2 : Example2API
{
	override:
		Aggregate queryAccumulateAll(Aggregate[] input)
		{
			import std.algorithm;
			// Some sweet functional D
			return reduce!(
				(a, b) => Aggregate(a.name ~ b.name, a.count + b.count, Aggregate.Type.Type3)
			)(Aggregate.init, input);
		}
}

unittest
{
	auto router = new URLRouter;
	registerRestInterface(router, new Example2(), MethodStyle.upperUnderscored);
	auto routes = router.getAllRoutes();

	assert (routes[0].method == HTTPMethod.GET && routes[0].pattern == "/EXAMPLE2_API/ACCUMULATE_ALL");
}

/* --------- EXAMPLE 3 ---------- */

/* Nested REST interfaces may be used to better match your D code structure with URL paths.
 * Nested interfaces must always be getter properties, this is statically enforced by rest module.
 *
 * Some limited form of URL parameters exists via special "id" parameter.
 */
@rootPathFromName
interface Example3API
{
	/* Available under ./nested_module/
	 */
	@property Example3APINested nestedModule();

	/* "id" is special parameter name that is parsed from URL. No special magic happens here,
	 * it uses usual vibe.d URL pattern matching functionality.
	 * GET /:id/myid
	 */
	int getMyID(int id);
}

interface Example3APINested
{
	/* In this example it will be available under "GET /nested_module/number"
	 * But this interface does't really know it, it does not care about exact path
	 *
	 * Default parameter values work as expected - they get used if there are no data
	 & for that parameter in request.
	 */
	int getNumber(int def_arg = 42);
}

class Example3 : Example3API
{
	private:
		Example3Nested m_nestedImpl;

	public:
		this()
		{
			m_nestedImpl = new Example3Nested();
		}

		override:
			int getMyID(int id)
			{
				return id;
			}

			@property Example3APINested nestedModule()
			{
				return m_nestedImpl;
			}
}

class Example3Nested : Example3APINested
{
	override:
		int getNumber(int def_arg)
		{
			return def_arg;
		}
}

unittest
{
	auto router = new URLRouter;
	registerRestInterface(router, new Example3());
	auto routes = router.getAllRoutes();

	assert (routes[0].method == HTTPMethod.GET && routes[0].pattern == "/example3_api/nested_module/number");
	assert (routes[1].method == HTTPMethod.GET && routes[1].pattern == "/example3_api/:id/myid");
}


/* If pre-defined conventions do not suit your needs, you can configure url and method
 * precisely via User Defined Attributes.
 */
@rootPathFromName
interface Example4API
{
	/* vibe.web.rest module provides two pre-defined UDA - @path and @method
	 * You can use any one of those or both. In case @path is used, not method style
	 * adjustment is made.
	 */
	@path("simple") @method(HTTPMethod.POST)
	void myNameDoesNotMatter();

	/* Only @path is used here, so HTTP method is deduced in usual way (GET)
	 * vibe.d does usual pattern matching on path and stores path parts marked with ":"
	 * in request parameters. If function parameter starts with "_" and matches one
	 * of stored request parameters, expected things happen.
	 */
	@path(":param/:another_param/data")
	int getParametersInURL(string _param, string _another_param);

	/* The underscore at the end of each parameter will be dropped in the
	 * protocol, so that D keywords, such as "body" or "in" can be used as
	 * identifiers.
	 */
	int querySpecialParameterNames(int body_, bool in_);
}

class Example4 : Example4API
{
	override:
		void myNameDoesNotMatter()
		{
		}

		int getParametersInURL(string _param, string _another_param)
		{
			import std.conv;
			return to!int(_param) + to!int(_another_param);
		}

		int querySpecialParameterNames(int body_, bool in_)
		{
			return body_ * (in_ ? -1 : 1);
		}
}

unittest
{
	auto router = new URLRouter;
	registerRestInterface(router, new Example4());
	auto routes = router.getAllRoutes();

	assert (routes[0].method == HTTPMethod.POST && routes[0].pattern == "/example4_api/simple");
	assert (routes[1].method == HTTPMethod.GET && routes[1].pattern == "/example4_api/:param/:another_param/data");
	assert (routes[2].method == HTTPMethod.GET && routes[2].pattern == "/example4_api/special_parameter_names");
}

/* It is possible to attach function hooks to methods via User-Define Attributes.
 *
 * Such hook must be a free function that
 *     1) accepts HTTPServerRequest and HTTPServerResponse
 *     2) is attached to specific parameter of a method
 *     3) has same return type as that parameter type
 *
 * REST API framework will call attached functions before actual
 * method call and use their result as an input to method call.
 *
 * There is also another attribute function type that can be called
 * to post-process method return value.
 *
 * Refer to `vibe.internal.meta.funcattr` for more details.
 */
@rootPathFromName
interface Example5API
{
	import vibe.web.rest : before, after;

	@before!authenticate("user") @after!addBrackets()
	string getSecret(int num, User user);
}

User authenticate(HTTPServerRequest req, HTTPServerResponse res)
{
	return User("admin", true);
}

struct User
{
	string name;
	bool authorized;
}

string addBrackets(string result, HTTPServerRequest, HTTPServerResponse)
{
	return "{" ~ result ~ "}";
}

class Example5 : Example5API
{
	string getSecret(int num, User user)
	{
		import std.conv : to;
		import std.string : format;

		if (!user.authorized)
			return "";

		return format("secret #%s for %s", num, user.name);
	}
}

unittest
{
	auto router = new URLRouter;
	registerRestInterface(router, new Example5());
	auto routes = router.getAllRoutes();

	assert (routes[0].method == HTTPMethod.GET && routes[0].pattern == "/example5_api/secret");
}

/**
 * The default convention of this module  is to pass parameters via:
 * - the URI for parameter starting with underscore (see example 4);
 * - query for GET/PUT requests;
 * - body for POST requests;
 *
 * This is configurable by means of:
 * - @headerParam : Get a parameter from the query header;
 * - @queryParam : Get a parameter from the query URL;
 * - @bodyParam : Get a parameter from the body;
 *
 * In addition, @headerParam have a special handling of 'out' and
 * 'ref' parameters:
 * - 'out' are neither send by the client nor read by the server, but
 *	their value (except for null string) is returned by the server.
 * - 'ref' are send by the client, read by the server, returned by
 *	the server, and read by the client.
 * This is to be consistent with the way D 'out' and 'ref' works.
 * However, it makes no sense to have 'ref' or 'out' parameters on
 * body or query parameter, so those are treated as error at compile time.
 *
 * If no Json fieldname is passed to @bodyParam, the entire Json body is deserialized into the respective field.
 */
@rootPathFromName
interface Example6API
{
	// The first parameter of @headerParam is the identifier (must match one of the parameter name).
	// The second is the name of the field in the header, such as "Accept", "Content-Type", "User-Agent"...
	@headerParam("auth", "Authorization")
	@headerParam("tester", "X-Custom-Tester")
	@headerParam("www", "WWW-Authenticate")
	string getPortal(string auth,
					 ref string tester,
					 out Nullable!string www);

	// As with @headerParam, the first parameter of @queryParam is the identifier.
	// The second being the field name, e.g for a query such as: 'GET /root/node?foo=bar', "foo" will be the second parameter.
	@queryParam("fortyTwo", "qparam")
	string postAnswer(string fortyTwo);
	// Finally, there is @bodyParam. It works as you expect it to work,
	// currently serializing passed data as Json and pass them through the body.
	@bodyParam("myFoo", "parameter")
	string postConcat(FooType myFoo);

	// If no field name is passed to @bodyParam the entire json object is
	// serialized into the parameter.
	// Moreover if only one bodyParameter is present, this is the default
	// behavior.
	@bodyParam("obj")
	string postConcatBody(FooType obj);

	struct FooType {
		int a;
		string s;
		double d;
	}
}

class Example6 : Example6API
{
override:
	string getPortal(string auth, ref string tester,
					 out Nullable!string www)
	{
		// For a string parameter, null means 'not returned'
		// If you want to return something empty, use "".
		if (tester == "Chell")
			tester = "The cake is a lie";
		else
			tester = null;

		// If the user provided credentials Aladdin / 'open sesame'
		if (auth == "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==")
			return "Hello, Caroline";

		www = `Basic realm="Aperture"`;
		throw new HTTPStatusException(401);
	}

	string postAnswer(string fortyTwo)
	{
		if (fortyTwo == "Life_universe_and_the_rest")
			return "True";
		return "False";
	}

	string postConcat(FooType myFoo)
	{
		import std.conv : to;
		return to!string(myFoo.a)~myFoo.s~to!string(myFoo.d);
	}

	string postConcatBody(FooType obj)
	{
		return postConcat(obj);
	}
}

unittest
{
	auto router = new URLRouter;
	registerRestInterface(router, new Example6());
	auto routes = router.getAllRoutes();

	assert (routes[0].method == HTTPMethod.GET && routes[0].pattern == "/example6_api/portal");
	assert (routes[1].method == HTTPMethod.POST && routes[1].pattern == "/example6_api/answer");
	assert (routes[0].method == HTTPMethod.GET && routes[2].pattern == "/example6_api/concat");
}

@rootPathFromName
interface Example7API {
	// GET /example7_api/
	// returns a custom JSON response
	Json get();
}

class Example7 : Example7API {
	Json get()
	{
		return serializeToJson(["foo": 42, "bar": 13]);
	}
}


shared static this()
{
	// Registering our REST services in router
	auto routes = new URLRouter;
	registerRestInterface(routes, new Example1());
	// note additional last parameter that defines used naming convention for compile-time introspection
	registerRestInterface(routes, new Example2(), MethodStyle.upperUnderscored);
	// naming style is default again, those can be router path specific.
	registerRestInterface(routes, new Example3());
	registerRestInterface(routes, new Example4());
	registerRestInterface(routes, new Example5());
	registerRestInterface(routes, new Example6());
	registerRestInterface(routes, new Example7());

	auto settings = new HTTPServerSettings();
	settings.port = 8080;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	listenHTTP(settings, routes);

	/* At this moment, server is prepared to process requests.
	 * After a small delay to let socket become ready, the very same D interfaces
	 * will be used to define some form of Remote Procedure Calling via HTTP in client code.
	 *
	 * It greatly simplifies writing client applications and gurantees that server and client API
	 * will always stay in sync. Care about method style naming convention mismatch though.
	 */
	setTimer(1.seconds, {
		scope(exit)
			exitEventLoop(true);

		logInfo("Starting communication with REST interface. Use capture tool (i.e. wireshark) to check how it looks on HTTP protocol level");
		// Example 1
		{
			auto api = new RestInterfaceClient!Example1API("http://127.0.0.1:8080");
			assert(api.getSomeInfo() == "Some Info!");
			assert(api.getter == "Getter");
			assert(api.postSum(2, 3) == 5);
		}
		// Example 2
		{
			auto api = new RestInterfaceClient!Example2API("http://127.0.0.1:8080", MethodStyle.upperUnderscored);
			Example2API.Aggregate[] data = [
				{ "one", 1, Example2API.Aggregate.Type.Type1 },
				{ "two", 2, Example2API.Aggregate.Type.Type2 }
			];
			auto accumulated = api.queryAccumulateAll(data);
			assert(accumulated.type == Example2API.Aggregate.Type.Type3);
			assert(accumulated.count == 3);
			assert(accumulated.name == "onetwo");
		}
		// Example 3
		{
			auto api = new RestInterfaceClient!Example3API("http://127.0.0.1:8080");
			assert(api.getMyID(9000) == 9000);
			assert(api.nestedModule.getNumber() == 42);
			assert(api.nestedModule.getNumber(1) == 1);
		}
		// Example 4
		{
			auto api = new RestInterfaceClient!Example4API("http://127.0.0.1:8080");
			api.myNameDoesNotMatter();
			assert(api.getParametersInURL("20", "30") == 50);
			assert(api.querySpecialParameterNames(10, true) == -10);
		}
		// Example 5
		{
			auto api = new RestInterfaceClient!Example5API("http://127.0.0.1:8080");
			auto secret = api.getSecret(42, User.init);
			assert(secret == "{secret #42 for admin}");
		}
		// Example 6
		{
			import vibe.http.client : requestHTTP;
			import vibe.stream.operations : readAllUTF8;

			auto api = new RestInterfaceClient!Example6API("http://127.0.0.1:8080");
			// First we make sure parameters are transmitted via headers.
			auto res = requestHTTP("http://127.0.0.1:8080/example6_api/portal",
			                       (scope r) {
				r.method = HTTPMethod.GET;
				r.headers["Authorization"] = "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==";
				r.headers["X-Custom-Tester"] = "GladOS";
			});

			assert(res.statusCode == 200);
			assert(!res.headers["X-Custom-Tester"].length, res.headers["X-Custom-Tester"]);
			assert(!("WWW-Authenticate" in res.headers), res.headers["WWW-Authenticate"]);
			assert(res.bodyReader.readAllUTF8() == `"Hello, Caroline"`);
			// Then we check that both can communicate together.
			string tester = "Chell";
			Nullable!string www;
			try {
				// We shouldn't reach the assert, this will throw
				auto answer = api.getPortal("Oops", tester, www);
				assert(0, answer);
			} catch (RestException e) {
				assert(tester == "The cake is a lie", tester);
				assert(www == `Basic realm="Aperture"`, www);
			}
		}

		// Example 6 -- Query
		{
			import vibe.http.client : requestHTTP;
			import vibe.stream.operations : readAllUTF8;

			// First we make sure parameters are transmitted via query.
			auto res = requestHTTP("http://127.0.0.1:8080/example6_api/answer?qparam=Life_universe_and_the_rest",
								   (scope r) { r.method = HTTPMethod.POST; });
			assert(res.statusCode == 200);
			assert(res.bodyReader.readAllUTF8() == `"True"`);
			// Then we check that both can communicate together.
			auto api = new RestInterfaceClient!Example6API("http://127.0.0.1:8080");
			auto answer = api.postAnswer("IDK");
			assert(answer == "False");

			Example6API.FooType fType = {a: 1, s: "str", d: 3.14};
			auto expected = "1str3.14";
			assert(api.postConcat(fType) == expected);
			assert(api.postConcatBody(fType) == expected);
		}

		// Example 7 -- Custom JSON response
		{
			auto api = new RestInterfaceClient!Example7API("http://127.0.0.1:8080");
			auto result = api.get();
			assert(result["foo"] == 42 && result["bar"] == 13);
		}

		// Example 6 -- Body
		{
			import vibe.http.client : requestHTTP;
			import vibe.stream.operations : readAllUTF8;

			enum expected = "42fortySomething51.42"; // to!string(51.42) doesn't work at CT

			auto api = new RestInterfaceClient!Example6API("http://127.0.0.1:8080");
			// First we make sure parameters are transmitted via query.
			auto res = requestHTTP("http://127.0.0.1:8080/example6_api/concat",
								   (scope r) {
							   import vibe.data.json;
							   r.method = HTTPMethod.POST;
							   Json obj = Json.emptyObject;
							   obj["parameter"] = serializeToJson(Example6API.FooType(42, "fortySomething", 51.42));
							   r.writeJsonBody(obj);
						   });

			assert(res.statusCode == 200);
			assert(res.bodyReader.readAllUTF8() == `"`~expected~`"`);
			// Then we check that both can communicate together.
			auto answer = api.postConcat(Example6API.FooType(42, "fortySomething", 51.42));
			assert(answer == expected);
		}

		logInfo("Success.");
	});
}
