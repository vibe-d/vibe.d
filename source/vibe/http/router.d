/**
	Pattern based URL router.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.http.router;

public import vibe.http.server;

import vibe.core.log;
import vibe.textfilter.urlencode;

import std.functional;


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
		Route[][HTTPMethod.max+1] m_routes;
	}

	/// Adds a new route for requests matching the specified HTTP method and pattern.
	URLRouter match(HTTPMethod method, string path, HTTPServerRequestDelegate cb)
	{
		import std.algorithm;
		assert(count(path, ':') <= maxRouteParameters, "Too many route parameters");
		logDebug("add route %s %s", method, path);
		m_routes[method] ~= Route(path, cb);
		return this;
	}
	
	/// Handles a HTTP request by dispatching it to the registered route handlers.
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto method = req.method;

		while(true)
		{
			if( auto pr = &m_routes[method] ){
				foreach( ref r; *pr ){
					if( r.matches(req.path, req.params) ){
						logTrace("route match: %s -> %s %s", req.path, req.method, r.pattern);
						// .. parse fields ..
						r.cb(req, res);
						if( res.headerWritten )
							return;
					}
				}
			}
			if( method == HTTPMethod.HEAD ) method = HTTPMethod.GET;
			else break;
		}

		logTrace("no route match: %s %s", req.method, req.requestURL);
	}

    /// Returns all registered routes as const AA
	const(typeof(m_routes)) getAllRoutes()
	{
		return m_routes;
	}
}

/// Deprecated compatibility alias
deprecated("Please use URLRouter instead.") alias UrlRouter = URLRouter;


private enum maxRouteParameters = 64;

private struct Route {
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
				tmpparams[tmppparams_length++] = tuple(name, urlDecode(match));
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
