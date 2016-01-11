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
import vibe.stream.tls;
import vibe.stream.wrapper : ConnectionProxyStream;
import vibe.stream.zlib;
import vibe.textfilter.urlencode;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string;

import core.atomic;
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

	Returns:
		A handle is returned that can be used to stop listening for further HTTP
		requests with the supplied settings. Another call to `listenHTTP` can be
		used afterwards to start listening again.
*/
HTTPListener listenHTTP(HTTPServerSettings settings, HTTPServerRequestDelegate request_handler)
{
	enforce(settings.bindAddresses.length, "Must provide at least one bind address for a HTTP server.");

	HTTPServerContext ctx;
	ctx.id = atomicOp!"+="(g_contextIDCounter, 1);
	ctx.settings = settings;
	ctx.requestHandler = request_handler;

	if (settings.accessLogToConsole)
		ctx.loggers ~= new HTTPConsoleLogger(settings, settings.accessLogFormat);
	if (settings.accessLogFile.length)
		ctx.loggers ~= new HTTPFileLogger(settings, settings.accessLogFormat, settings.accessLogFile);

	synchronized (g_listenersMutex)
		addContext(ctx);

	// if a VibeDist host was specified on the command line, register there instead of listening
	// directly.
	if (s_distHost.length && !settings.disableDistHost) {
		listenHTTPDist(settings, request_handler, s_distHost, s_distPort);
	} else {
		listenHTTPPlain(settings);
	}

	return HTTPListener(ctx.id);
}
/// ditto
HTTPListener listenHTTP(HTTPServerSettings settings, HTTPServerRequestFunction request_handler)
{
	return listenHTTP(settings, toDelegate(request_handler));
}
/// ditto
HTTPListener listenHTTP(HTTPServerSettings settings, HTTPServerRequestHandler request_handler)
{
	return listenHTTP(settings, &request_handler.handleRequest);
}
/// ditto
HTTPListener listenHTTP(HTTPServerSettings settings, HTTPServerRequestDelegateS request_handler)
{
	return listenHTTP(settings, cast(HTTPServerRequestDelegate)request_handler);
}
/// ditto
HTTPListener listenHTTP(HTTPServerSettings settings, HTTPServerRequestFunctionS request_handler)
{
	return listenHTTP(settings, toDelegate(request_handler));
}
/// ditto
HTTPListener listenHTTP(HTTPServerSettings settings, HTTPServerRequestHandlerS request_handler)
{
	return listenHTTP(settings, &request_handler.handleRequest);
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
	Renders the given Diet template and makes all ALIASES available to the template.

	You can call this function as a pseudo-member of `HTTPServerResponse` using
	D's uniform function call syntax.

	See_also: `vibe.templ.diet.compileDietFile`

	Examples:
		---
		string title = "Hello, World!";
		int pageNumber = 1;
		res.render!("mytemplate.dt", title, pageNumber);
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
	auto tls = url.schema == "https";
	auto ret = new HTTPServerRequest(Clock.currTime(UTC()), url.port ? url.port : tls ? 443 : 80);
	ret.path = url.pathString;
	ret.queryString = url.queryString;
	ret.username = url.username;
	ret.password = url.password;
	ret.requestURL = url.localURI;
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
{
	import vibe.stream.wrapper;

	HTTPServerSettings settings;
	if (session_store) {
		settings = new HTTPServerSettings;
		settings.sessionStore = session_store;
	}
	if (!data_sink) data_sink = new NullOutputStream;
	auto stream = new ProxyStream(null, data_sink);
	auto ret = new HTTPServerResponse(stream, null, settings, defaultAllocator());
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

		The default value is 80. If you are running a TLS enabled server you may want to set this
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

	/// If set, a HTTPS server will be started instead of plain HTTP.
	TLSContext tlsContext;

	/// Compatibility alias - use `tlsContext` instead.
	alias sslContext = tlsContext;

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
		SysTime m_timeCreated;
		HTTPServerSettings m_settings;
		ushort m_port;
	}

	public {
		/// The IP address of the client
		string peer;
		/// ditto
		NetworkAddress clientAddress;

		/// Determines if the request should be logged to the access log file.
		bool noLog;

		/// Determines if the request was issued over an TLS encrypted channel.
		bool tls;

		/// Compatibility alias - use `tls` instead.
		alias ssl = tls;

		/** Information about the TLS certificate provided by the client.

			Remarks: This field is only set if `tls` is true, and the peer
			presented a client certificate.
		*/
		TLSCertificateInformation clientCertificate;

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
		import vibe.utils.dictionarylist;
		DictionaryList!(string, true, 8) params;

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

			Remarks:
				This field is only set if HTTPServerOption.parseJsonBody is set.

				A JSON request must have the Content-Type "application/json" or "application/vnd.api+json".
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

	this(SysTime time, ushort port)
	{
		m_timeCreated = time.toUTC();
		m_port = port;
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

	/** The relative path to the root folder.

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
		Stream m_conn;
		ConnectionStream m_rawConnection;
		OutputStream m_bodyWriter;
		Allocator m_requestAlloc;
		FreeListRef!ChunkedOutputStream m_chunkedBodyWriter;
		FreeListRef!CountingOutputStream m_countingWriter;
		FreeListRef!GzipOutputStream m_gzipOutputStream;
		FreeListRef!DeflateOutputStream m_deflateOutputStream;
		HTTPServerSettings m_settings;
		Session m_session;
		bool m_headerWritten = false;
		bool m_isHeadResponse = false;
		bool m_tls;
		SysTime m_timeFinalized;
	}

	this(Stream conn, ConnectionStream raw_connection, HTTPServerSettings settings, Allocator req_alloc)
	{
		m_conn = conn;
		m_rawConnection = raw_connection;
		m_countingWriter = FreeListRef!CountingOutputStream(conn);
		m_settings = settings;
		m_requestAlloc = req_alloc;
	}

	/** Returns the time at which the request was finalized.

		Note that this field will only be set after `finalize` has been called.
	*/
	@property SysTime timeFinalized() { return m_timeFinalized; }

	/** Determines if the HTTP header has already been written.
	*/
	@property bool headerWritten() const { return m_headerWritten; }

	/** Determines if the response does not need a body.
	*/
	bool isHeadResponse() const { return m_isHeadResponse; }

	/** Determines if the response is sent over an encrypted connection.
	*/
	bool tls() const { return m_tls; }

	/// Compatibility alias - use `tls` instead.
	alias ssl = tls;

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
	/// ditto
	void writeBody(scope InputStream data, string content_type = null)
	{
		if (content_type != "") headers["Content-Type"] = content_type;
		bodyWriter.write(data);
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
		assert(!m_headerWritten, "A body was already written!");
		writeHeader();
		if (m_isHeadResponse) return;

		auto bytes = stream.size - stream.tell();
		m_conn.write(stream);
		m_countingWriter.increment(bytes);
	}
	/// ditto
	void writeRawBody(InputStream stream, size_t num_bytes = 0)
	{
		assert(!m_headerWritten, "A body was already written!");
		writeHeader();
		if (m_isHeadResponse) return;

		if (num_bytes > 0) {
			m_conn.write(stream, num_bytes);
			m_countingWriter.increment(num_bytes);
		} else  m_countingWriter.write(stream, num_bytes);
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
		m_conn.flush();
	}

	/** A stream for writing the body of the HTTP response.

		Note that after 'bodyWriter' has been accessed for the first time, it
		is not allowed to change any header or the status code of the response.
	*/
	@property OutputStream bodyWriter()
	{
		assert(m_conn !is null);
		if (m_bodyWriter) return m_bodyWriter;

		assert(!m_headerWritten, "A void body was already written!");

		if (m_isHeadResponse) {
			// for HEAD requests, we define a NullOutputWriter for convenience
			// - no body will be written. However, the request handler should call writeVoidBody()
			// and skip writing of the body in this case.
			if ("Content-Length" !in headers)
				headers["Transfer-Encoding"] = "chunked";
			writeHeader();
			m_bodyWriter = new NullOutputStream;
			return m_bodyWriter;
		}

		if ("Content-Encoding" in headers && "Content-Length" in headers) {
			// we do not known how large the compressed body will be in advance
			// so remove the content-length and use chunked transfer
			headers.remove("Content-Length");
		}

		if ("Content-Length" in headers) {
			writeHeader();
			m_bodyWriter = m_countingWriter; // TODO: LimitedOutputStream(m_conn, content_length)
		} else {
			headers["Transfer-Encoding"] = "chunked";
			writeHeader();
			m_chunkedBodyWriter = FreeListRef!ChunkedOutputStream(m_countingWriter);
			m_bodyWriter = m_chunkedBodyWriter;
		}

		if (auto pce = "Content-Encoding" in headers) {
			if (icmp2(*pce, "gzip") == 0) {
				m_gzipOutputStream = FreeListRef!GzipOutputStream(m_bodyWriter);
				m_bodyWriter = m_gzipOutputStream;
			} else if (icmp2(*pce, "deflate") == 0) {
				m_deflateOutputStream = FreeListRef!DeflateOutputStream(m_bodyWriter);
				m_bodyWriter = m_deflateOutputStream;
			} else {
				logWarn("Unsupported Content-Encoding set in response: '"~*pce~"'");
			}
		}

		return m_bodyWriter;
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

		Notice: For the overload that returns a `ConnectionStream`, it must be
			ensured that the returned instance doesn't outlive the request
			handler callback.

		Params:
			protocol = The protocol set in the "Upgrade" header of the response.
				Use an empty string to skip setting this field.
	*/
	ConnectionStream switchProtocol(string protocol)
	{
		statusCode = HTTPStatus.SwitchingProtocols;
		if (protocol.length) headers["Upgrade"] = protocol;
		writeVoidBody();
		return new ConnectionProxyStream(m_conn, m_rawConnection);
	}
	/// ditto
	void switchProtocol(string protocol, scope void delegate(scope ConnectionStream) del)
	{
		statusCode = HTTPStatus.SwitchingProtocols;
		if (protocol.length) headers["Upgrade"] = protocol;
		writeVoidBody();
		scope conn = new ConnectionProxyStream(m_conn, m_rawConnection);
		del(conn);
		finalize();
		m_rawConnection.close(); // connection not reusable after a protocol upgrade
	}

	/** Sets the specified cookie value.

		Params:
			name = Name of the cookie
			value = New cookie value - pass null to clear the cookie
			path = Path (as seen by the client) of the directory tree in which the cookie is visible
	*/
	Cookie setCookie(string name, string value, string path = "/", Cookie.Encoding encoding = Cookie.Encoding.url)
	{
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
		if (!m_session) return;
		auto cookie = setCookie(m_settings.sessionIdCookie, null, m_session.get!string("$sessionCookiePath"));
		cookie.secure = m_session.get!bool("$sessionCookieSecure");
		m_session.destroy();
		m_session = Session.init;
	}

	@property ulong bytesWritten() { return m_countingWriter.bytesWritten; }

	/**
		Deprecated - use `render` instead.

		This version of render() works around an old compiler bug in DMD < 2.064 (Issue 2962).

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
	deprecated("Use the non-compatibility render() call instead.")
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
		if (!m_rawConnection || !m_rawConnection.connected) return true;
		m_rawConnection.waitForData(timeout);
		return !m_rawConnection.connected;
	}

	/**
		Finalizes the response. This is usually called automatically by the server.

		This method can be called manually after writing the response to force
		all network traffic associated with the current request to be finalized.
		After the call returns, the `timeFinalized` property will be set.
	*/
	void finalize()
	{
		if (m_gzipOutputStream) {
			m_gzipOutputStream.finalize();
			m_gzipOutputStream.destroy();
		}
		if (m_deflateOutputStream) {
			m_deflateOutputStream.finalize();
			m_deflateOutputStream.destroy();
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
				m_rawConnection.close();
			}
			m_rawConnection = null;
		}

		if (m_conn) {
			m_conn = null;
			m_timeFinalized = Clock.currTime(UTC());
		}
	}

	private void writeHeader()
	{
		import vibe.stream.wrapper;

		assert(!m_bodyWriter && !m_headerWritten, "Try to write header after body has already begun.");
		m_headerWritten = true;
		auto dst = StreamOutputRange(m_conn);

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
			cookie.writeString(&dst, n);
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
		size_t m_contextID;
	}

	private this(size_t id) { m_contextID = id; }

	/** Stops handling HTTP requests and closes the TCP listening port if
		possible.
	*/
	void stopListening()
	{
		import std.algorithm : countUntil;

		synchronized (g_listenersMutex) {
			auto contexts = getContexts();

			auto idx = contexts.countUntil!(c => c.id == m_contextID);
			if (idx < 0) return;

			// remove context entry
			auto ctx = getContexts()[idx];
			removeContext(idx);

			// stop listening on all unused TCP ports
			auto port = ctx.settings.port;
			foreach (addr; ctx.settings.bindAddresses) {
				// any other context still occupying the same addr/port?
				if (getContexts().canFind!(c => c.settings.port == port && c.settings.bindAddresses.canFind(addr)))
					continue;

				auto lidx = g_listeners.countUntil!(l => l.bindAddress == addr && l.bindPort == port);
				if (lidx >= 0) {
					g_listeners[lidx].listener.stopListening();
					logInfo("Stopped to listen for HTTP%s requests on %s:%s", ctx.settings.tlsContext ? "S": "", addr, port);
					g_listeners = g_listeners[0 .. lidx] ~ g_listeners[lidx+1 .. $];
				}
			}
		}
	}
}


/**************************************************************************************************/
/* Private types                                                                                  */
/**************************************************************************************************/

private struct HTTPServerContext {
	HTTPServerRequestDelegate requestHandler;
	HTTPServerSettings settings;
	HTTPLogger[] loggers;
	size_t id;
}

private final class HTTPListenInfo {
	TCPListener listener;
	string bindAddress;
	ushort bindPort;
	TLSContext tlsContext;

	this(string bind_address, ushort bind_port, TLSContext tls_context)
	{
		this.bindAddress = bind_address;
		this.bindPort = bind_port;
		this.tlsContext = tls_context;
	}
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

/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

private {
	import core.sync.mutex;

	shared string s_distHost;
	shared ushort s_distPort = 11000;
	shared size_t g_contextIDCounter = 1;

	// protects g_listeners and *write* accesses to g_contexts
	__gshared Mutex g_listenersMutex;
	__gshared HTTPListenInfo[] g_listeners;

	// accessed for every request, needs to be kept thread-safe by only atomically assigning new
	// arrays (COW). shared immutable(HTTPServerContext)[] would be the right candidate here, but
	// is impractical due to type system limitations.
	align(16) shared HTTPServerContext[] g_contexts;

	HTTPServerContext[] getContexts()
	{
		static if (__VERSION__ >= 2067) {
			version (Win64) return cast(HTTPServerContext[])g_contexts;
			else return cast(HTTPServerContext[])atomicLoad(g_contexts);
		}
		else
			return cast(HTTPServerContext[])g_contexts;
	}

	void addContext(HTTPServerContext ctx)
	{
		synchronized (g_listenersMutex) {
			static if (__VERSION__ >= 2067)
				atomicStore(g_contexts, g_contexts ~ cast(shared)ctx);
			else
				g_contexts = g_contexts ~ cast(shared)ctx;
		}
	}

	void removeContext(size_t idx)
	{
		// write a new complete array reference to avoid race conditions during removal
		auto contexts = g_contexts;
		auto newarr = contexts[0 .. idx] ~ contexts[idx+1 .. $];
		static if (__VERSION__ >= 2067)
			atomicStore(g_contexts, newarr);
		else
			g_contexts = newarr;
	}
}

/**
	[private] Starts a HTTP server listening on the specified port.

	This is the same as listenHTTP() except that it does not use a VibeDist host for
	remote listening, even if specified on the command line.
*/
private void listenHTTPPlain(HTTPServerSettings settings)
{
	import std.algorithm : canFind;

	static TCPListener doListen(HTTPListenInfo listen_info, bool dist)
	{
		try {
			auto ret = listenTCP(listen_info.bindPort, (TCPConnection conn) {
					handleHTTPConnection(conn, listen_info);
				}, listen_info.bindAddress, dist ? TCPListenOptions.distribute : TCPListenOptions.defaults);
			auto proto = listen_info.tlsContext ? "https" : "http";
			auto urladdr = listen_info.bindAddress;
			if (urladdr.canFind(':')) urladdr = "["~urladdr~"]";
			logInfo("Listening for requests on %s://%s:%s/", proto, urladdr, listen_info.bindPort);
			return ret;
		} catch( Exception e ) {
			logWarn("Failed to listen on %s:%s", listen_info.bindAddress, listen_info.bindPort);
			return null;
		}
	}

	void addVHost(ref HTTPListenInfo lst)
	{
		TLSContext onSNI(string servername)
		{
			foreach (ctx; getContexts())
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
			logDebug("Create SNI TLS context for %s, port %s", lst.bindAddress, lst.bindPort);
			lst.tlsContext = createTLSContext(TLSContextKind.serverSNI);
			lst.tlsContext.sniCallback = &onSNI;
		}

		foreach (ctx; getContexts()) {
			if (ctx.settings.port != settings.port) continue;
			if (!ctx.settings.bindAddresses.canFind(lst.bindAddress)) continue;
			/*enforce(ctx.settings.hostName != settings.hostName,
				"A server with the host name '"~settings.hostName~"' is already "
				"listening on "~addr~":"~to!string(settings.port)~".");*/
		}
	}

	bool any_successful = false;

	synchronized (g_listenersMutex) {
		// Check for every bind address/port, if a new listening socket needs to be created and
		// check for conflicting servers
		foreach (addr; settings.bindAddresses) {
			bool found_listener = false;
			foreach (i, ref lst; g_listeners) {
				if (lst.bindAddress == addr && lst.bindPort == settings.port) {
					addVHost(lst);
					assert(!settings.tlsContext || settings.tlsContext is lst.tlsContext
						|| lst.tlsContext.kind == TLSContextKind.serverSNI,
						format("Got multiple overlapping TLS bind addresses (port %s), but no SNI TLS context!?", settings.port));
					found_listener = true;
					any_successful = true;
					break;
				}
			}
			if (!found_listener) {
				auto linfo = new HTTPListenInfo(addr, settings.port, settings.tlsContext);
				if (auto tcp_lst = doListen(linfo, (settings.options & HTTPServerOption.distribute) != 0)) // DMD BUG 2043
				{
					linfo.listener = tcp_lst;
					found_listener = true;
					any_successful = true;
					g_listeners ~= linfo;
				}
			}
			if (settings.hostName.length) {
				auto proto = settings.tlsContext ? "https" : "http";
				auto port = settings.tlsContext && settings.port == 443 || !settings.tlsContext && settings.port == 80 ? "" : ":" ~ settings.port.to!string;
				logInfo("Added virtual host %s://%s%s/ (%s)", proto, settings.hostName, port, addr);
			}
		}
	}

	enforce(any_successful, "Failed to listen for incoming HTTP connections on any of the supplied interfaces.");
}


private void handleHTTPConnection(TCPConnection connection, HTTPListenInfo listen_info)
{
	Stream http_stream = connection;

	// Set NODELAY to true, to avoid delays caused by sending the response
	// header and body in separate chunks. Note that to avoid other performance
	// issues (caused by tiny packets), this requires using an output buffer in
	// the event driver, which is the case at least for the default libevent
	// based driver.
	connection.tcpNoDelay = true;

	version(VibeNoSSL) {} else {
		import std.traits : ReturnType;
		ReturnType!createTLSStreamFL tls_stream;
	}

	if (!connection.waitForData(10.seconds())) {
		logDebug("Client didn't send the initial request in a timely manner. Closing connection.");
		return;
	}

	// If this is a HTTPS server, initiate TLS
	if (listen_info.tlsContext) {
		version (VibeNoSSL) assert(false, "No TLS support compiled in (VibeNoSSL)");
		else {
			logDebug("Accept TLS connection: %s", listen_info.tlsContext.kind);
			// TODO: reverse DNS lookup for peer_name of the incoming connection for TLS client certificate verification purposes
			tls_stream = createTLSStreamFL(http_stream, listen_info.tlsContext, TLSStreamState.accepting, null, connection.remoteAddress);
			http_stream = tls_stream;
		}
	}

	while (!connection.empty) {
		HTTPServerSettings settings;
		bool keep_alive;
		handleRequest(http_stream, connection, listen_info, settings, keep_alive);
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

private bool handleRequest(Stream http_stream, TCPConnection tcp_connection, HTTPListenInfo listen_info, ref HTTPServerSettings settings, ref bool keep_alive)
{
	import std.algorithm : canFind;

	SysTime reqtime = Clock.currTime(UTC());

	//auto request_allocator = scoped!(PoolAllocator)(1024, defaultAllocator());
	scope request_allocator = new PoolAllocator(1024, threadLocalAllocator());
	scope(exit) request_allocator.reset();

	// some instances that live only while the request is running
	FreeListRef!HTTPServerRequest req = FreeListRef!HTTPServerRequest(reqtime, listen_info.bindPort);
	FreeListRef!TimeoutHTTPInputStream timeout_http_input_stream;
	FreeListRef!LimitedHTTPInputStream limited_http_input_stream;
	FreeListRef!ChunkedInputStream chunked_input_stream;

	// store the IP address (IPv4 addresses forwarded over IPv6 are stored in IPv4 format)
	auto peer_address_string = tcp_connection.peerAddress;
	if (peer_address_string.startsWith("::ffff:") && peer_address_string[7 .. $].indexOf(":") < 0)
		req.peer = peer_address_string[7 .. $];
	else req.peer = peer_address_string;
	req.clientAddress = tcp_connection.remoteAddress;

	// Default to the first virtual host for this listener
	HTTPServerRequestDelegate request_task;
	HTTPServerContext context;
	foreach (ctx; getContexts())
		if (ctx.settings.port == listen_info.bindPort) {
			bool found = false;
			foreach (addr; ctx.settings.bindAddresses)
				if (addr == listen_info.bindAddress)
					found = true;
			if (!found) continue;
			context = ctx;
			settings = ctx.settings;
			request_task = ctx.requestHandler;
			break;
		}

	if (!settings) {
		logWarn("Didn't find a HTTP listening context for incoming connection. Dropping.");
		keep_alive = false;
		return false;
	}

	// Create the response object
	auto res = FreeListRef!HTTPServerResponse(http_stream, tcp_connection, settings, request_allocator/*.Scoped_payload*/);
	req.tls = res.m_tls = listen_info.tlsContext !is null;
	if (req.tls) req.clientCertificate = (cast(TLSStream)http_stream).peerCertificate;

	// Error page handler
	void errorOut(int code, string msg, string debug_msg, Throwable ex){
		assert(!res.headerWritten);

		// stack traces sometimes contain random bytes - make sure they are replaced
		debug_msg = sanitizeUTF8(cast(ubyte[])debug_msg);

		res.statusCode = code;
		if (settings && settings.errorPageHandler) {
			scope err = new HTTPServerErrorInfo;
			err.code = code;
			err.message = msg;
			err.debugMessage = debug_msg;
			err.exception = ex;
			settings.errorPageHandler(req, res, err);
		} else {
			res.writeBody(format("%s - %s\n\n%s\n\nInternal error information:\n%s", code, httpStatusText(code), msg, debug_msg));
		}
		assert(res.headerWritten);
	}

	bool parsed = false;
	/*bool*/ keep_alive = false;

	// parse the request
	try {
		logTrace("reading request..");

		// limit the total request time
		InputStream reqReader;
		if (settings.maxRequestTime == dur!"seconds"(0)) reqReader = http_stream;
		else {
			timeout_http_input_stream = FreeListRef!TimeoutHTTPInputStream(http_stream, settings.maxRequestTime, reqtime);
			reqReader = timeout_http_input_stream;
		}

		// basic request parsing
		parseRequestHeader(req, reqReader, request_allocator, settings.maxRequestHeaderSize);
		logTrace("Got request header.");

		// find the matching virtual host
		string reqhost;
		ushort reqport = 0;
		import std.algorithm : splitter;
		auto reqhostparts = req.host.splitter(":");
		if (!reqhostparts.empty) { reqhost = reqhostparts.front; reqhostparts.popFront(); }
		if (!reqhostparts.empty) { reqport = reqhostparts.front.to!ushort; reqhostparts.popFront(); }
		enforce(reqhostparts.empty, "Invalid suffix found in host header");
		foreach (ctx; getContexts())
			if (icmp2(ctx.settings.hostName, reqhost) == 0 &&
				(!reqport || reqport == ctx.settings.port))
			{
				if (ctx.settings.port != listen_info.bindPort) continue;
				bool found = false;
				foreach (addr; ctx.settings.bindAddresses)
					if (addr == listen_info.bindAddress)
						found = true;
				if (!found) continue;
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
			chunked_input_stream = FreeListRef!ChunkedInputStream(reqReader);
			limited_http_input_stream = FreeListRef!LimitedHTTPInputStream(chunked_input_stream, settings.maxRequestSize, true);
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

		// URL parsing if desired
		if (settings.options & HTTPServerOption.parseURL) {
			auto url = URL.parse(req.requestURL);
			req.path = urlDecode(url.pathString);
			req.queryString = url.queryString;
			req.username = url.username;
			req.password = url.password;
		}

		// query string parsing if desired
		if (settings.options & HTTPServerOption.parseQueryString) {
			if (!(settings.options & HTTPServerOption.parseURL))
				logWarn("Query string parsing requested but URL parsing is disabled!");
			parseURLEncodedForm(req.queryString, req.query);
		}

		// cookie parsing if desired
		if (settings.options & HTTPServerOption.parseCookies) {
			auto pv = "cookie" in req.headers;
			if (pv) parseCookies(*pv, req.cookies);
		}

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

		if (settings.options & HTTPServerOption.parseFormBody) {
			auto ptype = "Content-Type" in req.headers;
			if (ptype) parseFormData(req.form, req.files, *ptype, req.bodyReader, MaxHTTPHeaderLineLength);
		}

		if (settings.options & HTTPServerOption.parseJsonBody) {
			if (icmp2(req.contentType, "application/json") == 0 || icmp2(req.contentType, "application/vnd.api+json") == 0 ) {
				auto bodyStr = cast(string)req.bodyReader.readAll();
				if (!bodyStr.empty) req.json = parseJson(bodyStr);
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
			logDiagnostic("No response written for %s", req.requestURL);
			if (settings.options & HTTPServerOption.errorStackTraces)
				dbg_msg = format("No routes match path '%s'", req.requestURL);
			errorOut(HTTPStatus.notFound, httpStatusText(HTTPStatus.notFound), dbg_msg, null);
		}
	} catch (HTTPStatusException err) {
		string dbg_msg;
		if (settings.options & HTTPServerOption.errorStackTraces) {
			if (err.debugMessage != "") dbg_msg = err.debugMessage;
			else dbg_msg = err.toString().sanitize;
		}
		if (!res.headerWritten) errorOut(err.status, err.msg, dbg_msg, err);
		else logDiagnostic("HTTPSterrorOutatusException while writing the response: %s", err.msg);
		logDebug("Exception while handling request %s %s: %s", req.method, req.requestURL, err.toString().sanitize);
		if (!parsed || res.headerWritten || justifiesConnectionClose(err.status))
			keep_alive = false;
	} catch (UncaughtException e) {
		auto status = parsed ? HTTPStatus.internalServerError : HTTPStatus.badRequest;
		string dbg_msg;
		if (settings.options & HTTPServerOption.errorStackTraces) dbg_msg = e.toString().sanitize;
		if (!res.headerWritten && tcp_connection.connected) errorOut(status, httpStatusText(status), dbg_msg, e);
		else logDiagnostic("Error while writing the response: %s", e.msg);
		logDebug("Exception while handling request %s %s: %s", req.method, req.requestURL, e.toString().sanitize());
		if (!parsed || res.headerWritten || !cast(Exception)e) keep_alive = false;
	}

	if (tcp_connection.connected) {
		if (req.bodyReader && !req.bodyReader.empty) {
			auto nullWriter = scoped!NullOutputStream();
			nullWriter.write(req.bodyReader);
			logTrace("dropped body");
		}
	}

	// finalize (e.g. for chunked encoding)
	res.finalize();

	foreach (k, v ; req.files) {
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

	logTrace("return %s (used pool memory: %s/%s)", keep_alive, request_allocator.allocatedSize, request_allocator.totalSize);
	return keep_alive != false;
}


private void parseRequestHeader(HTTPServerRequest req, InputStream http_stream, Allocator alloc, ulong max_header_size)
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

private void parseCookies(string str, ref CookieValueMap cookies)
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

shared static this()
{
	g_listenersMutex = new Mutex;

	version (VibeNoDefaultArgs) {}
	else {
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
