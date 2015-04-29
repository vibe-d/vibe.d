/**
	A HTTP 1.1/1.0 server implementation.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger, Ilya Shipunov
*/
module vibe.http.server;

public import vibe.core.net;
public import vibe.http.common;
public import vibe.http.session;

import vibe.core.core;
import vibe.core.file;
import vibe.core.log;
import vibe.data.json;
import vibe.http.dist;
import vibe.http.log;
import vibe.inet.message;
import vibe.inet.url;
import vibe.inet.webform;
import vibe.stream.counting;
import vibe.stream.operations;
import vibe.stream.ssl;
import vibe.stream.wrapper : ConnectionProxyStream;
import vibe.stream.zlib;
import vibe.textfilter.urlencode;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string;
import vibe.http.http2;

import core.vararg;
import std.array;
import std.conv;
import std.datetime;
import std.encoding : sanitize;
import std.exception;
import std.format;
import std.functional;
import std.string;
import std.typecons;
import std.uri;

version(VibeNoTLS) {} else {
	version(Botan) {} else {
		version(OpenSSL) {} else {
			static if (__traits(compiles, { import deimos.openssl.ssl; }))
				version = OpenSSL;
			else static if (__traits(compiles, { import botan.constants; }))
				version = Botan;
		}
	}
}

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
		settings = Customizes the HTTP servers functionality.
		request_handler = This callback is invoked for each incoming request and is responsible
			for generating the response.
*/
void listenHTTP(HTTPServerSettings settings, HTTPServerRequestDelegate request_handler)
{
	enforce(settings.bindAddresses.length, "Must provide at least one bind address for a HTTP server.");

	HTTPServerContext ctx = FreeListObjectAlloc!HTTPServerContext.alloc();
	ctx.settings = settings;
	ctx.requestHandler = request_handler;

	if (settings.accessLogToConsole)
		ctx.loggers ~= new HTTPConsoleLogger(settings, settings.accessLogFormat);
	if (settings.accessLogFile.length)
		ctx.loggers ~= new HTTPFileLogger(settings, settings.accessLogFormat, settings.accessLogFile);

	g_contexts ~= ctx;

	// TLS ALPN and SNI UserData setup
	if (settings.tlsContext) {
		logDebug("Set user data: %s", g_contexts[$-1]);
		settings.tlsContext.setUserData(cast(void*)g_contexts[$-1]);

		if (settings.disableHTTP2) {
			static string h1chooser(string[] arr) {
				// we assume http/1.1 is in the list because it would error out anyways
				return "http/1.1";
			}
			settings.tlsContext.alpnCallback = toDelegate(&h1chooser);
		} else if (!settings.tlsContext.alpnCallback) {
			static string h2chooser(string[] arr) {
				import std.algorithm : canFind;
				string[] choices = ["h2", "h2-16", "h2-14", "http/1.1"];
				foreach (choice; choices) {
					if (arr.canFind(choice))
						return choice;
				}
				return "";
			}
			settings.tlsContext.alpnCallback = toDelegate(&h2chooser);
		}
		else {
			logDebug("Cannot register HTTP/2");
		}
	}

	// if a VibeDist host was specified on the command line, register there instead of listening
	// directly.
	if (s_distHost.length && !settings.disableDistHost) {
		listenHTTPDist(settings, request_handler, s_distHost, s_distPort);
	} else {
		listenHTTPPlain(settings);
	}
}
/// ditto
void listenHTTP(HTTPServerSettings settings, HTTPServerRequestFunction request_handler)
{
	listenHTTP(settings, toDelegate(request_handler));
}
/// ditto
void listenHTTP(HTTPServerSettings settings, HTTPServerRequestHandler request_handler)
{
	listenHTTP(settings, &request_handler.handleRequest);
}
/// ditto
void listenHTTP(HTTPServerSettings settings, HTTPServerRequestDelegateS request_handler)
{
	listenHTTP(settings, cast(HTTPServerRequestDelegate)request_handler);
}
/// ditto
void listenHTTP(HTTPServerSettings settings, HTTPServerRequestFunctionS request_handler)
{
	listenHTTP(settings, toDelegate(request_handler));
}
/// ditto
void listenHTTP(HTTPServerSettings settings, HTTPServerRequestHandlerS request_handler)
{
	listenHTTP(settings, &request_handler.handleRequest);
}

/**
	[private] Starts a HTTP server listening on the specified port.
	This is the same as listenHTTP() except that it does not use a VibeDist host for
	remote listening, even if specified on the command line.
*/
private void listenHTTPPlain(HTTPServerSettings settings)
{
	import std.algorithm : canFind;

	static bool doListen(HTTPServerSettings settings, size_t listener_idx, string addr)
	{
		try {
			bool dist = (settings.options & HTTPServerOption.distribute) != 0;
			listenTCP(settings.port, (TCPConnection conn){ handleHTTPConnection(conn, g_listeners[listener_idx]); }, addr, dist ? TCPListenOptions.distribute : TCPListenOptions.defaults);
			logInfo("Listening for HTTP%s requests on %s:%s", settings.tlsContext ? "S" : "", addr, settings.port);
			return true;
		} catch( Exception e ) {
			logWarn("Failed to listen on %s:%s", addr, settings.port);
			return false;
		}
	}

	void addVHost(ref HTTPServerListener lst)
	{
		TLSContext onSNI(string servername)
		{
			foreach (ctx; g_contexts)
				if (ctx.settings.bindAddresses.canFind(lst.bindAddress)
					&& ctx.settings.port == lst.bindPort
					&& ctx.settings.hostName.icmp(servername) == 0)
			{
				logDebug("Found context for SNI host '%s'.", servername);
				return ctx.settings.tlsContext;
			}
			logDebug("No context found for SNI host '%s'.", servername);
			return null;
		}

		if (settings.tlsContext !is lst.tlsContext && lst.tlsContext.kind != TLSContextKind.serverSNI) {
			logDebug("Create SNI SSL context for %s, port %s", lst.bindAddress, lst.bindPort);
			lst.tlsContext = createTLSContext(TLSContextKind.serverSNI);
			lst.tlsContext.sniCallback = &onSNI;
		}

		foreach (ctx; g_contexts) {
			if (ctx.settings.port != settings.port) continue;
			if (!ctx.settings.bindAddresses.canFind(lst.bindAddress)) continue;

			assert(ctx.settings.hostName, "Cannot setup virtual hosts on "~lst.bindAddress~":"~to!string(settings.port) ~ ": one of the HTTP listeners has no hostName set.");
			//assert(ctx.settings.hostName != settings.hostName, "A server with the host name '"~settings.hostName~"' is already "
			//	"listening on "~lst.bindAddress~":"~to!string(settings.port)~". You must call listenHTTP at most once for every hostName in the server settings.");
		}

		lst.vhosts++;
	}

	bool any_successful = false;

	// Check for every bind address/port, if a new listening socket needs to be created and
	// check for conflicting servers
	foreach (addr; settings.bindAddresses) {
		bool found_listener = false;
		foreach (i, ref lst; g_listeners) {
			if (lst.bindAddress == addr && lst.bindPort == settings.port) {
				addVHost(lst);
				assert(!settings.tlsContext || settings.tlsContext is lst.tlsContext || lst.tlsContext.kind == TLSContextKind.serverSNI,
						format("Got multiple overlapping SSL bind addresses (port %s), but no SNI TLS context!?", settings.port));
				found_listener = true;
				any_successful = true;
				break;
			}
		}
		if (!found_listener) {
			auto listener = HTTPServerListener(addr, settings.port, settings.tlsContext);
			if (doListen(settings, g_listeners.length, addr)) // DMD BUG 2043
			{
				found_listener = true;
				any_successful = true;
				g_listeners ~= listener;
			}
		}
	}

	enforce(any_successful, "Failed to listen for incoming HTTP connections on any of the supplied interfaces.");
}

/**
	Provides a HTTP request handler that responds with a static Diet template.
*/
@property HTTPServerRequestDelegateS staticTemplate(string template_file)()
{
	import vibe.templ.diet;
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
{
	return (HTTPServerRequest req, HTTPServerResponse res){
		res.redirect(url, status);
	};
}
/// ditto
HTTPServerRequestDelegate staticRedirect(URL url, HTTPStatus status = HTTPStatus.found)
{
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
{
	s_distHost = host;
	s_distPort = port;
}


/**
	Renders the given template and makes all ALIASES available to the template.

	This currently suffers from multiple DMD bugs - use renderCompat() instead for the time being.

	You can call this function as a member of HTTPServerResponse using D's uniform function
	call syntax.

	Examples:
		---
		string title = "Hello, World!";
		int pageNumber = 1;
		res.render!("mytemplate.jd", title, pageNumber);
		---
*/
@property void render(string template_file, ALIASES...)(HTTPServerResponse res)
{
	import vibe.templ.diet;
	res.headers["Content-Type"] = "text/html; charset=UTF-8";
	parseDietFile!(template_file, ALIASES)(res.bodyWriter);
}


/**
	Creates a HTTPServerRequest suitable for writing unit tests.
*/
HTTPServerRequest createTestHTTPServerRequest(URL url, HTTPMethod method = HTTPMethod.GET, InputStream data = null)
{
	InetHeaderMap headers;
	return createTestHTTPServerRequest(url, method, headers, data);
}
/// ditto
HTTPServerRequest createTestHTTPServerRequest(URL url, HTTPMethod method, InetHeaderMap headers, InputStream data = null)
{
	auto is_tls = url.schema == "https";
	auto ret = new HTTPServerRequest(url.port ? url.port : is_tls ? 443 : 80);
	ret.path = url.pathString;
	ret.queryString = url.queryString;
	ret.username = url.username;
	ret.password = url.password;
	ret.requestURL = url.localURI;
	ret.method = method;
	ret.tls = is_tls;
	ret.headers = headers;
	ret.bodyReader = data;
	return ret;
}

/**
	Creates a HTTPServerResponse suitable for writing unit tests.
*/
HTTPServerResponse createTestHTTPServerResponse(OutputStream data_sink = null, SessionStore session_store = null)
{
	import vibe.stream.wrapper;

	HTTPServerSettings settings;
	if (session_store) {
		settings = new HTTPServerSettings;
		settings.sessionStore = session_store;
	}
	if (!data_sink) data_sink = new NullOutputStream;
	auto stream = new ProxyStream(null, data_sink);
	auto ret = new HTTPServerResponse(stream, settings, defaultAllocator());
	return ret;
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/// Delegate based request handler
alias HTTPServerRequestDelegate = void delegate(HTTPServerRequest req, HTTPServerResponse res);
/// Static function based request handler
alias HTTPServerRequestFunction = void function(HTTPServerRequest req, HTTPServerResponse res);
/// Interface for class based request handlers
interface HTTPServerRequestHandler {
	/// Handles incoming HTTP requests
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res);
}

/// Delegate based request handler with scoped parameters
alias HTTPServerRequestDelegateS = void delegate(scope HTTPServerRequest req, scope HTTPServerResponse res);
/// Static function based request handler with scoped parameters
alias HTTPServerRequestFunctionS = void function(scope HTTPServerRequest req, scope HTTPServerResponse res);
/// Interface for class based request handlers with scoped parameters
interface HTTPServerRequestHandlerS {
	/// Handles incoming HTTP requests
	void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res);
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
alias HTTPServerErrorPageHandler = void delegate(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error);


/**
	Specifies optional features of the HTTP server.

	Disabling unneeded features can speed up the server or reduce its memory usage.

	Note that the options parseFormBody, parseJsonBody and parseMultiPartBody
	will also drain the HTTPServerRequest.bodyReader stream whenever a request
	body with form or JSON data is encountered.
*/
enum HTTPServerOption {
	none                      = 0,
	/// Fills the .path, .queryString fields in the request
	parseURL                  = 1<<0,
	/// Fills the .query field in the request
	parseQueryString          = 1<<1 | parseURL,
	/// Fills the .form field in the request
	parseFormBody             = 1<<2,
	/// Fills the .json field in the request
	parseJsonBody             = 1<<3,
	/// Enables use of the .nextPart() method in the request
	parseMultiPartBody        = 1<<4, // todo
	/// Fills the .cookies field in the request
	parseCookies              = 1<<5,
	/// Distributes request processing among worker threads
	distribute                = 1<<6,
	/** Enables stack traces (HTTPServerErrorInfo.debugMessage).

		Note that generating the stack traces are generally a costly
		operation that should usually be avoided in production
		environments. It can also reveal internal information about
		the application, such as function addresses, which can
		help an attacker to abuse possible security holes.
	*/
	errorStackTraces          = 1<<7,

	/** The default set of options.

		Includes all options, except for distribute.
	*/
	defaults =
		parseURL |
		parseQueryString |
		parseFormBody |
		parseJsonBody |
		parseMultiPartBody |
		parseCookies |
		errorStackTraces,

	/// deprecated
	None = none,
	/// deprecated
	ParseURL = parseURL,
	/// deprecated
	ParseQueryString = parseQueryString,
	/// deprecated
	ParseFormBody = parseFormBody,
	/// deprecated
	ParseJsonBody = parseJsonBody,
	/// deprecated
	ParseMultiPartBody = parseMultiPartBody,
	/// deprecated
	ParseCookies = parseCookies
}


/**
	Contains all settings for configuring a basic HTTP server.

	The defaults are sufficient for most normal uses.
*/
final class HTTPServerSettings {
	/** The port on which the HTTP server is listening.

		The default value is 80. If you are running a SSL enabled server you may want to set this
		to 443 instead.
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
	HTTPServerOption options = HTTPServerOption.defaults;

	/** Time of a request after which the connection is closed with an error; not supported yet

		The default limit of 0 means that the request time is not limited.
	*/
	Duration maxRequestTime;// = dur!"seconds"(0);

	/** Maximum time between two request on a keep-alive connection

		The default value is 10 seconds.
	*/
	Duration keepAliveTimeout;// = dur!"seconds"(10);

	/// Maximum number of transferred bytes per request after which the connection is closed with
	/// an error; not supported yet
	ulong maxRequestSize = 2097152;


	///	Maximum number of transferred bytes for the request header. This includes the request line
	/// the url and all headers.
	ulong maxRequestHeaderSize = 8192;

	/// Sets a custom handler for displaying error pages for HTTP errors
	HTTPServerErrorPageHandler errorPageHandler = null;

	@property void sslContext(TLSContext ctx) { tlsContext = ctx; }
	@property TLSContext sslContext() { return tlsContext; }

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

	/// Returns a duplicate of the settings object.
	@property HTTPServerSettings dup()
	{
		auto ret = new HTTPServerSettings;
		foreach (mem; __traits(allMembers, HTTPServerSettings)) {
			static if (mem == "bindAddresses") ret.bindAddresses = bindAddresses.dup;
			else static if (__traits(compiles, __traits(getMember, ret, mem) = __traits(getMember, this, mem)))
				__traits(getMember, ret, mem) = __traits(getMember, this, mem);
		}
		return ret;
	}

	/// Disable support for HTTP/2 connection handling
	bool disableHTTP2 = false;

	/// The HTTP/2 settings for this domain
	HTTP2Settings http2Settings;

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
	Duration webSocketPingInterval;// = dur!"seconds"(60);

	this()
	{
		// need to use the contructor because the Ubuntu 13.10 GDC cannot CTFE dur()
		maxRequestTime = 0.seconds;
		keepAliveTimeout = 10.seconds;
		webSocketPingInterval = 60.seconds;
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
		union Reader {
			InputStream delegate() del;
			InputStream stream;
		}

		SysTime m_timeCreated;
		FixedAppender!(string, 31) m_dateAppender;
		HTTPServerSettings m_settings;
		ushort m_port;
		Reader m_bodyReader;
		bool m_isReaderDelegate;

	}

	public {
		/// The IP address of the client
		string peer;
		/// ditto
		NetworkAddress clientAddress;

		deprecated("Use req.tls") {
			@property bool ssl() const { return tls; }
			@property void ssl(bool b) { tls = b; }
		}

		/// Determines if the request was issued over an TLS encrypted channel.
		bool tls;

		/** Information about the SSL certificate provided by the client.

			Remarks: This field is only set if ssl is true, and the peer
			presented a client certificate.
		*/
		SSLCertificateInformation clientCertificate;

		/** The _path part of the URL.

			Remarks: This field is only set if HTTPServerOption.parseURL is set.
		*/
		string path;

		/** The user name part of the URL, if present.

			Remarks: This field is only set if HTTPServerOption.parseURL is set.
		*/
		string username;

		/** The _password part of the URL, if present.

			Remarks: This field is only set if HTTPServerOption.parseURL is set.
		*/
		string password;

		/** The _query string part of the URL.

			Remarks: This field is only set if HTTPServerOption.parseURL is set.
		*/
		string queryString;

		/** Contains the list of _cookies that are stored on the client.

			Note that the a single cookie name may occur multiple times if multiple
			cookies have that name but different paths or domains that all match
			the request URI. By default, the first cookie will be returned, which is
			the or one of the cookies with the closest path match.

			Remarks: This field is only set if HTTPServerOption.parseCookies is set.
		*/
		CookieValueMap cookies;

		/** Contains all _form fields supplied using the _query string.

			The fields are stored in the same order as they are received.

			Remarks: This field is only set if HTTPServerOption.parseQueryString is set.
		*/
		FormFields query;

		/** A map of general parameters for the request.

			This map is supposed to be used by middleware functionality to store
			information for later stages. For example vibe.http.router.URLRouter uses this map
			to store the value of any named placeholders.
		*/
		string[string] params;

		/** Supplies the request body as a stream.

			Note that when certain server options are set (such as
			HTTPServerOption.parseJsonBody) and a matching request was sent,
			the returned stream will be empty. If needed, remove those
			options and do your own processing of the body when launching
			the server. HTTPServerOption has a list of all options that affect
			the request body.
		*/
		@property InputStream bodyReader() { return m_isReaderDelegate ? m_bodyReader.del() : m_bodyReader.stream; }

		/// ditto
		@property void bodyReader(InputStream body_reader) {
			m_isReaderDelegate = false;
			m_bodyReader.stream = body_reader;
		}

		/// Evaluates the body reader using the supplied delegate. Used to avoid initialization
		/// of streams in requests that contain no body
		@property void bodyReader(InputStream delegate() body_reader) {
			m_isReaderDelegate = true;
			m_bodyReader.del = body_reader;
		}

		/** Contains the parsed Json for a JSON request.

			Remarks:
				This field is only set if HTTPServerOption.parseJsonBody is set.

				A JSON request must have the Content-Type "application/json".
		*/
		Json json;

		/** Contains the parsed parameters of a HTML POST _form request.

			The fields are stored in the same order as they are received.

			Remarks:
				This field is only set if HTTPServerOption.parseFormBody is set.

				A form request must either have the Content-Type
				"application/x-www-form-urlencoded" or "multipart/form-data".
		*/
		FormFields form;

		/** Contains information about any uploaded file for a HTML _form request.

			Remarks:
				This field is only set if HTTPServerOption.parseFormBody is set
				and if the Content-Type is "multipart/form-data".
		*/
		FilePartFormFields files;

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
		@property const(HTTPServerSettings) serverSettings() const
		{
			return m_settings;
		}
	}

	this(SysTime reqtime, ushort port)
	{
		m_timeCreated = reqtime;
		m_port = port;
		writeRFC822DateTimeString(m_dateAppender, m_timeCreated);
		this.headers["Date"] = m_dateAppender.data();
	}

	this(ushort port)
	{
		this(Clock.currTime(UTC()), port);
	}

	/** Time when this request started processing.
	*/
	@property inout(SysTime) timeCreated() inout { return m_timeCreated; }


	/** The full URL that corresponds to this request.

		The host URL includes the protocol, host and optionally the user
		and password that was used for this request. This field is useful to
		construct self referencing URLs.

		Note that the port is currently not set, so that this only works if
		the standard port is used.
	*/
	@property URL fullURL()
	const {
		URL url;
		auto fh = this.headers.get("X-Forwarded-Host", "");
		if (!fh.empty) {
			url.schema = this.headers.get("X-Forwarded-Proto", "http");
			url.host = fh;
		} else {
			if (!this.host.empty) url.host = this.host;
			else if (!m_settings.hostName.empty) url.host = m_settings.hostName;
			else url.host = m_settings.bindAddresses[0];

			if (this.tls) {
				url.schema = "https";
				if (m_port != 443) url.port = m_port;
			} else {
				url.schema = "http";
				if (m_port != 80) url.port = m_port;
			}
		}
		url.host = url.host.split(":")[0];
		url.username = this.username;
		url.password = this.password;
		url.path = Path(path);
		url.queryString = queryString;
		return url;
	}

	/** The relative path the the root folder.

		Using this function instead of absolute URLs for embedded links can be
		useful to avoid dead link when the site is piped through a
		reverse-proxy.

		The returned string always ends with a slash.
	*/
	@property string rootDir() const {
		if (path.length == 0) return "./";
		auto depth = count(path[1 .. $], '/');
		return depth == 0 ? "./" : replicate("../", depth);
	}
}


/**
	Represents a HTTP response as sent from the server side.
*/
final class HTTPServerResponse : HTTPResponse {
	private {
		union Connection {
			ConnectionStack stack;
			ConnectionStream test;
		}

		struct ConnectionStack {
			TCPConnection tcp;
			TLSStream tls;
			HTTP2Stream http2;
		}

		Connection m_conn;
		CompressionStream m_compressionStream;
		BodyStream m_bodyStream;

		Allocator m_requestAlloc;
		HTTPServerSettings m_settings;
		Session m_session;

		bool m_isTest;
		bool m_isGzip;
		bool m_isChunked;
		bool m_headerWritten;
		bool m_isHeadResponse;
		bool m_outputStream;
		SysTime m_timeFinalized;
	}

	union CompressionStream {
		GzipOutputStream gzip;
		DeflateOutputStream deflate;
	}

	union BodyStream {
		/// Counts content-length to validate the value specified in the headers
		CountingOutputStream counting;
		/// Sends chunks of data after every flush
		ChunkedOutputStream chunked;
		/// For HEAD Requests
		NullOutputStream none;
	}

	/// Identifies the stream most suitable for writing through
	private {
		@property OutputStream outputStream() {
			if (!m_outputStream) return null;
			if (!hasCompression) {
				if (isHeadResponse) return cast(OutputStream) m_bodyStream.none;
				else if (m_isChunked) return cast(OutputStream) m_bodyStream.chunked;
				else return cast(OutputStream) m_bodyStream.counting;
			}
			else if (m_isGzip) return cast(OutputStream) m_compressionStream.gzip;
			else return cast(OutputStream) m_compressionStream.deflate;
		}

		@property ConnectionStream topStream() { return m_isTest ? cast(ConnectionStream) m_conn.test : (m_conn.stack.http2 ? cast(ConnectionStream) m_conn.stack.http2 : ( m_conn.stack.tls ? cast(ConnectionStream) m_conn.stack.tls : cast(ConnectionStream) m_conn.stack.tcp)); }
	}

	// Test constructor.
	this(Stream test_stream, HTTPServerSettings settings, Allocator req_alloc)
	{
		m_isTest = true;
		m_conn.test = new ConnectionProxyStream(test_stream, null);
		m_settings = settings;
		m_requestAlloc = req_alloc;
	}

	// Regular constructor taking a connection stack
	this(TCPConnection tcp_conn, TLSStream tls_stream, HTTP2Stream http2_stream, HTTPServerSettings settings, Allocator req_alloc)
	{
		m_conn.stack.tcp = tcp_conn;
		m_conn.stack.tls = tls_stream;
		m_conn.stack.http2 = http2_stream;
		m_settings = settings;
		m_requestAlloc = req_alloc;
	}

	~this() {
		// The connection streams, allocator and settings were not owned by the HTTPServerResponse
		if (!outputStream) return;

		if (hasCompression) {
			if (m_isGzip && m_compressionStream.gzip) {
				FreeListObjectAlloc!GzipOutputStream.free(m_compressionStream.gzip);
				m_compressionStream.gzip = null;
			}
			else {
				FreeListObjectAlloc!DeflateOutputStream.free(m_compressionStream.deflate);
				m_compressionStream.deflate = null;
			}
		}
		
		if (isHeadResponse && m_bodyStream.none) {
			FreeListObjectAlloc!NullOutputStream.free(m_bodyStream.none);
			m_bodyStream.none = null;
		}
		else {
			if (m_isChunked && m_bodyStream.chunked) {
				FreeListObjectAlloc!ChunkedOutputStream.free(m_bodyStream.chunked);
				m_bodyStream.chunked = null;
			}
			else if (m_bodyStream.counting) {
				FreeListObjectAlloc!CountingOutputStream.free(m_bodyStream.counting);
				m_bodyStream.counting = null;
			}
		}

	}

	private @property bool isHTTP2() { return !m_isTest && m_conn.stack.http2 !is null; }

	@property SysTime timeFinalized() { return m_timeFinalized; }

	/// Determines if compression is used in this response.
	@property bool hasCompression() { return m_compressionStream.gzip !is null; }

	/// Determines if the HTTP header has already been written.
	@property bool headerWritten() const { return m_headerWritten; }

	/// Determines if the response does not need a body.
	bool isHeadResponse() const { return m_isHeadResponse; }

	/// Determines if the response is sent over an encrypted connection.
	bool tls() const { return (!m_isTest && m_conn.stack.tls) ? true : false; }

	/// ditto
	bool ssl() const { return tls(); }

	/// Writes the entire response body at once.
	void writeBody(in ubyte[] data, string content_type = null)
	{
		if (content_type != "") headers["Content-Type"] = content_type;
		headers["Content-Length"] = formatAlloc(m_requestAlloc, "%d", data.length);
		bodyWriter.write(data);
	}
	/// ditto
	void writeBody(string data, string content_type = "text/plain; charset=UTF-8")
	{
		writeBody(cast(ubyte[])data, content_type);
	}
	/// ditto
	void writeBody(in ubyte[] data, int status, string content_type = null)
	{
		statusCode = status;
		writeBody(data, content_type);
	}
	/// ditto
	void writeBody(string data, int status, string content_type = "text/plain; charset=UTF-8")
	{
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
	void writeRawBody(RandomAccessStream stream)
	{
		OutputStream writer = bodyWriter();
		enforce(!m_isChunked, "The raw body can only be written if Content-Type is set");
		if (auto null_writer = cast(NullOutputStream) writer)
			return;
		auto bytes = stream.size - stream.tell();
		topStream.write(stream);
		m_bodyStream.counting.increment(bytes);
	}
	/// ditto
	void writeRawBody(InputStream stream, size_t num_bytes = 0)
	{

		OutputStream writer = bodyWriter();
		enforce(!m_isChunked, "The raw body can only be written if Content-Type is set");
		if (auto null_writer = cast(NullOutputStream) writer)
			return;
		if (num_bytes > 0) {
			topStream.write(stream, num_bytes);
			m_bodyStream.counting.increment(num_bytes);
		} else m_bodyStream.counting.write(stream, num_bytes);
	}
	/// ditto
	void writeRawBody(RandomAccessStream stream, int status)
	{
		statusCode = status;
		writeRawBody(stream);
	}
	/// ditto
	void writeRawBody(InputStream stream, int status, size_t num_bytes = 0)
	{
		statusCode = status;
		writeRawBody(stream, num_bytes);
	}

	/// Writes a JSON message with the specified status
	void writeJsonBody(T)(T data, int status = HTTPStatus.OK, string content_type = "application/json; charset=UTF-8", bool allow_chunked = false)
	{
		import std.traits;
		import vibe.stream.wrapper;

		static if (is(typeof(data.data())) && isArray!(typeof(data.data()))) {
			static assert(!is(T == Appender!(typeof(data.data()))), "Passed an Appender!T to writeJsonBody - this is most probably not doing what's indended.");
		}

		statusCode = status;
		headers["Content-Type"] = content_type;

		// set an explicit content-length field if chunked encoding is not allowed
		if (!allow_chunked) {
			import vibe.internal.rangeutil;
			long length = 0;
			auto counter = RangeCounter(&length);
			serializeToJson(counter, data);
			headers["Content-Length"] = formatAlloc(m_requestAlloc, "%d", length);
		}

		auto rng = StreamOutputRange(bodyWriter);
		serializeToJson(&rng, data);
	}

	/**
	 * Writes the response with no body.
	 *
	 * This method should be used in situations where no body is
	 * requested, such as a HEAD request. For an empty body, just use writeBody,
	 * as this method causes problems with some keep-alive connections.
	 */
	void writeVoidBody()
	{
		if (!m_isHeadResponse) {
			assert("Content-Length" !in headers);
			assert("Transfer-Encoding" !in headers);
		}
		assert(!headerWritten);
		writeHeader();
	}

	/** A stream for writing the body of the HTTP response.

		Note that after 'bodyWriter' has been accessed for the first time, it
		is not allowed to change any header or the status code of the response.
	*/
	@property OutputStream bodyWriter()
	{
		if (outputStream) {
			logDebug("Returning existing outputstream: ", cast(void*) outputStream);
			return outputStream;
		}
		logDebug("Calculating bodyWriter");
		assert(!m_headerWritten, "A void body was already written!");

		m_outputStream = true;

		if (m_isHeadResponse) {
			// for HEAD requests, we define a NullOutputWriter for convenience
			// - no body will be written. However, the request handler should call writeVoidBody()
			// and skip writing of the body in this case.
			if ("Content-Length" !in headers && !m_session) {
				m_isChunked = true;
				headers["Transfer-Encoding"] = "chunked";
			}
			writeHeader();
			m_bodyStream.none = FreeListObjectAlloc!NullOutputStream.alloc();
			return outputStream;
		}

		if (("Content-Encoding" in headers || "Transfer-Encoding" in headers) && "Content-Length" in headers) {
			// we do not known how large the compressed body will be in advance
			// so remove the content-length and use chunked transfer
			headers.remove("Content-Length");
			m_isChunked = true;
		}

		if ("Content-Length" in headers || isHTTP2) {
			m_isChunked = false;
			m_bodyStream.counting = FreeListObjectAlloc!CountingOutputStream.alloc(topStream);
		} else if (!isHTTP2) {
			headers["Transfer-Encoding"] = "chunked";
			m_isChunked = true;
			m_bodyStream.chunked = FreeListObjectAlloc!ChunkedOutputStream.alloc(topStream);
		}

		bool applyCompression(string val) {
			if (icmp2(val, "gzip") == 0) {
				m_compressionStream.gzip = FreeListObjectAlloc!GzipOutputStream.alloc(outputStream);
				m_isGzip = true;
				return true;
			} else if (icmp2(val, "deflate") == 0) {
				m_compressionStream.deflate = FreeListObjectAlloc!DeflateOutputStream.alloc(outputStream);
				return true;
			}
			return false;
		}

		if (auto pce = "Content-Encoding" in headers) {
			if (!applyCompression(*pce))
			{
				logWarn("Attemped to return body with a Content-Encoding which is not supported");
				headers.remove("Content-Encoding");
			}
		}

		// todo: Add TE header support, and Transfer-Encoding: gzip, chunked

		writeHeader();

		return outputStream;
	}

	/** Sends a redirect request to the client.

		Params:
			url = The URL to redirect to
			status = The HTTP redirect status (3xx) to send - by default this is $D(D HTTPStatus.found)
	*/
	void redirect(string url, int status = HTTPStatus.Found)
	{
		statusCode = status;
		headers["Location"] = url;
		headers["Content-Length"] = "14";
		bodyWriter.write("redirecting...");
	}
	/// ditto
	void redirect(URL url, int status = HTTPStatus.Found)
	{
		redirect(url.toString(), status);
	}

	///
	unittest {
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
	*/
	ConnectionStream switchProtocol(string protocol)
	{
		statusCode = HTTPStatus.SwitchingProtocols;
		headers["Upgrade"] = protocol;
		writeVoidBody();
		return topStream;
	}

	/** Sets the specified cookie value.

		Params:
			name = Name of the cookie
			value = New cookie value - pass null to clear the cookie
			path = Path (as seen by the client) of the directory tree in which the cookie is visible
	*/
	Cookie setCookie(string name, string value, string path = "/")
	{
		auto cookie = new Cookie();
		cookie.path = path;
		cookie.value = value;
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
	{
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
	{
		assert(m_session, "Try to terminate a session, but none is started.");
		auto cookie = setCookie(m_settings.sessionIdCookie, null, m_session.get!string("$sessionCookiePath"));
		cookie.secure = m_session.get!bool("$sessionCookieSecure");
		m_session.destroy();
		m_session = Session.init;
	}

	/// Returns the number of bytes currently flushed to the connection stream after all encodings are processed,
	/// including the size of the chunk size specifier if applicable. HEAD response are generally 0
	@property ulong bytesWritten() { return !m_headerWritten ? 0 : (m_isHeadResponse ? 0 : (outputStream ? (m_isChunked ? m_bodyStream.chunked.bytesWritten : (m_bodyStream.counting !is null ? m_bodyStream.counting.bytesWritten : 0)) : 0)); }

	/**
		Compatibility version of render() that takes a list of explicit names and types instead
		of variable aliases.

		This version of render() works around a compiler bug in DMD (Issue 2962). You should use
		this method instead of render() as long as this bug is not fixed.

		The first template argument is the name of the template file. All following arguments
		must be pairs of a type and a string, each specifying one parameter. Parameter values
		can be passed either as a value of the same type as specified by the template
		arguments, or as a Variant which has the same type stored.

		Note that the variables are copied and not referenced inside of the template - any
		modification you do on them from within the template will get lost.

		Examples:
			---
			string title = "Hello, World!";
			int pageNumber = 1;
			res.renderCompat!("mytemplate.jd",
				string, "title",
				int, "pageNumber")
				(title, pageNumber);
			---
	*/
	void renderCompat(string template_file, TYPES_AND_NAMES...)(...)
	{
		import vibe.templ.diet;
		headers["Content-Type"] = "text/html; charset=UTF-8";
		compileDietFileCompatV!(template_file, TYPES_AND_NAMES)(bodyWriter, _argptr, _arguments);
	}

	/**
		Waits until either the connection closes or until the given timeout is
		reached.

		Returns:
			$(D true) if the connection was closed and $(D false) when the
			timeout was reached.
	*/
	bool waitForConnectionClose(Duration timeout = Duration.max)
	{
		if (!topStream || !topStream.connected) return true;
		topStream.waitForData(timeout);
		return !topStream.connected;
	}

	// Finalizes the response. This is called automatically by the server.
	private void finalize()
	{
		ulong bytes_written = bytesWritten();
		logDebug("Finalized to: %d", bytes_written);

		if (!m_headerWritten) {
			writeHeader(); 

			// No streams were opened in this response, because they are created in bodyWriter()
		}
		else {
			assert(outputStream !is null);
			if (hasCompression) {
				if (m_isGzip) {
					m_compressionStream.gzip.finalize();
					FreeListObjectAlloc!GzipOutputStream.free(m_compressionStream.gzip);
					m_compressionStream.gzip = null;
				}
				else {
					m_compressionStream.deflate.finalize();
					FreeListObjectAlloc!DeflateOutputStream.free(m_compressionStream.deflate);
					m_compressionStream.deflate = null;
				}
			}

			if (isHeadResponse) {
				FreeListObjectAlloc!NullOutputStream.free(m_bodyStream.none);
				m_bodyStream.none = null;
			}
			else {
				if (m_isChunked) {
					m_bodyStream.chunked.finalize();
					FreeListObjectAlloc!ChunkedOutputStream.free(m_bodyStream.chunked);
					m_bodyStream.chunked = null;
				}
				else {
					m_bodyStream.counting.finalize();
					FreeListObjectAlloc!CountingOutputStream.free(m_bodyStream.counting);
					m_bodyStream.counting = null;
				}
			}
		}

		// ignore exceptions caused by an already closed connection - the client
		// may have closed the connection already and this doesn't usually indicate
		// a problem.
		try {
			if (!isHTTP2) topStream.flush();
			// flush yields on HTTP/2, finalize instead will attempt an atomic response before flushing, in case no flushes were made previously.
			else topStream.finalize(); 	
		}
		catch (Exception e) logDebug("Failed to flush connection after finishing HTTP response: %s", e.msg);

		m_timeFinalized = Clock.currTime(UTC());

		if (!isHeadResponse && bytes_written < headers.get("Content-Length", "0").to!long) {
			logDebug("HTTP response only written partially before finalization. Terminating connection.");
			topStream.close();
		}
		else if (isHTTP2)
			topStream.close(); // HTTP/2 stream can be closed safely here

		m_conn.stack = ConnectionStack.init;
		m_settings = null;
		if (m_session) m_session.destroy();
	}

	private void writeHeader()
	{
		import vibe.stream.wrapper;

		assert(!m_headerWritten, "Try to write header after body has already begun.");
		m_headerWritten = true;

		if (isHTTP2)
		{
			// Use integrated header writer
			m_conn.stack.http2.writeHeader(cast(HTTPStatus)this.statusCode, this.headers, this.cookies); 
			return;
		}

		auto dst = StreamOutputRange(outputStream);

		void writeLine(T...)(string fmt, T args)
		{
			formattedWrite(&dst, fmt, args);
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
		foreach (k, v; this.headers)
			writeLine("%s: %s", k, v);

		logTrace("---------------------");

		// write cookies
		foreach (n, cookie; this.cookies) {
			dst.put("Set-Cookie: ");
			cookie.writeString(&dst, n);
			dst.put("\r\n");
		}

		// finalize response header
		dst.put("\r\n");
		dst.flush();

		// This would break atomic responses for HTTP/2
		if (!isHTTP2)
			topStream.flush();
	}
}

/**************************************************************************************************/
/* Private types                                                                                  */
/**************************************************************************************************/

private class HTTPServerContext {
	HTTPServerRequestDelegate requestHandler;
	HTTPServerSettings settings;
	HTTPLogger[] loggers;
}

private struct HTTPServerListener {
	string bindAddress;
	ushort bindPort;
	TLSContext tlsContext;
	ushort vhosts;
}

private enum MaxHTTPHeaderLineLength = 4096;

private final class LimitedHTTPInputStream : LimitedInputStream {
	this(InputStream stream, ulong byte_limit, bool silent_limit = false) {
		super(stream, byte_limit, silent_limit);
	}
	override void onSizeLimitReached() {
		throw new HTTPStatusException(HTTPStatus.requestEntityTooLarge);
	}
}

private final class TimeoutHTTPInputStream : InputStream {
	private {
		long m_timeref;
		long m_timeleft;
		InputStream m_in;
	}

	this(InputStream stream, Duration timeleft, SysTime reftime)
	{
		enforce(timeleft > dur!"seconds"(0), "Timeout required");
		m_in = stream;
		m_timeleft = timeleft.total!"hnsecs"();
		m_timeref = reftime.stdTime();
	}

	@property bool empty() { enforce(m_in !is null, "InputStream missing"); return m_in.empty(); }
	@property ulong leastSize() { enforce(m_in !is null, "InputStream missing"); return m_in.leastSize();  }
	@property bool dataAvailableForRead() {  enforce(m_in !is null, "InputStream missing"); return m_in.dataAvailableForRead; }
	const(ubyte)[] peek() { return m_in.peek(); }

	void read(ubyte[] dst)
	{
		enforce(m_in !is null, "InputStream missing");
		checkTimeout();
		m_in.read(dst);
	}

	private void checkTimeout()
	{
		auto curr = Clock.currStdTime();
		auto diff = curr - m_timeref;
		if (diff > m_timeleft) throw new HTTPStatusException(HTTPStatus.RequestTimeout);
		m_timeleft -= diff;
		m_timeref = curr;
	}
}

private:

shared string s_distHost;
shared ushort s_distPort = 11000;
__gshared HTTPServerContext[] g_contexts;
__gshared HTTPServerListener[] g_listeners;

HTTPServerContext getServerContext(ref HTTPServerListener listen_info, string authority /* example.com:port */) {
	string reqhost;
	ushort reqport = 0;
	import std.algorithm : splitter;
	auto reqhostparts = authority.splitter(":");
	if (!reqhostparts.empty) { reqhost = reqhostparts.front; reqhostparts.popFront(); }
	if (!reqhostparts.empty) { reqport = reqhostparts.front.to!ushort; reqhostparts.popFront(); }
	enforce(reqhostparts.empty, "Invalid suffix found in host header");
	
	foreach (ctx; g_contexts)
		if (icmp2(ctx.settings.hostName, reqhost) == 0 && (!reqport || reqport == ctx.settings.port))
			if (ctx.settings.port == listen_info.bindPort)
				foreach (addr; ctx.settings.bindAddresses)
					if (addr == listen_info.bindAddress)
						return ctx;

	return HTTPServerContext.init;
}

HTTPServerContext getServerContext(ref HTTPServerListener listen_info)
{
	foreach (ctx; g_contexts)
		if (ctx.settings.port == listen_info.bindPort)
			foreach (addr; ctx.settings.bindAddresses)
				if (addr == listen_info.bindAddress)
					return ctx;
	return HTTPServerContext.init;
}

struct HTTP2HandlerContext
{
	bool started;
	
	TCPConnection tcpConn;
	TLSStream tlsStream;
	HTTP2Session session;
	
	HTTPServerListener listenInfo;
	HTTPServerContext context;
	
	// Used only in h2c upgrade, to allow the loop to be kept active after the response is sent
	// we can't end the scope because the response will need to happen through HTTP/2
	Task evloop;
	
	@property bool isUpgrade() { return evloop != Task(); }
	@property bool isTLS() { return tlsStream?true:false; }
	
	~this() {
		if (session) {
			FreeListObjectAlloc!HTTP2Session.free(session);
			session = null;
		}
	}
	
	this(TCPConnection tcp_conn, TLSStream tls_stream, HTTPServerListener listen_info, HTTPServerContext _context) {
		listenInfo = listen_info;
		tcpConn = tcp_conn;
		tlsStream = tls_stream;
		context = _context;
	}

	void close(string error) {
		session.stop(error);
	}
	
	bool tryStart(string chosen_alpn)
	{
		assert(!started);
		
		// see if the client has an HTTP/2 preface for a quick cleartext upgrade attempt
		if (!tlsStream)
		{
			ulong preface_length = tcpConn.leastSize();
			if (preface_length >= 24 && tcpConn.peek()[0 .. 24] == "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
			{
				startHTTP2(); // event loop starts here
				return true;
			}
		}
		// We check for HTTP/2 over secured connection with ALPN
		else if (context.settings && !context.settings.disableHTTP2 && chosen_alpn.length >= 2 && chosen_alpn[0 .. 2] == "h2")
		{
			startTLSHTTP2();
			return true;
		}
		
		return false;
	}
	
	void startTLSHTTP2() { // using ALPN prior knowledge over secured stream. Restrict to a specific context
		started = true;
		HTTP2Settings local_settings;
		if (context.settings)
			local_settings = context.settings.http2Settings;
		session = FreeListObjectAlloc!HTTP2Session.alloc(true, &handler, tcpConn, tlsStream, local_settings);
		session.run(); // blocks, loops and handles requests here
	}
	
	void startHTTP2() { // using prior knowledge over cleartext
		started = true;
		HTTP2Settings local_settings;
		if (context.settings)
			local_settings = context.settings.http2Settings;
		session = FreeListObjectAlloc!HTTP2Session.alloc(true, &handler, tcpConn, null, local_settings);
		session.run(); // blocks, loops and handles requests here
	}
	
	HTTP2Stream tryStartUpgrade(ref InetHeaderMap headers)
	{
		// assert(!isTLS, "Can only upgrade over cleartext TCP");

		// using HTTP/1.1 upgrade mechanism over cleartext
		string upgrade_hd = headers.get("Upgrade", null);
		if (!upgrade_hd || upgrade_hd.length < 3 || upgrade_hd[0 .. 3] != "h2c")
			return null;
		
		string connection_hd = headers.get("Connection", null);
		if (!connection_hd || icmp2(connection_hd, "Upgrade, HTTP2-Settings") != 0)
			return null;
		
		string base64_settings = headers.get("HTTP2-Settings", null);
		if (!base64_settings)
			return null;

		HTTP2Settings local_settings;
		if (context.settings)
			local_settings = context.settings.http2Settings;

		session = FreeListObjectAlloc!HTTP2Session.alloc(&handler, tcpConn, cast(ubyte[]) base64_settings, local_settings);
		tcpConn.write("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: h2c\r\n\r\n");
		evloop = runTask( { session.run(); } );
		started = true;
		return session.getUpgradeStream();
	}
	
	void continueHTTP2Upgrade() {
		started = true;
		// for upgrade mechanism, let the event loop accept new connections through HTTP/2
		if (evloop != Task())
			evloop.join();
		// the handleRequest scope stays active while connected once the initial request is handled
	}
	
	void handler(HTTP2Stream stream)
	{
		bool keep_alive = false;
		.handleRequest(tcpConn, tlsStream, stream, listenInfo, listenInfo.vhosts > 0, context, this, keep_alive);
	}
}

void handleHTTPConnection(TCPConnection tcp_conn, HTTPServerListener listen_info)
{
	version(Botan) {
		import vibe.stream.botan : BotanTLSStream;
		FreeListRef!BotanTLSStream tls_stream;
	}
	version(OpenSSL) {
		import vibe.stream.openssl : OpenSSLStream;
		FreeListRef!OpenSSLStream tls_stream;
	}
	version(VibeNoTLS) {
		TLSStream tls_stream;
	}
	if (!tcp_conn.waitForData(10.seconds())) {
		logDebug("Client didn't send the initial request in a timely manner. Closing connection.");
		return;
	}
	
	logTrace("reading request..");
	scope(exit) 
		logTrace("Done handling connection.");
	
	string chosen_alpn;
	HTTPServerContext context;
	// if vhosts == 0, we keep the listener context. We use the it until the headers specify a `Host`
	bool has_vhosts = listen_info.vhosts > 0;
	if (listen_info.tlsContext !is null) {
		logTrace("Accept TLS connection: %s", listen_info.tlsContext.kind);
		// TODO: reverse DNS lookup for peer_name of the incoming connection for TLS client certificate verification purposes
		version(VibeNoTLS) {} else {
			tls_stream = createTLSStreamFL(tcp_conn, listen_info.tlsContext, TLSStreamState.accepting, null, tcp_conn.remoteAddress);
		}
		if (has_vhosts) {
			logDebug("got user data: %s", cast(void*)tls_stream.getUserData());
			context = cast(HTTPServerContext) tls_stream.getUserData();
		}
		else
			context = listen_info.getServerContext();
		chosen_alpn = tls_stream.alpn;
		logTrace("Chose alpn: %s", chosen_alpn);
	}
	else {
		context = listen_info.getServerContext();
	}
	logDebug("Got context: %s", cast(void*)context);
	assert(context !is null, "Request being processed without a context");
	//assert(context.settings, "Request being loaded without settings");
	auto http2_handler = HTTP2HandlerContext(tcp_conn, tls_stream, listen_info, context);
	
	// Will block here if it succeeds. The handler is kept handy in case HTTP/2 Upgrade is attempted in the headers of an HTTP/1.1 request
	if (http2_handler.tryStart(chosen_alpn))
		// HTTP/2 session terminated, exit
		return;
	else if (tls_stream)
		// That was the only way to start HTTP/2 over TLS
		http2_handler.destroy();
	
	/// Loop for HTTP/1.1 or HTTP/1.0 only
	do {
		bool keep_alive;
		handleRequest(tcp_conn, tls_stream, null, listen_info, has_vhosts, context, http2_handler, keep_alive);
		
		if (http2_handler.isUpgrade) {
			// The HTTP/2 Upgrade request was turned into HTTP/2 stream ID#1, we can now listen for more with an HTTP/2 session
			http2_handler.continueHTTP2Upgrade();
			return;
		}
		if (!keep_alive) { logTrace("No keep-alive - disconnecting client."); break; }
		
		logTrace("Waiting for next request...");
		// wait for another possible request on a keep-alive connection
		if (!tcp_conn.waitForData(context.settings.keepAliveTimeout)) {
			if (!tcp_conn.connected) logTrace("Client disconnected.");
			else logTrace("Keep-alive connection timed out!");
			break;
		}
	} while(!tcp_conn.empty);
}

// Lazily loads the body reader in a HTTPServerRequest. Used in `handleRequest`
struct BodyReader
{
	// true if the bodyReader was initialized
	bool cached;
	
	InputStream reader;
	HTTPServerRequest req;
	
	// bodyReader filters
	FreeListRef!TimeoutHTTPInputStream timeout;
	FreeListRef!LimitedHTTPInputStream limited;
	FreeListRef!ChunkedInputStream chunked;
	
	InputStream bodyReader() {
		if (cached)
			return reader;
		
		if (!req.m_settings) {
			logDebug("No m_settings defined!");
			limited = FreeListRef!LimitedHTTPInputStream(reader, 0);
			reader = limited;
			cached = true;
			return reader;
		}
		
		if (req.m_settings.maxRequestTime != Duration.zero) {
			timeout = FreeListRef!TimeoutHTTPInputStream(reader, req.m_settings.maxRequestTime, req.timeCreated);
			reader = timeout;
		}
		
		// limit request size
		if (auto pcl = "Content-Length" in req.headers) {
			string v = *pcl;
			ulong contentLength = v.to!ulong;
			enforceBadRequest(v.length == 0, "Invalid content-length");
			enforceBadRequest(req.m_settings.maxRequestSize == 0 || contentLength <= req.m_settings.maxRequestSize, "Request size too big");
			limited = FreeListRef!LimitedHTTPInputStream(reader, contentLength);
		} else if (auto pt = "Transfer-Encoding" in req.headers) {
			// allow chunked because HTTP/2 cleartext upgrade stream #1 might use it
			chunked = FreeListRef!ChunkedInputStream(reader);
			limited = FreeListRef!LimitedHTTPInputStream(chunked, req.m_settings.maxRequestSize, true);
		} else {
			limited = FreeListRef!LimitedHTTPInputStream(reader, 0);
		}
		reader = limited;
		cached = true;
		return reader;
	}
}

void handleRequest(TCPConnection tcp_conn, 
				   TLSStream tls_stream, 
				   HTTP2Stream http2_stream,
				   HTTPServerListener listen_info,
				   bool verify_context, // vhosts > 0
				   ref HTTPServerContext context,
				   ref HTTP2HandlerContext http2_handler,
				   ref bool keep_alive)
{
	ConnectionStream topStream() 
	{ 
		if (http2_stream !is null)
			return cast(ConnectionStream) http2_stream;
		if (tls_stream !is null)
			return cast(ConnectionStream) tls_stream;
		return cast(ConnectionStream) tcp_conn;
	}

	static void errorOut(HTTPServerRequest req, HTTPServerResponse res, int code, string msg, string debug_msg, Throwable ex)
	in { assert(!res.headerWritten); }
	out { assert(res.headerWritten); }
	body {
		// stack traces sometimes contain random bytes - make sure they are replaced
		debug_msg = sanitizeUTF8(cast(ubyte[])debug_msg);

		res.statusCode = code;
		if (res.m_settings && res.m_settings.errorPageHandler) {
			auto err = scoped!HTTPServerErrorInfo;
			err.code = code;
			err.message = msg;
			err.debugMessage = debug_msg;
			err.exception = ex;
			return res.m_settings.errorPageHandler(req, res, err);
		}
		//else
		res.writeBody(format("%s - %s\n\n%s\n\nInternal error information:\n%s", code, httpStatusText(code), msg, debug_msg));
		
	}

	// some instances that live only while the request is running
	HTTPServerRequest req = FreeListObjectAlloc!HTTPServerRequest.alloc(listen_info.bindPort);
	HTTPServerResponse res;

	scope(exit) {
		FreeListObjectAlloc!HTTPServerRequest.free(req);
		if (res) {
			FreeListObjectAlloc!HTTPServerResponse.free(res);
			res = null;
		}
	}

	// store the IP address (IPv4 addresses forwarded over IPv6 are stored in IPv4 format)
	if (tcp_conn.peerAddress.startsWith("::ffff:") && tcp_conn.peerAddress[7 .. $].indexOf(":") < 0)
		req.peer = tcp_conn.peerAddress[7 .. $];
	else req.peer = tcp_conn.peerAddress;
	req.clientAddress = tcp_conn.remoteAddress;

	bool parsed;
	keep_alive = false;

	// Used for the parser and the HTTPServerResponse
	PoolAllocator request_allocator = FreeListObjectAlloc!PoolAllocator.alloc(1024, defaultAllocator());
	scope(exit) {
		request_allocator.reset();
		FreeListObjectAlloc!PoolAllocator.free(request_allocator);
	}
	// parse the request
	try {
		BodyReader reqReader;
		// During an upgrade, we would need to read with HTTP/1.1 and write with HTTP/2, 
		// so we define the InputStream before the upgrade starts
		reqReader.reader = cast(InputStream) topStream;

		if (!http2_stream) {
			// HTTP/1.1 headers
			parseRequestHeader(req, reqReader.reader, request_allocator, context.settings.maxRequestHeaderSize);

			// find/verify context
			string authority = req.headers.get("Host", null);
			enforceBadRequest(authority, "No Host header was defined");

			if (verify_context) {
				context = listen_info.getServerContext(authority);
				enforceBadRequest(context !is null, "Invalid hostname requested");
			}

			// Replace topStream with the HTTP/2 stream
			if (!context.settings.disableHTTP2 && !tls_stream)
				http2_stream = http2_handler.tryStartUpgrade(req.headers);
		}
		else
		{ 
			// HTTP/2 headers
			enforce(http2_handler.started, "HTTP/2 session is invalid");
			parseHTTP2RequestHeader(req, http2_stream, request_allocator);

			// find/verify context
			string authority = req.headers.get("Host", null);
			enforceBadRequest(authority, "No Host header was defined");

			enforceBadRequest(!verify_context || listen_info.getServerContext(authority) == http2_handler.context, "Invalid hostname requested for this session.");
		}

		logTrace("Got request header.");

		req.m_settings = context.settings;		
		reqReader.req = req;
		
		// Lazily load the body reader because most requests don't need it
		req.bodyReader = &reqReader.bodyReader;

		res = FreeListObjectAlloc!HTTPServerResponse.alloc(tcp_conn, tls_stream, http2_stream, context.settings, request_allocator);
		scope(exit) {
			// Flush the body if it still contains data when we're done
			if (topStream.connected) {
				if (req.bodyReader && !req.bodyReader.empty) {
					auto nullWriter = scoped!NullOutputStream();
					nullWriter.write(req.bodyReader);
					logTrace("dropped body");
				}
				
				// finalize (e.g. for chunked encoding)
				if (res) res.finalize();
			}
		}
		if (req.tls)
			req.clientCertificate = tls_stream.peerCertificate;
			
		// Setup compressed output with client priority ordering
		if (context.settings.useCompressionIfPossible) {
			if (auto pae = "Accept-Encoding" in req.headers) {
				immutable(char)* c = (*pae).ptr;
				for (size_t i = 0; i < (*pae).length; i++) {
					if (c[i] == 'g' || c[i] == 'G') {
						if (icmp2(c[i .. i+4], "gzip") == 0) {
							res.headers["Content-Encoding"] = "gzip";
							break;
						}
					}

					if (c[i] == 'd' || c[i] == 'D') {
						if (icmp2(c[i .. i + "deflate".length], "deflate") == 0) {
							res.headers["Content-Encoding"] = "deflate";
							break;
						}
					}

				}
			}
		}
				
		// handle Expect header
		if (auto pv = "Expect" in req.headers) {
			if (icmp2(*pv, "100-continue") == 0) {
				logTrace("sending 100 continue");
				topStream.write("HTTP/1.1 100 Continue\r\n\r\n");
			}
		}
		
		// URL parsing if desired. Note that http/2 automatically parsed it
		if (req.httpVersion != HTTPVersion.HTTP_2 && context.settings.options & HTTPServerOption.parseURL) {
			auto url = URL.parse(req.requestURL);
			req.path = urlDecode(url.pathString);
			req.queryString = url.queryString;
			req.username = url.username;
			req.password = url.password;
		}
		
		// query string parsing if desired
		if (context.settings.options & HTTPServerOption.parseQueryString) {
			if (!(context.settings.options & HTTPServerOption.parseURL))
				logWarn("Query string parsing requested but URL parsing is disabled!");
			parseURLEncodedForm(req.queryString, req.query);
		}
		
		// cookie parsing if desired
		if (context.settings.options & HTTPServerOption.parseCookies) {
			auto pv = "cookie" in req.headers;
			if (pv) parseCookies(*pv, req.cookies);
		}
		
		// lookup the session
		if (context.settings.sessionStore) {
			auto pv = context.settings.sessionIdCookie in req.cookies;
			if (pv) {
				// use the first cookie that contains a valid session ID in case
				// of multiple matching session cookies
				foreach (v; req.cookies.getAll(context.settings.sessionIdCookie)) {
					req.session = context.settings.sessionStore.open(v);
					res.m_session = req.session;
					if (req.session) break;
				}
			}
		}
		
		if (context.settings.options & HTTPServerOption.parseFormBody) {
			auto ptype = "Content-Type" in req.headers;
			if (ptype) parseFormData(req.form, req.files, *ptype, req.bodyReader, MaxHTTPHeaderLineLength);
		}
		
		if (context.settings.options & HTTPServerOption.parseJsonBody) {
			if (icmp2(req.contentType, "application/json") == 0) {
				auto bodyStr = cast(string)req.bodyReader.readAll();
				if (!bodyStr.empty) req.json = parseJson(bodyStr);
			}
		}
		
		// write default headers
		if (req.method == HTTPMethod.HEAD) res.m_isHeadResponse = true;
		if (context.settings.serverString.length)
			res.headers["Server"] = context.settings.serverString;
		res.headers["Date"] = formatRFC822DateAlloc(request_allocator, req.timeCreated);
		if (req.persistent && !http2_stream) res.headers["Keep-Alive"] = formatAlloc(request_allocator, "timeout=%d", context.settings.keepAliveTimeout.total!"seconds"());
		
		// finished parsing the request
		parsed = true;
		logTrace("persist: %s", req.persistent);
		keep_alive = req.persistent;
		
		// handle the request
		// logTrace("handle request (body %d)", req.bodyReader.leastSize);
		res.httpVersion = http2_stream ? HTTPVersion.HTTP_2 : req.httpVersion;
		context.requestHandler(req, res);
		
		// if no one has written anything, return 404
		if (!res.headerWritten) {
			string dbg_msg;
			logDiagnostic("No response written for %s", req.requestURL);
			if (context.settings.options & HTTPServerOption.errorStackTraces)
				dbg_msg = format("Not routes match path '%s'", req.requestURL);
			errorOut(req, res, HTTPStatus.notFound, httpStatusText(HTTPStatus.notFound), dbg_msg, null);
		}
	} catch (HTTPStatusException err) {
		string dbg_msg;
		if (context.settings.options & HTTPServerOption.errorStackTraces) {
			if (err.debugMessage) dbg_msg = err.debugMessage;
			else dbg_msg = err.toString().sanitize;
		}
		if (res && !res.headerWritten) errorOut(req, res, err.status, err.msg, dbg_msg, err);
		else logDiagnostic("HTTPSterrorOutatusException while writing the response: %s", err.msg);
		logDebug("Exception while handling request %s %s: %s", req.method, req.requestURL, err.toString().sanitize);
		if (!parsed || (res && res.headerWritten) || justifiesConnectionClose(err.status))
			keep_alive = false;
	} catch (UncaughtException e) {
		auto status = parsed ? HTTPStatus.internalServerError : HTTPStatus.badRequest;
		string dbg_msg;
		if (context.settings.options & HTTPServerOption.errorStackTraces) dbg_msg = e.toString().sanitize;
		if (res && !res.headerWritten && topStream.connected) errorOut(req, res, status, httpStatusText(status), dbg_msg, e);
		else logDiagnostic("Error while writing the response: %s", e.msg);
		logDebug("Exception while handling request %s %s: %s", req.method, req.requestURL, e.toString().sanitize());
		if (!parsed || (res && res.headerWritten) || !cast(Exception)e) keep_alive = false;
	}

	foreach (k, v ; req.files) {
		if (existsFile(v.tempPath)) {
			removeFile(v.tempPath);
			logDebug("Deleted upload tempfile %s", v.tempPath.toString());
		}
	}
	
	// log the request to access log
	foreach (log; context.loggers)
		log.log(req, res);
	
	logTrace("return %s (used pool memory: %s/%s)", keep_alive, request_allocator.allocatedSize, request_allocator.totalSize);

}

void parseHTTP2RequestHeader(HTTPServerRequest req, HTTP2Stream http2_stream, Allocator alloc/*, max_header_size*/) // header sizes restricted through HTTP/2 settings
{
	logTrace("----------------------");
	logTrace("HTTP/2 server request:");
	logTrace("----------------------");
	// the entire url should be parsed here to simplify processing of pseudo-headers in HTTP/2
	URL url;
	http2_stream.readHeader(url, req.method, req.headers, alloc);
	req.httpVersion = HTTPVersion.HTTP_2;
	req.requestURL = url.pathString;
	req.path = urlDecode(url.pathString);
	req.queryString = url.queryString;
	req.username = url.username;
	req.password = url.password;

	logTrace("%s", url.toString());

	foreach (k, v; req.headers)
		logTrace("%s: %s", k, v);
	logTrace("----------------------");
}

void parseRequestHeader(HTTPServerRequest req, InputStream http_stream, Allocator alloc, ulong max_header_size)
{
	auto stream = FreeListRef!LimitedHTTPInputStream(http_stream, max_header_size);

	logTrace("HTTP server reading status line");
	auto reqln = cast(string)stream.readLine(MaxHTTPHeaderLineLength, "\r\n", alloc);

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

	req.requestURL = reqln[0 .. pos];
	reqln = reqln[pos+1 .. $];

	req.httpVersion = parseHTTPVersion(reqln);

	//headers
	parseRFC5322Header(stream, req.headers, MaxHTTPHeaderLineLength, alloc, false);

	foreach (k, v; req.headers)
		logTrace("%s: %s", k, v);
	logTrace("--------------------");
}

void parseCookies(string str, ref CookieValueMap cookies)
{
	while(str.length > 0) {
		auto idx = str.indexOf('=');
		enforceBadRequest(idx > 0, "Expected name=value.");
		string name = str[0 .. idx].strip();
		str = str[idx+1 .. $];

		for (idx = 0; idx < str.length && str[idx] != ';'; idx++) {}
		string value = str[0 .. idx].strip();
		cookies[name] = urlDecode(value);
		str = idx < str.length ? str[idx+1 .. $] : null;
	}
}

version (VibeNoDefaultArgs) {}
else {
	shared static this()
	{
		string disthost = s_distHost;
		ushort distport = s_distPort;
		import vibe.core.args : readOption;
		readOption("disthost|d", &disthost, "Sets the name of a vibedist server to use for load balancing.");
		readOption("distport", &distport, "Sets the port used for load balancing.");
		setVibeDistHost(disthost, distport);
	}
}

private string formatRFC822DateAlloc(Allocator alloc, SysTime time)
{
	auto app = AllocAppender!string(alloc);
	writeRFC822DateTimeString(app, time);
	return app.data;
}

version (VibeDebugCatchAll) private alias UncaughtException = Throwable;
else private alias UncaughtException = Exception;
