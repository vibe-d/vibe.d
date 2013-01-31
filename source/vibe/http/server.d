/**
	A HTTP 1.1/1.0 server implementation.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.server;

public import vibe.core.net;
public import vibe.http.common;
public import vibe.http.session;

import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.dist;
import vibe.http.form;
import vibe.http.log;
import vibe.inet.message;
import vibe.inet.url;
import vibe.stream.counting;
import vibe.stream.operations;
import vibe.stream.ssl;
import vibe.stream.zlib;
import vibe.textfilter.urlencode;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string;
import vibe.core.file;

import core.vararg;
import std.algorithm : countUntil, map, min;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.functional;
import std.string;
import std.typecons;
import std.uri;
public import std.variant;


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Starts a HTTP server listening on the specified port.

	request_handler will be called for each HTTP request that is made. The
	res parameter of the callback then has to be filled with the response
	data.
	
	request_handler can be either HttpServerRequestDelegate/HttpServerRequestFunction
	or a class/struct with a member function 'handleRequest' that has the same
	signature.

	Note that if the application has been started with the --disthost command line
	switch, listenHttp() will automatically listen on the specified VibeDist host
	instead of locally. This allows for a seamless switch from single-host to 
	multi-host scenarios without changing the code. If you need to listen locally,
	use listenHttpPlain() instead.

	Params:
		settings = Customizes the HTTP servers functionality.
		request_handler = This callback is invoked for each incoming request and is responsible
			for generating the response.
*/
void listenHttp(HttpServerSettings settings, HttpServerRequestDelegate request_handler)
{
	enforce(settings.bindAddresses.length, "Must provide at least one bind address for a HTTP server.");

	HTTPServerContext ctx;
	ctx.settings = settings;
	ctx.requestHandler = request_handler;

	if( settings.accessLogToConsole )
		ctx.loggers ~= new HttpConsoleLogger(settings, settings.accessLogFormat);
	if( settings.accessLogFile.length )
		ctx.loggers ~= new HttpFileLogger(settings, settings.accessLogFormat, settings.accessLogFile);

	g_contexts ~= ctx;

	if( !s_listenersStarted ) return;

	// if a VibeDist host was specified on the command line, register there instead of listening
	// directly.
	if( s_distHost.length ){
		listenHttpDist(settings, request_handler, s_distHost, s_distPort);
	} else {
		listenHttpPlain(settings, request_handler);
	}
}
/// ditto
void listenHttp(HttpServerSettings settings, HttpServerRequestFunction request_handler)
{
	listenHttp(settings, toDelegate(request_handler));
}
/// ditto
void listenHttp(HttpServerSettings settings, IHttpServerRequestHandler request_handler)
{
	listenHttp(settings, &request_handler.handleRequest);
}


/**
	Starts a HTTP server listening on the specified port.

	This is the same as listenHttp() except that it does not use a VibeDist host for
	remote listening, even if specified on the command line.
*/
void listenHttpPlain(HttpServerSettings settings, HttpServerRequestDelegate request_handler)
{
	static void doListen(HttpServerSettings settings, HTTPServerListener listener, string addr)
	{
		try {
			listenTcp(settings.port, (TcpConnection conn){ handleHttpConnection(conn, listener); }, addr);
			logInfo("Listening for HTTP%s requests on %s:%s", settings.sslKeyFile.length || settings.sslCertFile.length ? "S" : "", addr, settings.port);
		} catch( Exception e ) logWarn("Failed to listen on %s:%s", addr, settings.port);
	}

	// Check for every bind address/port, if a new listening socket needs to be created and
	// check for conflicting servers
	foreach( addr; settings.bindAddresses ){
		bool found_listener = false;
		foreach( lst; g_listeners ){
			if( lst.bindAddress == addr && lst.bindPort == settings.port ){
				enforce(settings.sslKeyFile == lst.sslKeyFile
					&& settings.sslCertFile == lst.sslCertFile,
					"A HTTP server is already listening on "~addr~":"~to!string(settings.port)~
					" but the SSL mode differs.");
				foreach( ctx; g_contexts ){
					if( ctx.settings.port != settings.port ) continue;
					if( countUntil(ctx.settings.bindAddresses, addr) < 0 ) continue;
					/*enforce(ctx.settings.hostName != settings.hostName,
						"A server with the host name '"~settings.hostName~"' is already "
						"listening on "~addr~":"~to!string(settings.port)~".");*/
				}
				found_listener = true;
				break;
			}
		}
		if( !found_listener ){
			auto listener = HTTPServerListener(addr, settings.port, settings.sslCertFile, settings.sslKeyFile);
			g_listeners ~= listener;
			doListen(settings, listener, addr); // DMD BUG 2043
		}
	}
}


/**
	Provides a HTTP request handler that responds with a static Diet template.
*/
@property HttpServerRequestDelegate staticTemplate(string template_file)()
{
	import vibe.templ.diet;
	return (HttpServerRequest req, HttpServerResponse res){
		//res.render!(template_file, req);
		//res.headers["Content-Type"] = "text/html; charset=UTF-8";
		//parseDietFile!(template_file, req)(res.bodyWriter);
		res.renderCompat!(template_file, HttpServerRequest, "req")(Variant(req));
	};
}

/**
	Provides a HTTP request handler that responds with a static redirection to the specified URL.
*/
HttpServerRequestDelegate staticRedirect(string url)
{
	return (HttpServerRequest req, HttpServerResponse res){
		res.redirect(url);
	};
}

/**
	Sets a VibeDist host to register with.
*/
void setVibeDistHost(string host, ushort port)
{
	s_distHost = host;
	s_distPort = port;
}

void startListening()
{
	assert(!s_listenersStarted);
	s_listenersStarted = true;
	foreach( ctx; g_contexts ){
		// if a VibeDist host was specified on the command line, register there instead of listening
		// directly.
		if( s_distHost.length ){
			listenHttpDist(ctx.settings, ctx.requestHandler, s_distHost, s_distPort);
		} else {
			listenHttpPlain(ctx.settings, ctx.requestHandler);
		}
	}
}

/**
	Renders the given template and makes all ALIASES available to the template.

	This currently suffers from multiple DMD bugs - use renderCompat() instead for the time being.

	You can call this function as a member of HttpServerResponse using D's uniform function
	call syntax.

	Examples:
		---
		string title = "Hello, World!";
		int pageNumber = 1;
		res.render!("mytemplate.jd", title, pageNumber);
		---
*/
@property void render(string template_file, ALIASES...)(HttpServerResponse res)
{
	import vibe.templ.diet;
	res.headers["Content-Type"] = "text/html; charset=UTF-8";
	parseDietFile!(template_file, ALIASES)(res.bodyWriter);
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/// Delegate based request handler
alias void delegate(HttpServerRequest req, HttpServerResponse res) HttpServerRequestDelegate;
/// Static function based request handler
alias void function(HttpServerRequest req, HttpServerResponse res) HttpServerRequestFunction;
/// Interface for class based request handlers
interface IHttpServerRequestHandler {
	/// Handles incoming HTTP requests
	void handleRequest(HttpServerRequest req, HttpServerResponse res);
}

/// Aggregates all information about an HTTP error status.
class HttpServerErrorInfo {
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
alias void delegate(HttpServerRequest req, HttpServerResponse res, HttpServerErrorInfo error) HttpServerErrorPageHandler;

/**
	Specifies optional features of the HTTP server.

	Disabling unneeded features can speed up the server or reduce its memory usage.
*/
enum HttpServerOption {
	None                      = 0,
	/// Fills the .path, .queryString fields in the request
	ParseURL                  = 1<<0,
	/// Fills the .query field in the request
	ParseQueryString          = 1<<1 | ParseURL,
	/// Fills the .form field in the request
	ParseFormBody             = 1<<2,
	/// Fills the .json field in the request
	ParseJsonBody             = 1<<3,
	/// Enables use of the .nextPart() method in the request
	ParseMultiPartBody        = 1<<4, // todo
	/// Fills the .cookies field in the request
	ParseCookies              = 1<<5,
}


/**
	Contains all settings for configuring a basic HTTP server.

	The defaults are sufficient for most normal uses.
*/
class HttpServerSettings {
	/** The port on which the HTTP server is listening.

		The default value is 80. If you are running a SSL enabled server you may want to set this
		to 443 instead.
	*/
	ushort port = 80;

	/** The interfaces on which the HTTP server is listening.
		
		By default, the server will listen on all IPv4 and IPv6 interfaces.
	*/
	string[] bindAddresses = ["0.0.0.0", "::"];

	/** Determines the server host name.

		If multiple servers are listening on the same port, the host name will determine which one
		gets a request.
	*/
	string hostName;
	
	/** Configures optional features of the HTTP server
	
		Disabling unneeded features can improve performance or reduce the server
		load in case of invalid or unwanted requests (DoS).
	*/
	HttpServerOption options =
		HttpServerOption.ParseURL |
		HttpServerOption.ParseQueryString |
		HttpServerOption.ParseFormBody |
		HttpServerOption.ParseJsonBody |
		HttpServerOption.ParseMultiPartBody |
		HttpServerOption.ParseCookies;
	
	/// Time of a request after which the connection is closed with an error; not supported yet
	Duration maxRequestTime = dur!"seconds"(0);

	/// Maximum time between two request on a keep-alive connection
	Duration keepAliveTimeout = dur!"seconds"(10);
	
	/// Maximum number of transferred bytes per request after which the connection is closed with
	/// an error; not supported yet
	ulong maxRequestSize = 2097152;


	///	Maximum number of transferred bytes for the request header. This includes the request line 
	/// the url and all headers. 
	ulong maxRequestHeaderSize = 8192;

	/// Sets a custom handler for displaying error pages for HTTP errors
	HttpServerErrorPageHandler errorPageHandler = null;

	/// If set, a HTTPS server will be started instead of plain HTTP
	string sslCertFile;
	/// ditto
	string sslKeyFile;

	/// Session management is enabled if a session store instance is provided
	SessionStore sessionStore;
	string sessionIdCookie = "vibe.session_id";

	///
	string serverString = "vibe.d/" ~ VibeVersionString;

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
	@property HttpServerSettings dup()
	{
		auto ret = new HttpServerSettings;
		foreach( mem; __traits(allMembers, HttpServerSettings) ){
			static if( mem == "bindAddresses" ) ret.bindAddresses = bindAddresses.dup;
			else static if( __traits(compiles, __traits(getMember, ret, mem) = __traits(getMember, this, mem)) )
				__traits(getMember, ret, mem) = __traits(getMember, this, mem);
		}
		return ret;
	}
}


/**
	Represents a HTTP request as received by the server side.
*/
final class HttpServerRequest : HttpRequest {
	public {
		/// The IP address of the client
		string peer;

		/// Determines if the request was issued over an SSL encrypted channel.
		bool ssl;

		/** The _path part of the URL.

			Remarks: This field is only set if HttpServerOption.ParseURL is set.
		*/
		string path;

		/** The user name part of the URL, if present.

			Remarks: This field is only set if HttpServerOption.ParseURL is set.
		*/
		string username;

		/** The _password part of the URL, if present.

			Remarks: This field is only set if HttpServerOption.ParseURL is set.
		*/
		string password;

		/** The _query string part of the URL.

			Remarks: This field is only set if HttpServerOption.ParseURL is set.
		*/
		string queryString;

		/** Contains the list of _cookies that are stored on the client.

			Remarks: This field is only set if HttpServerOption.ParseCookies is set.
		*/
		string[string] cookies;
		
		/** Contains all _form fields supplied using the _query string.

			Remarks: This field is only set if HttpServerOption.ParseQueryString is set.
		*/
		string[string] query;

		/** A map of general parameters for the request.

			This map is supposed to be used by middleware functionality to store
			information for later stages. For example vibe.http.router.UrlRouter uses this map
			to store the value of any named placeholders.
		*/
		string[string] params;

		/** Supplies the request body as a stream.

			If the body has not already been read because one of the body parsers has
			processed it (e.g. HttpServerOption.ParseFormBody), it can be read from
			this stream.
		*/
		InputStream bodyReader;

		/** Contains the parsed Json for a JSON request.

			Remarks:
				This field is only set if HttpServerOption.ParseJsonBody is set.

				A JSON request must have the Content-Type "application/json".
		*/
		Json json;

		/** Contains the parsed parameters of a HTML POST _form request.

			Remarks:
				This field is only set if HttpServerOption.ParseFormBody is set.

				A form request must either have the Content-Type
				"application/x-www-form-urlencoded" or "multipart/form-data".
		*/
		string[string] form;

		/** Contains information about any uploaded file for a HTML _form request.

			Remarks:
				This field is only set if HttpServerOption.ParseFormBody is set amd
				if the Content-Type is "multipart/form-data".
		*/
		FilePart[string] files;

		/** The current Session object.

			This field is set if HttpServerResponse.startSession() has been called
			on a previous response and if the client has sent back the matching
			cookie.

			Remarks: Requires the HttpServerOption.ParseCookies option.
		*/
		Session session;
	}
	private {
		SysTime m_timeCreated;
	}

	this()
	{
		m_timeCreated = Clock.currTime().toUTC();
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
	@property Url fullUrl()
	const {
		Url url;
		url.schema = this.ssl ? "https" : "http";
		auto pfh = "X-Forwarded-Host" in this.headers;
		url.host = pfh ? *pfh : this.host;
		// TODO: also include the port
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
		if( path.length == 0 ) return "./";
		auto depth = count(path[1 .. $], '/');
		return depth == 0 ? "./" : replicate("../", depth);
	}
}


/**
	Represents a HTTP response as sent from the server side.
*/
final class HttpServerResponse : HttpResponse {
	private {
		Stream m_conn;
		OutputStream m_bodyWriter;
		Allocator m_requestAlloc;
		FreeListRef!ChunkedOutputStream m_chunkedBodyWriter;
		FreeListRef!CountingOutputStream m_countingWriter;
		FreeListRef!GzipOutputStream m_gzipOutputStream;
		FreeListRef!DeflateOutputStream m_deflateOutputStream;
		HttpServerSettings m_settings;
		Session m_session;
		bool m_headerWritten = false;
		bool m_isHeadResponse = false;
		SysTime m_timeFinalized;
	}

	this(Stream conn, HttpServerSettings settings, Allocator req_alloc)
	{
		m_conn = conn;
		m_countingWriter = FreeListRef!CountingOutputStream(conn);
		m_settings = settings;
		m_requestAlloc = req_alloc;
	}
	
	@property SysTime timeFinalized() { return m_timeFinalized; }

	/** Determines if the HTTP header has already been written.
	*/
	@property bool headerWritten() const { return m_headerWritten; }

	/** Determines if the response does not need a body.
	*/
	bool isHeadResponse() const { return m_isHeadResponse; }

	/// Writes the entire response body at once.
	void writeBody(in ubyte[] data, string content_type = null)
	{
		if( content_type ) headers["Content-Type"] = content_type;
		headers["Content-Length"] = formatAlloc(m_requestAlloc, "%d", data.length);
		bodyWriter.write(data);
	}
	/// ditto
	void writeBody(string data, string content_type = "text/plain")
	{
		writeBody(cast(ubyte[])data, content_type);
	}
	
	/** Writes the whole response body at once, without doing any further encoding.

		The called has to make sure that the appropriate headers are set correctly
		(i.e. Content-Type and Content-Encoding).
	*/
	void writeRawBody(RandomAccessStream stream)
	{
		assert(!m_headerWritten, "A body was already written!");

		writeHeader();

		if( m_isHeadResponse ) return;

		auto bytes = stream.size - stream.tell();
		if( "Transfer-Encoding" in headers ) headers.remove("Transfer-Encoding");
		headers["Content-Length"] = formatAlloc(m_requestAlloc, "%d", bytes);
		m_conn.write(stream);
		m_countingWriter.increment(bytes);
	}

	/// Writes a JSON message with the specified status
	void writeJsonBody(T)(T data, int status = HttpStatus.OK)
	{
		import std.traits;
		static if( is(typeof(data.data())) && isArray!(typeof(data.data())) ){
			static assert(!is(T == Appender!(typeof(data.data()))), "Passed an Appender!T to writeJsonBody - this is most probably not doing what's indended.");
		}

		statusCode = status;
		writeBody(cast(ubyte[])serializeToJson(data).toString(), "application/json");
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
		if( !m_isHeadResponse ){
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
		assert(m_conn !is null);
		if( m_bodyWriter ) return m_bodyWriter;		
		
		assert(!m_headerWritten, "A void body was already written!");

		if( m_isHeadResponse ){
			// for HEAD requests, we define a NullOutputWriter for convenience
			// - no body will be written. However, the request handler should call writeVoidBody()
			// and skip writing of the body in this case.
			if( "Content-Length" !in headers )
				headers["Transfer-Encoding"] = "chunked";
			writeHeader();
			m_bodyWriter = new NullOutputStream;
			return m_bodyWriter;
		}

		if( "Content-Encoding" in headers && "Content-Length" in headers ){
			// we do not known how large the compressed body will be in advance
			// so remove the content-length and use chunked transfer
			headers.remove("Content-Encoding");
		}
		
		if ( "Content-Length" in headers ) {
			writeHeader();
			m_bodyWriter = m_countingWriter; // TODO: LimitedOutputStream(m_conn, content_length)
		} else {
			headers["Transfer-Encoding"] = "chunked";
			writeHeader();
			m_chunkedBodyWriter = FreeListRef!ChunkedOutputStream(m_countingWriter);
			m_bodyWriter = m_chunkedBodyWriter;
		}

		if( auto pce = "Content-Encoding" in headers ){
			if( *pce == "gzip" ){
				m_gzipOutputStream = FreeListRef!GzipOutputStream(m_bodyWriter);
				m_bodyWriter = m_gzipOutputStream; 
			} else if( *pce == "deflate" ){
				m_deflateOutputStream = FreeListRef!DeflateOutputStream(m_bodyWriter);
				m_bodyWriter = m_deflateOutputStream;
			} else {
				logWarn("Unsupported Content-Encoding set in response: '"~*pce~"'");
			}
		}
		
		return m_bodyWriter;
	}	

	/// Sends a redirect request to the client.
	void redirect(string url, int status = HttpStatus.Found)
	{
		statusCode = status;
		headers["Location"] = url;
		headers["Content-Length"] = "14";
		bodyWriter.write("redirecting...");
	}

	/** Special method sending a SWITCHING_PROTOCOLS response to the client.
	*/
	Stream switchProtocol(string protocol) {
		statusCode = HttpStatus.SwitchingProtocols;
		headers["Upgrade"] = protocol;
		writeVoidBody();
		return m_conn;
	}

	/// Sets the specified cookie value.
	Cookie setCookie(string name, string value) {
		auto cookie = new Cookie();
		cookie.setValue(value);
		cookies[name] = cookie;
		return cookie;
	}

	/**
		Initiates a new session.
		
		The session is stored in the SessionStore that was specified when
		creating the server. Depending on this, the session can be persistent
		or temporary and specific to this server instance.
	*/
	Session startSession() {
		assert(m_settings.sessionStore, "no session store set");
		assert(!m_session, "Try to start a session, but already started one.");
		m_session = m_settings.sessionStore.create();
		setCookie(m_settings.sessionIdCookie, m_session.id);
		return m_session;
	}

	/**
		Terminates the current session (if any).
	*/
	void terminateSession() {
		assert(m_session, "Try to terminate a session, but none is started.");
		setCookie(m_settings.sessionIdCookie, "");
		m_session.destroy();
		m_session = null;
	}

	@property ulong bytesWritten() {
		return m_countingWriter.bytesWritten;
	}
	
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

	// Finalizes the response. This is called automatically by the server.
	private void finalize() 
	{
		if( m_bodyWriter ) m_bodyWriter.finalize();
		if( m_chunkedBodyWriter && m_chunkedBodyWriter !is m_bodyWriter ) m_chunkedBodyWriter.finalize();
		m_conn.flush();
		m_timeFinalized = Clock.currTime().toUTC();
	}

	private void writeHeader()
	{
		assert(!m_bodyWriter && !m_headerWritten, "Try to write header after body has already begun.");
		m_headerWritten = true;
		auto app = appender!string();
		app.reserve(512);

		void writeLine(T...)(string fmt, T args)
		{
			formattedWrite(app, fmt, args);
			app.put("\r\n");
		}

		// write the status line
		writeLine("%s %d %s", 
			getHttpVersionString(this.httpVersion), 
			this.statusCode,
			this.statusPhrase.length ? this.statusPhrase : httpStatusText(this.statusCode));

		// write all normal headers
		foreach( n, v; this.headers ){
			app.put(n);
			app.put(':');
			app.put(' ');
			app.put(v);
			app.put("\r\n");
		}

		// NOTE: AA.length is very slow so this helper function is used to determine if an AA is empty.
		static bool empty(AA)(AA aa)
		{
			foreach( _; aa ) return false;
			return true;
		}

		// write cookies
		if( !empty(cookies) ) {
			foreach( n, cookie; this.cookies ) {
				app.put("Set-Cookie: ");
				app.put(n);
				app.put('=');
				filterUrlEncode(app, cookie.value);
				if ( cookie.domain ) {
					app.put("; Domain=");
					app.put(cookie.domain);
				}
				if ( cookie.path ) {
					app.put("; Path=");
					app.put(cookie.path);
				}
				if ( cookie.expires ) {
					app.put("; Expires=");
					app.put(cookie.expires);
				}
				if ( cookie.maxAge ) {
					app.put("; MaxAge=");
					formattedWrite(app, "%s", cookie.maxAge);
				}
				if ( cookie.isSecure ) {
					app.put("; Secure");
				}
				if ( cookie.isHttpOnly ) {
					app.put("; HttpOnly");
				}
				app.put("\r\n");
			}
		}

		// finalize reposonse header
		app.put("\r\n");
		m_conn.write(app.data(), true);
	}

}


/**************************************************************************************************/
/* Private types                                                                                  */
/**************************************************************************************************/

private struct HTTPServerContext {
	HttpServerRequestDelegate requestHandler;
	HttpServerSettings settings;
	HttpLogger[] loggers;
}

private struct HTTPServerListener {
	string bindAddress;
	ushort bindPort;
	string sslCertFile;
	string sslKeyFile;
}

private enum MaxHttpHeaderLineLength = 4096;

private class LimitedHttpInputStream : LimitedInputStream {
	this(InputStream stream, ulong byte_limit, bool silent_limit = false) {
		super(stream, byte_limit, silent_limit);
	}
	override void onSizeLimitReached() {
		throw new HttpStatusException(HttpStatus.RequestEntityTooLarge);
	}
}

private class TimeoutHttpInputStream : InputStream {
	private {
		SysTime m_timeref;
		Duration m_timeleft;
		InputStream m_in;
	}

	this(InputStream stream, Duration timeleft) {
		enforce(timeleft > dur!"seconds"(0), "Timeout required");
		m_in = stream;
		m_timeleft = timeleft;
		m_timeref = Clock.currTime();
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

	private void checkTimeout() {
		SysTime curr = Clock.currTime();
		auto diff = curr - m_timeref;
		if( diff > m_timeleft ) throw new HttpStatusException(HttpStatus.RequestTimeout);
		m_timeleft -= diff;
		m_timeref = curr;
	}
}

/**************************************************************************************************/
/* Private functions                                                                              */
/**************************************************************************************************/

private {
	shared string s_distHost;
	shared ushort s_distPort = 11000;
	shared bool s_listenersStarted = false;
	__gshared HTTPServerContext[] g_contexts;
	__gshared HTTPServerListener[] g_listeners;
}

/// private
private void handleHttpConnection(TcpConnection conn_, HTTPServerListener listen_info)
{
	FreeListRef!SslContext ssl_ctx;
	FreeListRef!SslContext ssl_context;
	if( listen_info.sslCertFile.length || listen_info.sslKeyFile.length ){
		logDebug("Creating SSL context...");
		assert(listen_info.sslCertFile.length && listen_info.sslKeyFile.length);
		ssl_ctx = FreeListRef!SslContext(listen_info.sslCertFile, listen_info.sslKeyFile);
		logDebug("... done");
	}

	Stream conn;
	FreeListRef!SslStream ssl_stream;

	// If this is a HTTPS server, initiate SSL
	if( ssl_ctx ){
		logTrace("accept ssl");
		ssl_stream = FreeListRef!SslStream(conn_, ssl_ctx, SslStreamState.Accepting);
		conn = ssl_stream;
	} else conn = conn_;

	bool persistent;
	do {
		HttpServerSettings settings;
		persistent = handleRequest(conn, conn_.peerAddress, listen_info, settings);

		// wait for another possible request on a keep-alive connection
		if( persistent && !conn_.waitForData(settings.keepAliveTimeout) ) {
			logDebug("persistent connection timeout!");
			break;
		}
	} while( persistent && conn_.connected );
}

private bool handleRequest(Stream conn, string peer_address, HTTPServerListener listen_info, ref HttpServerSettings settings)
{
	auto request_allocator = scoped!PoolAllocator(1024, defaultAllocator());
	scope(exit) request_allocator.reset();

	// some instances that live only while the request is running
	FreeListRef!NullOutputStream nullWriter = FreeListRef!NullOutputStream();
	FreeListRef!HttpServerRequest req = FreeListRef!HttpServerRequest();
	FreeListRef!TimeoutHttpInputStream timeout_http_input_stream;
	FreeListRef!LimitedHttpInputStream limited_http_input_stream;
	FreeListRef!ChunkedInputStream chunked_input_stream;

	// Default to the first virtual host for this listener
	HttpServerRequestDelegate request_task;
	HTTPServerContext context;
	foreach( ctx; g_contexts )
		if( ctx.settings.port == listen_info.bindPort ){
			bool found = false;
			foreach( addr; ctx.settings.bindAddresses )
				if( addr == listen_info.bindAddress )
					found = true;
			if( !found ) continue;
			context = ctx;
			settings = ctx.settings;
			request_task = ctx.requestHandler;
			break;
		}
	req.ssl = listen_info.sslCertFile.length || listen_info.sslKeyFile.length;

	// Create the response object
	auto res = FreeListRef!HttpServerResponse(conn, settings, request_allocator.Scoped_payload);

	// Error page handler
	void errorOut(int code, string msg, string debug_msg, Throwable ex){
		assert(!res.headerWritten);

		// stack traces sometimes contain random bytes - make sure they are replaced
		debug_msg = sanitizeUTF8(cast(ubyte[])debug_msg);

		res.statusCode = code;
		if( settings && settings.errorPageHandler ){
			scope err = new HttpServerErrorInfo;
			err.code = code;
			err.message = msg;
			err.debugMessage = debug_msg;
			err.exception = ex;
			settings.errorPageHandler(req, res, err);
		} else {
			res.contentType = "text/plain";
			res.bodyWriter.write(to!string(code) ~ " - " ~ httpStatusText(code) ~ "\n\n" ~ msg ~ "\n\nInternal error information:\n" ~ debug_msg);
		}
		assert(res.headerWritten);
	}

	bool parsed = false;
	bool keep_alive = false;

	// parse the request
	try {
		logTrace("reading request..");

		// limit the total request size
		InputStream reqReader;
		if( settings.maxRequestTime == dur!"seconds"(0) ) reqReader = conn;
		else {
			timeout_http_input_stream = FreeListRef!TimeoutHttpInputStream(conn, settings.maxRequestTime);
			reqReader = timeout_http_input_stream;
		}

		// basic request parsing
		req.peer = peer_address;
		parseRequestHeader(req, reqReader, request_allocator, settings.maxRequestHeaderSize);
		logTrace("Got request header.");

		// find the matching virtual host
		foreach( ctx; g_contexts )
			if( icmp2(ctx.settings.hostName, req.host) == 0 ){
				if( ctx.settings.port != listen_info.bindPort ) continue;
				bool found = false;
				foreach( addr; ctx.settings.bindAddresses )
					if( addr == listen_info.bindAddress )
						found = true;
				if( !found ) continue;
				context = ctx;
				settings = ctx.settings;
				request_task = ctx.requestHandler;
				break;
			}
		res.m_settings = settings;

		// setup compressed output
		if( auto pae = "Accept-Encoding" in req.headers ){
			if( countUntil(*pae, "gzip") >= 0 ){
				res.headers["Content-Encoding"] = "gzip";
			} else if( countUntil(*pae, "deflate") >= 0 ){
				res.headers["Content-Encoding"] = "deflate";
			}
		}

		// limit request size
		if( auto pcl = "Content-Length" in req.headers ) {
			string v = *pcl;
			auto contentLength = parse!ulong(v); // DMDBUG: to! thinks there is a H in the string
			enforce(v.length == 0, "Invalid content-length");
			enforce(settings.maxRequestSize <= 0 || contentLength <= settings.maxRequestSize, "Request size too big");
			limited_http_input_stream = FreeListRef!LimitedHttpInputStream(reqReader, contentLength);
		} else if( auto pt = "Transfer-Encoding" in req.headers ){
			enforce(*pt == "chunked");
			chunked_input_stream = FreeListRef!ChunkedInputStream(reqReader);
			limited_http_input_stream = FreeListRef!LimitedHttpInputStream(chunked_input_stream, settings.maxRequestSize, true);
		} else {
			limited_http_input_stream = FreeListRef!LimitedHttpInputStream(reqReader, 0);
		}
		req.bodyReader = limited_http_input_stream;

		// handle Expect header
		if( auto pv = "Expect" in req.headers) {
			if( *pv == "100-continue" ) {
				logTrace("sending 100 continue");
				conn.write("HTTP/1.1 100 Continue\r\n\r\n");
			}
		}

		// Url parsing if desired
		if( settings.options & HttpServerOption.ParseURL ){
			auto url = Url.parse(req.requestUrl);
			req.path = url.pathString;
			req.queryString = url.queryString;
			req.username = url.username;
			req.password = url.password;
		}

		// query string parsing if desired
		if( settings.options & HttpServerOption.ParseQueryString ){
			if( !(settings.options & HttpServerOption.ParseURL) )
				logWarn("Query string parsing requested but URL parsing is disabled!");
			parseUrlEncodedForm(req.queryString, req.query);
		}

		// cookie parsing if desired
		if( settings.options & HttpServerOption.ParseCookies ){
			auto pv = "cookie" in req.headers;
			if ( pv ) parseCookies(*pv, req.cookies);
		}

		// lookup the session
		if ( settings.sessionStore ) {
			auto pv = settings.sessionIdCookie in req.cookies;
			if (pv && *pv != "") {
				req.session = settings.sessionStore.open(*pv);
				res.m_session = req.session;
			}
		}

		if( settings.options & HttpServerOption.ParseFormBody ){
			auto ptype = "Content-Type" in req.headers;				
			if( ptype ) parseFormData(req.form, req.files, *ptype, req.bodyReader, MaxHttpHeaderLineLength);
		}

		if( settings.options & HttpServerOption.ParseJsonBody ){
			if( req.contentType == "application/json" ){
				auto bodyStr = cast(string)req.bodyReader.readAll();
				req.json = parseJson(bodyStr);
			}
		}

		// write default headers
		if( req.method == HttpMethod.HEAD ) res.m_isHeadResponse = true;
		if( settings.serverString.length )
			res.headers["Server"] = settings.serverString;
		res.headers["Date"] = toRFC822DateTimeString(Clock.currTime().toUTC());
		if( req.persistent ) res.headers["Keep-Alive"] = formatAlloc(request_allocator, "timeout=%d", settings.keepAliveTimeout.total!"seconds"());

		// finished parsing the request
		parsed = true;
		keep_alive = req.persistent;

		// handle the request
		logTrace("handle request (body %d)", req.bodyReader.leastSize);
		res.httpVersion = req.httpVersion;
		request_task(req, res);

		// if no one has written anything, return 404
		if( !res.headerWritten )
			throw new HttpStatusException(HttpStatus.NotFound);
	} catch(HttpStatusException err) {
		logDebug("http error thrown: %s", err.toString());
		if ( !res.headerWritten ) errorOut(err.status, err.msg, err.toString(), err);
		else logError("HttpStatusException after page has been written: %s", err.toString());
		logDebug("Exception while handling request %s %s: %s", req.method, req.requestUrl, err.toString());
		if ( !parsed || justifiesConnectionClose(err.status) )
			keep_alive = false;
	} catch (Throwable e) {
		auto status = parsed ? HttpStatus.InternalServerError : HttpStatus.BadRequest;
		if( !res.headerWritten ) errorOut(status, httpStatusText(status), e.toString(), e);
		else logError("Error after page has been written: %s", e.toString());
		logDebug("Exception while handling request %s %s: %s", req.method, req.requestUrl, e.toString());
		if ( !parsed )
			keep_alive = false;
	}

	if( req.bodyReader && !req.bodyReader.empty )
		nullWriter.write(req.bodyReader);

	// finalize (e.g. for chunked encoding)
	res.finalize();

	foreach( k, v ; req.files ){
		if( existsFile(v.tempPath) ) {
			removeFile(v.tempPath); 
			logDebug("Deleted upload tempfile %s", v.tempPath.toString()); 
		}
	}

	// log the request to access log
	foreach( log; context.loggers )
		log.log(req, res);

	return keep_alive;
}


private void parseRequestHeader(HttpServerRequest req, InputStream conn, Allocator alloc, ulong max_header_size)
{
	auto stream = FreeListRef!LimitedHttpInputStream(conn, max_header_size);

	logTrace("HTTP server reading status line");
	auto reqln = cast(string)stream.readLine(MaxHttpHeaderLineLength, "\r\n", alloc);
	logTrace("req: %s", reqln);
	
	//Method
	auto pos = reqln.indexOf(' ');
	enforce( pos >= 0, "invalid request method" );

	req.method = httpMethodFromString(reqln[0 .. pos]);
	reqln = reqln[pos+1 .. $];
	//Path
	pos = reqln.indexOf(' ');
	enforce( pos >= 0, "invalid request path" );

	req.requestUrl = reqln[0 .. pos];
	reqln = reqln[pos+1 .. $];

	req.httpVersion = parseHttpVersion(reqln);
	
	//headers
	parseRfc5322Header(stream, req.headers, MaxHttpHeaderLineLength, alloc);
}

private void parseCookies(string str, ref string[string] cookies) 
{
	while(str.length > 0) {
		auto idx = str.indexOf('=');
		enforce(idx > 0, "Expected name=value.");
		string name = str[0 .. idx].strip();
		str = str[idx+1 .. $];

		for( idx = 0; idx < str.length && str[idx] != ';'; idx++) {}
		string value = str[0 .. idx].strip();
		cookies[name] = urlDecode(value);
		str = idx < str.length ? str[idx+1 .. $] : null;
	}
}

private string formatAlloc(ARGS...)(Allocator alloc, string fmt, ARGS args)
{
	auto app = AllocAppender!string(alloc);
	formattedWrite(&app, fmt, args);
	return app.data;
}
