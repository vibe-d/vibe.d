/**
	A simple HTTP/1.1 client implementation.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.client;

public import vibe.core.net;
public import vibe.http.common;
public import vibe.inet.url;

import vibe.core.connectionpool;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.cookiejar;
import vibe.http.internal.http2;
import vibe.inet.message;
import vibe.inet.url;
import vibe.stream.counting;
import vibe.stream.tls;
import vibe.stream.operations;
import vibe.stream.wrapper : ConnectionProxyStream;
import vibe.stream.zlib;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string : icmp2;

import core.exception : AssertError;
import std.algorithm : splitter;
import std.array;
import std.conv;
import std.encoding : sanitize;
import std.exception;
import std.format;
import std.string;
import std.typecons;
import std.datetime;


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Performs a synchronous HTTP request on the specified URL.

	The requester parameter allows to customize the request and to specify the request body for
	non-GET requests before it is sent. A response object is then returned or passed to the
	responder callback synchronously.

	This function is a low-level HTTP client facility. It will not perform automatic redirect,
	caching or similar tasks. For a high-level download facility (similar to cURL), see the
	`vibe.inet.urltransfer` module.

	Note that it is highly recommended to use one of the overloads that take a responder callback,
	as they can avoid some memory allocations and are safe against accidentally leaving stale
	response objects (objects whose response body wasn't fully read). For the returning overloads
	of the function it is recommended to put a `scope(exit)` right after the call in which
	`HTTPClientResponse.dropBody` is called to avoid this.

	See_also: `vibe.inet.urltransfer.download`
*/
HTTPClientResponse requestHTTP(string url, scope void delegate(scope HTTPClientRequest req) requester = null, HTTPClientSettings settings = defaultSettings)
{
	return requestHTTP(URL.parse(url), requester, settings);
}
/// ditto
HTTPClientResponse requestHTTP(URL url, scope void delegate(scope HTTPClientRequest req) requester = null, HTTPClientSettings settings = defaultSettings)
{
	enforce(url.schema == "http" || url.schema == "https", "URL schema must be http(s).");
	enforce(url.host.length > 0, "URL must contain a host name.");
	bool use_tls = url.schema == "https";

	auto cli = connectHTTP(url.host, url.port, use_tls, settings);
	auto res = cli.request((req){
			// When sending through a proxy, full URL to the resource must be on the first line of the request
			if (settings.proxyURL.schema !is null) {
				req.requestURL = url.toString();
			} else if (url.localURI.length) {
				assert(url.path.absolute, "Request URL path must be absolute.");
				req.requestURL = url.localURI;
			}

			if ("authorization" !in req.headers && url.username != "") {
				import std.base64;
				string pwstr = url.username ~ ":" ~ url.password;
				req.headers["Authorization"] = "Basic " ~
					cast(string)Base64.encode(cast(ubyte[])pwstr);
			}
			if (requester) requester(req);
		});

	// make sure the connection stays locked if the body still needs to be read
	if( res.m_client && !res.m_client.isHTTP2Started ) res.lockedConnection = cli;

	logTrace("Returning HTTPClientResponse for conn %s", cast(void*)res.lockedConnection.__conn);
	return res;
}
/// ditto
void requestHTTP(string url, scope void delegate(scope HTTPClientRequest req) requester, scope void delegate(scope HTTPClientResponse req) responder, HTTPClientSettings settings = defaultSettings)
{
	requestHTTP(URL(url), requester, responder, settings);
}
/// ditto
void requestHTTP(URL url, scope void delegate(scope HTTPClientRequest req) requester, scope void delegate(scope HTTPClientResponse req) responder, HTTPClientSettings settings = defaultSettings)
{
	enforce(url.schema == "http" || url.schema == "https", "URL schema must be http(s).");
	enforce(url.host.length > 0, "URL must contain a host name.");
	bool use_tls = url.schema == "https";

	auto cli = connectHTTP(url.host, url.port, use_tls, settings);

	cli.request((scope req) {
		// When sending through a proxy, full URL to the resource must be on the first line of the request		
		if (settings.proxyURL.schema !is null) {
			req.requestURL = url.toString();
		} else if (url.localURI.length) {
			assert(url.path.absolute, "Request URL path must be absolute.");
			req.requestURL = url.localURI;
		}

		if ("authorization" !in req.headers && url.username != "") {
			import std.base64;
			string pwstr = url.username ~ ":" ~ url.password;
			req.headers["Authorization"] = "Basic " ~
				cast(string)Base64.encode(cast(ubyte[])pwstr);
		}
		if (requester) requester(req);
	}, responder);
	assert(!cli.m_state.requesting, "HTTP client still requesting after return!?");
	assert(!cli.m_state.responding, "HTTP client still responding after return!?");
}

/** Posts a simple JSON request. Note that the server www.example.org does not
	exists, so there will be no meaningful result.
*/
unittest {
	import vibe.core.log;
	import vibe.http.client;
	import vibe.stream.operations;

	void test()
	{
		requestHTTP("http://www.example.org/",
			(scope req) {
				req.method = HTTPMethod.POST;
				//req.writeJsonBody(["name": "My Name"]);
			},
			(scope res) {
				logInfo("Response: %s", res.bodyReader.readAllUTF8());
			}
		);
	}
}


/**
	Returns a HTTPClient proxy object that is connected to the specified host.

	Internally, a connection pool is used to reuse already existing connections. Note that
	usually requestHTTP should be used for making requests instead of manually using a
	HTTPClient to do so.
*/
auto connectHTTP(string host, ushort port = 0, bool use_tls = false, HTTPClientSettings settings = defaultSettings)
{
	static struct ConnInfo { string host; ushort port; HTTPClientSettings settings; }
	static FixedRingBuffer!(Tuple!(ConnInfo, ConnectionPool!HTTPClient), 16) s_connections;

	if( port == 0 ) port = use_tls ? 443 : 80;
	auto ckey = ConnInfo(host, port, settings);

	ConnectionPool!HTTPClient pool;
	foreach (c; s_connections)
		if (c[0].host == host && c[0].port == port && settings is c[0].settings)
			pool = c[1];

	if (!pool) {
		logDebug("Create HTTP client pool %s:%s %s proxy %s:%d", host, port, use_tls, ( settings ) ? settings.proxyURL.host : string.init, ( settings ) ? settings.proxyURL.port : 0);
		pool = new ConnectionPool!HTTPClient({
				auto ret = new HTTPClient;
				ret.connect(host, port, use_tls, settings);
				return ret;
			});
		if (s_connections.full) s_connections.popFront();
		s_connections.put(tuple(ckey, pool));
	}
	auto conn = pool.lockConnection();
	if (conn.isHTTP2Started) {
		logDebug("Lock http/2 connection pool");
		if (!conn.m_http2Context.pool)
			conn.m_http2Context.pool = new ConnectionPool!HTTPClient(&conn.connectionFactory);
		return conn.m_http2Context.pool.lockConnection();
	}
	return conn;
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/**
	Defines the options used in an HTTPClient for defining its requests.

	A new connection will be opened in requestHTTP for each different HTTPClientSettings.
*/
final class HTTPClientSettings {
	/** Sets the URL of a proxy to use for requests.

		If an HTTP proxy is used, the URL must be provided. It will be resolved,
		and the `HTTPClient` will throw if it cannot connect to it.
	*/
	URL proxyURL;

	/** Default maximum amount of time to keep a connection open after a request.

		Maximum amount of time the client should wait for the next request when
		there are none active. Note that the server will usually report its own
		keep-alive timeout, which will then be used instead.

		This setting is obeyed for HTTP/1.1 and HTTP/2 connections.
	*/
	Duration maxKeepAliveTimeout = 10.seconds; 

	/** Sets the user agent string to report in requests.

		If left empty, the default vibe.d user agent string will be used. Use
		`HTTPClient.setUserAgentString` to set a different default user agent
		globally.
	*/
	string userAgent;

	/// General option flags
	HTTPClientOptions options = HTTPClientOption.defaults;

	/// All cookies will be processed from and to the cookie jar if specified
	CookieStore cookieJar;

	/** If set, sends ping frames at regular intervals to avoid peer
		inactivity timeout.

		Note that this field only has an effect for HTTP/2 connections.
	*/
	Duration pingInterval; 
	
	/** Maxiumum time to wait when reading or writing data.

		This setting only has an effect for HTTP/2 connections. When a read or
		write operation takes longer than set here, the connection gets dropped.
	*/
	Duration connectionTimeout = 5.minutes;
	
	/// Custom TLS context for this client
	TLSContext tlsContext;
}


/** Option flags used to configure the HTTP client.
*/
enum HTTPClientOption {
	/** Uses HTTP/2 requests without prior checks.

		If enabled, the client will always send a client preface without trying
		upgrade or checking the ALPN value.
	*/
	forceHTTP2,
	
	/** Disables HTTP/2 and performs only HTTP/1.x requests.
	
		If left enabled, HTTP/2 upgrade will take place and after a successful
		connection, all further (concurrent or sequential) requests will be
		multiplexed over the same TCP Connection until it is timed out through
		keep-alive or inactivity.
	*/
	disableHTTP2,

	/// Will not try to upgrade the connection on non-TLS connections.
	onlyEncryptedHTTP2,

	/// Default set of flags - enables normal HTTP/2 upgrades on TLS connections.
	defaults = onlyEncryptedHTTP2,
}

/*static if (__VERSION__ >= 2067) {
	import std.typecons : BitFlags;
	alias HTTPClientOptions = BitFlags!HTTPClientOption;
} else*/ alias HTTPClientOptions = HTTPClientOption;

///
unittest {
	void test() {

		HTTPClientSettings settings = new HTTPClientSettings;
		settings.proxyURL = URL.parse("http://proxyuser:proxypass@192.168.2.50:3128");
		settings.maxKeepAliveTimeout = 0.seconds; // closes connection immediately after receiving the data.
		requestHTTP("http://www.example.org",
					(scope req){
			req.method = HTTPMethod.GET;
		},
		(scope res){
			logInfo("Headers:");
			foreach(key, ref value; res.headers) {
				logInfo("%s: %s", key, value);
			}
			logInfo("Response: %s", res.bodyReader.readAllUTF8());
		}, settings);

	}
}


/**
	Implementation of a HTTP 1.0/1.1 client with keep-alive support.

	Note that it is usually recommended to use requestHTTP for making requests as that will use a
	pool of HTTPClient instances to keep the number of connection establishments low while not
	blocking requests from different tasks.
*/
final class HTTPClient {
	enum maxHeaderLineLength = 4096;

	private {
		static __gshared ms_userAgent = "vibe.d/"~vibeVersionString~" (HTTPClient, +http://vibed.org/)";
		static __gshared void function(TLSContext) ms_tlsSetup;

		HTTPClientConnection m_conn;
		HTTPClientState m_state; // by-value
		HTTPClientSettings m_settings;

		HTTP2ClientContext m_http2Context;

		@property bool isHTTP2Started() { return m_http2Context !is null && m_conn.tcp !is null && m_conn.tcp.connected && m_http2Context.isSupported && m_http2Context.isValidated && m_http2Context.session !is null; }
		@property bool canUpgradeHTTP2() { return !(m_settings.options & HTTPClientOption.disableHTTP2)&& !(m_settings.options & HTTPClientOption.onlyEncryptedHTTP2) && !isHTTP2Started && !m_conn.forceTLS && !unsupportedHTTP2; }
		@property bool unsupportedHTTP2() { return m_http2Context is null || (!m_http2Context.isSupported && m_http2Context.isValidated); }
		@property Stream topStream() {
			if (isHTTP2Started) return m_state.http2Stream;
			if (m_conn.tlsStream) return m_conn.tlsStream;
			return m_conn.tcp;
		}
	}

	/** Get the current settings for the HTTP client. **/
	@property const(HTTPClientSettings) settings() const {
		return m_settings;
	}

	@property bool connected() const { return m_conn.tcp && m_conn.tcp.connected; }

	/**
		Sets the default user agent string for new HTTP requests.
	*/
	static void setUserAgentString(string str) { ms_userAgent = str; }

	/**
		Sets a callback that will be called for every TLS context that is created.

		If a TLS context was specified in the HTTPClientSettings, this callback is unused.

		Setting such a callback is useful for adjusting the validation parameters
		of the TLS context.
	*/
	static void setTLSSetupCallback(void function(TLSContext) func) { ms_tlsSetup = func; }

	/// Compatibility alias - will be deprecated soon.
	alias setSSLSetupCallback = setTLSSetupCallback;

	/**
		Connects to a specific server.

		This method may only be called if any previous connection has been closed.
	*/
	void connect(string server, ushort port = 80, bool use_tls = false, HTTPClientSettings settings = defaultSettings)
	in { assert(!isHTTP2Started && (!m_conn || !m_conn.tcp || !m_conn.tcp.connected) && port != 0, "Cannot establish a new connection on a connected client. Use disconnect() before, or reconnect()."); }
	body {
		m_settings = settings;
		m_http2Context = new HTTP2ClientContext();
		m_conn = new HTTPClientConnection();
		m_conn.server = server;
		m_conn.port = port;
		if (use_tls)
			setupTLS();

		connect();
	}

	private void setupTLS()
	{
		if (m_conn.forceTLS || (m_settings.proxyURL.schema !is null && m_settings.proxyURL.schema == "https"))
			return;
		m_conn.forceTLS = true;

		// use TLS either if the web server or the proxy has it
		if ((m_conn.forceTLS && !m_settings.proxyURL.schema) || m_settings.proxyURL.schema == "https") {
			m_conn.tlsContext = m_settings.tlsContext;
			
			if (!m_settings.tlsContext) {
				m_conn.tlsContext = createTLSContext(TLSContextKind.client);

				// this will be changed to trustedCert once a proper root CA store is available by default
				m_conn.tlsContext.peerValidationMode = TLSPeerValidationMode.none;

				if (ms_tlsSetup) 
					ms_tlsSetup(m_conn.tlsContext);
			}
						
			if (m_settings.options & HTTPClientOption.disableHTTP2)
				m_conn.tlsContext.setClientALPN(["http/1.1"]);
			else
				m_conn.tlsContext.setClientALPN(["h2", "h2-14", "h2-16", "http/1.1"]);
		}

	}

	private void connect()
	{
		if (m_settings.proxyURL.schema !is null){
			NetworkAddress proxyAddr = resolveHost(m_settings.proxyURL.host);
			proxyAddr.port = m_settings.proxyURL.port;

			// we connect to the proxy directly
			m_conn.tcp = connectTCP(proxyAddr);
			if (m_settings.proxyURL.schema == "https") {
				m_conn.tlsStream = createTLSStream(m_conn.tcp, m_conn.tlsContext, TLSStreamState.connecting, m_settings.proxyURL.host, proxyAddr);
			}
		}
		else // connect to the requested server/port
		{
			logDebug("Connect without proxy");
			m_conn.tcp = connectTCP(m_conn.server, m_conn.port);
			if (m_conn.tlsContext) {
				m_conn.tlsStream = createTLSStream(m_conn.tcp, m_conn.tlsContext, TLSStreamState.connecting, m_conn.server, m_conn.tcp.remoteAddress);
				logDebug("Got alpn: %s", m_conn.tlsStream.alpn);
			}
		}

		if (m_settings.pingInterval != Duration.zero) {
			m_http2Context.pinger = setTimer(m_settings.pingInterval, &onPing, true);
		}

		// alpn http/2 connection
		if ((m_settings.options & HTTPClientOption.forceHTTP2) || (m_conn.tlsStream && !(m_settings.options & HTTPClientOption.disableHTTP2) && m_conn.tlsStream.alpn.startsWith("h2"))) {
			logDebug("Got alpn: %s", m_conn.tlsStream.alpn);
			HTTP2Settings local_settings = getHTTP2Settings(m_settings);
			m_http2Context.session = new HTTP2Session(false, null, cast(TCPConnection) m_conn.tcp, m_conn.tlsStream, local_settings, &onRemoteSettings);
			m_http2Context.worker = runTask(&runHTTP2Worker, false);
			yield();
			logDebug("Worker started, continuing");
			m_http2Context.isValidated = true;
			m_http2Context.isSupported = true;
		}
		// pre-verified http/2 cleartext connection
		else if (canUpgradeHTTP2 && m_http2Context.isSupported) {
			logDebug("Upgrading HTTP/2");
			HTTP2Settings local_settings = getHTTP2Settings(m_settings);
			m_http2Context.session = new HTTP2Session(false, null, cast(TCPConnection) m_conn.tcp, null, local_settings, &onRemoteSettings);
			m_http2Context.worker = runTask(&runHTTP2Worker, false);
			m_http2Context.isValidated = true;
			m_http2Context.isSupported = true;
		}
	}

	void reconnect(string reason = "")
	{
		if (m_conn.tcp && m_conn.tcp.connected)
			disconnect(false, reason);
		
		connect();
	}

	/**
		Forcefully closes the connection or HTTP/2 stream

		Before calling this method, be sure that the request is not currently being processed.
	*/
	void disconnect(bool rst_stream = true, string reason = "")
	{
		m_conn.totRequest = 0;
		m_conn.maxRequests = int.max;
		void finalize() {
			try topStream().finalize();
			catch (Exception e) logDebug("Failed to finalize connection stream when closing HTTP client connection: %s", e.msg);
		}

		void closeTCP()
		{
			if (m_conn.keepAlive !is Timer.init && m_conn.keepAlive.pending)
				m_conn.keepAlive.stop();
			if (m_conn.tlsStream) m_conn.tlsStream.finalize(); // TLS has an alert for connection closure
			if (m_conn.tcp) {
				m_conn.tcp.finalize();
				m_conn.tcp.close();
			}
			m_conn.tcp = null;
			m_conn.tlsStream = null;
		}

		if (isHTTP2Started && !rst_stream && !m_http2Context.closing) {
			if (m_http2Context.pinger !is Timer.init && m_http2Context.pinger.pending)
				m_http2Context.pinger.stop();
			// closing an HTTP2 Session & TCP Connection

			// the event loop may take time, so make sure no other streams get started
			m_http2Context.closing = true;

			import libhttp2.frame : FrameError;
			if (m_state.http2Stream && m_state.http2Stream.connected) {
				finalize();
			}
			m_http2Context.session.stop(FrameError.NO_ERROR, reason);
			closeTCP();
			m_http2Context.worker.join();
			m_http2Context.closing = false;
		}
		else if (isHTTP2Started && rst_stream) {
			if (m_state.http2Stream && m_state.http2Stream.connected) {
				try m_state.http2Stream.close();
				catch (Exception e) logDebug("Failed to finalize connection stream when closing HTTP client connection: %s", e.msg);
			}
			m_state.http2Stream.destroy();
			m_state.http2Stream = null;
		}
		else if (!isHTTP2Started && m_conn.tcp && m_conn.tcp.connected) {
			finalize();
			closeTCP();
		}
		else {
			// no need to disconnect anything...
		}
	}

	/**
		Performs a HTTP request.

		requester is called first to populate the request with headers and the desired
		HTTP method and version. After a response has been received it is then passed
		to the caller which can in turn read the reponse body. Any part of the body
		that has not been processed will automatically be consumed and dropped.

		Note that the second form of this method (returning a HTTPClientResponse) is
		not recommended to use as it may accidentially block a HTTP connection when
		only part of the response body was read and also requires a heap allocation
		for the response object. The callback based version on the other hand uses
		a stack allocation and guarantees that the request has been fully processed
		once it has returned.
	*/
	void request(scope void delegate(scope HTTPClientRequest req) requester, scope void delegate(scope HTTPClientResponse) responder)
	{
				
		if (m_conn.nextTimeout == Duration.zero) {
			logDebug("Set keep-alive timer to: %s", m_settings.maxKeepAliveTimeout.total!"msecs");
			m_conn.keepAlive = setTimer(m_settings.maxKeepAliveTimeout, &onKeepAlive, false);
			m_conn.nextTimeout = m_settings.maxKeepAliveTimeout;
		}
		if (isHTTP2Started && m_http2Context.closing)
		{
			m_http2Context.worker.join(); // finish closing ...
			connect();
		}
		else if (!m_conn.tcp || !m_conn.tcp.connected)
			connect();
		else if (++m_conn.totRequest >= m_conn.maxRequests)
			reconnect("Max keep-alive requests exceeded");

		bool keepalive;
		HTTPMethod req_method;
		processRequest(requester, req_method, keepalive);
		processResponse(responder, req_method, keepalive);

		if (!keepalive)
			m_conn.keepAliveTimeout = Duration.zero;
	}

	/// ditto
	HTTPClientResponse request(scope void delegate(HTTPClientRequest) requester)
	{
		if (isHTTP2Started && m_http2Context.closing)
		{
			m_http2Context.worker.join();
			connect();
		}
		else if (!m_conn.tcp || !m_conn.tcp.connected)
			connect();
		else if (++m_conn.totRequest >= m_conn.maxRequests)
			reconnect("Max keep-alive requests exceeded");

		bool keepalive;
		HTTPClientResponse res;
		m_state.responding = false;
		HTTPMethod req_method;
		processRequest(requester, req_method, keepalive);
		m_state.responding = true;
		res = new HTTPClientResponse(this, req_method, keepalive);
		return res;
	}

	private HTTPClient connectionFactory()
	{
		HTTPClient client = new HTTPClient;
		client.m_conn = m_conn;
		client.m_http2Context = m_http2Context;
		client.m_settings = m_settings;
		return client;
	}
	
	private void processRequest(scope void delegate(HTTPClientRequest req) requester, ref HTTPMethod req_method, ref bool keepalive)
	{
		assert(!m_state.requesting, "Interleaved HTTP client requests detected!");
		assert(!m_state.responding, "Interleaved HTTP client request/response detected!");

		m_state.requesting = true;
		scope(exit) m_state.requesting = false;
		if (isHTTP2Started) m_state.http2Stream = m_http2Context.session.startRequest();
		string user_agent = m_settings.userAgent ? m_settings.userAgent : ms_userAgent;
		Duration latency = Duration.zero;
		logDebug("Creating scoped client");
		auto req = scoped!HTTPClientRequest(m_conn, m_state.http2Stream, m_settings.proxyURL, user_agent, canUpgradeHTTP2,
											m_http2Context ? m_http2Context.latency : latency, keepalive, m_settings.cookieJar);
		logDebug("Calling callback");
		requester(req);

		// after requester, to make sure it doesn't get corrupted
		if (canUpgradeHTTP2)
			startHTTP2Upgrade(req.headers);
		req.finalize();
		logDebug("Sent request");
		req_method = req.method;
	}

	private void processResponse(scope void delegate(scope HTTPClientResponse) responder, ref HTTPMethod req_method, ref bool keepalive) 
	{
		// fixme: Close HTTP/2 session when a response is not handled properly?

		m_state.responding = true;
		logDebug("Processing response");
		if (m_settings.maxKeepAliveTimeout != Duration.zero)
			keepalive = true;
		auto res = scoped!HTTPClientResponse(this, req_method, keepalive);
		logDebug("Response loaded");
		Exception user_exception;
		{
			scope (failure) {
				if (!isHTTP2Started) disconnect();
			}

			/// Throws exception if a proxy request was invalid
			if (m_settings.proxyURL.host !is null)
				verifyProxy(res.headers, cast(HTTPStatus)res.statusCode);

			try // Response callback
				responder(res);
			catch (Exception e) {
				logDebug("Error while handling response: %s", e.toString().sanitize());
				disconnect(false, "Internal error");
				user_exception = e;
			}
			if (m_state.responding) {
				logDebug("Failed to handle the complete response of the server - disconnecting.");
				res.disconnect();
			}
			assert(!m_state.responding, "Still in responding state after finalizing the response!?");
			
			if (!isHTTP2Started && res.headers.get("Connection") == "close")
				disconnect();
		}
		if (user_exception) throw user_exception;
	}

	private void startHTTP2Upgrade(ref InetHeaderMap headers) {
		logDebug("Starting HTTP/2 Upgrade");
		HTTP2Settings local_settings = getHTTP2Settings(m_settings);
		HTTP2Stream stream;
		m_http2Context.session = new HTTP2Session(m_conn.tcp, stream, local_settings, &onRemoteSettings);
		m_state.http2Stream = stream;
		m_http2Context.worker = runTask(&runHTTP2Worker, true); // delayed start
		m_http2Context.isUpgrading = true;

		headers["Connection"] = "Upgrade, HTTP2-Settings";
		headers["Upgrade"] = "h2c";
		headers["HTTP2-Settings"] = cast(string)local_settings.toBase64Settings();

	}

	// returns true if now using HTTP/2
	private void finalizeHTTP2Upgrade(string upgrade_hd) {
		// continue HTTP/2 initialization using upgrade mechanism
		if (m_http2Context.isUpgrading && upgrade_hd.length >= 3 && upgrade_hd[0 .. 3] == "h2c") {
			// we have an HTTP/2 connection
			m_http2Context.isUpgrading = false;
			m_http2Context.isSupported = true;
			m_http2Context.isValidated = true;
			logDebug("Session resume");
			m_http2Context.session.resume();
		}
		else if (m_http2Context.isUpgrading && (upgrade_hd.length < 3 || upgrade_hd[0 .. 3] != "h2c"))
		{
			m_http2Context.isUpgrading = false;
			m_http2Context.isSupported = false;
			m_http2Context.isValidated = true;
			logDebug("Session abort");
			m_http2Context.session.abort(m_state.http2Stream);
			m_state.http2Stream = null;
			m_http2Context.worker.join();
		}
	}

	private void extendKeepAliveTimeout() {
		m_conn.rearmKeepAlive();
	}

	/// Verify proxy response
	private void verifyProxy(ref InetHeaderMap headers, HTTPStatus status_code) {
		// proxy implementation
		if (headers.get("Proxy-Authenticate", null) !is null) {
			if (status_code == 407) {
				// send the request again with the proxy authentication information if available
				if (m_settings.proxyURL.username is null) {
					throw new HTTPStatusException(HTTPStatus.proxyAuthenticationRequired, "Proxy Authentication Required - No Username Provided.");
				}
				throw new HTTPStatusException(HTTPStatus.proxyAuthenticationRequired, "Proxy Authentication Required - Wrong Username Provided.");
			}
			
			throw new HTTPStatusException(HTTPStatus.ProxyAuthenticationRequired, "Proxy Authentication Failed With Error: " ~ status_code.to!string);
		}
	}
	

	private void runHTTP2Worker(bool upgrade = false) 
	{
		logDebug("Running HTTP/2 worker");

		m_http2Context.session.setReadTimeout(m_settings.connectionTimeout);
		m_http2Context.session.setWriteTimeout(m_settings.connectionTimeout);
		m_http2Context.session.setPauseTimeout(m_settings.connectionTimeout);

		// starting...
		m_http2Context.session.run(upgrade);
		// stopped here

		// all data is cleaned up in run()
		m_http2Context.session = null;
		m_http2Context.worker = Task();
		if (m_http2Context.pinger !is Timer.init && m_http2Context.pinger.pending)
			m_http2Context.pinger.stop();
		m_http2Context.closing = false;
		m_http2Context.pool.destroy();
		m_http2Context.pool = null;
		m_state.http2Stream = null;

		if (!upgrade || (upgrade && !unsupportedHTTP2)) {
			m_conn.keepAliveTimeout = 0.seconds;
			m_conn.tlsStream = null;
			m_conn.tcp = null;
		}
		logDebug("Cleaned HTTP/2 worker");
		
	}

	private void onKeepAlive() {
		logDebug("Keep-alive timeout");
		disconnect(false, "Keep-alive Timeout");
	}

	/// will update m_http2Context.latency with the latest latency
	private void ping()
	{
		Duration latency;
		logDebug("Running ping");
		auto cb = getEventDriver().createManualEvent();
		SysTime start = Clock.currTime();
		long sent = start.stdTime();
		SysTime recv;
		PingData data = PingData(sent, &recv, cb);
		
		m_http2Context.session.ping(data);
		
		cb.wait();
		cb.destroy();
		m_http2Context.latency = recv - start;
	}

	private void onPing() {
		if (!isHTTP2Started && !canUpgradeHTTP2)
			m_http2Context.pinger.stop();
		else runTask(&ping);
	}

	private void onRemoteSettings(ref HTTP2Settings settings)
	{
		if (!m_http2Context.pool)
			m_http2Context.pool = new ConnectionPool!HTTPClient(&connectionFactory);
		m_http2Context.pool.maxConcurrency = settings.maxConcurrentStreams;
	}

	private HTTP2Settings getHTTP2Settings(HTTPClientSettings settings)
	{
		HTTP2Settings ret;
		// ...
		return ret;
	}
}


/**
	Represents a HTTP client request (as sent to the server).
*/
final class HTTPClientRequest : HTTPRequest {
	private {
		HTTPClientConnection m_conn;
		HTTP2Stream m_http2Stream;
		OutputStream m_bodyWriter;
		CookieStore m_cookieJar;
		bool m_headerWritten;
		bool m_concatCookies;
		bool m_isUpgrading;
		FixedAppender!(string, 22) m_contentLengthBuffer;
		NetworkAddress m_localAddress;
		Duration* m_latency;

		@property inout(Stream) topStream()
		inout {
			if (m_http2Stream && !m_isUpgrading) return m_http2Stream;
			if (m_conn.tlsStream) return m_conn.tlsStream;
			return m_conn.tcp;
		}
	}

	/// private
	this(HTTPClientConnection conn, HTTP2Stream http2, URL proxy, string user_agent, bool is_http2_upgrading, 
		 ref Duration latency, ref bool keepalive, CookieStore cookie_jar)
	{

		m_conn = conn;
		m_http2Stream = http2;
		m_cookieJar = cookie_jar;
		m_latency = &latency;
		m_isUpgrading = is_http2_upgrading;

		if (!m_http2Stream)
			httpVersion = HTTPVersion.HTTP_1_1;
		else
			httpVersion = HTTPVersion.HTTP_2;

		if (m_conn.port != 0 && m_conn.port != 80)
			headers["Host"] = format("%s:%d", m_conn.server, m_conn.port);
		else headers["Host"] = m_conn.server;
		headers["User-Agent"] = user_agent;

		if (proxy.host !is null){
			headers["Proxy-Connection"] = "keep-alive";

			if (proxy.username.length || proxy.password.length) {
				import std.base64;			
				headers["Proxy-Authorization"] = "Basic " ~ cast(string) Base64.encode(cast(ubyte[])format("%s:%s", proxy.username, proxy.password));
			}
		}
		else if (!m_http2Stream && !is_http2_upgrading && httpVersion == HTTPVersion.HTTP_1_1) {
			headers["Connection"] = "keep-alive";
			keepalive = true;
		}

		headers["Accept-Encoding"] = "gzip, deflate";
	}

	/// True if this request is being made under an established HTTP/2 session
	@property bool isHTTP2() { return m_http2Stream !is null; }

	/// Returns the last latency recorded by the HTTP/2 session
	@property Duration latency() { return *m_latency; }

	/// For HTTP/2, specify true to force cookies to be concatenated. This is not recommended because it averts header indexing.
	@property void concatenateCookies(bool b) { m_concatCookies = b; }

	@property NetworkAddress localAddress() const { return m_conn.tcp.localAddress; }

	/**
		Accesses the Content-Length header of the request.

		Negative values correspond to an unset Content-Length header.
	*/
	@property long contentLength() const { return headers.get("Content-Length", "-1").to!long(); }
	/// ditto
	@property void contentLength(long value)
	{
		if (value >= 0) headers["Content-Length"] = clengthString(value);
		else if ("Content-Length" in headers) headers.remove("Content-Length");
	}

	/// Produces a ping request to evaluate the connection latency, or zero if HTTP/2 was not active
	Duration ping()
	{
		if (isHTTP2) {
			*m_latency = m_http2Stream.ping();
			return *m_latency;
		}
		return Duration.zero;
	}

	/**
		Writes the whole response body at once using raw bytes.
	*/
	void writeBody(RandomAccessStream data)
	{
		writeBody(data, data.size - data.tell());
	}
	/// ditto
	void writeBody(InputStream data)
	{
		headers["Transfer-Encoding"] = "chunked";
		bodyWriter.write(data);
		finalize();
	}
	/// ditto
	void writeBody(InputStream data, ulong length)
	{
		headers["Content-Length"] = clengthString(length);
		bodyWriter.write(data, length);
		finalize();
	}
	/// ditto
	void writeBody(in ubyte[] data, string content_type = null)
	{
		if( content_type != "" ) headers["Content-Type"] = content_type;
		headers["Content-Length"] = clengthString(data.length);
		bodyWriter.write(data);
		finalize();
	}

	/**
		Writes the response body as JSON data.
	*/
	void writeJsonBody(T)(T data, bool allow_chunked = false)
	{
		import vibe.stream.wrapper;

		headers["Content-Type"] = "application/json";

		// set an explicit content-length field if chunked encoding is not allowed
		if (!allow_chunked) {
			import vibe.internal.rangeutil;
			long length = 0;
			auto counter = RangeCounter(&length);
			serializeToJson(counter, data);
			headers["Content-Length"] = clengthString(length);
		}

		auto rng = StreamOutputRange(bodyWriter);
		serializeToJson(&rng, data);
		rng.flush();
		finalize();
	}

	void writePart(MultiPart part)
	{
		assert(false, "TODO");
	}

	/**
		An output stream suitable for writing the request body.

		The first retrieval will cause the request header to be written, make sure
		that all headers are set up in advance.s
	*/
	@property OutputStream bodyWriter()
	{
		if (m_bodyWriter) return m_bodyWriter;

		assert(!m_headerWritten, "Trying to write request body after body was already written.");

		if (!isHTTP2 && "Content-Length" !in headers && "Transfer-Encoding" !in headers && headers.get("Connection", "") != "close")
		{
			headers["Transfer-Encoding"] = "chunked";
		}

		writeHeader();
		m_bodyWriter = topStream();

		if (headers.get("Transfer-Encoding", null) == "chunked")
			m_bodyWriter = new ChunkedOutputStream(m_bodyWriter);

		return m_bodyWriter;
	}

	private void writeHeader()
	{
		import vibe.stream.wrapper;
		assert(!m_headerWritten, "HTTPClient tried to write headers twice.");
		m_headerWritten = true;

		// http/2
		if (isHTTP2) {
			logDebug("Writing HTTP/2 headers");
			m_http2Stream.writeHeader(requestURL, m_conn.tlsStream ? "https" : "http", method, headers, m_cookieJar, m_concatCookies);
			return;
		}

		/// http/1.1 or lower
		auto output = StreamOutputRange(topStream);

		formattedWrite(&output, "%s %s %s\r\n", httpMethodString(method), requestURL, getHTTPVersionString(httpVersion));
		logTrace("--------------------");
		logTrace("HTTP client request:");
		logTrace("--------------------");
		logTrace("%s", this);
		foreach( k, v; headers ){
			formattedWrite(&output, "%s: %s\r\n", k, v);
			logTrace("%s: %s", k, v);
		}
		if (m_cookieJar !is null) {
			m_cookieJar.get(headers["Host"], requestURL, m_conn.tlsStream !is null, (string cookie) {
				if (cookie.length) {
					logDebug("Cookie: %s", cookie);
					formattedWrite(&output, "Cookie: %s\r\n", cookie);
				}
			});
			logDebug("Done with cookies");
		}
		output.put("\r\n");
		logTrace("--------------------");
	}

	private void finalize()
	{
		logDebug("Finalize request");
		// test if already finalized
		if (m_headerWritten && !m_bodyWriter) {
			logDebug("Already finalized...");
			return;
		}
		// force the request to be sent
		if (!m_headerWritten) writeHeader();
		else {
			bodyWriter.flush();
			if (m_bodyWriter !is cast(OutputStream)topStream) {
				m_bodyWriter.finalize();
				topStream.flush();
			}
			m_bodyWriter = null;
		}

		// we may have a shot at an atomic request here. This will half-close the stream
		if (m_http2Stream) m_http2Stream.finalize();
	}

	private string clengthString(ulong len)
	{
		m_contentLengthBuffer.clear();
		formattedWrite(&m_contentLengthBuffer, "%s", len);
		return m_contentLengthBuffer.data;
	}
}


/**
	Represents a HTTP client response (as received from the server).
*/
final class HTTPClientResponse : HTTPResponse {
	private {
		HTTPClient m_client;
		LockedConnection!HTTPClient lockedConnection;

		// todo: move these to unions and manual allocations
		FreeListRef!LimitedInputStream m_limitedInputStream;
		FreeListRef!ChunkedInputStream m_chunkedInputStream;
		FreeListRef!GzipInputStream m_gzipInputStream;
		FreeListRef!DeflateInputStream m_deflateInputStream;
		FreeListRef!EndCallbackInputStream m_endCallback;

		InputStream m_bodyReader;
		Allocator m_alloc;
		bool m_keepAlive;
		bool m_finalized;
		int m_maxRequests = int.max;
	}

	/// Contains the keep-alive 'max' parameter, indicates how many requests a client can
	/// make before the server closes the connection.
	@property int maxRequests() const {
		return m_maxRequests;
	}

	/// private
	this(HTTPClient client, HTTPMethod req_method, ref bool keepalive)
	{
		version (VibeManualMemoryManagement) {
			m_alloc = new PoolAllocator(1024, defaultAllocator());
		} else m_alloc = defaultAllocator();

		m_client = client;
		m_keepAlive = keepalive;

		scope(failure) finalize(false);
		scope(success) finalize(keepalive);

		m_client.m_conn.rearmKeepAlive();

		if (m_client.isHTTP2Started) {
			logDebug("get response");
			// process HTTP/2 compressed headers
			m_client.m_state.http2Stream.readHeader(this.statusCode, this.headers, m_alloc);
			this.statusPhrase = httpStatusText(this.statusCode);
		}
		else {
			// read and parse status line ("HTTP/#.# #[ $]\r\n")
			logTrace("HTTP client reading status line");
			string stln = cast(string)client.topStream.readLine(HTTPClient.maxHeaderLineLength, "\r\n", m_alloc);
			logTrace("stln: %s", stln);
			this.httpVersion = parseHTTPVersion(stln);

			enforce(stln.startsWith(" "));
			stln = stln[1 .. $];
			this.statusCode = parse!int(stln);
			if( stln.length > 0 ){
				enforce(stln.startsWith(" "));
				stln = stln[1 .. $];
				this.statusPhrase = stln;
			}

			// read headers until an empty line is hit
			parseRFC5322Header(client.topStream, this.headers, HTTPClient.maxHeaderLineLength, m_alloc, false);

			auto upgrade_hd = this.headers.get("Upgrade", "");
			logDebug("Finalizing the upgrade process");
			m_client.finalizeHTTP2Upgrade(upgrade_hd);
		}

		logTrace("---------------------");
		logTrace("HTTP client response:");
		logTrace("---------------------");
		logTrace("%s", this);
		foreach (k, v; this.headers)
			logTrace("%s: %s", k, v);

		if (m_client.m_settings.cookieJar) {
			this.headers.getAll("Set-Cookie", (value) {
				logDebug("Save cookie: %s", value);
				m_client.m_settings.cookieJar.set(client.m_conn.server, value);
			});
		}
		logTrace("---------------------");

		// Treat HTTP/2 keep-alive and return
		if (m_client.isHTTP2Started)
			return;

		// Additional routines for HTTP/1.1 keep-alive headers handling
		{
			Duration server_timeout;
			bool has_server_timeout;

			if (auto pka = "Keep-Alive" in this.headers) {
				foreach(s; splitter(*pka, ',')){
					auto pair = s.splitter('=');
					auto name = pair.front.strip();
					pair.popFront();
					if (icmp2(name, "timeout") == 0) {
						has_server_timeout = true;
						server_timeout = pair.front.to!int().seconds;
					} else if (icmp2(name, "max") == 0) {
						m_maxRequests = pair.front.to!int();
						m_client.m_conn.maxRequests = m_maxRequests;
					}
				}
				keepalive = true;
			}

			if (has_server_timeout && m_client.m_settings.maxKeepAliveTimeout > server_timeout)
				m_client.m_conn.keepAliveTimeout = server_timeout;
			else if (this.httpVersion == HTTPVersion.HTTP_1_0) {
				keepalive = false;
				m_client.m_conn.keepAliveTimeout = Duration.zero;
			}
		}

	}

	~this()
	{
		debug if (m_client && m_client.m_state.responding) { import std.stdio; writefln("WARNING: HTTPClientResponse not fully processed before being finalized"); }
	}

	/// True if this response is encapsulated by an HTTP/2 session
	@property bool isHTTP2() {
		return m_client.isHTTP2Started;
	}

	/// Returns the last recorded latency for this HTTP/2 session
	@property Duration latency() {
		return isHTTP2 ? m_client.m_http2Context.latency : Duration.zero();
	}

	/// Produces a ping request to evaluate the connection latency, or zero if HTTP/2 was not active
	Duration ping() {
		if (isHTTP2) {
			m_client.ping();
			return m_client.m_http2Context.latency;
		}
		return Duration.zero;
	}

	/**
		An input stream suitable for reading the response body.
	*/
	@property InputStream bodyReader()
	{
		if( m_bodyReader ) { 
			logDebug("Returning bodyreader: http2=%s", isHTTP2);
			return m_bodyReader;
		}

		logDebug("Creating bodyreader: http2=%s", isHTTP2);
		assert (m_client, "Response was already read or no response body, may not use bodyReader.");

		m_bodyReader = m_client.topStream;
		// prepare body the reader
		if( auto pte = "Transfer-Encoding" in this.headers ){
			if (icmp2(*pte, "chunked") == 0) {
				m_chunkedInputStream = FreeListRef!ChunkedInputStream(m_client.topStream);
				m_bodyReader = this.m_chunkedInputStream;
			}
			// todo: Handle Transfer-Encoding: gzip
			//else if (!handleCompression(*pte))
			else enforce(icmp2(*pte, "identity") == 0, "Unsuported Transfer-Encoding: "~*pte);
		} else if( auto pcl = "Content-Length" in this.headers ){
			m_limitedInputStream = FreeListRef!LimitedInputStream(m_client.topStream, to!ulong(*pcl));
			m_bodyReader = m_limitedInputStream;
		} else if (!isHTTP2) {
			m_limitedInputStream = FreeListRef!LimitedInputStream(m_client.topStream, 0);
			m_bodyReader = m_limitedInputStream;
		}

		bool handleCompression(string val) {
			if (icmp2(val, "deflate") == 0){
				m_deflateInputStream = FreeListRef!DeflateInputStream(m_bodyReader);
				m_bodyReader = m_deflateInputStream;
				return true;
			} else if (icmp2(val, "gzip") == 0){
				m_gzipInputStream = FreeListRef!GzipInputStream(m_bodyReader);
				m_bodyReader = m_gzipInputStream;
				return true;
			}
			return false;
		}

		if( auto pce = "Content-Encoding" in this.headers )
			if (!handleCompression(*pce))
				enforce(icmp2(*pce, "identity") == 0, "Unsuported Content-Encoding: "~*pce);

		// be sure to free resouces as soon as the response has been read
		m_endCallback = FreeListRef!EndCallbackInputStream(m_bodyReader, &this.finalize);
		m_bodyReader = m_endCallback;

		return m_bodyReader;
	}

	/**
		Provides unsafe means to read raw data from the connection.

		No transfer decoding and no content decoding is done on the data.

		Not that the provided delegate must read the whole stream,
		as the state of the response is unknown after raw bytes have been
		taken. Failure to read the right amount of data will lead to
		protocol corruption in later requests.
	*/
	void readRawBody(scope void delegate(scope InputStream stream) del)
	{
		assert(!m_bodyReader, "May not mix use of readRawBody and bodyReader.");
		del(m_client.topStream);
		finalize();
	}

	/**
		Reads the whole response body and tries to parse it as JSON.
	*/
	Json readJson(){
		auto bdy = bodyReader.readAllUTF8();
		return parseJson(bdy);
	}

	/**
		Reads and discards the response body.
	*/
	void dropBody()
	{
		if (!m_finalized && m_client) {
			if (bodyReader.empty) {
				finalize();
			} else {
				nullSink().write(bodyReader);
				assert(!lockedConnection.__conn);
			}
		}
	}

	/**
		Forcefully terminates the connection regardless of the current state.
		If a reason is used and this is an HTTP/2 stream, all HTTP/2 streams
		will be forcefully closed as well.

		Note that for HTTP/1.0 and HTTP/1.1,  this will only actually disconnect 
		if the request has not yet been fully processed. If the whole body was 
		already read, the connection is not owned by the current request operation 
		anymore and cannot be accessed. Use a "Connection: close" header instead 
		in this case to let the server close the connection.
	*/
	void disconnect(string reason = "")
	{
		if (m_client && m_client.isHTTP2Started)
			m_client.disconnect(false, reason);
		else finalize(false);
	}

	/**
		Switches the connection to a new protocol and returns the resulting ConnectionStream.

		The caller caller gets ownership of the ConnectionStream and is responsible
		for closing it.
		Params:
			newProtocol = The protocol to which the connection is expected to upgrade. Should match the Upgrade header of the request.
	*/
	ConnectionStream switchProtocol(in string newProtocol)
	{
		enforce(statusCode == HTTPStatus.switchingProtocols, "Server did not send a 101 - Switching Protocols response");
		string *resNewProto = "Upgrade" in headers;
		enforce(resNewProto, "Server did not send an Upgrade header");
		enforce(*resNewProto == newProtocol, "Expected Upgrade: " ~ newProtocol ~", received Upgrade: " ~ *resNewProto);
		if (auto cs = cast(ConnectionStream)m_client.topStream) return cs;
		return new ConnectionProxyStream(m_client.topStream, m_client.m_conn.tcp);
	}

	private void finalize()
	{
		finalize(m_keepAlive);
	}

	private void finalize(bool keepalive)
	{
		// ignore duplicate and too early calls to finalize
		// (too early happesn for empty response bodies)
		if (m_finalized) return;
		m_finalized = true;

		auto cli = m_client;
		cli.m_state.responding = false;
		destroy(m_deflateInputStream);
		destroy(m_gzipInputStream);
		destroy(m_chunkedInputStream);
		destroy(m_limitedInputStream);
		if (!keepalive && !cli.isHTTP2Started) cli.disconnect();
		destroy(m_endCallback);
		destroy(lockedConnection);
		if (auto alloc = cast(PoolAllocator) m_alloc)
			alloc.reset();
		m_alloc = null;
		m_keepAlive = false;
		m_maxRequests = int.max;
	}
}

private class HTTPClientConnection {
	string server;
	ushort port;
	bool forceTLS;
	TCPConnection tcp;
	TLSStream tlsStream;
	TLSContext tlsContext;
	Timer keepAlive;
	Duration nextTimeout; //keepalive
	int totRequest;
	int maxRequests = int.max;

	void rearmKeepAlive() {
		if (keepAlive is Timer.init) {
			logTrace("Keep-alive is init");
			return;
		}
		if (nextTimeout == Duration.zero) {
			logTrace("NextTimeout is zero");
			if (keepAlive.pending) {
				logTrace("Stopped timer");
				keepAlive.stop();
			}
			return;
		}
		logTrace("Rearming to: %s", nextTimeout);
		keepAlive.rearm(nextTimeout);
	}

	@property Duration keepAliveTimeout() { return nextTimeout; }

	@property void keepAliveTimeout(Duration timeout) {
		if (keepAlive is Timer.init) {
			logTrace("Keep-alive is init");
			return;
		}
		if (timeout != nextTimeout) {
			logTrace("Keep-alive from %s to %s", nextTimeout.total!"msecs", timeout.total!"msecs");
			nextTimeout = timeout;
		}
		if (Duration.zero == timeout) {
			logTrace("Got zero keep-alive timeout");
			if (keepAlive.pending) {
				logTrace("Stop keep-alive");
				keepAlive.stop();
			}
		}
		else {
			logTrace("Re-arming keep-alive to: %s", timeout.total!"msecs");
			keepAlive.rearm(timeout);
		}
	}
}

private class HTTP2ClientContext {
	int refcnt;
	HTTP2Session session;
	Task worker; // running the event loop async
	ConnectionPool!HTTPClient pool;

	/// true if peer was validated for HTTP/2 support
	bool isValidated; 
	/// true if peer has HTTP/2 support
	bool isSupported;
	/// true if upgrade is ongoing
	bool isUpgrading;
	/// true if the connection is going away, streams shouldn't open until reconnected
	bool closing;

	Duration latency;
	Timer pinger;
} 

private struct HTTPClientState {
	HTTP2Stream http2Stream;
	bool requesting;
	bool responding;
} 

// This object is a placeholder and should to never be modified.
private __gshared HTTPClientSettings defaultSettings = new HTTPClientSettings;
