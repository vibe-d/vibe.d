/**
	Pattern based URL router.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.router;

public import vibe.http.server;

import vibe.core.log;

import std.functional;

//version = VibeRouterTreeMatch;


/**
	An interface for HTTP request routers.
*/
interface HTTPRouter : HTTPServerRequestHandler {
	/// Adds a new route for request that match the path and method
	HTTPRouter match(HTTPMethod method, string path, HTTPServerRequestDelegate cb);
	/// ditto
	final HTTPRouter match(HTTPMethod method, string path, HTTPServerRequestHandler cb) { return match(method, path, &cb.handleRequest); }
	/// ditto
	final HTTPRouter match(HTTPMethod method, string path, HTTPServerRequestFunction cb) { return match(method, path, toDelegate(cb)); }

	/// Handles the HTTP request by dispatching it to the registered request handlers.
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res);

	/// Adds a new route for GET requests matching the specified pattern.
	final HTTPRouter get(string url_match, HTTPServerRequestHandler cb) { return get(url_match, &cb.handleRequest); }
	/// ditto
	final HTTPRouter get(string url_match, HTTPServerRequestFunction cb) { return get(url_match, toDelegate(cb)); }
	/// ditto
	final HTTPRouter get(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.GET, url_match, cb); }

	/// Adds a new route for POST requests matching the specified pattern.
	final HTTPRouter post(string url_match, HTTPServerRequestHandler cb) { return post(url_match, &cb.handleRequest); }
	/// ditto
	final HTTPRouter post(string url_match, HTTPServerRequestFunction cb) { return post(url_match, toDelegate(cb)); }
	/// ditto
	final HTTPRouter post(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.POST, url_match, cb); }

	/// Adds a new route for PUT requests matching the specified pattern.
	final HTTPRouter put(string url_match, HTTPServerRequestHandler cb) { return put(url_match, &cb.handleRequest); }
	/// ditto
	final HTTPRouter put(string url_match, HTTPServerRequestFunction cb) { return put(url_match, toDelegate(cb)); }
	/// ditto
	final HTTPRouter put(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.PUT, url_match, cb); }

	/// Adds a new route for DELETE requests matching the specified pattern.
	final HTTPRouter delete_(string url_match, HTTPServerRequestHandler cb) { return delete_(url_match, &cb.handleRequest); }
	/// ditto
	final HTTPRouter delete_(string url_match, HTTPServerRequestFunction cb) { return delete_(url_match, toDelegate(cb)); }
	/// ditto
	final HTTPRouter delete_(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.DELETE, url_match, cb); }

	/// Adds a new route for PATCH requests matching the specified pattern.
	final HTTPRouter patch(string url_match, HTTPServerRequestHandler cb) { return patch(url_match, &cb.handleRequest); }
	/// ditto
	final HTTPRouter patch(string url_match, HTTPServerRequestFunction cb) { return patch(url_match, toDelegate(cb)); }
	/// ditto
	final HTTPRouter patch(string url_match, HTTPServerRequestDelegate cb) { return match(HTTPMethod.PATCH, url_match, cb); }

	/// Adds a new route for requests matching the specified pattern, regardless of their HTTP verb.
	final HTTPRouter any(string url_match, HTTPServerRequestHandler cb) { return any(url_match, &cb.handleRequest); }
	/// ditto
	final HTTPRouter any(string url_match, HTTPServerRequestFunction cb) { return any(url_match, toDelegate(cb)); }
	/// ditto
	final HTTPRouter any(string url_match, HTTPServerRequestDelegate cb)
	{
		return get(url_match, cb).post(url_match, cb)
			.put(url_match, cb).delete_(url_match, cb).patch(url_match, cb);
	}
}

/// Deprecated compatibility alias
deprecated("Please use HTTPRouter instead.") alias HttpRouter = HTTPRouter;


/++
	Routes HTTP requests based on the request method and URL.

	Routes are matched using a special URL match string that supports two forms of placeholders.
	The following example shows how these are used.

	Registered routes are matched in the same sequence as initially specified.
	Matching ends as soon as a route handler writes a response using res.writeBody()
	or similar means. If no route matches or if no route handler writes a response,
	the router will simply not handle the request and the HTTP server may generate
	a 404 error.

	---
	void addGroup(HTTPServerRequest req, HTTPServerResponse res)
	{
		// Route variables are accessible via the params map
		logInfo("Getting group %s for user %s.", req.params["groupname"], req.params["username"]);
	}

	static this()
	{
		auto router = new URLRouter;
		// Matches all GET requests for /users/*/groups/* and places
		// the place holders in req.params as 'username' and 'groupname'.
		router.get("/users/:username/groups/:groupname", &addGroup);

		// Natches all requests. This can be useful for authorization and
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
	---
+/
class URLRouter : HTTPRouter {
	private {
		version (VibeRouterTreeMatch) MatchTree!Route m_routes;
		else Route[] m_routes;
	}

	/// Adds a new route for requests matching the specified HTTP method and pattern.
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestDelegate cb)
	{
		import std.algorithm;
		assert(count(path, ':') <= maxRouteParameters, "Too many route parameters");
		logDebug("add route %s %s", method, path);
		version (VibeRouterTreeMatch) m_routes.addTerminal(path, Route(method, path, cb));
		else m_routes ~= Route(method, path, cb);
		return this;
	}

	alias match = HTTPRouter.match;
	
	/// Handles a HTTP request by dispatching it to the registered route handlers.
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto method = req.method;

		version (VibeRouterTreeMatch) {
			bool done = false;
			m_routes.match(req.path, (ridx, values) {
				if (done) return;
				auto r = &m_routes.getTerminalData(ridx);
				logInfo("route match: %s -> %s %s %s", req.path, req.method, r.pattern, values);
				if (r.method == method) {
					foreach (i, v; values) req.params[m_routes.getTerminalVarNames(ridx)[i]] = v;
					r.cb(req, res);
					done = res.headerWritten;
				}
			});
			if (done) return;
		} else {
			while(true)
			{
				foreach (ref r; m_routes) {
					if (r.method == method && r.matches(req.path, req.params)) {
						logTrace("route match: %s -> %s %s", req.path, req.method, r.pattern);
						// .. parse fields ..
						r.cb(req, res);
						if (res.headerWritten) return;
					}
				}
				if (method == HTTPMethod.HEAD) method = HTTPMethod.GET;
				//else if (method == HTTPMethod.OPTIONS)
				else break;
			}
		}

		logInfo("no route match: %s %s", req.method, req.requestURL);
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

/// Deprecated compatibility alias
deprecated("Please use URLRouter instead.") alias UrlRouter = URLRouter;


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
			uint[ubyte.max] edges = uint.max; // character -> index into m_nodes
		}
		struct TerminalTag { size_t index; size_t var; }
		struct Terminal {
			string pattern;
			T data;
			string[] varNames;
			string[] varValues; // preallocated storage used during match()
			size_t activeVar = size_t.max; // used during match()
			size_t activeVarStart = size_t.max; // used during match()
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

	void match(string text, scope void delegate(size_t terminal, string[] vars) del)
	{
		rebuildGraph();

		foreach (ref t; m_terminals) {
			t.activeVar = size_t.max;
			t.activeVarStart = size_t.max;
		}

		auto n = &m_nodes[0];

		void updatePlaceholders(size_t i)
		{
			// handle named placeholders
			foreach (t; m_terminalTags[n.terminalsStart .. n.terminalsEnd]) {
				auto term = &m_terminals[t.index];
				if (t.var != term.activeVar && term.activeVar != size_t.max) {
					term.varValues[term.activeVar] = text[term.activeVarStart .. i-1];
					term.activeVar = size_t.max;
				}
				if (t.var != size_t.max && term.activeVar == size_t.max) {
					term.activeVar = t.var;
					term.activeVarStart = i;
				}
			}
		}

		next_char:
		foreach (i, char ch; text) {
			updatePlaceholders(i);

			auto nidx = n.edges[ch];
			if (nidx == uint.max) return;
			n = &m_nodes[nidx];
		}

		updatePlaceholders(text.length);

		auto nidx = n.edges[TerminalChar];
		if (nidx == uint.max) return;
		n = &m_nodes[nidx];

		foreach (t; m_terminalTags[n.terminalsStart .. n.terminalsEnd]) {
			auto term = &m_terminals[t.index];
			// terminate any open named placeholders
			if (term.activeVar != size_t.max) term.varValues[term.activeVar] = text[term.activeVarStart .. $];
			del(t.index, term.varValues);
		}
	}

	const(string)[] getTerminalVarNames(size_t terminal) const { return m_terminals[terminal].varNames; }
	ref inout(T) getTerminalData(size_t terminal) inout { return m_terminals[terminal].data; }

	void print()
	const {
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

	private void rebuildGraph()
	{
		if (m_upToDate) return;
		m_upToDate = true;

		m_nodes = null;
		m_terminalTags = null;

		MatchGraphBuilder builder;
		foreach (i, ref t; m_terminals) {
			t.varNames = builder.insert(t.pattern, i);
			t.varValues.length = t.varNames.length;
			t.varValues[] = null;
			t.activeVar = size_t.max;
			t.activeVarStart = size_t.max;
		}
		//builder.print();
		builder.disambiguate();

		auto nodemap = new size_t[builder.m_nodes.length];
		nodemap[] = size_t.max;

		uint process(size_t n)
		{
			if (nodemap[n] != size_t.max) return nodemap[n];
			auto nmidx = cast(uint)m_nodes.length;
			nodemap[n] = nmidx;
			m_nodes.length++;

			Node nn;
			nn.terminalsStart = m_terminalTags.length;
			foreach (t; builder.m_nodes[n].terminals) {
				auto var = t.var.length ? m_terminals[t.index].varNames.countUntil(t.var) : size_t.max;
				assert(!m_terminalTags[nn.terminalsStart .. $].canFind!(u => u.index == t.index && u.var == var));
				m_terminalTags ~= TerminalTag(t.index, var);
			}
			nn.terminalsEnd = m_terminalTags.length;
			foreach (e; builder.m_nodes[n].edges)
				nn.edges[e.ch] = process(e.to);

			m_nodes[nmidx] = nn;

			return nmidx;
		}
		assert(builder.m_nodes[0].edges.length == 1, "Graph must be disambiguated before purging.");
		process(builder.m_nodes[0].edges[0].to);
	}
}

unittest {
	import std.string : format;
	MatchTree!int m;

	void testMatch(string str, size_t[] terms, string[] vars)
	{
		size_t[] mterms;
		string[] mvars;
		m.match(str, (t, vals) {
			mterms ~= t;
			mvars ~= vals;
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
	testMatch("a", [1], [""]);
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
		string[] vars;
		if (!m_nodes.length) addNode();

		// create start node and connect to zero node
		auto nidx = addNode();
		addEdge(0, nidx, '^', terminal, null);

		while (pattern.length) {
			auto ch = pattern[0];
			if (ch == '*') {
				assert(pattern.length == 1, "Asterisk is only allowed at the end of a pattern!");
				pattern = null;

				foreach (v; ubyte.min .. ubyte.max+1) {
					if (v == TerminalChar) continue;
					addEdge(nidx, nidx, cast(ubyte)v, terminal, null);
				}
			} else if (ch == ':') {
				pattern = pattern[1 .. $];
				auto name = skipPathNode(pattern);
				assert(name.length > 0, "Missing placeholder name.");
				assert(!vars.canFind(name), "Duplicate placeholder name: ':"~name~"'");
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
logInfo("Disambiguate");
		import vibe.utils.hashmap;
		HashMap!(/*immutable(size_t)[]*/string, size_t) combined_nodes;
		auto visited = new bool[m_nodes.length * 2];
		void process(size_t n)
		{
			while (n >= visited.length) visited.length = visited.length * 2;
			if (visited[n]) return;
logInfo("Disambiguate %s", n);
			visited[n] = true;

			Edge[] newedges;
			immutable(size_t)[][ubyte.max+1] edges;
			foreach (e; m_nodes[n].edges) edges[e.ch] ~= e.to;
			foreach (ch_; ubyte.min .. ubyte.max+1) {
				ubyte ch = cast(ubyte)ch_;
				auto chnodes = edges[ch_];
				auto chnodeskey = format("%s", chnodes);

				// handle trivial cases
				if (!chnodes.length) continue;
				if (chnodes.length == 1) { addToArray(newedges, Edge(ch, chnodes[0])); continue; }

				// generate combined state for ambiguous edges
				if (auto pn = chnodeskey in combined_nodes) { addToArray(newedges, Edge(ch, *pn)); continue; }

				// for new combinations, create a new node
				size_t ncomb = addNode();
				combined_nodes[chnodeskey] = ncomb;
				foreach (chn; chnodes) {
					addToArray(m_nodes[ncomb].edges, m_nodes[chn].edges);
					addToArray(m_nodes[ncomb].terminals, m_nodes[chn].terminals);
					foreach (i; 1 .. m_nodes[ncomb].terminals.length)
						assert(m_nodes[ncomb].terminals[0] != m_nodes[ncomb].terminals[i]);
				}
				newedges ~= Edge(ch, ncomb);
			}
			m_nodes[n].edges = newedges;

			// process nodes recursively
			foreach (e; newedges) process(e.to);
		}
		process(0);
logInfo("Disambiguate done");
	}

	void print()
	const {
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
	private static addToArray(T)(ref T[] arr, T elem) { if (!arr.canFind(elem)) arr ~= elem; }
}
