/* This example module consists from several small example REST interfaces.
 * Features are not grouped by topic but by common their are needed. Each example
 * introduces few new more advanced features. Sometimes registration code in module constructor
 * is also important, it is then mentioned in example comment explicitly.
 */

import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import vibe.http.rest;
import vibe.http.router;
import vibe.http.server;

import core.time;

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

	/* "Index" is special method name. Its matching url path is "/", not "/index"
	 * HTTP method selection remains the same.
	 *
	 * Resulting matching request: "GET /"
	 */
	string index();

	/* Parameters are supported in a similar fashion.
	 * Despite this is only an interface, make sure parameter names are not omitted, those are used for serialization.
	 * If it is a GET reuqest, parameters are embedded into query URL.
	 * Stored in POST data for POST, of course.
	 */
	int postSum(int a, int b);

	/* @property getters are always GET. @property setters are always PUT.
	 * All supported convention prefixes are documentated : http://vibed.org/api/vibe.http.rest/registerRestInterface
	 * Rather obvious and thus omitted in this example interface.
	 */
}

class Example1 : Example1API
{
	override: // use of this handy D feature is highly recommended
		string getSomeInfo()
		{
			return "Some Info!";
		}

		string index()
		{
			return "Index!";
		}

		int postSum(int a, int b)
		{
			return a + b;
		}
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
	 * Macthing request for this function will be "GET /ACCUMULATE_ALL?input=<encoded json data>"
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
			return reduce!( (a, b) => Aggregate(a.name ~ b.name, a.count + b.count, Aggregate.Type.Type3) )(Aggregate.init, input);
		}
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
	 */
	int getNumber();
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
		int getNumber()
		{
			return 42;
		}
}

/* If pre-defined conventions do not suit your needs, you can configure url and method
 * precisely via User Defined Attributes.
 */
@rootPathFromName
interface Example4API
{
	/* vibe.http.rest module provides two pre-defined UDA - @path and @method
	 * You can use any one of those or both. In case @path is used, not method style
	 * adjustment is made.
	 */
	@path("simple") @method(HttpMethod.POST)
	void myNameDoesNotMatter();

	/* Only @path is used here, so HTTP method is deduced in usual way (GET)
	 * vibe.d does usual pattern matching on path and stores path parts marked with ":"
	 * in request parameters. If function parameter starts with "_" and matches one
	 * of stored request parameters, expected things happen.
	 */
	@path(":param/:another_param/data")
	int getParametersInURL(string _param, string _another_param);
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

	auto settings = new HTTPServerSettings();
	settings.port = 8080;

	listenHTTP(settings, routes);

	/* At this moment, server is prepared to process requests.
	 * After a small delay to let socket become ready, the very same D interfaces
	 * will be used to define some form of Remote Procedure Calling via HTTP in client code.
	 * 
	 * It greatly simplifies writing client applications and gurantees that server and client API
	 * will always stay in sync. Care about method style naming convention mismatch though.
	 */
	setTimer(dur!"seconds"(1), {
		logInfo("Starting communication with REST interface. Use capture tool (i.e. wireshark) to check how it looks on HTTP protocol level");
		// Example 1
		{
			auto api = new RestInterfaceClient!Example1API("http://127.0.0.1:8080");
			assert(api.getSomeInfo() == "Some Info!");
			assert(api.index() == "Index!");
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
		}
		// Example 4
		{
			auto api = new RestInterfaceClient!Example4API("http://127.0.0.1:8080");
			api.myNameDoesNotMatter();
			assert(api.getParametersInURL("20", "30") == 50);
		}
		logInfo("Success.");
	});
}
