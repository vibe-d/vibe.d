module vibe.web.something;

import vibe.http.router;
import vibe.web.common;

void register (T) (URLRouter router, T app)
	if (is (T == class))
{
	static bool isUserMethod(string name)
	{
		class Empty { }
		import std.algorithm : canFind;
		return !canFind([__traits(allMembers, Empty)], name);
	}

	import vibe.internal.meta.uda : findFirstUDA;

	foreach (method_name; __traits(allMembers, T)) {
		static if (isUserMethod(method_name)) {
			mixin ("alias method    = app." ~ method_name ~ ";");
			mixin ("auto  method_dg = &app." ~ method_name ~ ";");

			static assert (is(
				typeof(method_dg) ==
					void delegate (HTTPServerRequest, HTTPServerResponse)
			));

			enum http = findFirstUDA!(MethodAttribute, method);
			enum path = findFirstUDA!(PathAttribute, method);

			static if (path.found) {
				static if (http.found) {
					switch (http.value.data) {
						case HTTPMethod.GET:
							router.get(path.value, method_dg);
							break;
						case HTTPMethod.POST:
							router.post(path.value, method_dg);
							break;
						case HTTPMethod.DELETE:
							router.delete_(path.value, method_dg);
							break;
						case HTTPMethod.PATCH:
							router.patch(path.value, method_dg);
							break;
						case HTTPMethod.PUT:
							router.put(path.value, method_dg);
							break;
						default:
							assert (false);
					}
				}
				else {
					router.any(path.value, method_dg);
				}
			}
		}
	}
}

unittest
{
	// default method (any)

	class WebApp
	{
		@path("/something")
		void handler(HTTPServerRequest req, HTTPServerResponse res) { }
	}

	auto app = new WebApp;
	auto router = new URLRouter;
	router.register(app);

	auto routes = router.getAllRoutes();

	import std.traits : EnumMembers;
	import std.conv;
	assert (routes.length == EnumMembers!HTTPMethod.length, to!string(routes.length));
}

unittest
{
	// explicit method

	class WebApp
	{
		@path("/42") @method(HTTPMethod.GET)
		void f1(HTTPServerRequest req, HTTPServerResponse res) { }

		@path("/43") @method(HTTPMethod.PUT)
		void f2(HTTPServerRequest req, HTTPServerResponse res) { }

		@path("/44") @method(HTTPMethod.POST)
		void f3(HTTPServerRequest req, HTTPServerResponse res) { }

		@path("/45") @method(HTTPMethod.PATCH)
		void f4(HTTPServerRequest req, HTTPServerResponse res) { }

		@path("/46") @method(HTTPMethod.DELETE)
		void f5(HTTPServerRequest req, HTTPServerResponse res) { }
	}

	auto app = new WebApp;
	auto router = new URLRouter;
	router.register(app);

	auto routes = router.getAllRoutes();
	assert (routes[0].method == HTTPMethod.GET
		&& routes[0].pattern == "/42");
	assert (routes[1].method == HTTPMethod.PUT
		&& routes[1].pattern == "/43");
	assert (routes[2].method == HTTPMethod.POST
		&& routes[2].pattern == "/44");
	assert (routes[3].method == HTTPMethod.PATCH
		&& routes[3].pattern == "/45");
	assert (routes[4].method == HTTPMethod.DELETE
		&& routes[4].pattern == "/46");
}
