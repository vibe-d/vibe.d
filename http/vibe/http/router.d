/**
	Pattern based URL router for HTTP request.

	See `URLRouter` for more details.

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.router;

public import vibe.http.server;

import vibe.core.log;

import std.functional;


/**
	Routes HTTP requests based on the request method and URL.

	Routes are matched using a special URL match string that supports two forms
	of placeholders. See the sections below for more details.

	Registered routes are matched according to the same sequence as initially
	specified using `match`, `get`, `post` etc. Matching ends as soon as a route
	handler writes a response using `res.writeBody()` or similar means. If no
	route matches or if no route handler writes a response, the router will
	simply not handle the request and the HTTP server will automatically
	generate a 404 error.

	Match_patterns:
		Match patterns are character sequences that can optionally contain
		placeholders or raw wildcards ("*"). Raw wild cards match any character
		sequence, while placeholders match only sequences containing no slash
		("/") characters.

		Placeholders are started using a colon (":") and are directly followed
		by their name. The first "/" character (or the end of the match string)
		denotes the end of the placeholder name. The part of the string that
		matches a placeholder will be stored in the `HTTPServerRequest.params`
		map using the placeholder name as the key.

		Match strings are subject to the following rules:
		$(UL
			$(LI A raw wildcard ("*") may only occur at the end of the match string)
			$(LI At least one character must be placed between any two placeholders or wildcards)
			$(LI The maximum allowed number of placeholders in a single match string is 64)
		)

	Match_String_Examples:
		$(UL
			$(LI `"/foo/bar"` matches only `"/foo/bar"` itself)
			$(LI `"/foo/*"` matches `"/foo/"`, `"/foo/bar"`, `"/foo/bar/baz"` or _any other string beginning with `"/foo/"`)
			$(LI `"/:x/"` matches `"/foo/"`, `"/bar/"` and similar strings (and stores `"foo"`/`"bar"` in `req.params["x"]`), but not `"/foo/bar/"`)
			$(LI Matching partial path entries with wildcards is possible: `"/foo:x"` matches `"/foo"`, `"/foobar"`, but not `"/foo/bar"`)
			$(LI Multiple placeholders and raw wildcards can be combined: `"/:x/:y/*"`)
		)
*/
final class URLRouter : HTTPServerRequestHandler {
	@safe:

	private {
		MatchTree!Route m_routes;
		string m_prefix;
		bool m_computeBasePath;
	}

	this(string prefix = null)
	{
		m_prefix = prefix;
	}

	/** Sets a common prefix for all registered routes.

		All routes will implicitly have this prefix prepended before being
		matched against incoming requests.
	*/
	@property string prefix() const { return m_prefix; }

	/** Controls the computation of the "routerRootDir" parameter.

		This parameter is available as `req.params["routerRootDir"]` and
		contains the relative path to the base path of the router. The base
		path is determined by the `prefix` property.

		Note that this feature currently is requires dynamic memory allocations
		and is opt-in for this reason.
	*/
	@property void enableRootDir(bool enable) { m_computeBasePath = enable; }

	/// Returns a single route handle to conveniently register multiple methods.
	URLRoute route(string path)
	in { assert(path.length, "Cannot register null or empty path!"); }
	body { return URLRoute(this, path); }

	///
	unittest {
		void getFoo(scope HTTPServerRequest req, scope HTTPServerResponse res) { /* ... */ }
		void postFoo(scope HTTPServerRequest req, scope HTTPServerResponse res) { /* ... */ }
		void deleteFoo(scope HTTPServerRequest req, scope HTTPServerResponse res) { /* ... */ }

		auto r = new URLRouter;

		// using 'with' statement
		with (r.route("/foo")) {
			get(&getFoo);
			post(&postFoo);
			delete_(&deleteFoo);
		}

		// using method chaining
		r.route("/foo")
			.get(&getFoo)
			.post(&postFoo)
			.delete_(&deleteFoo);

		// without using route()
		r.get("/foo", &getFoo);
		r.post("/foo", &postFoo);
		r.delete_("/foo", &deleteFoo);
	}

	/// Adds a new route for requests matching the specified HTTP method and pattern.
	URLRouter match(Handler)(HTTPMethod method, string path, Handler handler)
		if (isValidHandler!Handler)
	{
		import std.algorithm;
		assert(path.length, "Cannot register null or empty path!");
		assert(count(path, ':') <= maxRouteParameters, "Too many route parameters");
		logDebug("add route %s %s", method, path);
		m_routes.addTerminal(path, Route(method, path, handlerDelegate(handler)));
		return this;
	}

	/// ditto
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestDelegate handler)
	{
		return match!HTTPServerRequestDelegate(method, path, handler);
	}

	/// Adds a new route for GET requests matching the specified pattern.
	URLRouter get(Handler)(string url_match, Handler handler) if (isValidHandler!Handler) { return match(HTTPMethod.GET, url_match, handler); }
	/// ditto
	URLRouter get(string url_match, HTTPServerRequestDelegate handler) { return match(HTTPMethod.GET, url_match, handler); }

	/// Adds a new route for POST requests matching the specified pattern.
	URLRouter post(Handler)(string url_match, Handler handler) if (isValidHandler!Handler) { return match(HTTPMethod.POST, url_match, handler); }
	/// ditto
	URLRouter post(string url_match, HTTPServerRequestDelegate handler) { return match(HTTPMethod.POST, url_match, handler); }

	/// Adds a new route for PUT requests matching the specified pattern.
	URLRouter put(Handler)(string url_match, Handler handler) if (isValidHandler!Handler) { return match(HTTPMethod.PUT, url_match, handler); }
	/// ditto
	URLRouter put(string url_match, HTTPServerRequestDelegate handler) { return match(HTTPMethod.PUT, url_match, handler); }

	/// Adds a new route for DELETE requests matching the specified pattern.
	URLRouter delete_(Handler)(string url_match, Handler handler) if (isValidHandler!Handler) { return match(HTTPMethod.DELETE, url_match, handler); }
	/// ditto
	URLRouter delete_(string url_match, HTTPServerRequestDelegate handler) { return match(HTTPMethod.DELETE, url_match, handler); }

	/// Adds a new route for PATCH requests matching the specified pattern.
	URLRouter patch(Handler)(string url_match, Handler handler) if (isValidHandler!Handler) { return match(HTTPMethod.PATCH, url_match, handler); }
	/// ditto
	URLRouter patch(string url_match, HTTPServerRequestDelegate handler) { return match(HTTPMethod.PATCH, url_match, handler); }

	/// Adds a new route for requests matching the specified pattern, regardless of their HTTP verb.
	URLRouter any(Handler)(string url_match, Handler handler)
	{
		import std.traits;
		static HTTPMethod[] all_methods = [EnumMembers!HTTPMethod];
		foreach(immutable method; all_methods)
			match(method, url_match, handler);

		return this;
	}
	/// ditto
	URLRouter any(string url_match, HTTPServerRequestDelegate handler) { return any!HTTPServerRequestDelegate(url_match, handler); }


	/** Rebuilds the internal matching structures to account for newly added routes.

		This should be used after a lot of routes have been added to the router, to
		force eager computation of the match structures. The alternative is to
		let the router lazily compute the structures when the first request happens,
		which can delay this request.
	*/
	void rebuild()
	{
		m_routes.rebuildGraph();
	}

	/// Handles a HTTP request by dispatching it to the registered route handlers.
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto method = req.method;

		string calcBasePath()
		@safe {
			import vibe.inet.path;
			auto p = InetPath(prefix.length ? prefix : "/");
			p.endsWithSlash = true;
			return p.relativeToWeb(InetPath(req.path)).toString();
		}

		auto path = req.path;
		if (path.length < m_prefix.length || path[0 .. m_prefix.length] != m_prefix) return;
		path = path[m_prefix.length .. $];

		while (true) {
			bool done = m_routes.match(path, (ridx, scope values) @safe {
				auto r = () @trusted { return &m_routes.getTerminalData(ridx); } ();
				if (r.method != method) return false;

				logDebugV("route match: %s -> %s %s %s", req.path, r.method, r.pattern, values);
				foreach (i, v; values) req.params[m_routes.getTerminalVarNames(ridx)[i]] = v;
				if (m_computeBasePath) req.params["routerRootDir"] = calcBasePath();
				r.cb(req, res);
				return res.headerWritten;
			});
			if (done) return;

			if (method == HTTPMethod.HEAD) method = HTTPMethod.GET;
			else break;
		}

		logDebug("no route match: %s %s", req.method, req.requestURL);
	}

	/// Returns all registered routes as const AA
	const(Route)[] getAllRoutes()
	{
		auto routes = new Route[m_routes.terminalCount];
		foreach (i, ref r; routes)
			r = m_routes.getTerminalData(i);
		return routes;
	}

	template isValidHandler(Handler) {
		@system {
			alias USDel = void delegate(HTTPServerRequest, HTTPServerResponse) @system;
			alias USFun = void function(HTTPServerRequest, HTTPServerResponse) @system;
			alias USDelS = void delegate(scope HTTPServerRequest, scope HTTPServerResponse) @system;
			alias USFunS = void function(scope HTTPServerRequest, scope HTTPServerResponse) @system;
		}

		static if (
				is(Handler : HTTPServerRequestDelegate) ||
				is(Handler : HTTPServerRequestFunction) ||
				is(Handler : HTTPServerRequestHandler) ||
				is(Handler : HTTPServerRequestDelegateS) ||
				is(Handler : HTTPServerRequestFunctionS) ||
				is(Handler : HTTPServerRequestHandlerS)
			)
		{
			enum isValidHandler = true;
		} else static if (
				is(Handler : USDel) || is(Handler : USFun) ||
				is(Handler : USDelS) || is(Handler : USFunS)
			)
		{
			enum isValidHandler = true;
		} else {
			enum isValidHandler = false;
		}
	}

	static void delegate(HTTPServerRequest, HTTPServerResponse) @safe handlerDelegate(Handler)(Handler handler)
	{
		import std.traits : isFunctionPointer;
		static if (isFunctionPointer!Handler) return handlerDelegate(() @trusted { return toDelegate(handler); } ());
		else static if (is(Handler == class) || is(Handler == interface)) return &handler.handleRequest;
		else static if (__traits(compiles, () @safe { handler(HTTPServerRequest.init, HTTPServerResponse.init); } ())) return handler;
		else return (req, res) @trusted { handler(req, res); };
	}

	unittest {
		static assert(isValidHandler!HTTPServerRequestFunction);
		static assert(isValidHandler!HTTPServerRequestDelegate);
		static assert(isValidHandler!HTTPServerRequestHandler);
		static assert(isValidHandler!HTTPServerRequestFunctionS);
		static assert(isValidHandler!HTTPServerRequestDelegateS);
		static assert(isValidHandler!HTTPServerRequestHandlerS);
		static assert(isValidHandler!(void delegate(HTTPServerRequest req, HTTPServerResponse res) @system));
		static assert(isValidHandler!(void function(HTTPServerRequest req, HTTPServerResponse res) @system));
		static assert(isValidHandler!(void delegate(scope HTTPServerRequest req, scope HTTPServerResponse res) @system));
		static assert(isValidHandler!(void function(scope HTTPServerRequest req, scope HTTPServerResponse res) @system));
		static assert(!isValidHandler!(int delegate(HTTPServerRequest req, HTTPServerResponse res) @system));
		static assert(!isValidHandler!(int delegate(HTTPServerRequest req, HTTPServerResponse res) @safe));
		void test(H)(H h)
		{
			static assert(isValidHandler!H);
		}
		test((HTTPServerRequest req, HTTPServerResponse res) {});
	}
}

///
@safe unittest {
	import vibe.http.fileserver;

	void addGroup(HTTPServerRequest req, HTTPServerResponse res)
	{
		// Route variables are accessible via the params map
		logInfo("Getting group %s for user %s.", req.params["groupname"], req.params["username"]);
	}

	void deleteUser(HTTPServerRequest req, HTTPServerResponse res)
	{
		// ...
	}

	void auth(HTTPServerRequest req, HTTPServerResponse res)
	{
		// TODO: check req.session to see if a user is logged in and
		//       write an error page or throw an exception instead.
	}

	void setup()
	{
		auto router = new URLRouter;
		// Matches all GET requests for /users/*/groups/* and places
		// the place holders in req.params as 'username' and 'groupname'.
		router.get("/users/:username/groups/:groupname", &addGroup);

		// Matches all requests. This can be useful for authorization and
		// similar tasks. The auth method will only write a response if the
		// user is _not_ authorized. Otherwise, the router will fall through
		// and continue with the following routes.
		router.any("*", &auth);

		// Matches a POST request
		router.post("/users/:username/delete", &deleteUser);

		// Matches all GET requests in /static/ such as /static/img.png or
		// /static/styles/sty.css
		router.get("/static/*", serveStaticFiles("public/"));

		// Setup a HTTP server...
		auto settings = new HTTPServerSettings;
		// ...

		// The router can be directly passed to the listenHTTP function as
		// the main request handler.
		listenHTTP(settings, router);
	}
}

/** Using nested routers to map components to different sub paths. A component
	could for example be an embedded blog engine.
*/
@safe unittest {
	// some embedded component:

	void showComponentHome(HTTPServerRequest req, HTTPServerResponse res)
	{
		// ...
	}

	void showComponentUser(HTTPServerRequest req, HTTPServerResponse res)
	{
		// ...
	}

	void registerComponent(URLRouter router)
	{
		router.get("/", &showComponentHome);
		router.get("/users/:user", &showComponentUser);
	}

	// main application:

	void showHome(HTTPServerRequest req, HTTPServerResponse res)
	{
		// ...
	}

	void setup()
	{
		auto c1router = new URLRouter("/component1");
		registerComponent(c1router);

		auto mainrouter = new URLRouter;
		mainrouter.get("/", &showHome);
		// forward all unprocessed requests to the component router
		mainrouter.any("*", c1router);

		// now the following routes will be matched:
		// / -> showHome
		// /component1/ -> showComponentHome
		// /component1/users/:user -> showComponentUser

		// Start the HTTP server
		auto settings = new HTTPServerSettings;
		// ...
		listenHTTP(settings, mainrouter);
	}
}

@safe unittest { // issue #1668
	auto r = new URLRouter;
	r.get("/", (req, res) {
		if ("foo" in req.headers)
			res.writeBody("bar");
	});

	r.get("/", (scope req, scope res) {
		if ("foo" in req.headers)
			res.writeBody("bar");
	});
	r.get("/", (req, res) {});
	r.post("/", (req, res) {});
	r.put("/", (req, res) {});
	r.delete_("/", (req, res) {});
	r.patch("/", (req, res) {});
	r.any("/", (req, res) {});
}

@safe unittest { // issue #1866
	auto r = new URLRouter;
	r.match(HTTPMethod.HEAD, "/foo", (scope req, scope res) { res.writeVoidBody; });
	r.match(HTTPMethod.HEAD, "/foo", (req, res) { res.writeVoidBody; });
	r.match(HTTPMethod.HEAD, "/foo", (scope HTTPServerRequest req, scope HTTPServerResponse res) { res.writeVoidBody; });
	r.match(HTTPMethod.HEAD, "/foo", (HTTPServerRequest req, HTTPServerResponse res) { res.writeVoidBody; });

	auto r2 = new URLRouter;
	r.match(HTTPMethod.HEAD, "/foo", r2);
}

@safe unittest {
	import vibe.inet.url;

	auto router = new URLRouter;
	string result;
	void a(HTTPServerRequest req, HTTPServerResponse) { result ~= "A"; }
	void b(HTTPServerRequest req, HTTPServerResponse) { result ~= "B"; }
	void c(HTTPServerRequest req, HTTPServerResponse) { assert(req.params["test"] == "x", "Wrong variable contents: "~req.params["test"]); result ~= "C"; }
	void d(HTTPServerRequest req, HTTPServerResponse) { assert(req.params["test"] == "y", "Wrong variable contents: "~req.params["test"]); result ~= "D"; }
	router.get("/test", &a);
	router.post("/test", &b);
	router.get("/a/:test", &c);
	router.get("/a/:test/", &d);

	auto res = createTestHTTPServerResponse();
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/")), res);
	assert(result == "", "Matched for non-existent / path");
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/test")), res);
	assert(result == "A", "Didn't match a simple GET request");
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/test"), HTTPMethod.POST), res);
	assert(result == "AB", "Didn't match a simple POST request");
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/a/"), HTTPMethod.GET), res);
	assert(result == "AB", "Matched empty variable. "~result);
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/a/x"), HTTPMethod.GET), res);
	assert(result == "ABC", "Didn't match a trailing 1-character var.");
	// currently fails due to Path not accepting "//"
	//router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/a//"), HTTPMethod.GET), res);
	//assert(result == "ABC", "Matched empty string or slash as var. "~result);
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/a/y/"), HTTPMethod.GET), res);
	assert(result == "ABCD", "Didn't match 1-character infix variable.");
}

@safe unittest {
	import vibe.inet.url;

	auto router = new URLRouter("/test");

	string result;
	void a(HTTPServerRequest req, HTTPServerResponse) { result ~= "A"; }
	void b(HTTPServerRequest req, HTTPServerResponse) { result ~= "B"; }
	router.get("/x", &a);
	router.get("/y", &b);

	auto res = createTestHTTPServerResponse();
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/test")), res);
	assert(result == "");
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/test/x")), res);
	assert(result == "A");
	router.handleRequest(createTestHTTPServerRequest(URL("http://localhost/test/y")), res);
	assert(result == "AB");
}

@safe unittest {
	string ensureMatch(string pattern, string local_uri, string[string] expected_params = null)
	{
		import vibe.inet.url : URL;
		string ret = local_uri ~ " did not match " ~ pattern;
		auto r = new URLRouter;
		r.get(pattern, (req, res) {
			ret = null;
			foreach (k, v; expected_params) {
				if (k !in req.params) { ret = "Parameter "~k~" was not matched."; return; }
				if (req.params[k] != v) { ret = "Parameter "~k~" is '"~req.params[k]~"' instead of '"~v~"'."; return; }
			}
		});
		auto req = createTestHTTPServerRequest(URL("http://localhost"~local_uri));
		auto res = createTestHTTPServerResponse();
		r.handleRequest(req, res);
		return ret;
	}

	assert(ensureMatch("/foo bar/", "/foo%20bar/") is null);   // normalized pattern: "/foo%20bar/"
	//assert(ensureMatch("/foo%20bar/", "/foo%20bar/") is null); // normalized pattern: "/foo%20bar/"
	assert(ensureMatch("/foo/bar/", "/foo/bar/") is null);     // normalized pattern: "/foo/bar/"
	//assert(ensureMatch("/foo/bar/", "/foo%2fbar/") !is null);
	//assert(ensureMatch("/foo%2fbar/", "/foo%2fbar/") is null); // normalized pattern: "/foo%2Fbar/"
	//assert(ensureMatch("/foo%2Fbar/", "/foo%2fbar/") is null); // normalized pattern: "/foo%2Fbar/"
	//assert(ensureMatch("/foo%2fbar/", "/foo%2Fbar/") is null);
	//assert(ensureMatch("/foo%2fbar/", "/foo/bar/") !is null);
	//assert(ensureMatch("/:foo/", "/foo%2Fbar/", ["foo": "foo/bar"]) is null);
	assert(ensureMatch("/:foo/", "/foo/bar/") !is null);
}


/**
	Convenience abstraction for a single `URLRouter` route.

	See `URLRouter.route` for a usage example.
*/
struct URLRoute {
@safe:

	URLRouter router;
	string path;

	ref URLRoute get(Handler)(Handler h) { router.get(path, h); return this; }
	ref URLRoute post(Handler)(Handler h) { router.post(path, h); return this; }
	ref URLRoute put(Handler)(Handler h) { router.put(path, h); return this; }
	ref URLRoute delete_(Handler)(Handler h) { router.delete_(path, h); return this; }
	ref URLRoute patch(Handler)(Handler h) { router.patch(path, h); return this; }
	ref URLRoute any(Handler)(Handler h) { router.any(path, h); return this; }
	ref URLRoute match(Handler)(HTTPMethod method, Handler h) { router.match(method, path, h); return this; }
}


private enum maxRouteParameters = 64;

private struct Route {
	HTTPMethod method;
	string pattern;
	HTTPServerRequestDelegate cb;
}

private string skipPathNode(string str, ref size_t idx)
@safe {
	size_t start = idx;
	while( idx < str.length && str[idx] != '/' ) idx++;
	return str[start .. idx];
}

private string skipPathNode(ref string str)
@safe {
	size_t idx = 0;
	auto ret = skipPathNode(str, idx);
	str = str[idx .. $];
	return ret;
}

private struct MatchTree(T) {
@safe:

	import std.algorithm : countUntil;
	import std.array : array;

	private {
		alias NodeIndex = uint;
		alias TerminalTagIndex = uint;
		alias TerminalIndex = ushort;
		alias VarIndex = ushort;

		struct Node {
			TerminalTagIndex terminalsStart; // slice into m_terminalTags
			TerminalTagIndex terminalsEnd;
			NodeIndex[ubyte.max+1] edges = NodeIndex.max; // character -> index into m_nodes
		}
		struct TerminalTag {
			TerminalIndex index; // index into m_terminals array
			VarIndex var = VarIndex.max; // index into Terminal.varNames/varValues or VarIndex.max
		}
		struct Terminal {
			string pattern;
			T data;
			string[] varNames;
			VarIndex[NodeIndex] varMap;
		}
		Node[] m_nodes; // all nodes as a single array
		TerminalTag[] m_terminalTags;
		Terminal[] m_terminals;

		enum TerminalChar = 0;
		bool m_upToDate = false;
	}

	@property size_t terminalCount() const { return m_terminals.length; }

	void addTerminal(string pattern, T data)
	{
		assert(m_terminals.length < TerminalIndex.max, "Attempt to register too many routes.");
		m_terminals ~= Terminal(pattern, data, null, null);
		m_upToDate = false;
	}

	bool match(string text, scope bool delegate(size_t terminal, scope string[] vars) @safe del)
	{
		// lazily update the match graph
		if (!m_upToDate) rebuildGraph();

		return doMatch(text, del);
	}

	const(string)[] getTerminalVarNames(size_t terminal) const { return m_terminals[terminal].varNames; }
	ref inout(T) getTerminalData(size_t terminal) inout { return m_terminals[terminal].data; }

	void print()
	const {
		import std.algorithm : map;
		import std.array : join;
		import std.conv : to;
		import std.range : iota;
		import std.string : format;

		logInfo("Nodes:");
		foreach (i, n; m_nodes) {
			logInfo("  %s %s", i, m_terminalTags[n.terminalsStart .. n.terminalsEnd]
				.map!(t => format("T%s%s", t.index, t.var != VarIndex.max ? "("~m_terminals[t.index].varNames[t.var]~")" : "")).join(" "));
			//logInfo("  %s %s-%s", i, n.terminalsStart, n.terminalsEnd);


			static string mapChar(ubyte ch) {
				if (ch == TerminalChar) return "$";
				if (ch >= '0' && ch <= '9') return to!string(cast(dchar)ch);
				if (ch >= 'a' && ch <= 'z') return to!string(cast(dchar)ch);
				if (ch >= 'A' && ch <= 'Z') return to!string(cast(dchar)ch);
				if (ch == '/') return "/";
				if (ch == '^') return "^";
				return ch.to!string;
			}

			void printRange(uint node, ubyte from, ubyte to)
			{
				if (to - from <= 10) logInfo("    %s -> %s", iota(from, cast(uint)to+1).map!(ch => mapChar(cast(ubyte)ch)).join("|"), node);
				else logInfo("    %s-%s -> %s", mapChar(from), mapChar(to), node);
			}

			auto last_to = NodeIndex.max;
			ubyte last_ch = 0;
			foreach (ch, e; n.edges)
				if (e != last_to) {
					if (last_to != NodeIndex.max)
						printRange(last_to, last_ch, cast(ubyte)(ch-1));
					last_ch = cast(ubyte)ch;
					last_to = e;
				}
			if (last_to != NodeIndex.max)
				printRange(last_to, last_ch, ubyte.max);
		}
	}

	private bool doMatch(string text, scope bool delegate(size_t terminal, scope string[] vars) @safe del)
	const {
		string[maxRouteParameters] vars_buf;// = void;

		import std.algorithm : canFind;

		// first, determine the end node, if any
		auto n = matchTerminals(text);
		if (!n) return false;

		// then, go through the terminals and match their variables
		foreach (ref t; m_terminalTags[n.terminalsStart .. n.terminalsEnd]) {
			auto term = &m_terminals[t.index];
			auto vars = vars_buf[0 .. term.varNames.length];
			matchVars(vars, term, text);
			if (vars.canFind!(v => v.length == 0)) continue; // all variables must be non-empty to match
			if (del(t.index, vars)) return true;
		}
		return false;
	}

	private inout(Node)* matchTerminals(string text)
	inout {
		if (!m_nodes.length) return null;

		auto n = &m_nodes[0];

		// follow the path through the match graph
		foreach (i, char ch; text) {
			auto nidx = n.edges[cast(size_t)ch];
			if (nidx == NodeIndex.max) return null;
			n = &m_nodes[nidx];
		}

		// finally, find a matching terminal node
		auto nidx = n.edges[TerminalChar];
		if (nidx == NodeIndex.max) return null;
		n = &m_nodes[nidx];
		return n;
	}

	private void matchVars(string[] dst, in Terminal* term, string text)
	const {
		NodeIndex nidx = 0;
		VarIndex activevar = VarIndex.max;
		size_t activevarstart;

		dst[] = null;

		// folow the path throgh the match graph
		foreach (i, char ch; text) {
			auto var = term.varMap.get(nidx, VarIndex.max);

			// detect end of variable
			if (var != activevar && activevar != VarIndex.max) {
				dst[activevar] = text[activevarstart .. i-1];
				activevar = VarIndex.max;
			}

			// detect beginning of variable
			if (var != VarIndex.max && activevar == VarIndex.max) {
				activevar = var;
				activevarstart = i;
			}

			nidx = m_nodes[nidx].edges[cast(ubyte)ch];
			assert(nidx != NodeIndex.max);
		}

		// terminate any active varible with the end of the input string or with the last character
		auto var = term.varMap.get(nidx, VarIndex.max);
		if (activevar != VarIndex.max) dst[activevar] = text[activevarstart .. (var == activevar ? $ : $-1)];
	}

	private void rebuildGraph()
	@trusted {
		import std.array : appender;
		import std.conv : to;

		if (m_upToDate) return;
		m_upToDate = true;

		m_nodes = null;
		m_terminalTags = null;

		if (!m_terminals.length) return;

		MatchGraphBuilder builder;
		foreach (i, ref t; m_terminals) {
			t.varNames = builder.insert(t.pattern, i.to!TerminalIndex);
			assert(t.varNames.length <= VarIndex.max, "Too many variables in route.");
		}
		//builder.print();
		builder.disambiguate();

		auto nodemap = new NodeIndex[builder.m_nodes.length];
		nodemap[] = NodeIndex.max;

		auto nodes = appender!(Node[]);
		nodes.reserve(1024);
		auto termtags = appender!(TerminalTag[]);
		termtags.reserve(1024);

		NodeIndex process(NodeIndex n)
		{
			import std.algorithm : canFind;

			if (nodemap[n] != NodeIndex.max) return nodemap[n];
			auto nmidx = cast(NodeIndex)nodes.data.length;
			nodemap[n] = nmidx;
			nodes.put(Node.init);

			Node nn;
			nn.terminalsStart = termtags.data.length.to!TerminalTagIndex;
			foreach (t; builder.m_nodes[n].terminals) {
				auto var = cast(VarIndex)t.var;
				assert(!termtags.data[nn.terminalsStart .. $].canFind!(u => u.index == t.index && u.var == var));
				termtags ~= TerminalTag(cast(TerminalIndex)t.index, var);
				if (var != VarIndex.max)
					m_terminals[t.index].varMap[nmidx] = var;
			}
			nn.terminalsEnd = termtags.data.length.to!TerminalTagIndex;
			foreach (ch, targets; builder.m_nodes[n].edges)
				foreach (to; builder.m_edgeEntries.getItems(targets))
					nn.edges[ch] = process(to);

			nodes.data[nmidx] = nn;

			return nmidx;
		}
		assert(builder.m_edgeEntries.hasLength(builder.m_nodes[0].edges['^'], 1),
			"Graph must be disambiguated before purging.");
		process(builder.m_edgeEntries.getItems(builder.m_nodes[0].edges['^']).front);

		m_nodes = nodes.data;
		m_terminalTags = termtags.data;

		logDebug("Match tree has %s (of %s in the builder) nodes, %s terminals", m_nodes.length, builder.m_nodes.length, m_terminals.length);
	}
}

unittest {
	import std.string : format;
	MatchTree!int m;

	void testMatch(string str, size_t[] terms, string[] vars)
	{
		size_t[] mterms;
		string[] mvars;
		m.match(str, (t, scope vals) {
			mterms ~= t;
			mvars ~= vals;
			return false;
		});
		assert(mterms == terms, format("Mismatched terminals: %s (expected %s)", mterms, terms));
		assert(mvars == vars, format("Mismatched variables; %s (expected %s)", mvars, vars));
	}

	m.addTerminal("a", 0);
	m.addTerminal("b", 0);
	m.addTerminal("ab", 0);
	m.rebuildGraph();
	assert(m.getTerminalVarNames(0) == []);
	assert(m.getTerminalVarNames(1) == []);
	assert(m.getTerminalVarNames(2) == []);
	testMatch("a", [0], []);
	testMatch("ab", [2], []);
	testMatch("abc", [], []);
	testMatch("b", [1], []);

	m = MatchTree!int.init;
	m.addTerminal("ab", 0);
	m.addTerminal("a*", 0);
	m.rebuildGraph();
	assert(m.getTerminalVarNames(0) == []);
	assert(m.getTerminalVarNames(1) == []);
	testMatch("a", [1], []);
	testMatch("ab", [0, 1], []);
	testMatch("abc", [1], []);

	m = MatchTree!int.init;
	m.addTerminal("ab", 0);
	m.addTerminal("a:var", 0);
	m.rebuildGraph();
	assert(m.getTerminalVarNames(0) == []);
	assert(m.getTerminalVarNames(1) == ["var"], format("%s", m.getTerminalVarNames(1)));
	testMatch("a", [], []); // vars may not be empty
	testMatch("ab", [0, 1], ["b"]);
	testMatch("abc", [1], ["bc"]);

	m = MatchTree!int.init;
	m.addTerminal(":var1/:var2", 0);
	m.addTerminal("a/:var3", 0);
	m.addTerminal(":var4/b", 0);
	m.rebuildGraph();
	assert(m.getTerminalVarNames(0) == ["var1", "var2"]);
	assert(m.getTerminalVarNames(1) == ["var3"]);
	assert(m.getTerminalVarNames(2) == ["var4"]);
	testMatch("a", [], []);
	testMatch("a/a", [0, 1], ["a", "a", "a"]);
	testMatch("a/b", [0, 1, 2], ["a", "b", "b", "a"]);
	testMatch("a/bc", [0, 1], ["a", "bc", "bc"]);
	testMatch("ab/b", [0, 2], ["ab", "b", "ab"]);
	testMatch("ab/bc", [0], ["ab", "bc"]);

	m = MatchTree!int.init;
	m.addTerminal(":var1/", 0);
	m.rebuildGraph();
	assert(m.getTerminalVarNames(0) == ["var1"]);
	testMatch("ab/", [0], ["ab"]);
	testMatch("ab", [], []);
	testMatch("/ab", [], []);
	testMatch("a/b", [], []);
	testMatch("ab//", [], []);
}


private struct MatchGraphBuilder {
@safe:
	import std.container.array : Array;
	import std.array : array;
	import std.algorithm : filter;
	import std.string : format;

	alias NodeIndex = uint;
	alias TerminalIndex = ushort;
	alias VarIndex = ushort;
	alias NodeSet = LinkedSetBacking!NodeIndex.Handle;

	private {
		enum TerminalChar = 0;
		struct TerminalTag {
			TerminalIndex index;
			VarIndex var = VarIndex.max;
		}
		struct Node {
			Array!TerminalTag terminals;
			NodeSet[ubyte.max+1] edges;
		}
		Array!Node m_nodes;
		LinkedSetBacking!NodeIndex m_edgeEntries;
	}

	@disable this(this);

	string[] insert(string pattern, TerminalIndex terminal)
	{
		import std.algorithm : canFind;

		auto full_pattern = pattern;
		string[] vars;
		if (!m_nodes.length) addNode();

		// create start node and connect to zero node
		auto nidx = addNode();
		addEdge(0, nidx, '^', terminal);

		while (pattern.length) {
			auto ch = pattern[0];
			if (ch == '*') {
				assert(pattern.length == 1, "Asterisk is only allowed at the end of a pattern: "~full_pattern);
				pattern = null;

				foreach (v; ubyte.min .. ubyte.max+1) {
					if (v == TerminalChar) continue;
					addEdge(nidx, nidx, cast(ubyte)v, terminal);
				}
			} else if (ch == ':') {
				pattern = pattern[1 .. $];
				auto name = skipPathNode(pattern);
				assert(name.length > 0, "Missing placeholder name: "~full_pattern);
				assert(!vars.canFind(name), "Duplicate placeholder name ':"~name~"': '"~full_pattern~"'");
				auto varidx = cast(VarIndex)vars.length;
				vars ~= name;
				assert(!pattern.length || (pattern[0] != '*' && pattern[0] != ':'),
					"Cannot have two placeholders directly follow each other.");

				foreach (v; ubyte.min .. ubyte.max+1) {
					if (v == TerminalChar || v == '/') continue;
					addEdge(nidx, nidx, cast(ubyte)v, terminal, varidx);
				}
			} else {
				nidx = addEdge(nidx, ch, terminal);
				pattern = pattern[1 .. $];
			}
		}

		addEdge(nidx, TerminalChar, terminal);
		return vars;
	}

	void disambiguate()
	@trusted {
		import std.algorithm : map, sum;
		import std.array : appender, join;

		//logInfo("Disambiguate with %s initial nodes", m_nodes.length);
		if (!m_nodes.length) return;

		import vibe.utils.hashmap;
		HashMap!(size_t, NodeIndex) combined_nodes;
		Array!bool visited;
		visited.length = m_nodes.length * 2;
		Stack!NodeIndex node_stack;
		node_stack.reserve(m_nodes.length);
		node_stack.push(0);
		while (!node_stack.empty) {
			auto n = node_stack.pop();

			while (n >= visited.length) visited.length = visited.length * 2;
			if (visited[n]) continue;
			//logInfo("Disambiguate %s (stack=%s)", n, node_stack.fill);
			visited[n] = true;

			foreach (ch; ubyte.min .. ubyte.max+1) {
				auto chnodes = m_nodes[n].edges[ch];
				size_t chhash = m_edgeEntries.getHash(chnodes);

				// handle trivial cases
				if (m_edgeEntries.hasMaxLength(chnodes, 1))
					continue;

				// generate combined state for ambiguous edges
				if (auto pn = () @trusted { return chhash in combined_nodes; } ()) {
					m_nodes[n].edges[ch] = m_edgeEntries.create(*pn);
					assert(m_edgeEntries.hasLength(m_nodes[n].edges[ch], 1));
					continue;
				}

				// for new combinations, create a new node
				NodeIndex ncomb = addNode();
				combined_nodes[chhash] = ncomb;

				// write all edges
				size_t idx = 0;
				foreach (to_ch; ubyte.min .. ubyte.max+1) {
					auto e = &m_nodes[ncomb].edges[to_ch];
					foreach (chn; m_edgeEntries.getItems(chnodes))
						m_edgeEntries.insert(e, m_edgeEntries.getItems(m_nodes[chn].edges[to_ch]));
				}

				// add terminal indices
				foreach (chn; m_edgeEntries.getItems(chnodes))
					foreach (t; m_nodes[chn].terminals)
						addTerminal(ncomb, t.index, t.var);
				foreach (i; 1 .. m_nodes[ncomb].terminals.length)
					assert(m_nodes[ncomb].terminals[0] != m_nodes[ncomb].terminals[i]);

				m_nodes[n].edges[ch] = m_edgeEntries.create(ncomb);
				assert(m_edgeEntries.hasLength(m_nodes[n].edges[ch], 1));
			}

			// process nodes recursively
			foreach (ch; ubyte.min .. ubyte.max+1) {
				// should only have single out-edges now
				assert(m_edgeEntries.hasMaxLength(m_nodes[n].edges[ch], 1));
				foreach (e; m_edgeEntries.getItems(m_nodes[n].edges[ch]))
					node_stack.push(e);
			}
		}

		import std.algorithm.sorting : sort;
		foreach (ref n; m_nodes)
			n.terminals[].sort!((a, b) => a.index < b.index)();

		debug logDebug("Disambiguate done: %s nodes, %s max stack size", m_nodes.length, node_stack.maxSize);
	}

	void print()
	const @trusted {
		import std.algorithm : map;
		import std.array : join;
		import std.conv : to;
		import std.string : format;

		logInfo("Nodes:");
		size_t i = 0;
		foreach (n; m_nodes) {
			string mapChar(ubyte ch) {
				if (ch == TerminalChar) return "$";
				if (ch >= '0' && ch <= '9') return to!string(cast(dchar)ch);
				if (ch >= 'a' && ch <= 'z') return to!string(cast(dchar)ch);
				if (ch >= 'A' && ch <= 'Z') return to!string(cast(dchar)ch);
				if (ch == '^') return "^";
				if (ch == '/') return "/";
				return format("$%s", ch);
			}
			logInfo("  %s: %s", i, n.terminals[].map!(t => t.var != VarIndex.max ? format("T%s(%s)", t.index, t.var) : format("T%s", t.index)).join(" "));
			ubyte first_char;
			size_t list_hash;
			NodeSet list;

			void printEdges(ubyte last_char) {
				if (!list.empty) {
					string targets;
					foreach (tn; m_edgeEntries.getItems(list))
						targets ~= format(" %s", tn);
					if (targets.length > 0)
						logInfo("    [%s ... %s] -> %s", mapChar(first_char), mapChar(last_char), targets);
				}
			}
			foreach (ch, tnodes; n.edges) {
				auto h = m_edgeEntries.getHash(tnodes);
				if (h != list_hash) {
					printEdges(cast(ubyte)(ch-1));
					list_hash = h;
					list = tnodes;
					first_char = cast(ubyte)ch;
				}
			}
			printEdges(ubyte.max);
			i++;
		}
	}

	private void addEdge(NodeIndex from, NodeIndex to, ubyte ch, TerminalIndex terminal, VarIndex var = VarIndex.max)
	@trusted {
		m_edgeEntries.insert(&m_nodes[from].edges[ch], to);
		addTerminal(to, terminal, var);
	}

	private NodeIndex addEdge(NodeIndex from, ubyte ch, TerminalIndex terminal, VarIndex var = VarIndex.max)
	@trusted {
		import std.algorithm : canFind;
		import std.string : format;
		if (!m_nodes[from].edges[ch].empty)
			assert(false, format("%s is in %s", ch, m_nodes[from].edges[]));
		auto nidx = addNode();
		addEdge(from, nidx, ch, terminal, var);
		return nidx;
	}

	private void addTerminal(NodeIndex node, TerminalIndex terminal, VarIndex var)
	@trusted {
		foreach (ref t; m_nodes[node].terminals) {
			if (t.index == terminal) {
				if (t.var != VarIndex.max && t.var != var)
					assert(false, format("Ambiguous route var match!? %s vs %s", t.var, var));
				t.var = var;
				return;
			}
		}
		m_nodes[node].terminals ~= TerminalTag(terminal, var);
	}

	private NodeIndex addNode()
	@trusted {
		assert(m_nodes.length <= 1_000_000_000, "More than 1B nodes in tree!?");
		auto idx = cast(NodeIndex)m_nodes.length;
		m_nodes ~= Node.init;
		return idx;
	}
}

struct LinkedSetBacking(T) {
	import std.container.array : Array;
	import std.range : isInputRange;

	static struct Handle {
		uint index = uint.max;
		@property bool empty() const { return index == uint.max; }
	}

	private {
		static struct Entry {
			uint next;
			T value;
		}

		Array!Entry m_storage;

		static struct Range {
			private {
				Array!Entry* backing;
				uint index;
			}

			@property bool empty() const { return index == uint.max; }
			@property ref const(T) front() const { return (*backing)[index].value; }

			void popFront()
			{
				index = (*backing)[index].next;
			}
		}
	}

	@property Handle emptySet() { return Handle.init; }

	Handle create(scope T[] items...)
	{
		Handle ret;
		foreach (i; items)
			ret.index = createNode(i, ret.index);
		return ret;
	}

	void insert(Handle* h, T value)
	{
		/*foreach (c; getItems(*h))
			if (value == c)
				return;*/
		h.index = createNode(value, h.index);
	}

	void insert(R)(Handle* h, R items)
		if (isInputRange!R)
	{
		foreach (itm; items)
			insert(h, itm);
	}

	size_t getHash(Handle sh)
	const {
		// NOTE: the returned hash is order independent, to avoid bogus
		//       mismatches when comparing lists of different order
		size_t ret = 0x72d2da6c;
		while (sh != Handle.init) {
			ret ^= (hashOf(m_storage[sh.index].value) ^ 0xb1bdfb8d) * 0x5dbf04a4;
			sh.index = m_storage[sh.index].next;
		}
		return ret;
	}

	auto getItems(Handle sh) { return Range(&m_storage, sh.index); }
	auto getItems(Handle sh) const { return Range(&(cast()this).m_storage, sh.index); }

	bool hasMaxLength(Handle sh, size_t l)
	const {
		uint idx = sh.index;
		do {
			if (idx == uint.max) return true;
			idx = m_storage[idx].next;
		} while (l-- > 0);
		return false;
	}

	bool hasLength(Handle sh, size_t l)
	const {
		uint idx = sh.index;
		while (l-- > 0) {
			if (idx == uint.max) return false;
			idx = m_storage[idx].next;
		}
		return idx == uint.max;
	}

	private uint createNode(ref T val, uint next)
	{
		auto id = cast(uint)m_storage.length;
		m_storage ~= Entry(next, val);
		return id;
	}
}

unittest {
	import std.algorithm.comparison : equal;

	LinkedSetBacking!int b;
	auto s = b.emptySet;
	assert(s.empty);
	assert(b.getItems(s).empty);
	s = b.create(3, 5, 7);
	assert(b.getItems(s).equal([7, 5, 3]));
	assert(!b.hasLength(s, 2));
	assert(b.hasLength(s, 3));
	assert(!b.hasLength(s, 4));
	assert(!b.hasMaxLength(s, 2));
	assert(b.hasMaxLength(s, 3));
	assert(b.hasMaxLength(s, 4));

	auto h = b.getHash(s);
	assert(h != b.getHash(b.emptySet));
	s = b.create(5, 3, 7);
	assert(b.getHash(s) == h);

	b.insert(&s, 11);
	assert(b.hasLength(s, 4));
	assert(b.getHash(s) != h);
}

private struct Stack(E)
{
	import std.range : isInputRange;

	private {
		E[] m_storage;
		size_t m_fill;
		debug size_t m_maxFill;
	}

	@property bool empty() const { return m_fill == 0; }

	@property size_t fill() const { return m_fill; }

	debug @property size_t maxSize() const { return m_maxFill; }

	void reserve(size_t amt)
	{
		auto minsz = m_fill + amt;
		if (m_storage.length < minsz) {
			auto newlength = 64;
			while (newlength < minsz) newlength *= 2;
			m_storage.length = newlength;
		}
	}

	void push(E el)
	{
		reserve(1);
		m_storage[m_fill++] = el;
		debug if (m_fill > m_maxFill) m_maxFill = m_fill;
	}

	void push(R)(R els)
		if (isInputRange!R)
	{
		reserve(els.length);
		foreach (el; els)
			m_storage[m_fill++] = el;
		debug if (m_fill > m_maxFill) m_maxFill = m_fill;
	}

	E pop()
	{
		assert(!empty, "Stack underflow.");
		return m_storage[--m_fill];
	}
}
