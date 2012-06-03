/**
	A HTTP 1.1/1.0 server implementation.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.server;

public import vibe.core.tcp;
public import vibe.http.common;
public import vibe.http.session;

import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.dist;
import vibe.http.form;
import vibe.http.log;
import vibe.inet.rfc5322;
import vibe.inet.url;
import vibe.stream.counting;
import vibe.stream.ssl;
import vibe.stream.zlib;
import vibe.templ.diet;
import vibe.textfilter.urlencode;
import vibe.utils.string;
import vibe.core.file;

import std.algorithm : countUntil, min;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.functional;
import std.string;
import std.uri;
public import std.variant;


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Starts a HTTP server listening on the specified port.

	'request_task' will be called for each HTTP request that is made. The
	'res' parameter of the callback then has to be filled with the response
	data.
	
	The 'ip4_addr' or 'ip6_addr' parameters can be used to specify the network
	interface on which the server socket is supposed to listen for connections.
	By default, all IPv4 and IPv6 interfaces will be used.
	
	request_task can be either HttpServerRequestDelegate/HttpServerRequestFunction
	or a class/struct with a member function 'handleRequest' that has the same
	signature as HttpServerRequestDelegate/Function.

	Note that if the application has been started with the --disthost command line
	switch, listenHttp() will automatically listen on the specified VibeDist host
	instead of locally. This allows for a seemless switch from single-host to 
	multi-host scenarios without changing the code. If you need to listen locally,
	use listenHttpPlain() instead.
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
			listenTcp(settings.port, (TcpConnection conn){ handleHttpConnection(conn, listener); }, addr);
		}
	}
}


/**
	Provides a HTTP request handler that responds with a static Diet template.
*/
@property HttpServerRequestDelegate staticTemplate(string template_file)()
{
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

	uint maxRequestHeaderCount = 100;

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

	/*
		Log format using Apache custom log format directives. E.g. NCSA combined:
		"%h - %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-agent}i\""
	*/
	string accessLogFormat = "%h - %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-agent}i\"";
	string accessLogFile = "";
	bool accessLogToConsole = false;

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


/// Throwing this exception from within a request handler will produce a matching error page.
class HttpServerError : Exception {
	private {
		int m_status;
	}

	this(int status, string message = null)
	{
		super(message ? message : httpStatusText(status));
		m_status = status;
	}
	
	@property int status() const { return m_status; }
}

/**
	Represents a HTTP request as received by the server side.
*/
final class HttpServerRequest : HttpRequest {
	public {
		string peer;

		// enabled if HttpServerOption.ParseURL is set
		string path;
		string username;
		string password;
		string queryString;

		// enabled if HttpServerOption.ParseCookies is set
		string[string] cookies;
		
		// enabled if HttpServerOption.ParseQueryString is set
		string[string] query;
		// filled by certain middleware (vibe.http.router)
		string[string] params;

		// body
		InputStream bodyReader;
		ubyte[] data;
		Json json; // only set if HttpServerOption.ParseJsonBoxy is set
		string[string] form; // only set if HttpServerOption.ParseFormBody is set
		FilePart[string] files; // only set if HttpServerOption.ParseFormBody is set

		/*
			body types:
				x-form-data
				json
				multi-part/files
		*/

		Session session;
	}
	private {
		SysTime m_timeCreated;
	}

	private this()
	{
		m_timeCreated = Clock.currTime().toUTC();
	}

	@property SysTime timeCreated() {
		return m_timeCreated;
	}

	MultiPart nextPart()
	{
		assert(false);
	}

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
		ChunkedOutputStream m_chunkedBodyWriter;
		CountingOutputStream m_countingWriter;
		HttpServerSettings m_settings;
		Session m_session;
		bool m_headerWritten = false;
		bool m_isHeadResponse = false;
		SysTime m_timeFinalized;
	}
	
	private this(Stream conn, HttpServerSettings settings)
	{
		m_conn = conn;
		m_countingWriter = new CountingOutputStream(conn);
		m_settings = settings;
	}
	
	@property bool headerWritten() const { return m_headerWritten; }

	bool isHeadResponse() const { return m_isHeadResponse; }

	/// Writes the hole body of the response at once.
	void writeBody(in ubyte[] data, string content_type = null)
	{
		if( content_type ) headers["Content-Type"] = content_type;
		headers["Content-Length"] = to!string(data.length);
		bodyWriter.write(data);
	}

	void writeBody(string data, string content_type = "text/plain")
	{
		writeBody(cast(ubyte[])data, content_type);
	}

	/// Writes a JSON message with the specified status
	void writeJsonBody(T)(T data, int status = HttpStatus.OK)
	{
		statusCode = status;
		writeBody(cast(ubyte[])serializeToJson(data).toString(), "application/json");
	}

	/** Writes the response with no body.
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
			m_chunkedBodyWriter = new ChunkedOutputStream(m_countingWriter);
			m_bodyWriter = m_chunkedBodyWriter;
		}

		if( auto pce = "Content-Encoding" in headers ){
			if( *pce == "gzip" ){
				m_bodyWriter = new GzipOutputStream(m_bodyWriter);
			} else if( *pce == "deflate" ){
				m_bodyWriter = new DeflateOutputStream(m_bodyWriter);
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

		Note that the variables are copied and not referenced inside of the template - any
		modification you do on them from within the template will get lost.

		Examples:
			---
			string title = "Hello, World!";
			int pageNumber = 1;
			res.renderCompat!("mytemplate.jd",
				string, "title",
				int, "pageNumber")
				(Variant(title), Variant(pageNumber));
			---
	*/
	void renderCompat(string template_file, TYPES_AND_NAMES...)(Variant[] args...)
	{
		headers["Content-Type"] = "text/html; charset=UTF-8";
		.parseDietFileCompat!(template_file, TYPES_AND_NAMES)(bodyWriter, args);
	}

	/// Finalizes the response. This is called automatically by the server.
	private void finalize() 
	{
		if( m_bodyWriter ) m_bodyWriter.finalize();
		if( m_chunkedBodyWriter && m_chunkedBodyWriter !is m_bodyWriter ) m_chunkedBodyWriter.finalize();
		m_conn.flush();
		m_timeFinalized = Clock.currTime().toUTC();
	}
	@property SysTime timeFinalized() { return m_timeFinalized; }

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

		// write cookies
		if ( cookies.length > 0 ) {
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
private enum MaxHttpRequestHeaderSize = 8192;

private class LimitedHttpInputStream : LimitedInputStream {
	this(InputStream stream, ulong byte_limit, bool silent_limit = false) {
		super(stream, byte_limit, silent_limit);
	}
	override void onSizeLimitReached() {
		throw new HttpServerError(HttpStatus.RequestEntityTooLarge);
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
		if( diff > m_timeleft ) throw new HttpServerError(HttpStatus.RequestTimeout);
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
	NullOutputStream nullWriter = new NullOutputStream();
	SslContext ssl_ctx;
	if( listen_info.sslCertFile.length || listen_info.sslKeyFile.length ){
		logDebug("Creating SSL context...");
		assert(listen_info.sslCertFile.length && listen_info.sslKeyFile.length);
		ssl_ctx = new SslContext(listen_info.sslCertFile, listen_info.sslKeyFile);
		logDebug("... done");
	}

	Stream conn;
	HttpServerRequest req;

	// If this is a HTTPS server, initiate SSL
	if( ssl_ctx ){
		logTrace("accept ssl");
		conn = new SslStream(conn_, ssl_ctx, SslStreamState.Accepting);
	} else conn = conn_;

	do {
		// Default to the first virtual host for this listener
		HttpServerSettings settings;
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

		// Create the response object
		scope res = new HttpServerResponse(conn, settings);

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

		// parse the request
		try {
			logTrace("reading request..");

			InputStream reqReader;
			if( settings.maxRequestTime == dur!"seconds"(0) ) reqReader = conn;
			else reqReader = new TimeoutHttpInputStream(conn, settings.maxRequestTime);

			// basic request parsing
			req = parseRequest(reqReader);
			req.peer = conn_.peerAddress;
			logTrace("Got request header.");

			//handle Expect-Header
			if( auto pv = "Expect" in req.headers) {
				if( *pv == "100-continue" ) {
					logTrace("sending 100 continue");
					conn.write("HTTP/1.1 100 Continue\r\n");
				}
			}

			// find the matching virtual host
			foreach( ctx; g_contexts )
				if( ctx.settings.hostName == req.host ){
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
				req.bodyReader = new LimitedHttpInputStream(reqReader, contentLength);
			} else {
				if( auto pt = "Transfer-Encoding" in req.headers ){
					enforce(*pt == "chunked");
					req.bodyReader = new LimitedHttpInputStream(new ChunkedInputStream(reqReader), settings.maxRequestSize, true);
				} else {
					auto pc = "Connection" in req.headers;
					if( pc && *pc == "close" )
						req.bodyReader = new LimitedHttpInputStream(reqReader, settings.maxRequestSize, true);
					else
						req.bodyReader = new LimitedHttpInputStream(reqReader, 0);
				}
			}

			// Url parsing if desired
			if( settings.options & HttpServerOption.ParseURL ){
				auto url = Url.parse(req.url);
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
				if( ptype ) parseFormData(req.form, req.files, *ptype, req.bodyReader);
			}

			if( settings.options & HttpServerOption.ParseJsonBody ){
				auto ptype = "Content-Type" in req.headers;				
				if( ptype && *ptype == "application/json" ){
					auto bodyStr = cast(string)req.bodyReader.readAll();
					req.json = parseJson(bodyStr);
				}
			}

			// write default headers
			if( req.method == "HEAD" ) res.m_isHeadResponse = true;
			if( settings.serverString.length )
				res.headers["Server"] = settings.serverString;
			res.headers["Date"] = toRFC822DateTimeString(Clock.currTime().toUTC());
			if( req.persistent ) res.headers["Keep-Alive"] = "timeout="~to!string(settings.keepAliveTimeout.total!"seconds"());

			// finished parsing the request
			parsed = true;

			// handle the request
			logTrace("handle request (body %d)", req.bodyReader.leastSize);
			res.httpVersion = req.httpVersion;
			request_task(req, res);
		} catch(HttpServerError err) {
			logDebug("http error thrown: %s", err.toString());
			if ( !res.headerWritten ) errorOut(err.status, err.msg, err.toString(), err);
			else logError("HttpServerError after page has been written: %s", err.toString());
			logDebug("Exception while handling request: %s", err.toString());
			if ( !parsed || justifiesConnectionClose(err.status) ) {
				conn_.close();
				break;
			}
		} catch (Throwable e) {
			logDebug("Exception while parsing request: %s", e.toString());
			if( !res.headerWritten ) errorOut(parsed ? HttpStatus.InternalServerError :
				HttpStatus.BadRequest, "Invalid request format.", e.toString(), e);
			else logError("Error after page has been written: %s", e.msg);
			logDebug("Exception while handling request: %s", e.toString());
			if ( !parsed ) {
				conn_.close();
				break;
			}
		}

		// if no one has written anything, return 404
		if( !res.headerWritten ) errorOut(HttpStatus.NotFound, "Not found.", "", null);

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

		// wait for another possible request on a keep-alive connection
		if( req.persistent && !conn_.waitForData(settings.keepAliveTimeout) ) {
			logDebug("persistent connection timeout!");
			break;
		}
	} while( req.persistent && conn_.connected );
}

private HttpServerRequest parseRequest(InputStream conn)
{
	auto req = new HttpServerRequest;
	auto stream = new LimitedHttpInputStream(conn, MaxHttpRequestHeaderSize);

	logTrace("HTTP server reading status line");
	auto reqln = cast(string)stream.readLine(MaxHttpHeaderLineLength);
	logTrace("req: %s", reqln);
	
	//Method
	auto pos = reqln.indexOf(' ');
	enforce( pos >= 0, "invalid request method" );

	req.method = reqln[0 .. pos];
	reqln = reqln[pos+1 .. $];
	//Path
	pos = reqln.indexOf(' ');
	enforce( pos >= 0, "invalid request path" );

	req.url = reqln[0 .. pos];
	reqln = reqln[pos+1 .. $];

	req.httpVersion = parseHttpVersion(reqln);
	
	//headers
	parseRfc5322Header(stream, req.headers, MaxHttpHeaderLineLength);

	return req;
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
