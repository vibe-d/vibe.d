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
interface HttpRouter : HttpServerRequestHandler {
	// Adds a new route for request that match the path and method
	HttpRouter match(HttpMethod method, string path, HttpServerRequestDelegate cb);
	// ditto
	final HttpRouter match(HttpMethod method, string path, HttpServerRequestHandler cb) { return match(method, path, &cb.handleRequest); }
	// ditto
	final HttpRouter match(HttpMethod method, string path, HttpServerRequestFunction cb) { return match(method, path, toDelegate(cb)); }

	// Handles the Http request by dispatching it to the registered request handler
	void handleRequest(HttpServerRequest req, HttpServerResponse res);

	// Adds a new route for GET requests matching the specified pattern.
	final HttpRouter get(string url_match, HttpServerRequestHandler cb) { return get(url_match, &cb.handleRequest); }
	// ditto
	final HttpRouter get(string url_match, HttpServerRequestFunction cb) { return get(url_match, toDelegate(cb)); }
	// ditto
	final HttpRouter get(string url_match, HttpServerRequestDelegate cb) { return match(HttpMethod.GET, url_match, cb); }

	// Adds a new route for POST requests matching the specified pattern.
	final HttpRouter post(string url_match, HttpServerRequestHandler cb) { return post(url_match, &cb.handleRequest); }
	// ditto
	final HttpRouter post(string url_match, HttpServerRequestFunction cb) { return post(url_match, toDelegate(cb)); }
	// ditto
	final HttpRouter post(string url_match, HttpServerRequestDelegate cb) { return match(HttpMethod.POST, url_match, cb); }

	// Adds a new route for PUT requests matching the specified pattern.
	final HttpRouter put(string url_match, HttpServerRequestHandler cb) { return put(url_match, &cb.handleRequest); }
	// ditto
	final HttpRouter put(string url_match, HttpServerRequestFunction cb) { return put(url_match, toDelegate(cb)); }
	// ditto
	final HttpRouter put(string url_match, HttpServerRequestDelegate cb) { return match(HttpMethod.PUT, url_match, cb); }

	// Adds a new route for DELETE requests matching the specified pattern.
	final HttpRouter delete_(string url_match, HttpServerRequestHandler cb) { return delete_(url_match, &cb.handleRequest); }
	// ditto
	final HttpRouter delete_(string url_match, HttpServerRequestFunction cb) { return delete_(url_match, toDelegate(cb)); }
	// ditto
	final HttpRouter delete_(string url_match, HttpServerRequestDelegate cb) { return match(HttpMethod.DELETE, url_match, cb); }

	// Adds a new route for PATCH requests matching the specified pattern.
	final HttpRouter patch(string url_match, HttpServerRequestHandler cb) { return patch(url_match, &cb.handleRequest); }
	// ditto
	final HttpRouter patch(string url_match, HttpServerRequestFunction cb) { return patch(url_match, toDelegate(cb)); }
	// ditto
	final HttpRouter patch(string url_match, HttpServerRequestDelegate cb) { return match(HttpMethod.PATCH, url_match, cb); }

	// Adds a new route for requests matching the specified pattern, regardless of their HTTP verb.
	final HttpRouter any(string url_match, HttpServerRequestHandler cb) { return any(url_match, &cb.handleRequest); }
	// ditto
	final HttpRouter any(string url_match, HttpServerRequestFunction cb) { return any(url_match, toDelegate(cb)); }
	// ditto
	final HttpRouter any(string url_match, HttpServerRequestDelegate cb)
	{
		return get(url_match, cb).post(url_match, cb)
			.put(url_match, cb).delete_(url_match, cb).patch(url_match, cb);
	}
}


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
	void addGroup(HttpServerRequest req, HttpServerResponse res)
	{
		// Route variables are accessible via the params map
		logInfo("Getting group %s for user %s.", req.params["groupname"], req.params["username"]);
	}

	static this()
	{
		auto router = new UrlRouter;
		// Matches all GET requests for /users/*/groups/* and places
		// the place holders in req.params as 'username' and 'groupname'.
		router.get("/users/:username/groups/:groupname", &addGroup);

		// Natches all requests. This can be useful for authorization and
		// similar tasks. The auth method will only write a response if the
		// user is _not_ authorized. Otherwise, the router will fall through
		// and continue with the following routes.
		router.any("*", &auth)

		// Matches a POST request
		router.post("/users/:username/delete", &deleteUser)

		// Matches all GET requests in /static/ such as /static/img.png or
		// /static/styles/sty.css
		router.get("/static/*", &serveStaticFiles)

		// Setup a HTTP server...
		auto settings = new HttpServerSettings;
		// ...

		// The router can be directly passed to the listenHttp function as
		// the main request handler.
		listenHttp(settings, router);
	}
	---
+/
class UrlRouter : HttpRouter {
	private {
		Route[][HttpMethod.max+1] m_routes;
	}

	/// Adds a new route for requests matching the specified HTTP method and pattern.
	UrlRouter match(HttpMethod method, string path, HttpServerRequestDelegate cb)
	{
		m_routes[method] ~= Route(path, cb);
		return this;
	}

	/// Alias for backwards compatibility
	deprecated("Please use match instead.")
	alias match addRoute;
	
	/// Handles a HTTP request by dispatching it to the registered route handlers.
	void handleRequest(HttpServerRequest req, HttpServerResponse res)
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
			if( method == HttpMethod.HEAD ) method = HttpMethod.GET;
			else break;
		}

		logTrace("no route match: %s %s", req.method, req.requestUrl);
	}
}


private struct Route {
	string pattern;
	HttpServerRequestDelegate cb;
	
	bool matches(string url, ref string[string] params)
	const {
		size_t i, j;
		for( i = 0, j = 0; i < url.length && j < pattern.length; ){
			if( pattern[j] == '*' ) return true;
			if( url[i] == pattern[j] ){
				i++;
				j++;
			} else if( pattern[j] == ':' ){
				j++;
				string name = skipPathNode(pattern, j);
				string match = skipPathNode(url, i);
				params[name] = urlDecode(match);
			} else return false;
		}

		if( j < pattern.length && pattern[j] == '*' )
			return true;

		return i == url.length && j == pattern.length;
	}
}


private string skipPathNode(string str, ref size_t idx)
{
	size_t start = idx;
	while( idx < str.length && str[idx] != '/' ) idx++;
	return str[start .. idx];
}
