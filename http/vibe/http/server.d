/**
	A HTTP 1.1/1.0 server implementation.

	Copyright: © 2012-2017 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger, Ilya Shipunov
*/
module vibe.http.server;

public import vibe.core.net;
public import vibe.http.common;
public import vibe.http.session;

import vibe.core.file;
import vibe.core.log;
import vibe.data.json;
import vibe.http.dist;
import vibe.http.log;
import vibe.inet.message;
import vibe.inet.url;
import vibe.inet.webform;
import vibe.internal.interfaceproxy : InterfaceProxy;
import vibe.stream.counting;
import vibe.stream.operations;
import vibe.stream.tls;
import vibe.stream.wrapper : ConnectionProxyStream, createConnectionProxyStream, createConnectionProxyStreamFL;
import vibe.stream.zlib;
import vibe.textfilter.urlencode;
import vibe.utils.array;
import vibe.internal.allocator;
import vibe.internal.freelistref;
import vibe.utils.string;

import core.atomic;
import core.vararg;
import diet.traits : SafeFilterCallback, dietTraits;
import std.algorithm : canFind;
import std.array;
import std.conv;
import std.datetime;
import std.encoding : sanitize;
import std.exception;
import std.format;
import std.functional : toDelegate;
import std.string;
import std.traits : ReturnType;
import std.typecons;
import std.uri;


version (VibeNoSSL) version = HaveNoTLS;
else version (Have_botan) {}
else version (Have_openssl) {}
else version = HaveNoTLS;

/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Starts a HTTP server listening on the specified port.

	request_handler will be called for each HTTP request that is made. The
	res parameter of the callback then has to be filled with the response
	data.

	request_handler can be either HTTPServerRequestDelegate/HTTPServerRequestFunction
	or a class/struct with a member function 'handleRequest' that has the same
	signature.

	Note that if the application has been started with the --disthost command line
	switch, listenHTTP() will automatically listen on the specified VibeDist host
	instead of locally. This allows for a seamless switch from single-host to
	multi-host scenarios without changing the code. If you need to listen locally,
	use listenHTTPPlain() instead.

	Params:
		settings = Customizes the HTTP servers functionality (host string or HTTPServerSettings object)
		request_handler = This callback is invoked for each incoming request and is responsible
			for generating the response.

	Returns:
		A handle is returned that can be used to stop listening for further HTTP
		requests with the supplied settings. Another call to `listenHTTP` can be
		used afterwards to start listening again.
*/
HTTPListener listenHTTP(Settings)(Settings _settings, HTTPServerRequestDelegate request_handler)
@safe
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	// auto-construct HTTPServerSettings
	static if (is(Settings == string))
		auto settings = new HTTPServerSettings(_settings);
	else
		alias settings = _settings;

	enforce(settings.bindAddresses.length, "Must provide at least one bind address for a HTTP server.");

	// if a VibeDist host was specified on the command line, register there instead of listening
	// directly.
	if (s_distHost.length && !settings.disableDistHost) {
		return listenHTTPDist(settings, request_handler, s_distHost, s_distPort);
	} else {
		return listenHTTPPlain(settings, request_handler);
	}
}
/// ditto
HTTPListener listenHTTP(Settings)(Settings settings, HTTPServerRequestFunction request_handler)
@safe
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, () @trusted { return toDelegate(request_handler); } ());
}
/// ditto
HTTPListener listenHTTP(Settings)(Settings settings, HTTPServerRequestHandler request_handler)
@safe
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, &request_handler.handleRequest);
}
/// ditto
HTTPListener listenHTTP(Settings)(Settings settings, HTTPServerRequestDelegateS request_handler)
@safe
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, cast(HTTPServerRequestDelegate)request_handler);
}
/// ditto
HTTPListener listenHTTP(Settings)(Settings settings, HTTPServerRequestFunctionS request_handler)
@safe
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, () @trusted { return toDelegate(request_handler); } ());
}
/// ditto
HTTPListener listenHTTP(Settings)(Settings settings, HTTPServerRequestHandlerS request_handler)
@safe
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, &request_handler.handleRequest);
}

/// Scheduled for deprecation - use a `@safe` callback instead.
HTTPListener listenHTTP(Settings)(Settings settings, void delegate(HTTPServerRequest, HTTPServerResponse) @system request_handler)
@system
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, (req, res) @trusted => request_handler(req, res));
}
/// ditto
HTTPListener listenHTTP(Settings)(Settings settings, void function(HTTPServerRequest, HTTPServerResponse) @system request_handler)
@system
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, (req, res) @trusted => request_handler(req, res));
}
/// ditto
HTTPListener listenHTTP(Settings)(Settings settings, void delegate(scope HTTPServerRequest, scope HTTPServerResponse) @system request_handler)
@system
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, (scope req, scope res) @trusted => request_handler(req, res));
}
/// ditto
HTTPListener listenHTTP(Settings)(Settings settings, void function(scope HTTPServerRequest, scope HTTPServerResponse) @system request_handler)
@system
if (is(Settings == string) || is(Settings == HTTPServerSettings)) {
	return listenHTTP(settings, (scope req, scope res) @trusted => request_handler(req, res));
}

unittest
{
	void test()
	{
		static void testSafeFunction(HTTPServerRequest req, HTTPServerResponse res) @safe {}
		listenHTTP("0.0.0.0:8080", &testSafeFunction);
		listenHTTP(":8080", new class HTTPServerRequestHandler {
			void handleRequest(HTTPServerRequest req, HTTPServerResponse res) @safe {}
		});
		listenHTTP(":8080", (req, res) {});

		static void testSafeFunctionS(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {}
		listenHTTP(":8080", &testSafeFunctionS);
		void testSafeDelegateS(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {}
		listenHTTP(":8080", &testSafeDelegateS);
		listenHTTP(":8080", new class HTTPServerRequestHandler {
			void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {}
		});
		listenHTTP(":8080", (scope req, scope res) {});
	}
}


/** Treats an existing connection as an HTTP connection and processes incoming
	requests.

	After all requests have been processed, the connection will be closed and
	the function returns to the caller.

	Params:
		connections = The stream to treat as an incoming HTTP client connection.
		context = Information about the incoming listener and available
			virtual hosts
*/
void handleHTTPConnection(TCPConnection connection, HTTPServerContext context)
@safe {
	InterfaceProxy!Stream http_stream;
	http_stream = connection;

	scope (exit) connection.close();

	// Set NODELAY to true, to avoid delays caused by sending the response
	// header and body in separate chunks. Note that to avoid other performance
	// issues (caused by tiny packets), this requires using an output buffer in
	// the event driver, which is the case at least for the default libevent
	// based driver.
	connection.tcpNoDelay = true;

	version(HaveNoTLS) {} else {
		TLSStreamType tls_stream;
	}

	if (!connection.waitForData(10.seconds())) {
		logDebug("Client didn't send the initial request in a timely manner. Closing connection.");
		return;
	}

	// If this is a HTTPS server, initiate TLS
	if (context.tlsContext) {
		version (HaveNoTLS) assert(false, "No TLS support compiled in.");
		else {
			logDebug("Accept TLS connection: %s", context.tlsContext.kind);
			// TODO: reverse DNS lookup for peer_name of the incoming connection for TLS client certificate verification purposes
			tls_stream = createTLSStreamFL(http_stream, context.tlsContext, TLSStreamState.accepting, null, connection.remoteAddress);
			http_stream = tls_stream;
		}
	}

	while (!connection.empty) {
		HTTPServerSettings settings;
		bool keep_alive;

		() @trusted {
			import vibe.internal.utilallocator: RegionListAllocator;

			version (VibeManualMemoryManagement)
				scope request_allocator = new RegionListAllocator!(shared(Mallocator), false)(1024, Mallocator.instance);
			else
				scope request_allocator = new RegionListAllocator!(shared(GCAllocator), true)(1024, GCAllocator.instance);

			handleRequest(http_stream, connection, context, settings, keep_alive, request_allocator);
		} ();
		if (!keep_alive) { logTrace("No keep-alive - disconnecting client."); break; }

		logTrace("Waiting for next request...");
		// wait for another possible request on a keep-alive connection
		if (!connection.waitForData(settings.keepAliveTimeout)) {
			if (!connection.connected) logTrace("Client disconnected.");
			else logDebug("Keep-alive connection timed out!");
			break;
		}
	}

	logTrace("Done handling connection.");
}


/**
	Provides a HTTP request handler that responds with a static Diet template.
*/
@property HTTPServerRequestDelegateS staticTemplate(string template_file)()
{
	return (scope HTTPServerRequest req, scope HTTPServerResponse res){
		res.render!(template_file, req);
	};
}

/**
	Provides a HTTP request handler that responds with a static redirection to the specified URL.

	Params:
		url = The URL to redirect to
		status = Redirection status to use $(LPAREN)by default this is $(D HTTPStatus.found)$(RPAREN).

	Returns:
		Returns a $(D HTTPServerRequestDelegate) that performs the redirect
*/
HTTPServerRequestDelegate staticRedirect(string url, HTTPStatus status = HTTPStatus.found)
@safe {
	return (HTTPServerRequest req, HTTPServerResponse res){
		res.redirect(url, status);
	};
}
/// ditto
HTTPServerRequestDelegate staticRedirect(URL url, HTTPStatus status = HTTPStatus.found)
@safe {
	return (HTTPServerRequest req, HTTPServerResponse res){
		res.redirect(url, status);
	};
}

///
unittest {
	import vibe.http.router;

	void test()
	{
		auto router = new URLRouter;
		router.get("/old_url", staticRedirect("http://example.org/new_url", HTTPStatus.movedPermanently));

		listenHTTP(new HTTPServerSettings, router);
	}
}


/**
	Sets a VibeDist host to register with.
*/
void setVibeDistHost(string host, ushort port)
@safe {
	s_distHost = host;
	s_distPort = port;
}


/**
	Renders the given Diet template and makes all ALIASES available to the template.

	You can call this function as a pseudo-member of `HTTPServerResponse` using
	D's uniform function call syntax.

	See_also: `diet.html.compileHTMLDietFile`

	Examples:
		---
		string title = "Hello, World!";
		int pageNumber = 1;
		res.render!("mytemplate.dt", title, pageNumber);
		---
*/
@property void render(string template_file, ALIASES...)(HTTPServerResponse res)
{
	res.contentType = "text/html; charset=UTF-8";
	version (VibeUseOldDiet)
		pragma(msg, "VibeUseOldDiet is not supported anymore. Please undefine in the package recipe.");
	import vibe.stream.wrapper : streamOutputRange;
	import diet.html : compileHTMLDietFile;
	auto output = streamOutputRange!1024(res.bodyWriter);
	compileHTMLDietFile!(template_file, ALIASES, DefaultDietFilters)(output);
}


/**
	Provides the default `css`, `javascript`, `markdown` and `htmlescape` filters
 */
@dietTraits
struct DefaultDietFilters {
	import diet.html : HTMLOutputStyle;
	import diet.traits : SafeFilterCallback;
	import std.string : splitLines;

	version (VibeOutputCompactHTML) enum HTMLOutputStyle htmlOutputStyle = HTMLOutputStyle.compact;
	else enum HTMLOutputStyle htmlOutputStyle = HTMLOutputStyle.pretty;

	static string filterCss(I)(I text, size_t indent = 0)
	{
		auto lines = splitLines(text);

		string indent_string = "\n";
		while (indent-- > 0) indent_string ~= '\t';

		string ret = indent_string~"<style type=\"text/css\"><!--";
		indent_string = indent_string ~ '\t';
		foreach (ln; lines) ret ~= indent_string ~ ln;
		indent_string = indent_string[0 .. $-1];
		ret ~= indent_string ~ "--></style>";

		return ret;
	}


	static string filterJavascript(I)(I text, size_t indent = 0)
	{
		auto lines = splitLines(text);

		string indent_string = "\n";
		while (indent-- > 0) indent_string ~= '\t';

		string ret = indent_string~"<script type=\"application/javascript\">";
		ret ~= indent_string~'\t' ~ "//<![CDATA[";
		foreach (ln; lines) ret ~= indent_string ~ '\t' ~ ln;
		ret ~= indent_string ~ '\t' ~ "//]]>" ~ indent_string ~ "</script>";

		return ret;
	}

	static string filterMarkdown(I)(I text)
	{
		import vibe.textfilter.markdown : markdown = filterMarkdown;
		// TODO: indent
		return markdown(text);
	}

	static string filterHtmlescape(I)(I text)
	{
		import vibe.textfilter.html : htmlEscape;
		// TODO: indent
		return htmlEscape(text);
	}

	static this()
	{
		filters["css"] = (input, scope output) { output(filterCss(input)); };
		filters["javascript"] = (input, scope output) { output(filterJavascript(input)); };
		filters["markdown"] = (input, scope output) { output(filterMarkdown(() @trusted { return cast(string)input; } ())); };
		filters["htmlescape"] = (input, scope output) { output(filterHtmlescape(input)); };
	}

	static SafeFilterCallback[string] filters;
}


unittest {
	static string compile(string diet)() {
		import std.array : appender;
		import std.string : strip;
		import diet.html : compileHTMLDietString;
		auto dst = appender!string;
		dst.compileHTMLDietString!(diet, DefaultDietFilters);
		return strip(cast(string)(dst.data));
	}

	assert(compile!":css .test" == "<style type=\"text/css\"><!--\n\t.test\n--></style>");
	assert(compile!":javascript test();" == "<script type=\"application/javascript\">\n\t//<![CDATA[\n\ttest();\n\t//]]>\n</script>");
	assert(compile!":markdown **test**" == "<p><strong>test</strong>\n</p>");
	assert(compile!":htmlescape <test>" == "&lt;test&gt;");
	assert(compile!":css !{\".test\"}" == "<style type=\"text/css\"><!--\n\t.test\n--></style>");
	assert(compile!":javascript !{\"test();\"}" == "<script type=\"application/javascript\">\n\t//<![CDATA[\n\ttest();\n\t//]]>\n</script>");
	assert(compile!":markdown !{\"**test**\"}" == "<p><strong>test</strong>\n</p>");
	assert(compile!":htmlescape !{\"<test>\"}" == "&lt;test&gt;");
	assert(compile!":javascript\n\ttest();" == "<script type=\"application/javascript\">\n\t//<![CDATA[\n\ttest();\n\t//]]>\n</script>");
}


/**
	Creates a HTTPServerRequest suitable for writing unit tests.
*/
HTTPServerRequest createTestHTTPServerRequest(URL url, HTTPMethod method = HTTPMethod.GET, InputStream data = null)
@safe {
	InetHeaderMap headers;
	return createTestHTTPServerRequest(url, method, headers, data);
}
/// ditto
HTTPServerRequest createTestHTTPServerRequest(URL url, HTTPMethod method, InetHeaderMap headers, InputStream data = null)
@safe {
	auto tls = url.schema == "https";
	auto ret = new HTTPServerRequest(Clock.currTime(UTC()), url.port ? url.port : tls ? 443 : 80);
	ret.requestPath = url.path;
	ret.queryString = url.queryString;
	ret.username = url.username;
	ret.password = url.password;
	ret.requestURI = url.localURI;
	ret.method = method;
	ret.tls = tls;
	ret.headers = headers;
	ret.bodyReader = data;
	return ret;
}

/**
	Creates a HTTPServerResponse suitable for writing unit tests.
*/
HTTPServerResponse createTestHTTPServerResponse(OutputStream data_sink = null, SessionStore session_store = null)
@safe {
	import vibe.stream.wrapper;

	HTTPServerSettings settings;
	if (session_store) {
		settings = new HTTPServerSettings;
		settings.sessionStore = session_store;
	}
	if (!data_sink) data_sink = new NullOutputStream;
	auto stream = createProxyStream(Stream.init, data_sink);
	auto ret = new HTTPServerResponse(stream, null, settings, () @trusted { return vibeThreadAllocator(); } ());
	return ret;
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/// Delegate based request handler
alias HTTPServerRequestDelegate = void delegate(HTTPServerRequest req, HTTPServerResponse res) @safe;
/// Static function based request handler
alias HTTPServerRequestFunction = void function(HTTPServerRequest req, HTTPServerResponse res) @safe;
/// Interface for class based request handlers
interface HTTPServerRequestHandler {
	/// Handles incoming HTTP requests
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res) @safe ;
}

/// Delegate based request handler with scoped parameters
alias HTTPServerRequestDelegateS = void delegate(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe;
/// Static function based request handler with scoped parameters
alias HTTPServerRequestFunctionS  = void function(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe;
/// Interface for class based request handlers with scoped parameters
interface HTTPServerRequestHandlerS {
	/// Handles incoming HTTP requests
	void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe;
}

unittest {
	static assert(is(HTTPServerRequestDelegateS : HTTPServerRequestDelegate));
	static assert(is(HTTPServerRequestFunctionS : HTTPServerRequestFunction));
}

/// Aggregates all information about an HTTP error status.
final class HTTPServerErrorInfo {
	/// The HTTP status code
	int code;
	/// The error message
	string message;
	/// Extended error message with debug information such as a stack trace
	string debugMessage;
	/// The error exception, if any
	Throwable exception;
}

/// Delegate type used for user defined error page generator callbacks.
alias HTTPServerErrorPageHandler = void delegate(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error) @safe;


private enum HTTPServerOptionImpl {
	none                      = 0,
	errorStackTraces          = 1<<7,
	reusePort                 = 1<<8,
	distribute                = 1<<9 // deprecated
}

// TODO: Should be turned back into an enum once the deprecated symbols can be removed
/**
	Specifies optional features of the HTTP server.

	Disabling unneeded features can speed up the server or reduce its memory usage.

	Note that the options `parseFormBody`, `parseJsonBody` and `parseMultiPartBody`
	will also drain the `HTTPServerRequest.bodyReader` stream whenever a request
	body with form or JSON data is encountered.
*/
struct HTTPServerOption {
	static enum none                      = HTTPServerOptionImpl.none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum parseURL                  = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum parseQueryString          = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum parseFormBody             = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum parseJsonBody             = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum parseMultiPartBody        = none;
	/** Deprecated: Distributes request processing among worker threads

		Note that this functionality assumes that the request handler
		is implemented in a thread-safe way. However, the D type system
		is bypassed, so that no static verification takes place.

		For this reason, it is recommended to instead use
		`vibe.core.core.runWorkerTaskDist` and call `listenHTTP`
		from each task/thread individually. If the `reusePort` option
		is set, then all threads will be able to listen on the same port,
		with the operating system distributing the incoming connections.

		If possible, instead of threads, the use of separate processes
		is more robust and often faster. The `reusePort` option works
		the same way in this scenario.
	*/
	deprecated("Use runWorkerTaskDist or start threads separately. It will be removed in 0.9.")
	static enum distribute                = HTTPServerOptionImpl.distribute;
	/** Enables stack traces (`HTTPServerErrorInfo.debugMessage`).

		Note that generating the stack traces are generally a costly
		operation that should usually be avoided in production
		environments. It can also reveal internal information about
		the application, such as function addresses, which can
		help an attacker to abuse possible security holes.
	*/
	static enum errorStackTraces          = HTTPServerOptionImpl.errorStackTraces;
	/// Enable port reuse in `listenTCP()`
	static enum reusePort                 = HTTPServerOptionImpl.reusePort;

	/** The default set of options.

		Includes all parsing options, as well as the `errorStackTraces`
		option if the code is compiled in debug mode.
	*/
	static enum defaults = () { debug return HTTPServerOptionImpl.errorStackTraces; else return HTTPServerOptionImpl.none; } ().HTTPServerOption;

	deprecated("None has been renamed to none.")
	static enum None = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum ParseURL = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum ParseQueryString = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum ParseFormBody = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum ParseJsonBody = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum ParseMultiPartBody = none;
	deprecated("This is done lazily. It will be removed in 0.9.")
	static enum ParseCookies = none;

	HTTPServerOptionImpl x;
	alias x this;
}


/**
	Contains all settings for configuring a basic HTTP server.

	The defaults are sufficient for most normal uses.
*/
final class HTTPServerSettings {
	/** The port on which the HTTP server is listening.

		The default value is 80. If you are running a TLS enabled server you may want to set this
		to 443 instead.

		Using a value of `0` instructs the server to use any available port on
		the given `bindAddresses` the actual addresses and ports can then be
		queried with `TCPListener.bindAddresses`.
	*/
	ushort port = 80;

	/** The interfaces on which the HTTP server is listening.

		By default, the server will listen on all IPv4 and IPv6 interfaces.
	*/
	string[] bindAddresses = ["::", "0.0.0.0"];

	/** Determines the server host name.

		If multiple servers are listening on the same port, the host name will determine which one
		gets a request.
	*/
	string hostName;

	/** Configures optional features of the HTTP server

		Disabling unneeded features can improve performance or reduce the server
		load in case of invalid or unwanted requests (DoS). By default,
		HTTPServerOption.defaults is used.
	*/
	HTTPServerOptionImpl options = HTTPServerOption.defaults;

	/** Time of a request after which the connection is closed with an error; not supported yet

		The default limit of 0 means that the request time is not limited.
	*/
	Duration maxRequestTime = 0.seconds;

	/** Maximum time between two request on a keep-alive connection

		The default value is 10 seconds.
	*/
	Duration keepAliveTimeout = 10.seconds;

	/// Maximum number of transferred bytes per request after which the connection is closed with
	/// an error
	ulong maxRequestSize = 2097152;


	///	Maximum number of transferred bytes for the request header. This includes the request line
	/// the url and all headers.
	ulong maxRequestHeaderSize = 8192;

	/// Sets a custom handler for displaying error pages for HTTP errors
	@property HTTPServerErrorPageHandler errorPageHandler() @safe { return errorPageHandler_; }
	/// ditto
	@property void errorPageHandler(HTTPServerErrorPageHandler del) @safe { errorPageHandler_ = del; }
	/// Scheduled for deprecation - use a `@safe` callback instead.
	@property void errorPageHandler(void delegate(HTTPServerRequest, HTTPServerResponse, HTTPServerErrorInfo) @system del)
	@system {
		this.errorPageHandler = (req, res, err) @trusted { del(req, res, err); };
	}

	private HTTPServerErrorPageHandler errorPageHandler_ = null;

	/// If set, a HTTPS server will be started instead of plain HTTP.
	TLSContext tlsContext;

	/// Session management is enabled if a session store instance is provided
	SessionStore sessionStore;
	string sessionIdCookie = "vibe.session_id";

	///
	import vibe.core.core : vibeVersionString;
	string serverString = "vibe.d/" ~ vibeVersionString;

	/** Specifies the format used for the access log.

		The log format is given using the Apache server syntax. By default NCSA combined is used.

		---
		"%h - %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-Agent}i\""
		---
	*/
	string accessLogFormat = "%h - %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-Agent}i\"";

	/// Spefifies the name of a file to which access log messages are appended.
	string accessLogFile = "";

	/// If set, access log entries will be output to the console.
	bool accessLogToConsole = false;

	/** Specifies a custom access logger instance.
	*/
	HTTPLogger accessLogger;

	/// Returns a duplicate of the settings object.
	@property HTTPServerSettings dup()
	@safe {
		auto ret = new HTTPServerSettings;
		foreach (mem; __traits(allMembers, HTTPServerSettings)) {
			static if (mem == "sslContext") {}
			else static if (mem == "bindAddresses") ret.bindAddresses = bindAddresses.dup;
			else static if (__traits(compiles, __traits(getMember, ret, mem) = __traits(getMember, this, mem)))
				__traits(getMember, ret, mem) = __traits(getMember, this, mem);
		}
		return ret;
	}

	/// Disable support for VibeDist and instead start listening immediately.
	bool disableDistHost = false;

	/** Responds to "Accept-Encoding" by using compression if possible.

		Compression can also be manually enabled by setting the
		"Content-Encoding" header of the HTTP response appropriately before
		sending the response body.

		This setting is disabled by default. Also note that there are still some
		known issues with the GZIP compression code.
	*/
	bool useCompressionIfPossible = false;


	/** Interval between WebSocket ping frames.

		The default value is 60 seconds; set to Duration.zero to disable pings.
	*/
	Duration webSocketPingInterval = 60.seconds;

	/** Constructs a new settings object with default values.
	*/
	this() @safe {}

	/** Constructs a new settings object with a custom bind interface and/or port.

		The syntax of `bind_string` is `[<IP address>][:<port>]`, where either of
		the two parts can be left off. IPv6 addresses must be enclosed in square
		brackets, as they would within a URL.

		Throws:
			An exception is thrown if `bind_string` is malformed.
	*/
	this(string bind_string)
	@safe {
		this();

		if (bind_string.startsWith('[')) {
			auto idx = bind_string.indexOf(']');
			enforce(idx > 0, "Missing closing bracket for IPv6 address.");
			bindAddresses = [bind_string[1 .. idx]];
			bind_string = bind_string[idx+1 .. $];

			enforce(bind_string.length == 0 || bind_string.startsWith(':'),
				"Only a colon may follow the IPv6 address.");
		}

		auto idx = bind_string.indexOf(':');
		if (idx < 0) {
			if (bind_string.length > 0) bindAddresses = [bind_string];
		} else {
			if (idx > 0) bindAddresses = [bind_string[0 .. idx]];
			port = bind_string[idx+1 .. $].to!ushort;
		}
	}

	///
	unittest {
		auto s = new HTTPServerSettings(":8080");
		assert(s.bindAddresses == ["::", "0.0.0.0"]); // default bind addresses
		assert(s.port == 8080);

		s = new HTTPServerSettings("123.123.123.123");
		assert(s.bindAddresses == ["123.123.123.123"]);
		assert(s.port == 80);

		s = new HTTPServerSettings("[::1]:443");
		assert(s.bindAddresses == ["::1"]);
		assert(s.port == 443);
	}
}


/**
	Options altering how sessions are created.

	Multiple values can be or'ed together.

	See_Also: HTTPServerResponse.startSession
*/
enum SessionOption {
	/// No options.
	none = 0,

	/** Instructs the browser to disallow accessing the session ID from JavaScript.

		See_Also: Cookie.httpOnly
	*/
	httpOnly = 1<<0,

	/** Instructs the browser to disallow sending the session ID over
		unencrypted connections.

		By default, the type of the connection on which the session is started
		will be used to determine if secure or noSecure is used.

		See_Also: noSecure, Cookie.secure
	*/
	secure = 1<<1,

	/** Instructs the browser to allow sending the session ID over unencrypted
		connections.

		By default, the type of the connection on which the session is started
		will be used to determine if secure or noSecure is used.

		See_Also: secure, Cookie.secure
	*/
	noSecure = 1<<2
}


/**
	Represents a HTTP request as received by the server side.
*/
final class HTTPServerRequest : HTTPRequest {
	private {
		SysTime m_timeCreated;
		HTTPServerSettings m_settings;
		ushort m_port;
		string m_peer;
	}

	public {
		/// The IP address of the client
		@property string peer()
		@safe nothrow {
			if (!m_peer) {
				version (Have_vibe_core) {} else scope (failure) assert(false);
				// store the IP address (IPv4 addresses forwarded over IPv6 are stored in IPv4 format)
				auto peer_address_string = this.clientAddress.toString();
				if (peer_address_string.startsWith("::ffff:") && peer_address_string[7 .. $].indexOf(':') < 0)
					m_peer = peer_address_string[7 .. $];
				else m_peer = peer_address_string;
			}
			return m_peer;
		}
		/// ditto
		NetworkAddress clientAddress;

		/// Determines if the request should be logged to the access log file.
		bool noLog;

		/// Determines if the request was issued over an TLS encrypted channel.
		bool tls;

		/** Information about the TLS certificate provided by the client.

			Remarks: This field is only set if `tls` is true, and the peer
			presented a client certificate.
		*/
		TLSCertificateInformation clientCertificate;

		/** Deprecated: The _path part of the URL.

			Note that this function contains the decoded version of the
			requested path, which can yield incorrect results if the path
			contains URL encoded path separators. Use `requestPath` instead to
			get an encoding-aware representation.
		*/
		string path() @safe {
			if (_path.isNull) {
				_path = urlDecode(requestPath.toString);
			}
			return _path.get;
		}

		private Nullable!string _path;

		/** The path part of the requested URI.
		*/
		InetPath requestPath;

		/** The user name part of the URL, if present.
		*/
		string username;

		/** The _password part of the URL, if present.
		*/
		string password;

		/** The _query string part of the URL.
		*/
		string queryString;

		/** Contains the list of _cookies that are stored on the client.

			Note that the a single cookie name may occur multiple times if multiple
			cookies have that name but different paths or domains that all match
			the request URI. By default, the first cookie will be returned, which is
			the or one of the cookies with the closest path match.
		*/
		@property ref CookieValueMap cookies() @safe {
			if (_cookies.isNull) {
				_cookies = CookieValueMap.init;
				if (auto pv = "cookie" in headers)
					parseCookies(*pv, _cookies);
			}
			return _cookies.get;
		}
		private Nullable!CookieValueMap _cookies;

		/** Contains all _form fields supplied using the _query string.

			The fields are stored in the same order as they are received.
		*/
		@property ref FormFields query() @safe {
			if (_query.isNull) {
				_query = FormFields.init;
				parseURLEncodedForm(queryString, _query);
			}

			return _query.get;
		}
		Nullable!FormFields _query;

		import vibe.utils.dictionarylist;
		/** A map of general parameters for the request.

			This map is supposed to be used by middleware functionality to store
			information for later stages. For example vibe.http.router.URLRouter uses this map
			to store the value of any named placeholders.
		*/
		DictionaryList!(string, true, 8) params;

		import std.variant : Variant;
		/** A map of context items for the request.

			This is especially useful for passing application specific data down
			the chain of processors along with the request itself.

			For example, a generic route may be defined to check user login status,
			if the user is logged in, add a reference to user specific data to the
			context.

			This is implemented with `std.variant.Variant` to allow any type of data.
		*/
		DictionaryList!(Variant, true, 2) context;

		/** Supplies the request body as a stream.

			Note that when certain server options are set (such as
			HTTPServerOption.parseJsonBody) and a matching request was sent,
			the returned stream will be empty. If needed, remove those
			options and do your own processing of the body when launching
			the server. HTTPServerOption has a list of all options that affect
			the request body.
		*/
		InputStream bodyReader;

		/** Contains the parsed Json for a JSON request.

			A JSON request must have the Content-Type "application/json" or "application/vnd.api+json".
		*/
		@property ref Json json() @safe {
			if (_json.isNull) {
				if (icmp2(contentType, "application/json") == 0 || icmp2(contentType, "application/vnd.api+json") == 0 ) {
					auto bodyStr = bodyReader.readAllUTF8();
					if (!bodyStr.empty) _json = parseJson(bodyStr);
					else _json = Json.undefined;
				} else {
					_json = Json.undefined;
				}
			}
			return _json.get;
		}

		private Nullable!Json _json;

		/** Contains the parsed parameters of a HTML POST _form request.

			The fields are stored in the same order as they are received.

			Remarks:
				A form request must either have the Content-Type
				"application/x-www-form-urlencoded" or "multipart/form-data".
		*/
		@property ref FormFields form() @safe {
			if (_form.isNull)
				parseFormAndFiles();

			return _form.get;
		}

		private Nullable!FormFields _form;

		private void parseFormAndFiles() @safe {
			_form = FormFields.init;
			parseFormData(_form, _files, headers.get("Content-Type", ""), bodyReader, MaxHTTPHeaderLineLength);
		}

		/** Contains information about any uploaded file for a HTML _form request.
		*/
		@property ref FilePartFormFields files() @safe {
			// _form and _files are parsed in one step
			if (_form.isNull) {
				parseFormAndFiles();
				assert(!_form.isNull);
			}

            return _files;
		}

		private FilePartFormFields _files;

		/** The current Session object.

			This field is set if HTTPServerResponse.startSession() has been called
			on a previous response and if the client has sent back the matching
			cookie.

			Remarks: Requires the HTTPServerOption.parseCookies option.
		*/
		Session session;
	}

	package {
		/** The settings of the server serving this request.
		 */
		@property const(HTTPServerSettings) serverSettings() const @safe
		{
			return m_settings;
		}
	}

	this(SysTime time, ushort port)
	@safe {
		m_timeCreated = time.toUTC();
		m_port = port;
	}

	/** Time when this request started processing.
	*/
	@property SysTime timeCreated() const @safe { return m_timeCreated; }


	/** The full URL that corresponds to this request.

		The host URL includes the protocol, host and optionally the user
		and password that was used for this request. This field is useful to
		construct self referencing URLs.

		Note that the port is currently not set, so that this only works if
		the standard port is used.
	*/
	@property URL fullURL()
	const @safe {
		URL url;

		auto xfh = this.headers.get("X-Forwarded-Host");
		auto xfp = this.headers.get("X-Forwarded-Port");
		auto xfpr = this.headers.get("X-Forwarded-Proto");

		// Set URL host segment.
		if (xfh.length) {
			url.host = xfh;
		} else if (!this.host.empty) {
			url.host = this.host;
		} else if (!m_settings.hostName.empty) {
			url.host = m_settings.hostName;
		} else {
			url.host = m_settings.bindAddresses[0];
		}

		// Set URL schema segment.
		if (xfpr.length) {
			url.schema = xfpr;
		} else if (this.tls) {
			url.schema = "https";
		} else {
			url.schema = "http";
		}

		// Set URL port segment.
		if (xfp.length) {
			try {
				url.port = xfp.to!ushort;
			} catch (ConvException) {
				// TODO : Consider responding with a 400/etc. error from here.
				logWarn("X-Forwarded-Port header was not valid port (%s)", xfp);
			}
		} else if (!xfh) {
			if (url.schema == "https") {
				if (m_port != 443U) url.port = m_port;
			} else {
				if (m_port != 80U)  url.port = m_port;
			}
		}

		if (url.host.startsWith('[')) { // handle IPv6 address
			auto idx = url.host.indexOf(']');
			if (idx >= 0 && idx+1 < url.host.length && url.host[idx+1] == ':')
				url.host = url.host[1 .. idx];
		} else { // handle normal host names or IPv4 address
			auto idx = url.host.indexOf(':');
			if (idx >= 0) url.host = url.host[0 .. idx];
		}

		url.username = this.username;
		url.password = this.password;
		url.localURI = this.requestURI;

		return url;
	}

	/** The relative path to the root folder.

		Using this function instead of absolute URLs for embedded links can be
		useful to avoid dead link when the site is piped through a
		reverse-proxy.

		The returned string always ends with a slash.
	*/
	@property string rootDir()
	const @safe {
		import std.algorithm.searching : count;
		auto depth = requestPath.bySegment.count!(s => s.name.length > 0);
		if (depth > 0 && !requestPath.endsWithSlash) depth--;
		return depth == 0 ? "./" : replicate("../", depth);
	}

	unittest {
		assert(createTestHTTPServerRequest(URL("http://localhost/")).rootDir == "./");
		assert(createTestHTTPServerRequest(URL("http://localhost/foo")).rootDir == "./");
		assert(createTestHTTPServerRequest(URL("http://localhost/foo/")).rootDir == "../");
		assert(createTestHTTPServerRequest(URL("http://localhost/foo/bar")).rootDir == "../");
		assert(createTestHTTPServerRequest(URL("http://localhost")).rootDir == "./");
	}
}


/**
	Represents a HTTP response as sent from the server side.
*/
final class HTTPServerResponse : HTTPResponse {
	private {
		InterfaceProxy!Stream m_conn;
		InterfaceProxy!ConnectionStream m_rawConnection;
		InterfaceProxy!OutputStream m_bodyWriter;
		IAllocator m_requestAlloc;
		FreeListRef!ChunkedOutputStream m_chunkedBodyWriter;
		FreeListRef!CountingOutputStream m_countingWriter;
		FreeListRef!ZlibOutputStream m_zlibOutputStream;
		HTTPServerSettings m_settings;
		Session m_session;
		bool m_headerWritten = false;
		bool m_isHeadResponse = false;
		bool m_tls;
		bool m_requiresConnectionClose;
		SysTime m_timeFinalized;
	}

	static if (!is(Stream == InterfaceProxy!Stream)) {
		this(Stream conn, ConnectionStream raw_connection, HTTPServerSettings settings, IAllocator req_alloc)
		@safe {
			this(InterfaceProxy!Stream(conn), InterfaceProxy!ConnectionStream(raw_connection), settings, req_alloc);
		}
	}

	this(InterfaceProxy!Stream conn, InterfaceProxy!ConnectionStream raw_connection, HTTPServerSettings settings, IAllocator req_alloc)
	@safe {
		m_conn = conn;
		m_rawConnection = raw_connection;
		m_countingWriter = createCountingOutputStreamFL(conn);
		m_settings = settings;
		m_requestAlloc = req_alloc;
	}

	/** Returns the time at which the request was finalized.

		Note that this field will only be set after `finalize` has been called.
	*/
	@property SysTime timeFinalized() const @safe { return m_timeFinalized; }

	/** Determines if the HTTP header has already been written.
	*/
	@property bool headerWritten() const @safe { return m_headerWritten; }

	/** Determines if the response does not need a body.
	*/
	bool isHeadResponse() const @safe { return m_isHeadResponse; }

	/** Determines if the response is sent over an encrypted connection.
	*/
	bool tls() const @safe { return m_tls; }

	/** Writes the entire response body at once.

		Params:
			data = The data to write as the body contents
			status = Optional response status code to set
			content_tyoe = Optional content type to apply to the response.
				If no content type is given and no "Content-Type" header is
				set in the response, this will default to
				`"application/octet-stream"`.

		See_Also: `HTTPStatusCode`
	*/
	void writeBody(in ubyte[] data, string content_type = null)
	@safe {
		if (content_type.length) headers["Content-Type"] = content_type;
		else if ("Content-Type" !in headers) headers["Content-Type"] = "application/octet-stream";
		headers["Content-Length"] = formatAlloc(m_requestAlloc, "%d", data.length);
		bodyWriter.write(data);
	}
	/// ditto
	void writeBody(in ubyte[] data, int status, string content_type = null)
	@safe {
		statusCode = status;
		writeBody(data, content_type);
	}
	/// ditto
	void writeBody(scope InputStream data, string content_type = null)
	@safe {
		if (content_type.length) headers["Content-Type"] = content_type;
		else if ("Content-Type" !in headers) headers["Content-Type"] = "application/octet-stream";
		data.pipe(bodyWriter);
	}

	/** Writes the entire response body as a single string.

		Params:
			data = The string to write as the body contents
			status = Optional response status code to set
			content_type = Optional content type to apply to the response.
				If no content type is given and no "Content-Type" header is
				set in the response, this will default to
				`"text/plain; charset=UTF-8"`.

		See_Also: `HTTPStatusCode`
	*/
	/// ditto
	void writeBody(string data, string content_type = null)
	@safe {
		if (!content_type.length && "Content-Type" !in headers)
			content_type = "text/plain; charset=UTF-8";
		writeBody(cast(const(ubyte)[])data, content_type);
	}
	/// ditto
	void writeBody(string data, int status, string content_type = null)
	@safe {
		statusCode = status;
		writeBody(data, content_type);
	}

	/** Writes the whole response body at once, without doing any further encoding.

		The caller has to make sure that the appropriate headers are set correctly
		(i.e. Content-Type and Content-Encoding).

		Note that the version taking a RandomAccessStream may perform additional
		optimizations such as sending a file directly from the disk to the
		network card using a DMA transfer.

	*/
	void writeRawBody(RandomAccessStream)(RandomAccessStream stream) @safe
		if (isRandomAccessStream!RandomAccessStream)
	{
		assert(!m_headerWritten, "A body was already written!");
		writeHeader();
		if (m_isHeadResponse) return;

		auto bytes = stream.size - stream.tell();
		stream.pipe(m_conn);
		m_countingWriter.increment(bytes);
	}
	/// ditto
	void writeRawBody(InputStream)(InputStream stream, size_t num_bytes = 0) @safe
		if (isInputStream!InputStream && !isRandomAccessStream!InputStream)
	{
		assert(!m_headerWritten, "A body was already written!");
		writeHeader();
		if (m_isHeadResponse) return;

		if (num_bytes > 0) {
			stream.pipe(m_conn, num_bytes);
			m_countingWriter.increment(num_bytes);
		} else stream.pipe(m_countingWriter, num_bytes);
	}
	/// ditto
	void writeRawBody(RandomAccessStream)(RandomAccessStream stream, int status) @safe
		if (isRandomAccessStream!RandomAccessStream)
	{
		statusCode = status;
		writeRawBody(stream);
	}
	/// ditto
	void writeRawBody(InputStream)(InputStream stream, int status, size_t num_bytes = 0) @safe
		if (isInputStream!InputStream && !isRandomAccessStream!InputStream)
	{
		statusCode = status;
		writeRawBody(stream, num_bytes);
	}


	/// Writes a JSON message with the specified status
	void writeJsonBody(T)(T data, int status, bool allow_chunked = false)
	{
		statusCode = status;
		writeJsonBody(data, allow_chunked);
	}
	/// ditto
	void writeJsonBody(T)(T data, int status, string content_type, bool allow_chunked = false)
	{
		statusCode = status;
		writeJsonBody(data, content_type, allow_chunked);
	}

	/// ditto
	void writeJsonBody(T)(T data, string content_type, bool allow_chunked = false)
	{
		headers["Content-Type"] = content_type;
		writeJsonBody(data, allow_chunked);
	}
	/// ditto
	void writeJsonBody(T)(T data, bool allow_chunked = false)
	{
		doWriteJsonBody!(T, false)(data, allow_chunked);
	}
	/// ditto
	void writePrettyJsonBody(T)(T data, bool allow_chunked = false)
	{
		doWriteJsonBody!(T, true)(data, allow_chunked);
	}

	private void doWriteJsonBody(T, bool PRETTY)(T data, bool allow_chunked = false)
	{
		import std.traits;
		import vibe.stream.wrapper;

		static if (!is(T == Json) && is(typeof(data.data())) && isArray!(typeof(data.data()))) {
			static assert(!is(T == Appender!(typeof(data.data()))), "Passed an Appender!T to writeJsonBody - this is most probably not doing what's indended.");
		}

		if ("Content-Type" !in headers)
			headers["Content-Type"] = "application/json; charset=UTF-8";


		// set an explicit content-length field if chunked encoding is not allowed
		if (!allow_chunked) {
			import vibe.internal.rangeutil;
			long length = 0;
			auto counter = RangeCounter(() @trusted { return &length; } ());
			static if (PRETTY) serializeToPrettyJson(counter, data);
			else serializeToJson(counter, data);
			headers["Content-Length"] = formatAlloc(m_requestAlloc, "%d", length);
		}

		auto rng = streamOutputRange!1024(bodyWriter);
		static if (PRETTY) serializeToPrettyJson(() @trusted { return &rng; } (), data);
		else serializeToJson(() @trusted { return &rng; } (), data);
	}

	/**
	 * Writes the response with no body.
	 *
	 * This method should be used in situations where no body is
	 * requested, such as a HEAD request. For an empty body, just use writeBody,
	 * as this method causes problems with some keep-alive connections.
	 */
	void writeVoidBody()
	@safe {
		if (!m_isHeadResponse) {
			assert("Content-Length" !in headers);
			assert("Transfer-Encoding" !in headers);
		}
		assert(!headerWritten);
		writeHeader();
		m_conn.flush();
	}

	/** A stream for writing the body of the HTTP response.

		Note that after 'bodyWriter' has been accessed for the first time, it
		is not allowed to change any header or the status code of the response.
	*/
	@property InterfaceProxy!OutputStream bodyWriter()
	@safe {
		assert(!!m_conn);
		if (m_bodyWriter) return m_bodyWriter;

		assert(!m_headerWritten, "A void body was already written!");

		if (m_isHeadResponse) {
			// for HEAD requests, we define a NullOutputWriter for convenience
			// - no body will be written. However, the request handler should call writeVoidBody()
			// and skip writing of the body in this case.
			if ("Content-Length" !in headers)
				headers["Transfer-Encoding"] = "chunked";
			writeHeader();
			m_bodyWriter = nullSink;
			return m_bodyWriter;
		}

		if ("Content-Encoding" in headers && "Content-Length" in headers) {
			// we do not known how large the compressed body will be in advance
			// so remove the content-length and use chunked transfer
			headers.remove("Content-Length");
		}

		if (auto pcl = "Content-Length" in headers) {
			writeHeader();
			m_countingWriter.writeLimit = (*pcl).to!ulong;
			m_bodyWriter = m_countingWriter;
		} else if (httpVersion <= HTTPVersion.HTTP_1_0) {
			if ("Connection" in headers)
				headers.remove("Connection"); // default to "close"
			writeHeader();
			m_bodyWriter = m_conn;
		} else {
			headers["Transfer-Encoding"] = "chunked";
			writeHeader();
			m_chunkedBodyWriter = createChunkedOutputStreamFL(m_countingWriter);
			m_bodyWriter = m_chunkedBodyWriter;
		}

		if (auto pce = "Content-Encoding" in headers) {
			if (icmp2(*pce, "gzip") == 0) {
				m_zlibOutputStream = createGzipOutputStreamFL(m_bodyWriter);
				m_bodyWriter = m_zlibOutputStream;
			} else if (icmp2(*pce, "deflate") == 0) {
				m_zlibOutputStream = createDeflateOutputStreamFL(m_bodyWriter);
				m_bodyWriter = m_zlibOutputStream;
			} else {
				logWarn("Unsupported Content-Encoding set in response: '"~*pce~"'");
			}
		}

		return m_bodyWriter;
	}

	/** Sends a redirect request to the client.

		Params:
			url = The URL to redirect to
			status = The HTTP redirect status (3xx) to send - by default this is $(D HTTPStatus.found)
	*/
	void redirect(string url, int status = HTTPStatus.Found)
	@safe {
		// Disallow any characters that may influence the header parsing
		enforce(!url.representation.canFind!(ch => ch < 0x20),
			"Control character in redirection URL.");

		statusCode = status;
		headers["Location"] = url;
		writeBody("redirecting...");
	}
	/// ditto
	void redirect(URL url, int status = HTTPStatus.Found)
	@safe {
		redirect(url.toString(), status);
	}

	///
	@safe unittest {
		import vibe.http.router;

		void request_handler(HTTPServerRequest req, HTTPServerResponse res)
		{
			res.redirect("http://example.org/some_other_url");
		}

		void test()
		{
			auto router = new URLRouter;
			router.get("/old_url", &request_handler);

			listenHTTP(new HTTPServerSettings, router);
		}
	}


	/** Special method sending a SWITCHING_PROTOCOLS response to the client.

		Notice: For the overload that returns a `ConnectionStream`, it must be
			ensured that the returned instance doesn't outlive the request
			handler callback.

		Params:
			protocol = The protocol set in the "Upgrade" header of the response.
				Use an empty string to skip setting this field.
	*/
	ConnectionStream switchProtocol(string protocol)
	@safe {
		statusCode = HTTPStatus.SwitchingProtocols;
		if (protocol.length) headers["Upgrade"] = protocol;
		writeVoidBody();
		m_requiresConnectionClose = true;
		return createConnectionProxyStream(m_conn, m_rawConnection);
	}
	/// ditto
	void switchProtocol(string protocol, scope void delegate(scope ConnectionStream) @safe del)
	@safe {
		statusCode = HTTPStatus.SwitchingProtocols;
		if (protocol.length) headers["Upgrade"] = protocol;
		writeVoidBody();
		m_requiresConnectionClose = true;
		() @trusted {
			auto conn = createConnectionProxyStreamFL(m_conn, m_rawConnection);
			del(conn);
		} ();
		finalize();
	}

	/** Special method for handling CONNECT proxy tunnel

		Notice: For the overload that returns a `ConnectionStream`, it must be
			ensured that the returned instance doesn't outlive the request
			handler callback.
	*/
	ConnectionStream connectProxy()
	@safe {
		return createConnectionProxyStream(m_conn, m_rawConnection);
	}
	/// ditto
	void connectProxy(scope void delegate(scope ConnectionStream) @safe del)
	@safe {
		() @trusted {
			auto conn = createConnectionProxyStreamFL(m_conn, m_rawConnection);
			del(conn);
		} ();
		finalize();
	}

	/** Sets the specified cookie value.

		Params:
			name = Name of the cookie
			value = New cookie value - pass null to clear the cookie
			path = Path (as seen by the client) of the directory tree in which the cookie is visible
	*/
	Cookie setCookie(string name, string value, string path = "/", Cookie.Encoding encoding = Cookie.Encoding.url)
	@safe {
		auto cookie = new Cookie();
		cookie.path = path;
		cookie.setValue(value, encoding);
		if (value is null) {
			cookie.maxAge = 0;
			cookie.expires = "Thu, 01 Jan 1970 00:00:00 GMT";
		}
		cookies[name] = cookie;
		return cookie;
	}

	/**
		Initiates a new session.

		The session is stored in the SessionStore that was specified when
		creating the server. Depending on this, the session can be persistent
		or temporary and specific to this server instance.
	*/
	Session startSession(string path = "/", SessionOption options = SessionOption.httpOnly)
	@safe {
		assert(m_settings.sessionStore, "no session store set");
		assert(!m_session, "Try to start a session, but already started one.");

		bool secure;
		if (options & SessionOption.secure) secure = true;
		else if (options & SessionOption.noSecure) secure = false;
		else secure = this.tls;

		m_session = m_settings.sessionStore.create();
		m_session.set("$sessionCookiePath", path);
		m_session.set("$sessionCookieSecure", secure);
		auto cookie = setCookie(m_settings.sessionIdCookie, m_session.id, path);
		cookie.secure = secure;
		cookie.httpOnly = (options & SessionOption.httpOnly) != 0;
		return m_session;
	}

	/**
		Terminates the current session (if any).
	*/
	void terminateSession()
	@safe {
		if (!m_session) return;
		auto cookie = setCookie(m_settings.sessionIdCookie, null, m_session.get!string("$sessionCookiePath"));
		cookie.secure = m_session.get!bool("$sessionCookieSecure");
		m_session.destroy();
		m_session = Session.init;
	}

	@property ulong bytesWritten() @safe const { return m_countingWriter.bytesWritten; }

	/**
		Waits until either the connection closes, data arrives, or until the
		given timeout is reached.

		Returns:
			$(D true) if the connection was closed and $(D false) if either the
			timeout was reached, or if data has arrived for consumption.

		See_Also: `connected`
	*/
	bool waitForConnectionClose(Duration timeout = Duration.max)
	@safe {
		if (!m_rawConnection || !m_rawConnection.connected) return true;
		m_rawConnection.waitForData(timeout);
		return !m_rawConnection.connected;
	}

	/**
		Determines if the underlying connection is still alive.

		Returns $(D true) if the remote peer is still connected and $(D false)
		if the remote peer closed the connection.

		See_Also: `waitForConnectionClose`
	*/
	@property bool connected()
	@safe const {
		if (!m_rawConnection) return false;
		return m_rawConnection.connected;
	}

	/**
		Finalizes the response. This is usually called automatically by the server.

		This method can be called manually after writing the response to force
		all network traffic associated with the current request to be finalized.
		After the call returns, the `timeFinalized` property will be set.
	*/
	void finalize()
	@safe {
		if (m_zlibOutputStream) {
			m_zlibOutputStream.finalize();
			m_zlibOutputStream.destroy();
		}
		if (m_chunkedBodyWriter) {
			m_chunkedBodyWriter.finalize();
			m_chunkedBodyWriter.destroy();
		}

		// ignore exceptions caused by an already closed connection - the client
		// may have closed the connection already and this doesn't usually indicate
		// a problem.
		if (m_rawConnection && m_rawConnection.connected) {
			try if (m_conn) m_conn.flush();
			catch (Exception e) logDebug("Failed to flush connection after finishing HTTP response: %s", e.msg);
			if (!isHeadResponse && bytesWritten < headers.get("Content-Length", "0").to!long) {
				logDebug("HTTP response only written partially before finalization. Terminating connection.");
				m_requiresConnectionClose = true;
			}

			m_rawConnection = InterfaceProxy!ConnectionStream.init;
		}

		if (m_conn) {
			m_conn = InterfaceProxy!Stream.init;
			m_timeFinalized = Clock.currTime(UTC());
		}
	}

	private void writeHeader()
	@safe {
		import vibe.stream.wrapper;

		assert(!m_bodyWriter && !m_headerWritten, "Try to write header after body has already begun.");
		m_headerWritten = true;
		auto dst = streamOutputRange!1024(m_conn);

		void writeLine(T...)(string fmt, T args)
		@safe {
			formattedWrite(() @trusted { return &dst; } (), fmt, args);
			dst.put("\r\n");
			logTrace(fmt, args);
		}

		logTrace("---------------------");
		logTrace("HTTP server response:");
		logTrace("---------------------");

		// write the status line
		writeLine("%s %d %s",
			getHTTPVersionString(this.httpVersion),
			this.statusCode,
			this.statusPhrase.length ? this.statusPhrase : httpStatusText(this.statusCode));

		// write all normal headers
		foreach (k, v; this.headers) {
			dst.put(k);
			dst.put(": ");
			dst.put(v);
			dst.put("\r\n");
			logTrace("%s: %s", k, v);
		}

		logTrace("---------------------");

		// write cookies
		foreach (n, cookie; this.cookies) {
			dst.put("Set-Cookie: ");
			cookie.writeString(() @trusted { return &dst; } (), n);
			dst.put("\r\n");
		}

		// finalize response header
		dst.put("\r\n");
	}
}

/**
	Represents the request listener for a specific `listenHTTP` call.

	This struct can be used to stop listening for HTTP requests at runtime.
*/
struct HTTPListener {
	private {
		size_t[] m_virtualHostIDs;
	}

	private this(size_t[] ids) @safe { m_virtualHostIDs = ids; }

	@property NetworkAddress[] bindAddresses()
	{
		NetworkAddress[] ret;
		foreach (l; s_listeners)
			if (l.m_virtualHosts.canFind!(v => m_virtualHostIDs.canFind(v.id))) {
				NetworkAddress a;
				a = resolveHost(l.bindAddress);
				a.port = l.bindPort;
				ret ~= a;
			}
		return ret;
	}

	/** Stops handling HTTP requests and closes the TCP listening port if
		possible.
	*/
	void stopListening()
	@safe {
		import std.algorithm : countUntil;

		foreach (vhid; m_virtualHostIDs) {
			foreach (lidx, l; s_listeners) {
				if (l.removeVirtualHost(vhid)) {
					if (!l.hasVirtualHosts) {
						l.m_listener.stopListening();
						logInfo("Stopped to listen for HTTP%s requests on %s:%s", l.tlsContext ? "S": "", l.bindAddress, l.bindPort);
						s_listeners = s_listeners[0 .. lidx] ~ s_listeners[lidx+1 .. $];
					}
				}
				break;
			}
		}
	}
}


/** Represents a single HTTP server port.

	This class defines the incoming interface, port, and TLS configuration of
	the public server port. The public server port may differ from the local
	one if a reverse proxy of some kind is facing the public internet and
	forwards to this HTTP server.

	Multiple virtual hosts can be configured to be served from the same port.
	Their TLS settings must be compatible and each virtual host must have a
	unique name.
*/
final class HTTPServerContext {
	private struct VirtualHost {
		HTTPServerRequestDelegate requestHandler;
		HTTPServerSettings settings;
		HTTPLogger[] loggers;
		size_t id;
	}

	private {
		TCPListener m_listener;
		VirtualHost[] m_virtualHosts;
		string m_bindAddress;
		ushort m_bindPort;
		TLSContext m_tlsContext;
		static size_t s_vhostIDCounter = 1;
	}

	@safe:

	this(string bind_address, ushort bind_port)
	{
		m_bindAddress = bind_address;
		m_bindPort = bind_port;
	}

	/** Returns the TLS context associated with the listener.

		For non-HTTPS listeners, `null` will be returned. Otherwise, if only a
		single virtual host has been added, the TLS context of that host's
		settings is returned. For multiple virtual hosts, an SNI context is
		returned, which forwards to the individual contexts based on the
		requested host name.
	*/
	@property TLSContext tlsContext() { return m_tlsContext; }

	/// The local network interface IP address associated with this listener
	@property string bindAddress() const { return m_bindAddress; }

	/// The local port associated with this listener
	@property ushort bindPort() const { return m_bindPort; }

	/// Determines if any virtual hosts have been addded
	@property bool hasVirtualHosts() const { return m_virtualHosts.length > 0; }

	/** Adds a single virtual host.

		Note that the port and bind address defined in `settings` must match the
		ones for this listener. The `settings.host` field must be unique for
		all virtual hosts.

		Returns: Returns a unique ID for the new virtual host
	*/
	size_t addVirtualHost(HTTPServerSettings settings, HTTPServerRequestDelegate request_handler)
	{
		assert(settings.port == 0 || settings.port == m_bindPort, "Virtual host settings do not match bind port.");
		assert(settings.bindAddresses.canFind(m_bindAddress), "Virtual host settings do not match bind address.");

		VirtualHost vhost;
		vhost.id = s_vhostIDCounter++;
		vhost.settings = settings;
		vhost.requestHandler = request_handler;

		if (settings.accessLogger) vhost.loggers ~= settings.accessLogger;
		if (settings.accessLogToConsole)
			vhost.loggers ~= new HTTPConsoleLogger(settings, settings.accessLogFormat);
		if (settings.accessLogFile.length)
			vhost.loggers ~= new HTTPFileLogger(settings, settings.accessLogFormat, settings.accessLogFile);

		if (!m_virtualHosts.length) m_tlsContext = settings.tlsContext;

		enforce((m_tlsContext !is null) == (settings.tlsContext !is null),
			"Cannot mix HTTP and HTTPS virtual hosts within the same listener.");

		if (m_tlsContext) addSNIHost(settings);

		m_virtualHosts ~= vhost;

		if (settings.hostName.length) {
			auto proto = settings.tlsContext ? "https" : "http";
			auto port = settings.tlsContext && settings.port == 443 || !settings.tlsContext && settings.port == 80 ? "" : ":" ~ settings.port.to!string;
			logInfo("Added virtual host %s://%s:%s/ (%s)", proto, settings.hostName, m_bindPort, m_bindAddress);
		}

		return vhost.id;
	}

	/// Removes a previously added virtual host using its ID.
	bool removeVirtualHost(size_t id)
	{
		import std.algorithm.searching : countUntil;

		auto idx = m_virtualHosts.countUntil!(c => c.id == id);
		if (idx < 0) return false;

		auto ctx = m_virtualHosts[idx];
		m_virtualHosts = m_virtualHosts[0 .. idx] ~ m_virtualHosts[idx+1 .. $];
		return true;
	}

	private void addSNIHost(HTTPServerSettings settings)
	{
		if (settings.tlsContext !is m_tlsContext && m_tlsContext.kind != TLSContextKind.serverSNI) {
			logDebug("Create SNI TLS context for %s, port %s", bindAddress, bindPort);
			m_tlsContext = createTLSContext(TLSContextKind.serverSNI);
			m_tlsContext.sniCallback = &onSNI;
		}

		foreach (ctx; m_virtualHosts) {
			/*enforce(ctx.settings.hostName != settings.hostName,
				"A server with the host name '"~settings.hostName~"' is already "
				"listening on "~addr~":"~to!string(settings.port)~".");*/
		}
	}

	private TLSContext onSNI(string servername)
	{
		foreach (vhost; m_virtualHosts)
			if (vhost.settings.hostName.icmp(servername) == 0) {
				logDebug("Found context for SNI host '%s'.", servername);
				return vhost.settings.tlsContext;
			}
		logDebug("No context found for SNI host '%s'.", servername);
		return null;
	}
}

/**************************************************************************************************/
/* Private types                                                                                  */
/**************************************************************************************************/

private enum MaxHTTPHeaderLineLength = 4096;

private final class LimitedHTTPInputStream : LimitedInputStream {
@safe:

	this(InterfaceProxy!InputStream stream, ulong byte_limit, bool silent_limit = false) {
		super(stream, byte_limit, silent_limit, true);
	}
	override void onSizeLimitReached() {
		throw new HTTPStatusException(HTTPStatus.requestEntityTooLarge);
	}
}

private final class TimeoutHTTPInputStream : InputStream {
@safe:

	private {
		long m_timeref;
		long m_timeleft;
		InterfaceProxy!InputStream m_in;
	}

	this(InterfaceProxy!InputStream stream, Duration timeleft, SysTime reftime)
	{
		enforce(timeleft > 0.seconds, "Timeout required");
		m_in = stream;
		m_timeleft = timeleft.total!"hnsecs"();
		m_timeref = reftime.stdTime();
	}

	@property bool empty() { enforce(m_in, "InputStream missing"); return m_in.empty(); }
	@property ulong leastSize() { enforce(m_in, "InputStream missing"); return m_in.leastSize();  }
	@property bool dataAvailableForRead() {  enforce(m_in, "InputStream missing"); return m_in.dataAvailableForRead; }
	const(ubyte)[] peek() { return m_in.peek(); }

	size_t read(scope ubyte[] dst, IOMode mode)
	{
		enforce(m_in, "InputStream missing");
		size_t nread = 0;
		checkTimeout();
		// FIXME: this should use ConnectionStream.waitForData to enforce the timeout during the
		// read operation
		return m_in.read(dst, mode);
	}

	alias read = InputStream.read;

	private void checkTimeout()
	@safe {
		auto curr = Clock.currStdTime();
		auto diff = curr - m_timeref;
		if (diff > m_timeleft) throw new HTTPStatusException(HTTPStatus.RequestTimeout);
		m_timeleft -= diff;
		m_timeref = curr;
	}
}

/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

private {
	import core.sync.mutex;

	shared string s_distHost;
	shared ushort s_distPort = 11000;

	HTTPServerContext[] s_listeners;
}

/**
	[private] Starts a HTTP server listening on the specified port.

	This is the same as listenHTTP() except that it does not use a VibeDist host for
	remote listening, even if specified on the command line.
*/
private HTTPListener listenHTTPPlain(HTTPServerSettings settings, HTTPServerRequestDelegate request_handler)
@safe {
	import vibe.core.core : runWorkerTaskDist;
	import std.algorithm : canFind, find;

	static TCPListener doListen(HTTPServerContext listen_info, bool dist, bool reusePort, bool is_tls)
	@safe {
		try {
			TCPListenOptions options = TCPListenOptions.defaults;
			if(reusePort) options |= TCPListenOptions.reusePort; else options &= ~TCPListenOptions.reusePort;
			auto ret = listenTCP(listen_info.bindPort, (TCPConnection conn) nothrow @safe {
					try handleHTTPConnection(conn, listen_info);
					catch (Exception e) {
						logError("HTTP connection handler has thrown: %s", e.msg);
						debug logDebug("Full error: %s", () @trusted { return e.toString().sanitize(); } ());
						try conn.close();
						catch (Exception e) logError("Failed to close connection: %s", e.msg);
					}
				}, listen_info.bindAddress, options);

			// support port 0 meaning any available port
			if (listen_info.bindPort == 0)
				listen_info.m_bindPort = ret.bindAddress.port;

			auto proto = is_tls ? "https" : "http";
			auto urladdr = listen_info.bindAddress;
			if (urladdr.canFind(':')) urladdr = "["~urladdr~"]";
			logInfo("Listening for requests on %s://%s:%s/", proto, urladdr, listen_info.bindPort);
			return ret;
		} catch( Exception e ) {
			logWarn("Failed to listen on %s:%s", listen_info.bindAddress, listen_info.bindPort);
			return TCPListener.init;
		}
	}

	size_t[] vid;

	// Check for every bind address/port, if a new listening socket needs to be created and
	// check for conflicting servers
	foreach (addr; settings.bindAddresses) {
		HTTPServerContext linfo;

		auto l = s_listeners.find!(l => l.bindAddress == addr && l.bindPort == settings.port);
		if (!l.empty) linfo = l.front;
		else {
			auto li = new HTTPServerContext(addr, settings.port);
			if (auto tcp_lst = doListen(li,
					(settings.options & HTTPServerOptionImpl.distribute) != 0,
					(settings.options & HTTPServerOption.reusePort) != 0,
					settings.tlsContext !is null)) // DMD BUG 2043
			{
				li.m_listener = tcp_lst;
				s_listeners ~= li;
				linfo = li;
			}
		}

		if (linfo) vid ~= linfo.addVirtualHost(settings, request_handler);
	}

	enforce(vid.length > 0, "Failed to listen for incoming HTTP connections on any of the supplied interfaces.");

	return HTTPListener(vid);
}

private alias TLSStreamType = ReturnType!(createTLSStreamFL!(InterfaceProxy!Stream));


private bool handleRequest(InterfaceProxy!Stream http_stream, TCPConnection tcp_connection, HTTPServerContext listen_info, ref HTTPServerSettings settings, ref bool keep_alive, scope IAllocator request_allocator)
@safe {
	import std.algorithm.searching : canFind;

	SysTime reqtime = Clock.currTime(UTC());

	// some instances that live only while the request is running
	FreeListRef!HTTPServerRequest req = FreeListRef!HTTPServerRequest(reqtime, listen_info.bindPort);
	FreeListRef!TimeoutHTTPInputStream timeout_http_input_stream;
	FreeListRef!LimitedHTTPInputStream limited_http_input_stream;
	FreeListRef!ChunkedInputStream chunked_input_stream;

	// store the IP address
	req.clientAddress = tcp_connection.remoteAddress;

	if (!listen_info.hasVirtualHosts) {
		logWarn("Didn't find a HTTP listening context for incoming connection. Dropping.");
		keep_alive = false;
		return false;
	}

	// Default to the first virtual host for this listener
	HTTPServerContext.VirtualHost context = listen_info.m_virtualHosts[0];
	HTTPServerRequestDelegate request_task = context.requestHandler;
	settings = context.settings;

	// temporarily set to the default settings, the virtual host specific settings will be set further down
	req.m_settings = settings;

	// Create the response object
	InterfaceProxy!ConnectionStream cproxy = tcp_connection;
	auto res = FreeListRef!HTTPServerResponse(http_stream, cproxy, settings, request_allocator/*.Scoped_payload*/);
	req.tls = res.m_tls = listen_info.tlsContext !is null;
	if (req.tls) {
		version (HaveNoTLS) assert(false);
		else {
			static if (is(InterfaceProxy!ConnectionStream == ConnectionStream))
				req.clientCertificate = (cast(TLSStream)http_stream).peerCertificate;
			else
				req.clientCertificate = http_stream.extract!TLSStreamType.peerCertificate;
		}
	}

	// Error page handler
	void errorOut(int code, string msg, string debug_msg, Throwable ex)
	@safe {
		assert(!res.headerWritten);

		// stack traces sometimes contain random bytes - make sure they are replaced
		debug_msg = sanitizeUTF8(cast(const(ubyte)[])debug_msg);

		res.statusCode = code;
		if (settings && settings.errorPageHandler) {
			/*scope*/ auto err = new HTTPServerErrorInfo;
			err.code = code;
			err.message = msg;
			err.debugMessage = debug_msg;
			err.exception = ex;
			settings.errorPageHandler_(req, res, err);
		} else {
			if (debug_msg.length)
				res.writeBody(format("%s - %s\n\n%s\n\nInternal error information:\n%s", code, httpStatusText(code), msg, debug_msg));
			else res.writeBody(format("%s - %s\n\n%s", code, httpStatusText(code), msg));
		}
		assert(res.headerWritten);
	}

	bool parsed = false;
	/*bool*/ keep_alive = false;

	// parse the request
	try {
		logTrace("reading request..");

		// limit the total request time
		InterfaceProxy!InputStream reqReader = http_stream;
		if (settings.maxRequestTime > dur!"seconds"(0) && settings.maxRequestTime != Duration.max) {
			timeout_http_input_stream = FreeListRef!TimeoutHTTPInputStream(reqReader, settings.maxRequestTime, reqtime);
			reqReader = timeout_http_input_stream;
		}

		// basic request parsing
		parseRequestHeader(req, reqReader, request_allocator, settings.maxRequestHeaderSize);
		logTrace("Got request header.");

		// find the matching virtual host
		string reqhost;
		ushort reqport = 0;
		{
			string s = req.host;
			enforceHTTP(s.length > 0 || req.httpVersion <= HTTPVersion.HTTP_1_0, HTTPStatus.badRequest, "Missing Host header.");
			if (s.startsWith('[')) { // IPv6 address
				auto idx = s.indexOf(']');
				enforce(idx > 0, "Missing closing ']' for IPv6 address.");
				reqhost = s[1 .. idx];
				s = s[idx+1 .. $];
			} else if (s.length) { // host name or IPv4 address
				auto idx = s.indexOf(':');
				if (idx < 0) idx = s.length;
				enforceHTTP(idx > 0, HTTPStatus.badRequest, "Missing Host header.");
				reqhost = s[0 .. idx];
				s = s[idx .. $];
			}
			if (s.startsWith(':')) reqport = s[1 .. $].to!ushort;
		}

		foreach (ctx; listen_info.m_virtualHosts)
			if (icmp2(ctx.settings.hostName, reqhost) == 0 &&
				(!reqport || reqport == ctx.settings.port))
			{
				context = ctx;
				settings = ctx.settings;
				request_task = ctx.requestHandler;
				break;
			}
		req.m_settings = settings;
		res.m_settings = settings;

		// setup compressed output
		if (settings.useCompressionIfPossible) {
			if (auto pae = "Accept-Encoding" in req.headers) {
				if (canFind(*pae, "gzip")) {
					res.headers["Content-Encoding"] = "gzip";
				} else if (canFind(*pae, "deflate")) {
					res.headers["Content-Encoding"] = "deflate";
				}
			}
		}

		// limit request size
		if (auto pcl = "Content-Length" in req.headers) {
			string v = *pcl;
			auto contentLength = parse!ulong(v); // DMDBUG: to! thinks there is a H in the string
			enforceBadRequest(v.length == 0, "Invalid content-length");
			enforceBadRequest(settings.maxRequestSize <= 0 || contentLength <= settings.maxRequestSize, "Request size too big");
			limited_http_input_stream = FreeListRef!LimitedHTTPInputStream(reqReader, contentLength);
		} else if (auto pt = "Transfer-Encoding" in req.headers) {
			enforceBadRequest(icmp(*pt, "chunked") == 0);
			chunked_input_stream = createChunkedInputStreamFL(reqReader);
			InterfaceProxy!InputStream ciproxy = chunked_input_stream;
			limited_http_input_stream = FreeListRef!LimitedHTTPInputStream(ciproxy, settings.maxRequestSize, true);
		} else {
			limited_http_input_stream = FreeListRef!LimitedHTTPInputStream(reqReader, 0);
		}
		req.bodyReader = limited_http_input_stream;

		// handle Expect header
		if (auto pv = "Expect" in req.headers) {
			if (icmp2(*pv, "100-continue") == 0) {
				logTrace("sending 100 continue");
				http_stream.write("HTTP/1.1 100 Continue\r\n\r\n");
			}
		}

        // eagerly parse the URL as its lightweight and defacto @nogc
		auto url = URL.parse(req.requestURI);
		req.queryString = url.queryString;
		req.username = url.username;
		req.password = url.password;
		req.requestPath = url.path;

		// lookup the session
		if (settings.sessionStore) {
			// use the first cookie that contains a valid session ID in case
			// of multiple matching session cookies
			foreach (val; req.cookies.getAll(settings.sessionIdCookie)) {
				req.session = settings.sessionStore.open(val);
				res.m_session = req.session;
				if (req.session) break;
			}
		}

		// write default headers
		if (req.method == HTTPMethod.HEAD) res.m_isHeadResponse = true;
		if (settings.serverString.length)
			res.headers["Server"] = settings.serverString;
		res.headers["Date"] = formatRFC822DateAlloc(request_allocator, reqtime);
		if (req.persistent) res.headers["Keep-Alive"] = formatAlloc(request_allocator, "timeout=%d", settings.keepAliveTimeout.total!"seconds"());

		// finished parsing the request
		parsed = true;
		logTrace("persist: %s", req.persistent);
		keep_alive = req.persistent;

		// handle the request
		logTrace("handle request (body %d)", req.bodyReader.leastSize);
		res.httpVersion = req.httpVersion;
		request_task(req, res);

		// if no one has written anything, return 404
		if (!res.headerWritten) {
			string dbg_msg;
			logDiagnostic("No response written for %s", req.requestURI);
			if (settings.options & HTTPServerOption.errorStackTraces)
				dbg_msg = format("No routes match path '%s'", req.requestURI);
			errorOut(HTTPStatus.notFound, httpStatusText(HTTPStatus.notFound), dbg_msg, null);
		}
	} catch (HTTPStatusException err) {
		if (!res.headerWritten) errorOut(err.status, err.msg, err.debugMessage, err);
		else logDiagnostic("HTTPSterrorOutatusException while writing the response: %s", err.msg);
		debug logDebug("Exception while handling request %s %s: %s", req.method, req.requestURI, () @trusted { return err.toString().sanitize; } ());
		if (!parsed || res.headerWritten || justifiesConnectionClose(err.status))
			keep_alive = false;
	} catch (UncaughtException e) {
		auto status = parsed ? HTTPStatus.internalServerError : HTTPStatus.badRequest;
		string dbg_msg;
		if (settings.options & HTTPServerOption.errorStackTraces) dbg_msg = () @trusted { return e.toString().sanitize; } ();
		if (!res.headerWritten && tcp_connection.connected) errorOut(status, httpStatusText(status), dbg_msg, e);
		else logDiagnostic("Error while writing the response: %s", e.msg);
		debug logDebug("Exception while handling request %s %s: %s", req.method, req.requestURI, () @trusted { return e.toString().sanitize(); } ());
		if (!parsed || res.headerWritten || !cast(Exception)e) keep_alive = false;
	}

	if (tcp_connection.connected && keep_alive) {
		if (req.bodyReader && !req.bodyReader.empty) {
			req.bodyReader.pipe(nullSink);
			logTrace("dropped body");
		}
	}

	// finalize (e.g. for chunked encoding)
	res.finalize();

	if (res.m_requiresConnectionClose)
		keep_alive = false;

	foreach (k, v ; req._files) {
		if (existsFile(v.tempPath)) {
			removeFile(v.tempPath);
			logDebug("Deleted upload tempfile %s", v.tempPath.toString());
		}
	}

	if (!req.noLog) {
		// log the request to access log
		foreach (log; context.loggers)
			log.log(req, res);
	}

	//logTrace("return %s (used pool memory: %s/%s)", keep_alive, request_allocator.allocatedSize, request_allocator.totalSize);
	logTrace("return %s", keep_alive);
	return keep_alive != false;
}


private void parseRequestHeader(InputStream)(HTTPServerRequest req, InputStream http_stream, IAllocator alloc, ulong max_header_size)
	if (isInputStream!InputStream)
{
	auto stream = FreeListRef!LimitedHTTPInputStream(http_stream, max_header_size);

	logTrace("HTTP server reading status line");
	auto reqln = () @trusted { return cast(string)stream.readLine(MaxHTTPHeaderLineLength, "\r\n", alloc); }();

	logTrace("--------------------");
	logTrace("HTTP server request:");
	logTrace("--------------------");
	logTrace("%s", reqln);

	//Method
	auto pos = reqln.indexOf(' ');
	enforceBadRequest(pos >= 0, "invalid request method");

	req.method = httpMethodFromString(reqln[0 .. pos]);
	reqln = reqln[pos+1 .. $];
	//Path
	pos = reqln.indexOf(' ');
	enforceBadRequest(pos >= 0, "invalid request path");

	req.requestURI = reqln[0 .. pos];
	reqln = reqln[pos+1 .. $];

	req.httpVersion = parseHTTPVersion(reqln);

	//headers
	parseRFC5322Header(stream, req.headers, MaxHTTPHeaderLineLength, alloc, false);

	foreach (k, v; req.headers)
		logTrace("%s: %s", k, v);
	logTrace("--------------------");
}

private void parseCookies(string str, ref CookieValueMap cookies)
@safe {
	import std.encoding : sanitize;
	import std.array : split;
	import std.string : strip;
	import std.algorithm.iteration : map, filter, each;
	import vibe.http.common : Cookie;
	() @trusted { return str.sanitize; } ()
		.split(";")
		.map!(kv => kv.strip.split("="))
		.filter!(kv => kv.length == 2) //ignore illegal cookies
		.each!(kv => cookies.add(kv[0], kv[1], Cookie.Encoding.raw) );
}

unittest
{
  auto cvm = CookieValueMap();
  parseCookies("foo=bar;; baz=zinga; öö=üü   ;   møøse=was=sacked;    onlyval1; =onlyval2; onlykey=", cvm);
  assert(cvm["foo"] == "bar");
  assert(cvm["baz"] == "zinga");
  assert(cvm["öö"] == "üü");
  assert( "møøse" ! in cvm); //illegal cookie gets ignored
  assert( "onlyval1" ! in cvm); //illegal cookie gets ignored
  assert(cvm["onlykey"] == "");
  assert(cvm[""] == "onlyval2");
  assert(cvm.length() == 5);
  cvm = CookieValueMap();
  parseCookies("", cvm);
  assert(cvm.length() == 0);
  cvm = CookieValueMap();
  parseCookies(";;=", cvm);
  assert(cvm.length() == 1);
  assert(cvm[""] == "");
}

shared static this()
{
	version (VibeNoDefaultArgs) {}
	else {
		string disthost = s_distHost;
		ushort distport = s_distPort;
		import vibe.core.args : readOption;
		readOption("disthost|d", () @trusted { return &disthost; } (), "Sets the name of a vibedist server to use for load balancing.");
		readOption("distport", () @trusted { return &distport; } (), "Sets the port used for load balancing.");
		setVibeDistHost(disthost, distport);
	}
}

private string formatRFC822DateAlloc(IAllocator alloc, SysTime time)
@safe {
	auto app = AllocAppender!string(alloc);
	writeRFC822DateTimeString(app, time);
	return () @trusted { return app.data; } ();
}

version (VibeDebugCatchAll) private alias UncaughtException = Throwable;
else private alias UncaughtException = Exception;
