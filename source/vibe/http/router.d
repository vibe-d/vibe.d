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

version (VibeOldRouterImpl) {
	pragma(msg, "-version=VibeOldRouterImpl is deprecated and will be removed in the next release.");
}
else version = VibeRouterTreeMatch;


/**
	An interface for HTTP request routers.

	As of 0.7.24, the interface has been replaced with a deprecated alias to URLRouter.
	This will break any code relying on HTTPRouter being an interface, but won't
	break signatures.

	Removal_notice:

	Note that this is planned to be removed, due to interface/behavior considerations.
	In particular, the exact behavior of the router (most importantly, the route match
	string format) must be considered part of the interface. However, this removes the
	prime argument for having an interface in the first place.
*/
deprecated("Will be removed in 0.7.25. See removal notice for more information.")
public alias HTTPRouter = URLRouter;

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
	private {
		version (VibeRouterTreeMatch) MatchTree!Route m_routes;
		else Route[] m_routes;
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
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestDelegate cb)
	in { assert(path.length, "Cannot register null or empty path!"); }
	body {
		import std.algorithm;
		assert(count(path, ':') <= maxRouteParameters, "Too many route parameters");
		logDebug("add route %s %s", method, path);
		version (VibeRouterTreeMatch) m_routes.addTerminal(path, Route(method, path, cb));
		else m_routes ~= Route(method, path, cb);
		return this;
	}
	/// ditto
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestHandler cb) { return match(method, path, &cb.handleRequest); }
	/// ditto
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestFunction cb) { return match(method, path, toDelegate(cb)); }
	/// ditto
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestDelegateS cb) { return match(method, path, cast(HTTPServerRequestDelegate)cb); }
	/// ditto
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestHandlerS cb) { return match(method, path, &cb.handleRequest); }
	/// ditto
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestFunctionS cb) { return match(method, path, toDelegate(cb)); }

	/// Adds a new route for GET requests matching the specified pattern.
	URLRouter get(string url_match, HTTPServerRequestHandler cb) { return get(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter get(string url_match, HTTPServerRequestFunction cb) { return get(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter get(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.GET, url_match, cb); }
	/// ditto
	URLRouter get(string url_match, HTTPServerRequestHandlerS cb) { return get(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter get(string url_match, HTTPServerRequestFunctionS cb) { return get(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter get(string url_match, HTTPServerRequestDelegateS cb) { return match(HTTPMethod.GET, url_match, cb); }

	/// Adds a new route for POST requests matching the specified pattern.
	URLRouter post(string url_match, HTTPServerRequestHandler cb) { return post(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter post(string url_match, HTTPServerRequestFunction cb) { return post(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter post(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.POST, url_match, cb); }
	/// ditto
	URLRouter post(string url_match, HTTPServerRequestHandlerS cb) { return post(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter post(string url_match, HTTPServerRequestFunctionS cb) { return post(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter post(string url_match, HTTPServerRequestDelegateS cb) { return match(HTTPMethod.POST, url_match, cb); }

	/// Adds a new route for PUT requests matching the specified pattern.
	URLRouter put(string url_match, HTTPServerRequestHandler cb) { return put(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter put(string url_match, HTTPServerRequestFunction cb) { return put(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter put(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.PUT, url_match, cb); }
	/// ditto
	URLRouter put(string url_match, HTTPServerRequestHandlerS cb) { return put(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter put(string url_match, HTTPServerRequestFunctionS cb) { return put(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter put(string url_match, HTTPServerRequestDelegateS cb) { return match(HTTPMethod.PUT, url_match, cb); }

	/// Adds a new route for DELETE requests matching the specified pattern.
	URLRouter delete_(string url_match, HTTPServerRequestHandler cb) { return delete_(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter delete_(string url_match, HTTPServerRequestFunction cb) { return delete_(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter delete_(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.DELETE, url_match, cb); }
	/// ditto
	URLRouter delete_(string url_match, HTTPServerRequestHandlerS cb) { return delete_(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter delete_(string url_match, HTTPServerRequestFunctionS cb) { return delete_(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter delete_(string url_match, HTTPServerRequestDelegateS cb) { return match(HTTPMethod.DELETE, url_match, cb); }

	/// Adds a new route for PATCH requests matching the specified pattern.
	URLRouter patch(string url_match, HTTPServerRequestHandler cb) { return patch(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter patch(string url_match, HTTPServerRequestFunction cb) { return patch(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter patch(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.PATCH, url_match, cb); }
	/// ditto
	URLRouter patch(string url_match, HTTPServerRequestHandlerS cb) { return patch(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter patch(string url_match, HTTPServerRequestFunctionS cb) { return patch(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter patch(string url_match, HTTPServerRequestDelegateS cb) { return match(HTTPMethod.PATCH, url_match, cb); }

	/// Adds a new route for requests matching the specified pattern, regardless of their HTTP verb.
	URLRouter any(string url_match, HTTPServerRequestHandler cb) { return any(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter any(string url_match, HTTPServerRequestFunction cb) { return any(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter any(string url_match, HTTPServerRequestDelegate cb)
	{
		import std.traits;
		static HTTPMethod[] all_methods = [EnumMembers!HTTPMethod];

		foreach(immutable method; all_methods)
			match(method, url_match, cb);

		return this;
	}
	/// ditto
	URLRouter any(string url_match, HTTPServerRequestHandlerS cb) { return any(url_match, &cb.handleRequest); }
	/// ditto
	URLRouter any(string url_match, HTTPServerRequestFunctionS cb) { return any(url_match, toDelegate(cb)); }
	/// ditto
	URLRouter any(string url_match, HTTPServerRequestDelegateS cb) { return any(url_match, cast(HTTPServerRequestDelegate)cb); }


	/** Rebuilds the internal matching structures to account for newly added routes.

		This should be used after a lot of routes have been added to the router, to
		force eager computation of the match structures. The alternative is to
		let the router lazily compute the structures when the first request happens,
		which can delay this request.
	*/
	void rebuild()
	{
		version (VibeRouterTreeMatch)
			m_routes.rebuildGraph();
	}

	/// Handles a HTTP request by dispatching it to the registered route handlers.
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto method = req.method;

		string calcBasePath()
		{
			import vibe.inet.path;
			auto p = Path(prefix.length ? prefix : "/");
			p.endsWithSlash = true;
			return p.relativeToWeb(Path(req.path)).toString();
		}

		auto path = req.path;
		if (path.length < m_prefix.length || path[0 .. m_prefix.length] != m_prefix) return;
		path = path[m_prefix.length .. $];

		version (VibeRouterTreeMatch) {
			while (true) {
				bool done = m_routes.match(path, (ridx, scope values) {
					auto r = &m_routes.getTerminalData(ridx);
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
		} else {
			while(true)
			{
				foreach (ref r; m_routes) {
					if (r.method == method && r.matches(path, req.params)) {
						logTrace("route match: %s -> %s %s", req.path, r.method, r.pattern);
						// .. parse fields ..
						req.params["routerRootDir"] = calcBasePath;
						r.cb(req, res);
						if (res.headerWritten) return;
					}
				}
				if (method == HTTPMethod.HEAD) method = HTTPMethod.GET;
				//else if (method == HTTPMethod.OPTIONS)
				else break;
			}
		}

		logDebug("no route match: %s %s", req.method, req.requestURL);
	}

	/// Returns all registered routes as const AA
	const(Route)[] getAllRoutes()
	{
		version (VibeRouterTreeMatch) {
			auto routes = new Route[m_routes.terminalCount];
			foreach (i, ref r; routes)
				r = m_routes.getTerminalData(i);
			return routes;
		} else return m_routes;
	}
}

///
unittest {
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
unittest {
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

unittest {
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

unittest {
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


/**
	Convenience abstraction for a single `URLRouter` route.

	See `URLRouter.route` for a usage example.
*/
struct URLRoute {
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

	bool matches(string url, ref string[string] params)
	const {
		size_t i, j;

		// store parameters until a full match is confirmed
		import std.typecons;
		Tuple!(string, string)[maxRouteParameters] tmpparams;
		size_t tmppparams_length = 0;

		for (i = 0, j = 0; i < url.length && j < pattern.length;) {
			if (pattern[j] == '*') {
				foreach (t; tmpparams[0 .. tmppparams_length])
					params[t[0]] = t[1];
				return true;
			}
			if (url[i] == pattern[j]) {
				i++;
				j++;
			} else if(pattern[j] == ':') {
				j++;
				string name = skipPathNode(pattern, j);
				string match = skipPathNode(url, i);
				assert(tmppparams_length < maxRouteParameters, "Maximum number of route parameters exceeded.");
				tmpparams[tmppparams_length++] = tuple(name, match);
			} else return false;
		}

		if ((j < pattern.length && pattern[j] == '*') || (i == url.length && j == pattern.length)) {
			foreach (t; tmpparams[0 .. tmppparams_length])
				params[t[0]] = t[1];
			return true;
		}

		return false;
	}
}


private string skipPathNode(string str, ref size_t idx)
{
	size_t start = idx;
	while( idx < str.length && str[idx] != '/' ) idx++;
	return str[start .. idx];
}

private string skipPathNode(ref string str)
{
	size_t idx = 0;
	auto ret = skipPathNode(str, idx);
	str = str[idx .. $];
	return ret;
}

private struct MatchTree(T) {
	import std.algorithm : countUntil;
	import std.array : array;

	private {
		struct Node {
			size_t terminalsStart; // slice into m_terminalTags
			size_t terminalsEnd;
			uint[ubyte.max+1] edges = uint.max; // character -> index into m_nodes
		}
		struct TerminalTag {
			size_t index; // index into m_terminals array
			size_t var; // index into Terminal.varNames/varValues or size_t.max
		}
		struct Terminal {
			string pattern;
			T data;
			string[] varNames;
			size_t[size_t] varMap; // maps node index to variable index
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
		m_terminals ~= Terminal(pattern, data, null, null);
		m_upToDate = false;
	}

	bool match(string text, scope bool delegate(size_t terminal, scope string[] vars) del)
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
				.map!(t => format("T%s%s", t.index, t.var != size_t.max ? "("~m_terminals[t.index].varNames[t.var]~")" : "")).join(" "));
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

			uint last_to = uint.max;
			ubyte last_ch = 0;
			foreach (ch, e; n.edges)
				if (e != last_to) {
					if (last_to != uint.max)
						printRange(last_to, last_ch, cast(ubyte)(ch-1));
					last_ch = cast(ubyte)ch;
					last_to = e;
				}
			if (last_to != uint.max)
				printRange(last_to, last_ch, ubyte.max);
		}
	}

	private bool doMatch(string text, scope bool delegate(size_t terminal, scope string[] vars) del)
	const {
		string[maxRouteParameters] vars_buf = void;

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
			auto nidx = n.edges[cast(ubyte)ch];
			if (nidx == uint.max) return null;
			n = &m_nodes[nidx];
		}

		// finally, find a matching terminal node
		auto nidx = n.edges[TerminalChar];
		if (nidx == uint.max) return null;
		n = &m_nodes[nidx];
		return n;
	}

	private void matchVars(string[] dst, in Terminal* term, string text)
	const {
		auto nidx = 0;
		size_t activevar = size_t.max;
		size_t activevarstart;

		dst[] = null;

		// folow the path throgh the match graph
		foreach (i, char ch; text) {
			auto var = term.varMap[nidx];

			// detect end of variable
			if (var != activevar && activevar != size_t.max) {
				dst[activevar] = text[activevarstart .. i-1];
				activevar = size_t.max;
			}

			// detect beginning of variable
			if (var != size_t.max && activevar == size_t.max) {
				activevar = var;
				activevarstart = i;
			}

			nidx = m_nodes[nidx].edges[cast(ubyte)ch];
			assert(nidx != uint.max);
		}

		// terminate any active varible with the end of the input string or with the last character
		auto var = term.varMap[nidx];
		if (activevar != size_t.max) dst[activevar] = text[activevarstart .. (var == activevar ? $ : $-1)];
	}

	private void rebuildGraph()
	{
		if (m_upToDate) return;
		m_upToDate = true;

		m_nodes = null;
		m_terminalTags = null;

		if (!m_terminals.length) return;

		MatchGraphBuilder builder;
		foreach (i, ref t; m_terminals)
			t.varNames = builder.insert(t.pattern, i);
		//builder.print();
		builder.disambiguate();

		auto nodemap = new uint[builder.m_nodes.length];
		nodemap[] = uint.max;

		uint process(size_t n)
		{
			import std.algorithm : canFind;

			if (nodemap[n] != uint.max) return nodemap[n];
			auto nmidx = cast(uint)m_nodes.length;
			nodemap[n] = nmidx;
			m_nodes.length++;

			Node nn;
			nn.terminalsStart = m_terminalTags.length;
			foreach (t; builder.m_nodes[n].terminals) {
				auto var = t.var.length ? m_terminals[t.index].varNames.countUntil(t.var) : size_t.max;
				assert(!m_terminalTags[nn.terminalsStart .. $].canFind!(u => u.index == t.index && u.var == var));
				m_terminalTags ~= TerminalTag(t.index, var);
				m_terminals[t.index].varMap[nmidx] = var;
			}
			nn.terminalsEnd = m_terminalTags.length;
			foreach (e; builder.m_nodes[n].edges)
				nn.edges[e.ch] = process(e.to);

			m_nodes[nmidx] = nn;

			return nmidx;
		}
		assert(builder.m_nodes[0].edges.length == 1, "Graph must be disambiguated before purging.");
		process(builder.m_nodes[0].edges[0].to);

		logDebug("Match tree has %s nodes, %s terminals", m_nodes.length, m_terminals.length);
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
	import std.array : array;
	import std.algorithm : filter;
	import std.string : format;

	private {
		enum TerminalChar = 0;
		struct TerminalTag {
			size_t index;
			string var;
			bool opEquals(in ref TerminalTag other) const { return index == other.index && var == other.var; }
		}
		struct Node {
			TerminalTag[] terminals;
			Edge[] edges;
		}
		struct Edge {
			ubyte ch;
			size_t to;
		}
		Node[] m_nodes;
	}

	string[] insert(string pattern, size_t terminal)
	{
		import std.algorithm : canFind;

		auto full_pattern = pattern;
		string[] vars;
		if (!m_nodes.length) addNode();

		// create start node and connect to zero node
		auto nidx = addNode();
		addEdge(0, nidx, '^', terminal, null);

		while (pattern.length) {
			auto ch = pattern[0];
			if (ch == '*') {
				assert(pattern.length == 1, "Asterisk is only allowed at the end of a pattern: "~full_pattern);
				pattern = null;

				foreach (v; ubyte.min .. ubyte.max+1) {
					if (v == TerminalChar) continue;
					addEdge(nidx, nidx, cast(ubyte)v, terminal, null);
				}
			} else if (ch == ':') {
				pattern = pattern[1 .. $];
				auto name = skipPathNode(pattern);
				assert(name.length > 0, "Missing placeholder name: "~full_pattern);
				assert(!vars.canFind(name), "Duplicate placeholder name ':"~name~"': '"~full_pattern~"'");
				vars ~= name;
				assert(!pattern.length || (pattern[0] != '*' && pattern[0] != ':'),
					"Cannot have two placeholders directly follow each other.");

				foreach (v; ubyte.min .. ubyte.max+1) {
					if (v == TerminalChar || v == '/') continue;
					addEdge(nidx, nidx, cast(ubyte)v, terminal, name);
				}
			} else {
				nidx = addEdge(nidx, ch, terminal, null);
				pattern = pattern[1 .. $];
			}
		}

		addEdge(nidx, TerminalChar, terminal, null);
		return vars;
	}

	void disambiguate()
	{
//logInfo("Disambiguate");
		if (!m_nodes.length) return;

		import vibe.utils.hashmap;
		HashMap!(immutable(size_t)[], size_t) combined_nodes;
		auto visited = new bool[m_nodes.length * 2];
		size_t[] node_stack = [0];
		while (node_stack.length) {
			auto n = node_stack[$-1];
			node_stack.length--;

			while (n >= visited.length) visited.length = visited.length * 2;
			if (visited[n]) continue;
//logInfo("Disambiguate %s", n);
			visited[n] = true;

			Edge[] newedges;
			immutable(size_t)[][ubyte.max+1] edges;
			foreach (e; m_nodes[n].edges) edges[e.ch] ~= e.to;
			foreach (ch_; ubyte.min .. ubyte.max+1) {
				ubyte ch = cast(ubyte)ch_;
				auto chnodes = edges[ch_];

				// handle trivial cases
				if (!chnodes.length) continue;
				if (chnodes.length == 1) { addToArray(newedges, Edge(ch, chnodes[0])); continue; }

				// generate combined state for ambiguous edges
				if (auto pn = chnodes in combined_nodes) { addToArray(newedges, Edge(ch, *pn)); continue; }

				// for new combinations, create a new node
				size_t ncomb = addNode();
				combined_nodes[chnodes] = ncomb;
				bool[ubyte][size_t] nc_edges;
				foreach (chn; chnodes) {
					foreach (e; m_nodes[chn].edges) {
						if (auto pv = e.to in nc_edges) {
							if (auto pw = e.ch in *pv)
								continue;
							else (*pv)[e.ch] = true;
						} else nc_edges[e.to][e.ch] = true;
						m_nodes[ncomb].edges ~= e;
					}
					addToArray(m_nodes[ncomb].terminals, m_nodes[chn].terminals);
				}
				foreach (i; 1 .. m_nodes[ncomb].terminals.length)
					assert(m_nodes[ncomb].terminals[0] != m_nodes[ncomb].terminals[i]);
				newedges ~= Edge(ch, ncomb);
			}
			m_nodes[n].edges = newedges;

			// process nodes recursively
			node_stack.assumeSafeAppend();
			foreach (e; newedges) node_stack ~= e.to;
		}
//logInfo("Disambiguate done");
	}

	void print()
	const {
		import std.algorithm : map;
		import std.array : join;
		import std.conv : to;
		import std.string : format;

		logInfo("Nodes:");
		foreach (i, n; m_nodes) {
			string mapChar(ubyte ch) {
				if (ch == TerminalChar) return "$";
				if (ch >= '0' && ch <= '9') return to!string(cast(dchar)ch);
				if (ch >= 'a' && ch <= 'z') return to!string(cast(dchar)ch);
				if (ch >= 'A' && ch <= 'Z') return to!string(cast(dchar)ch);
				if (ch == '/') return "/";
				return ch.to!string;
			}
			logInfo("  %s %s", i, n.terminals.map!(t => format("T%s%s", t.index, t.var.length ? "("~t.var~")" : "")).join(" "));
			foreach (e; n.edges)
				logInfo("    %s -> %s", mapChar(e.ch), e.to);
		}
	}

	private void addEdge(size_t from, size_t to, ubyte ch, size_t terminal, string var)
	{
		m_nodes[from].edges ~= Edge(ch, to);
		addTerminal(to, terminal, var);
	}

	private size_t addEdge(size_t from, ubyte ch, size_t terminal, string var)
	{
		import std.algorithm : canFind;
		import std.string : format;
		assert(!m_nodes[from].edges.canFind!(e => e.ch == ch), format("%s is in %s", ch, m_nodes[from].edges));
		auto nidx = addNode();
		addEdge(from, nidx, ch, terminal, var);
		return nidx;
	}

	private void addTerminal(size_t node, size_t terminal, string var)
	{
		foreach (ref t; m_nodes[node].terminals) {
			if (t.index == terminal) {
				assert(t.var.length == 0 || t.var == var, "Ambiguous route var match!? '"~t.var~"' vs. '"~var~"'");
				t.var = var;
				return;
			}
		}
		m_nodes[node].terminals ~= TerminalTag(terminal, var);
	}

	private size_t addNode()
	{
		auto idx = m_nodes.length;
		m_nodes ~= Node(null, null);
		return idx;
	}

	private static addToArray(T)(ref T[] arr, T[] elems) { foreach (e; elems) addToArray(arr, e); }
	private static addToArray(T)(ref T[] arr, T elem)
	{
		import std.algorithm : canFind;
		if (!arr.canFind(elem)) arr ~= elem;
	}
}
