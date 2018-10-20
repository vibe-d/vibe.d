/**
	Internal module with common functionality for REST interface generators.

	Copyright: © 2015-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.internal.rest.common;

import vibe.http.common : HTTPMethod;
import vibe.web.rest;

import std.algorithm : endsWith, startsWith;
import std.meta : anySatisfy, Filter;
import std.traits : hasUDA;


/**
	Provides all necessary tools to implement an automated REST interface.

	The given `TImpl` must be an `interface` or a `class` deriving from one.
*/
/*package(vibe.web.web)*/ struct RestInterface(TImpl)
	if (is(TImpl == class) || is(TImpl == interface))
{
@safe:

	import std.traits : FunctionTypeOf, InterfacesTuple, MemberFunctionsTuple,
		ParameterIdentifierTuple, ParameterStorageClass,
		ParameterStorageClassTuple, ParameterTypeTuple, ReturnType;
	import std.typetuple : TypeTuple;
	import vibe.inet.url : URL;
	import vibe.internal.meta.funcattr : IsAttributedParameter;
	import vibe.internal.meta.traits : derivedMethod;
	import vibe.internal.meta.uda;

	/// The settings used to generate the interface
	RestInterfaceSettings settings;

	/// Full base path of the interface, including an eventual `@path` annotation.
	string basePath;

	/// Full base URL of the interface, including an eventual `@path` annotation.
	string baseURL;

	// determine the implementation interface I and check for validation errors
	private alias BaseInterfaces = InterfacesTuple!TImpl;
	static assert (BaseInterfaces.length > 0 || is (TImpl == interface),
		       "Cannot registerRestInterface type '" ~ TImpl.stringof
		       ~ "' because it doesn't implement an interface");
	static if (BaseInterfaces.length > 1)
		pragma(msg, "Type '" ~ TImpl.stringof ~ "' implements more than one interface: make sure the one describing the REST server is the first one");


	static if (is(TImpl == interface))
		alias I = TImpl;
	else
		alias I = BaseInterfaces[0];
	static assert(getInterfaceValidationError!I is null, getInterfaceValidationError!(I));

	/// The name of each interface member
	enum memberNames = [__traits(allMembers, I)];

	/// Aliases to all interface methods
	alias AllMethods = GetAllMethods!();

	/** Aliases for each route method

		This tuple has the same number of entries as `routes`.
	*/
	alias RouteFunctions = GetRouteFunctions!();

	enum routeCount = RouteFunctions.length;

	/** Information about each route

		This array has the same number of fields as `RouteFunctions`
	*/
	Route[routeCount] routes;

	/// Static (compile-time) information about each route
	static if (routeCount) static const StaticRoute[routeCount] staticRoutes = computeStaticRoutes();
	else static const StaticRoute[0] staticRoutes;

	/** Aliases for each sub interface method

		This array has the same number of entries as `subInterfaces` and
		`SubInterfaceTypes`.
	*/
	alias SubInterfaceFunctions = GetSubInterfaceFunctions!();

	/** The type of each sub interface

		This array has the same number of entries as `subInterfaces` and
		`SubInterfaceFunctions`.
	*/
	alias SubInterfaceTypes = GetSubInterfaceTypes!();

	enum subInterfaceCount = SubInterfaceFunctions.length;

	/** Information about sub interfaces

		This array has the same number of entries as `SubInterfaceFunctions` and
		`SubInterfaceTypes`.
	*/
	SubInterface[subInterfaceCount] subInterfaces;


	/** Fills the struct with information.

		Params:
			settings = Optional settings object.
	*/
	this(RestInterfaceSettings settings, bool is_client)
	{
		import vibe.internal.meta.uda : findFirstUDA;

		this.settings = settings ? settings.dup : new RestInterfaceSettings;
		if (this.settings.baseURL == URL.init && !is_client) {
			// use a valid dummy base URL to be able to construct sub-URLs
			// for nested interfaces
			this.settings.baseURL = URL("http://localhost/");
		}
		this.basePath = this.settings.baseURL.path.toString();

		enum uda = findFirstUDA!(PathAttribute, I);
		static if (uda.found) {
			static if (uda.value.data == "") {
				auto path = "/" ~ adjustMethodStyle(I.stringof, this.settings.methodStyle);
				this.basePath = concatURL(this.basePath, path);
			} else {
				this.basePath = concatURL(this.basePath, uda.value.data);
			}
		}

		if (this.settings.baseURL != URL.init)
		{
			URL bu = this.settings.baseURL;
			bu.pathString = this.basePath;
			this.baseURL = bu.toString();
		}
		else this.baseURL = this.basePath;

		computeRoutes();
		computeSubInterfaces();
	}

	// copying this struct is costly, so we forbid it
	@disable this(this);

	private void computeRoutes()
	{
		import std.algorithm.searching : any;

		foreach (si, RF; RouteFunctions) {
			enum sroute = staticRoutes[si];
			Route route;
			route.functionName = sroute.functionName;
			route.method = sroute.method;

			static if (sroute.pathOverride) route.pattern = sroute.rawName;
			else route.pattern = computeDefaultPath!RF(sroute.rawName);
			route.method = sroute.method;
			extractPathParts(route.fullPathParts, this.basePath.endsWith("/") ? this.basePath : this.basePath ~ "/");

			route.parameters.length = sroute.parameters.length;

			bool prefix_id = false;

			alias PT = ParameterTypeTuple!RF;
			foreach (i, _; PT) {
				enum sparam = sroute.parameters[i];
				Parameter pi;
				pi.name = sparam.name;
				pi.kind = sparam.kind;
				pi.isIn = sparam.isIn;
				pi.isOut = sparam.isOut;

				static if (sparam.kind != ParameterKind.attributed && sparam.fieldName.length == 0) {
					pi.fieldName = stripTUnderscore(pi.name, settings);
				} else pi.fieldName = sparam.fieldName;

				static if (i == 0 && sparam.name == "id") {
					prefix_id = true;
					if (route.pattern.length && route.pattern[0] != '/')
						route.pattern = '/' ~ route.pattern;
					route.pathParts ~= PathPart(true, "id");
					route.fullPathParts ~= PathPart(true, "id");
				}

				route.parameters[i] = pi;

				final switch (pi.kind) {
					case ParameterKind.query: route.queryParameters ~= pi; break;
					case ParameterKind.body_: route.bodyParameters ~= pi; break;
					case ParameterKind.wholeBody: route.wholeBodyParameter = pi; break;
					case ParameterKind.header: route.headerParameters ~= pi; break;
					case ParameterKind.internal: route.internalParameters ~= pi; break;
					case ParameterKind.attributed: route.attributedParameters ~= pi; break;
					case ParameterKind.auth: route.authParameters ~= pi; break;
				}
			}

			extractPathParts(route.pathParts, route.pattern);
			extractPathParts(route.fullPathParts, !prefix_id && route.pattern.startsWith("/") ? route.pattern[1 .. $] : route.pattern);
			if (prefix_id) route.pattern = ":id" ~ route.pattern;
			route.fullPattern = concatURL(this.basePath, route.pattern);
			route.pathHasPlaceholders = route.fullPathParts.any!(p => p.isParameter);

			routes[si] = route;
		}
	}

	/** Returns an array with routes grouped by path pattern
	*/
	auto getRoutesGroupedByPattern()
	{
		import std.algorithm : map, sort, filter, any;
		import std.array : array;
		import std.typecons : tuple;
		// since /foo/:bar and /foo/:baz are the same route, we first normalize the patterns (by replacing each param with just ':')
		// after that we sort and chunkBy/groupBy, in order to group the related route
		auto sorted = routes[].map!((route){
				return tuple(route,route.fullPathParts.map!((part){
					return part.isParameter ? ":" : part.text;
				}).array()); // can probably remove the array here if we rewrite the comparison functions (in sort and in the foreach) to work on ranges
			})
			.array
			.sort!((a,b) => a[1] < b[1]);

		typeof(sorted)[] groups;
		if (sorted.length > 0)
		{
			// NOTE: we want to support 2.066 but it doesn't have chunkBy, so we do the classic loop thingy
			size_t start, idx = 1;
			foreach(route, path; sorted[1..$])
			{
				if (sorted[idx-1][1] != path)
				{
					groups ~= sorted[start..idx];
					start = idx;
				}
				++idx;
			}
			groups ~= sorted[start..$];
		}

		return groups.map!(group => group.map!(tuple => tuple[0]));
	}

	private static StaticRoute[routeCount] computeStaticRoutes()
	{
		static import std.traits;
		import vibe.web.auth : AuthInfo;
		import std.algorithm.searching : any, count;
		import std.meta : AliasSeq;

		assert(__ctfe);

		StaticRoute[routeCount] ret;

		alias AUTHTP = AuthInfo!TImpl;

		foreach (fi, func; RouteFunctions) {
			StaticRoute route;
			route.functionName = __traits(identifier, func);

			static if (!is(TImpl == I))
				alias cfunc = derivedMethod!(TImpl, func);
			else
				alias cfunc = func;

			alias FuncType = FunctionTypeOf!func;
			alias ParameterTypes = ParameterTypeTuple!FuncType;
			alias ReturnType = std.traits.ReturnType!FuncType;
			enum parameterNames = [ParameterIdentifierTuple!func];

			enum meta = extractHTTPMethodAndName!(func, false)();
			route.method = meta.method;
			route.rawName = meta.url;
			route.pathOverride = meta.hadPathUDA;

			foreach (i, PT; ParameterTypes) {
				enum pname = parameterNames[i];
				alias WPAT = UDATuple!(WebParamAttribute, func);

				// Comparison template for anySatisfy
				//template Cmp(WebParamAttribute attr) { enum Cmp = (attr.identifier == ParamNames[i]); }
				alias CompareParamName = GenCmp!("Loop"~func.mangleof, i, parameterNames[i]);
				mixin(CompareParamName.Decl);

				StaticParameter pi;
				pi.name = parameterNames[i];

				// determine in/out storage class
				enum SC = ParameterStorageClassTuple!func[i];
				static if (SC & ParameterStorageClass.out_) {
					pi.isOut = true;
				} else static if (SC & ParameterStorageClass.ref_) {
					pi.isIn = true;
					pi.isOut = true;
				} else {
					pi.isIn = true;
				}

				// determine parameter source/destination
				static if (is(PT == AUTHTP)) {
					pi.kind = ParameterKind.auth;
				} else static if (IsAttributedParameter!(func, pname)) {
					pi.kind = ParameterKind.attributed;
				} else static if (AliasSeq!(cfunc).length > 0 && IsAttributedParameter!(cfunc, pname)) {
					pi.kind = ParameterKind.attributed;
				} else static if (anySatisfy!(mixin(CompareParamName.Name), WPAT)) {
					alias PWPAT = Filter!(mixin(CompareParamName.Name), WPAT);
					pi.kind = PWPAT[0].origin;
					pi.fieldName = PWPAT[0].field;
					if (pi.kind == ParameterKind.body_ && pi.fieldName == "")
						pi.kind = ParameterKind.wholeBody;
				} else static if (pname.startsWith("_")) {
					pi.kind = ParameterKind.internal;
					pi.fieldName = parameterNames[i][1 .. $];
				} else static if (i == 0 && pname == "id") {
					pi.kind = ParameterKind.internal;
					pi.fieldName = "id";
				} else {
					pi.kind = route.method == HTTPMethod.GET ? ParameterKind.query : ParameterKind.body_;
				}

				route.parameters ~= pi;
			}

			auto nhb = route.parameters.count!(p => p.kind == ParameterKind.wholeBody);
			assert(nhb <= 1, "Multiple whole-body parameters defined for "~route.functionName~".");
			assert(nhb == 0 || !route.parameters.any!(p => p.kind == ParameterKind.body_),
				"Normal body parameters and a whole-body parameter defined at the same time for "~route.functionName~".");

			ret[fi] = route;
		}

		return ret;
	}

	private void computeSubInterfaces()
	{
		foreach (i, func; SubInterfaceFunctions) {
			enum meta = extractHTTPMethodAndName!(func, false)();

			static if (meta.hadPathUDA) string url = meta.url;
			else string url = computeDefaultPath!func(meta.url);

			SubInterface si;
			si.settings = settings.dup;
			si.settings.baseURL = URL(concatURL(this.baseURL, url, true));
			subInterfaces[i] = si;
		}

		assert(subInterfaces.length == SubInterfaceFunctions.length);
	}

	private template GetSubInterfaceFunctions() {
		template Impl(size_t idx) {
			static if (idx < AllMethods.length) {
				alias SI = SubInterfaceType!(AllMethods[idx]);
				static if (!is(SI == void)) {
					alias Impl = TypeTuple!(AllMethods[idx], Impl!(idx+1));
				} else {
					alias Impl = Impl!(idx+1);
				}
			} else alias Impl = TypeTuple!();
		}
		alias GetSubInterfaceFunctions = Impl!0;
	}

	private template GetSubInterfaceTypes() {
		template Impl(size_t idx) {
			static if (idx < AllMethods.length) {
				alias SI = SubInterfaceType!(AllMethods[idx]);
				static if (!is(SI == void)) {
					alias Impl = TypeTuple!(SI, Impl!(idx+1));
				} else {
					alias Impl = Impl!(idx+1);
				}
			} else alias Impl = TypeTuple!();
		}
		alias GetSubInterfaceTypes = Impl!0;
	}

	private template GetRouteFunctions() {
		template Impl(size_t idx) {
			static if (idx < AllMethods.length) {
				alias F = AllMethods[idx];
				alias SI = SubInterfaceType!F;
				static if (is(SI == void))
					alias Impl = TypeTuple!(F, Impl!(idx+1));
				else alias Impl = Impl!(idx+1);
			} else alias Impl = TypeTuple!();
		}
		alias GetRouteFunctions = Impl!0;
	}

	private template GetAllMethods() {
		template Impl(size_t idx) {
			static if (idx < memberNames.length) {
				enum name = memberNames[idx];
				// WORKAROUND #1045 / @@BUG14375@@
				static if (name.length != 0)
					alias Impl = TypeTuple!(Filter!(IsRouteMethod, MemberFunctionsTuple!(I, name)), Impl!(idx+1));
				else alias Impl = Impl!(idx+1);
			} else alias Impl = TypeTuple!();
		}
		alias GetAllMethods = Impl!0;
	}

	private string computeDefaultPath(alias method)(string name)
	{
		auto ret = adjustMethodStyle(stripTUnderscore(name, settings), settings.methodStyle);
		static if (is(I.CollectionIndices)) {
			alias IdxTypes = typeof(I.CollectionIndices.tupleof);
			alias PTypes = ParameterTypeTuple!method;
			enum has_index_param = PTypes.length >= IdxTypes.length && is(PTypes[0 .. IdxTypes.length] == IdxTypes);
			enum index_name = __traits(identifier, I.CollectionIndices.tupleof[$-1]);

			static if (has_index_param && index_name.startsWith("_"))
				ret = (":" ~ index_name[1 .. $] ~ "/").concatURL(ret);
		}
		return ret;
	}
}

private enum IsRouteMethod(alias M) = !hasUDA!(M, NoRouteAttribute);

struct Route {
	string functionName; // D name of the function
	HTTPMethod method;
	string pattern; // relative route path (relative to baseURL)
	string fullPattern; // absolute version of 'pattern'
	bool pathHasPlaceholders; // true if path/pattern contains any :placeholers
	PathPart[] pathParts; // path separated into text and placeholder parts
	PathPart[] fullPathParts; // full path separated into text and placeholder parts
	Parameter[] parameters;
	Parameter wholeBodyParameter;
	Parameter[] queryParameters;
	Parameter[] bodyParameters;
	Parameter[] headerParameters;
	Parameter[] attributedParameters;
	Parameter[] internalParameters;
	Parameter[] authParameters;
}

struct PathPart {
	/// interpret `text` as a parameter name (including the leading underscore) or as raw text
	bool isParameter;
	string text;
}

struct Parameter {
	ParameterKind kind;
	string name;
	string fieldName;
	bool isIn, isOut;
}

struct StaticRoute {
	string functionName; // D name of the function
	string rawName; // raw name as returned
	bool pathOverride; // @path UDA was used
	HTTPMethod method;
	StaticParameter[] parameters;
}

struct StaticParameter {
	ParameterKind kind;
	string name;
	string fieldName; // only set for parameters where the field name can be statically determined - use Parameter.fieldName in usual cases
	bool isIn, isOut;
}

enum ParameterKind {
	query,       // req.query[]
	body_,       // JSON body (single field)
	wholeBody,   // JSON body
	header,      // req.header[]
	attributed,  // @before
	internal,    // req.params[]
	auth         // @authrorized!T
}

struct SubInterface {
	RestInterfaceSettings settings;
}

template SubInterfaceType(alias F) {
	import std.traits : ReturnType, isInstanceOf;
	alias RT = ReturnType!F;
	static if (is(RT == interface)) alias SubInterfaceType = RT;
	else static if (isInstanceOf!(Collection, RT)) alias SubInterfaceType = RT.Interface;
	else alias SubInterfaceType = void;
}

private bool extractPathParts(ref PathPart[] parts, string pattern)
@safe {
	import std.string : indexOf;

	string p = pattern;

	bool has_placeholders = false;

	void addText(string str) {
		if (parts.length > 0 && !parts[$-1].isParameter)
			parts[$-1].text ~= str;
		else parts ~= PathPart(false, str);
	}

	while (p.length) {
		auto cidx = p.indexOf(':');
		if (cidx < 0) break;
		if (cidx > 0) addText(p[0 .. cidx]);
		p = p[cidx+1 .. $];

		auto sidx = p.indexOf('/');
		if (sidx < 0) sidx = p.length;
		assert(sidx > 0, "Empty path placeholders are illegal.");
		parts ~= PathPart(true, "_" ~ p[0 .. sidx]);
		has_placeholders = true;
		p = p[sidx .. $];
	}

	if (p.length) addText(p);

	return has_placeholders;
}

unittest {
	interface IDUMMY { void test(int dummy); }
	class DUMMY : IDUMMY { void test(int) {} }
	auto test = RestInterface!DUMMY(null, false);
}

unittest {
	interface IDUMMY {}
	class DUMMY : IDUMMY {}
	auto test = RestInterface!DUMMY(null, false);
}

unittest {
	interface I {
		void a();
		@path("foo") void b();
		void c(int id);
		@path("bar") void d(int id);
		@path(":baz") void e(int _baz);
		@path(":foo/:bar/baz") void f(int _foo, int _bar);
	}

	auto test = RestInterface!I(null, false);

	assert(test.routeCount == 6);
	assert(test.routes[0].pattern == "a");
	assert(test.routes[0].fullPattern == "/a");
	assert(test.routes[0].pathParts == [PathPart(false, "a")]);
	assert(test.routes[0].fullPathParts == [PathPart(false, "/a")]);

	assert(test.routes[1].pattern == "foo");
	assert(test.routes[1].fullPattern == "/foo");
	assert(test.routes[1].pathParts == [PathPart(false, "foo")]);
	assert(test.routes[1].fullPathParts == [PathPart(false, "/foo")]);

	assert(test.routes[2].pattern == ":id/c");
	assert(test.routes[2].fullPattern == "/:id/c");
	assert(test.routes[2].pathParts == [PathPart(true, "id"), PathPart(false, "/c")]);
	assert(test.routes[2].fullPathParts == [PathPart(false, "/"), PathPart(true, "id"), PathPart(false, "/c")]);

	assert(test.routes[3].pattern == ":id/bar");
	assert(test.routes[3].fullPattern == "/:id/bar");
	assert(test.routes[3].pathParts == [PathPart(true, "id"), PathPart(false, "/bar")]);
	assert(test.routes[3].fullPathParts == [PathPart(false, "/"), PathPart(true, "id"), PathPart(false, "/bar")]);

	assert(test.routes[4].pattern == ":baz");
	assert(test.routes[4].fullPattern == "/:baz");
	assert(test.routes[4].pathParts == [PathPart(true, "_baz")]);
	assert(test.routes[4].fullPathParts == [PathPart(false, "/"), PathPart(true, "_baz")]);

	assert(test.routes[5].pattern == ":foo/:bar/baz");
	assert(test.routes[5].fullPattern == "/:foo/:bar/baz");
	assert(test.routes[5].pathParts == [PathPart(true, "_foo"), PathPart(false, "/"), PathPart(true, "_bar"), PathPart(false, "/baz")]);
	assert(test.routes[5].fullPathParts == [PathPart(false, "/"), PathPart(true, "_foo"), PathPart(false, "/"), PathPart(true, "_bar"), PathPart(false, "/baz")]);
}

unittest {
	// Note: the RestInterface generates routes in a specific order.
	// since the assertions below also (indirectly) test ordering,
	// the assertions might trigger when the ordering of the routes
	// generated by the RestInterface changes.
	interface Options {
		@path("a") void getA();
		@path("a") void setA();
		@path("bar/:param") void setFoo(int _param);
		@path("bar/:marap") void addFoo(int _marap);
		void addFoo();
		void getFoo();
	}

	auto test = RestInterface!Options(null, false);
	import std.array : array;
	import std.algorithm : map;
	import std.range : dropOne, front;
	auto options = test.getRoutesGroupedByPattern.array;

	assert(options.length == 3);
	assert(options[0].front.fullPattern == "/a");
	assert(options[0].dropOne.front.fullPattern == "/a");
	assert(options[0].map!(route=>route.method).array == [HTTPMethod.GET,HTTPMethod.PUT]);

	assert(options[1].front.fullPattern == "/bar/:param");
	assert(options[1].dropOne.front.fullPattern == "/bar/:marap");
	assert(options[1].map!(route=>route.method).array == [HTTPMethod.PUT,HTTPMethod.POST]);

	assert(options[2].front.fullPattern == "/foo");
	assert(options[2].dropOne.front.fullPattern == "/foo");
	assert(options[2].map!(route=>route.method).array == [HTTPMethod.POST,HTTPMethod.GET]);
}

unittest {
	@rootPathFromName
	interface Foo
	{
		string bar();
	}

	auto test = RestInterface!Foo(null, false);

	assert(test.routeCount == 1);
	assert(test.routes[0].pattern == "bar");
	assert(test.routes[0].fullPattern == "/foo/bar");
	assert(test.routes[0].pathParts == [PathPart(false, "bar")]);
	assert(test.routes[0].fullPathParts == [PathPart(false, "/foo/bar")]);
}

unittest {
	@path("/foo/")
	interface Foo
	{
		@path("/bar/")
		string bar();
	}

	auto test = RestInterface!Foo(null, false);

	assert(test.routeCount == 1);
	assert(test.routes[0].pattern == "/bar/");
	assert(test.routes[0].fullPattern == "/foo/bar/");
	assert(test.routes[0].pathParts == [PathPart(false, "/bar/")]);
	assert(test.routes[0].fullPathParts == [PathPart(false, "/foo/bar/")]);
}

unittest { // #1285
	interface I {
		@headerParam("b", "foo") @headerParam("c", "bar")
		void a(int a, out int b, ref int c);
	}
	alias RI = RestInterface!I;
	static assert(RI.staticRoutes[0].parameters[0].name == "a");
	static assert(RI.staticRoutes[0].parameters[0].isIn && !RI.staticRoutes[0].parameters[0].isOut);
	static assert(RI.staticRoutes[0].parameters[1].name == "b");
	static assert(!RI.staticRoutes[0].parameters[1].isIn && RI.staticRoutes[0].parameters[1].isOut);
	static assert(RI.staticRoutes[0].parameters[2].name == "c");
	static assert(RI.staticRoutes[0].parameters[2].isIn && RI.staticRoutes[0].parameters[2].isOut);
}

unittest {
	interface Baz {
		struct CollectionIndices {
			string _barid;
			int _bazid;
		}

		void test(string _barid, int _bazid);
		void test2(string _barid);
	}

	interface Bar {
		struct CollectionIndices {
			string _barid;
		}

		Collection!Baz baz(string _barid);

		void test(string _barid);
		void test2();
	}

	interface Foo {
		Collection!Bar bar();
	}

	auto foo = RestInterface!Foo(null, false);
	assert(foo.subInterfaceCount == 1);

	auto bar = RestInterface!Bar(foo.subInterfaces[0].settings, false);
	assert(bar.routeCount == 2);
	assert(bar.routes[0].fullPattern == "/bar/:barid/test");
	assert(bar.routes[0].pathHasPlaceholders);
	assert(bar.routes[1].fullPattern == "/bar/test2", bar.routes[1].fullPattern);
	assert(!bar.routes[1].pathHasPlaceholders);
	assert(bar.subInterfaceCount == 1);

	auto baz = RestInterface!Baz(bar.subInterfaces[0].settings, false);
	assert(baz.routeCount == 2);
	assert(baz.routes[0].fullPattern == "/bar/:barid/baz/:bazid/test");
	assert(baz.routes[0].pathHasPlaceholders);
	assert(baz.routes[1].fullPattern == "/bar/:barid/baz/test2");
	assert(baz.routes[1].pathHasPlaceholders);
}

unittest { // #1648
	import vibe.web.auth;

	struct AI {}

	@requiresAuth!AI
	interface I {
		void a();
	}
	alias RI = RestInterface!I;
}

unittest {
	interface I1 { @bodyParam("foo") void a(int foo); }
	alias RI = RestInterface!I1;
	interface I2 { @bodyParam("foo") void a(int foo, int bar); }
	interface I3 { @bodyParam("foo") @bodyParam("bar") void a(int foo, int bar); }
	static assert(__traits(compiles, RestInterface!I1.init));
	static assert(!__traits(compiles, RestInterface!I2.init));
	static assert(!__traits(compiles, RestInterface!I3.init));
}

unittest {
	import vibe.http.server : HTTPServerResponse, HTTPServerRequest;
	int foocomp(HTTPServerRequest, HTTPServerResponse) { return 42; }
	interface I { void test(int foo); }
	class C : I { @before!foocomp("foo") void test(int foo) { assert(foo == 42); }}
	alias RI = RestInterface!C;
	static assert(RI.staticRoutes[0].parameters[0].kind == ParameterKind.attributed);
}
