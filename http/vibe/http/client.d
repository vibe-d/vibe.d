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
import vibe.inet.message;
import vibe.inet.url;
import vibe.stream.counting;
import vibe.stream.tls;
import vibe.stream.operations;
import vibe.stream.wrapper : createConnectionProxyStream;
import vibe.stream.zlib;
import vibe.utils.array;
import vibe.internal.allocator;
import vibe.internal.freelistref;
import vibe.internal.interfaceproxy : InterfaceProxy, interfaceProxy;

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
import std.socket : AddressFamily;

version(Posix)
{
	version(VibeLibeventDriver)
	{
		version = UnixSocket;
	}
}


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/
@safe:

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
HTTPClientResponse requestHTTP(string url, scope void delegate(scope HTTPClientRequest req) requester = null, const(HTTPClientSettings) settings = defaultSettings)
{
	return requestHTTP(URL.parse(url), requester, settings);
}
/// ditto
HTTPClientResponse requestHTTP(URL url, scope void delegate(scope HTTPClientRequest req) requester = null, const(HTTPClientSettings) settings = defaultSettings)
{
	import std.algorithm.searching : canFind;

	version(UnixSocket) {
		enforce(url.schema == "http" || url.schema == "https" || url.schema == "http+unix" || url.schema == "https+unix", "URL schema must be http(s) or http(s)+unix.");
	} else {
		enforce(url.schema == "http" || url.schema == "https", "URL schema must be http(s).");
	}
	enforce(url.host.length > 0, "URL must contain a host name.");
	bool use_tls;

	if (settings.proxyURL.schema !is null)
		use_tls = settings.proxyURL.schema == "https";
	else
	{
		version(UnixSocket)
			use_tls = url.schema == "https" || url.schema == "https+unix";
		else
			use_tls = url.schema == "https";
	}

	auto cli = connectHTTP(url.getFilteredHost, url.port, use_tls, settings);
	auto res = cli.request((req){
		if (url.localURI.length) {
			assert(url.path.absolute, "Request URL path must be absolute.");
			req.requestURL = url.localURI;
		}
		if (settings.proxyURL.schema !is null)
			req.requestURL = url.toString(); // proxy exception to the URL representation

		// Provide port number when it is not the default one (RFC2616 section 14.23)
		// IPv6 addresses need to be put into brackets
		auto hoststr = url.host.canFind(':') ? "["~url.host~"]" : url.host;
		if (url.port && url.port != url.defaultPort)
			req.headers["Host"] = format("%s:%d", hoststr, url.port);
		else
			req.headers["Host"] = hoststr;

		if ("authorization" !in req.headers && url.username != "") {
			import std.base64;
			string pwstr = url.username ~ ":" ~ url.password;
			req.headers["Authorization"] = "Basic " ~
				cast(string)Base64.encode(cast(ubyte[])pwstr);
		}
		if (requester) requester(req);
	});

	// make sure the connection stays locked if the body still needs to be read
	if( res.m_client ) res.lockedConnection = cli;

	logTrace("Returning HTTPClientResponse for conn %s", () @trusted { return cast(void*)res.lockedConnection.__conn; } ());
	return res;
}
/// ditto
void requestHTTP(string url, scope void delegate(scope HTTPClientRequest req) requester, scope void delegate(scope HTTPClientResponse req) responder, const(HTTPClientSettings) settings = defaultSettings)
{
	requestHTTP(URL(url), requester, responder, settings);
}
/// ditto
void requestHTTP(URL url, scope void delegate(scope HTTPClientRequest req) requester, scope void delegate(scope HTTPClientResponse req) responder, const(HTTPClientSettings) settings = defaultSettings)
{
	version(UnixSocket) {
		enforce(url.schema == "http" || url.schema == "https" || url.schema == "http+unix" || url.schema == "https+unix", "URL schema must be http(s) or http(s)+unix.");
	} else {
		enforce(url.schema == "http" || url.schema == "https", "URL schema must be http(s).");
	}
	enforce(url.host.length > 0, "URL must contain a host name.");
	bool use_tls;

	if (settings.proxyURL.schema !is null)
		use_tls = settings.proxyURL.schema == "https";
	else
	{
		version(UnixSocket)
			use_tls = url.schema == "https" || url.schema == "https+unix";
		else
			use_tls = url.schema == "https";
	}

	auto cli = connectHTTP(url.getFilteredHost, url.port, use_tls, settings);
	cli.request((scope req) {
		if (url.localURI.length) {
			assert(url.path.absolute, "Request URL path must be absolute.");
			req.requestURL = url.localURI;
		}
		if (settings.proxyURL.schema !is null)
			req.requestURL = url.toString(); // proxy exception to the URL representation

		// Provide port number when it is not the default one (RFC2616 section 14.23)
		if (url.port && url.port != url.defaultPort)
			req.headers["Host"] = format("%s:%d", url.host, url.port);
		else
			req.headers["Host"] = url.host;

		if ("authorization" !in req.headers && url.username != "") {
			import std.base64;
			string pwstr = url.username ~ ":" ~ url.password;
			req.headers["Authorization"] = "Basic " ~
				cast(string)Base64.encode(cast(ubyte[])pwstr);
		}
		if (requester) requester(req);
	}, responder);
	assert(!cli.m_requesting, "HTTP client still requesting after return!?");
	assert(!cli.m_responding, "HTTP client still responding after return!?");
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
auto connectHTTP(string host, ushort port = 0, bool use_tls = false, const(HTTPClientSettings) settings = null)
{
	static struct ConnInfo { string host; ushort port; bool useTLS; string proxyIP; ushort proxyPort; NetworkAddress bind_addr; }
	static vibe.utils.array.FixedRingBuffer!(Tuple!(ConnInfo, ConnectionPool!HTTPClient), 16) s_connections;

	auto sttngs = settings ? settings : defaultSettings;

	if( port == 0 ) port = use_tls ? 443 : 80;
	auto ckey = ConnInfo(host, port, use_tls, sttngs.proxyURL.host, sttngs.proxyURL.port, sttngs.networkInterface);

	ConnectionPool!HTTPClient pool;
	s_connections.opApply((ref c) @safe {
		if (c[0] == ckey)
			pool = c[1];
		return 0;
	});

	if (!pool) {
		logDebug("Create HTTP client pool %s:%s %s proxy %s:%d", host, port, use_tls, sttngs.proxyURL.host, sttngs.proxyURL.port);
		pool = new ConnectionPool!HTTPClient({
				auto ret = new HTTPClient;
				ret.connect(host, port, use_tls, sttngs);
				return ret;
			});
		if (s_connections.full) s_connections.popFront();
		s_connections.put(tuple(ckey, pool));
	}

	return pool.lockConnection();
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/**
	Defines an HTTP/HTTPS proxy request or a connection timeout for an HTTPClient.
*/
class HTTPClientSettings {
	URL proxyURL;
	Duration defaultKeepAliveTimeout = 10.seconds;

	/// Forces a specific network interface to use for outgoing connections.
	NetworkAddress networkInterface = anyAddress;

	/// Can be used to force looking up IPv4/IPv6 addresses for host names.
	AddressFamily dnsAddressFamily = AddressFamily.UNSPEC;

	/** Allows to customize the TLS context before connecting to a server.

		Note that this overrides a callback set with `HTTPClient.setTLSContextSetup`.
	*/
	void delegate(TLSContext ctx) @safe nothrow tlsContextSetup;

	@property HTTPClientSettings dup()
	const @safe {
		auto ret = new HTTPClientSettings;
		ret.proxyURL = this.proxyURL;
		ret.networkInterface = this.networkInterface;
		ret.dnsAddressFamily = this.dnsAddressFamily;
		ret.tlsContextSetup = this.tlsContextSetup;
		return ret;
	}
}

///
unittest {
	void test() {

		HTTPClientSettings settings = new HTTPClientSettings;
		settings.proxyURL = URL.parse("http://proxyuser:proxypass@192.168.2.50:3128");
		settings.defaultKeepAliveTimeout = 0.seconds; // closes connection immediately after receiving the data.
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
	@safe:

	enum maxHeaderLineLength = 4096;

	private {
		Rebindable!(const(HTTPClientSettings)) m_settings;
		string m_server;
		ushort m_port;
		bool m_useTLS;
		TCPConnection m_conn;
		InterfaceProxy!Stream m_stream;
		TLSStream m_tlsStream;
		TLSContext m_tls;
		static __gshared m_userAgent = "vibe.d/"~vibeVersionString~" (HTTPClient, +http://vibed.org/)";
		static __gshared void function(TLSContext) ms_tlsSetup;
		bool m_requesting = false, m_responding = false;
		SysTime m_keepAliveLimit;
		Duration m_keepAliveTimeout;
	}

	/** Get the current settings for the HTTP client. **/
	@property const(HTTPClientSettings) settings() const {
		return m_settings;
	}

	/**
		Sets the default user agent string for new HTTP requests.
	*/
	static void setUserAgentString(string str) @trusted { m_userAgent = str; }

	/**
		Sets a callback that will be called for every TLS context that is created.

		Setting such a callback is useful for adjusting the validation parameters
		of the TLS context.
	*/
	static void setTLSSetupCallback(void function(TLSContext) @safe func) @trusted { ms_tlsSetup = func; }

	/**
		Connects to a specific server.

		This method may only be called if any previous connection has been closed.
	*/
	void connect(string server, ushort port = 80, bool use_tls = false, const(HTTPClientSettings) settings = defaultSettings)
	{
		assert(!m_conn);
		assert(port != 0);
		disconnect();
		m_conn = TCPConnection.init;
		m_settings = settings;
		m_keepAliveTimeout = settings.defaultKeepAliveTimeout;
		m_keepAliveLimit = Clock.currTime(UTC()) + m_keepAliveTimeout;
		m_server = server;
		m_port = port;
		m_useTLS = use_tls;
		if (use_tls) {
			m_tls = createTLSContext(TLSContextKind.client);
			// this will be changed to trustedCert once a proper root CA store is available by default
			m_tls.peerValidationMode = TLSPeerValidationMode.none;
			if (settings.tlsContextSetup) settings.tlsContextSetup(m_tls);
			else () @trusted { if (ms_tlsSetup) ms_tlsSetup(m_tls); } ();
		}
	}

	/**
		Forcefully closes the TCP connection.

		Before calling this method, be sure that no request is currently being processed.
	*/
	void disconnect()
	{
		if (m_conn) {
			if (m_conn.connected) {
				try m_stream.finalize();
				catch (Exception e) logDebug("Failed to finalize connection stream when closing HTTP client connection: %s", e.msg);
				m_conn.close();
			}
			if (m_useTLS) () @trusted { return destroy(m_stream); } ();
			m_stream = InterfaceProxy!Stream.init;
			() @trusted { return destroy(m_conn); } ();
			m_conn = TCPConnection.init;
		}
	}

	private void doProxyRequest(T, U)(ref T res, U requester, ref bool close_conn, ref bool has_body)
	@trusted { // scope new
		import std.conv : to;
		import vibe.internal.utilallocator: RegionListAllocator;
		version (VibeManualMemoryManagement)
			scope request_allocator = new RegionListAllocator!(shared(Mallocator), false)(1024, Mallocator.instance);
		else
			scope request_allocator = new RegionListAllocator!(shared(GCAllocator), true)(1024, GCAllocator.instance);

		res.dropBody();
		scope(failure)
			res.disconnect();
		if (res.statusCode != 407) {
			throw new HTTPStatusException(HTTPStatus.internalServerError, "Proxy returned Proxy-Authenticate without a 407 status code.");
		}

		// send the request again with the proxy authentication information if available
		if (m_settings.proxyURL.username is null) {
			throw new HTTPStatusException(HTTPStatus.proxyAuthenticationRequired, "Proxy Authentication Required.");
		}

		m_responding = false;
		close_conn = false;
		bool found_proxy_auth;

		foreach (string proxyAuth; res.headers.getAll("Proxy-Authenticate"))
		{
			if (proxyAuth.length >= "Basic".length && proxyAuth[0.."Basic".length] == "Basic")
			{
				found_proxy_auth = true;
				break;
			}
		}

		if (!found_proxy_auth)
		{
			throw new HTTPStatusException(HTTPStatus.notAcceptable, "The Proxy Server didn't allow Basic Authentication");
		}

		SysTime connected_time;
		has_body = doRequestWithRetry(requester, true, close_conn, connected_time);
		m_responding = true;

		static if (is(T == HTTPClientResponse))
			res = new HTTPClientResponse(this, has_body, close_conn, request_allocator, connected_time);
		else
			res = scoped!HTTPClientResponse(this, has_body, close_conn, request_allocator, connected_time);

		if (res.headers.get("Proxy-Authenticate", null) !is null){
			res.dropBody();
			throw new HTTPStatusException(HTTPStatus.ProxyAuthenticationRequired, "Proxy Authentication Failed.");
		}

	}

	/**
		Performs a HTTP request.

		`requester` is called first to populate the request with headers and the desired
		HTTP method and version. After a response has been received it is then passed
		to the caller which can in turn read the reponse body. Any part of the body
		that has not been processed will automatically be consumed and dropped.

		Note that the `requester` callback might be invoked multiple times in the event
		that a request has to be resent due to a connection failure.

		Also note that the second form of this method (returning a `HTTPClientResponse`) is
		not recommended to use as it may accidentially block a HTTP connection when
		only part of the response body was read and also requires a heap allocation
		for the response object. The callback based version on the other hand uses
		a stack allocation and guarantees that the request has been fully processed
		once it has returned.
	*/
	void request(scope void delegate(scope HTTPClientRequest req) requester, scope void delegate(scope HTTPClientResponse) responder)
	@trusted { // scope new
		import vibe.internal.utilallocator: RegionListAllocator;
		version (VibeManualMemoryManagement)
			scope request_allocator = new RegionListAllocator!(shared(Mallocator), false)(1024, Mallocator.instance);
		else
			scope request_allocator = new RegionListAllocator!(shared(GCAllocator), true)(1024, GCAllocator.instance);

		bool close_conn;
		SysTime connected_time;
		bool has_body = doRequestWithRetry(requester, false, close_conn, connected_time);

		m_responding = true;
		auto res = scoped!HTTPClientResponse(this, has_body, close_conn, request_allocator, connected_time);

		// proxy implementation
		if (res.headers.get("Proxy-Authenticate", null) !is null) {
			doProxyRequest(res, requester, close_conn, has_body);
		}

		Exception user_exception;
		{
			scope (failure) {
				m_responding = false;
				disconnect();
			}
			try responder(res);
			catch (Exception e) {
				logDebug("Error while handling response: %s", e.toString().sanitize());
				user_exception = e;
			}
			if (m_responding) {
				logDebug("Failed to handle the complete response of the server - disconnecting.");
				res.disconnect();
			}
			assert(!m_responding, "Still in responding state after finalizing the response!?");

			if (user_exception || res.headers.get("Connection") == "close")
				disconnect();
		}
		if (user_exception) throw user_exception;
	}

	/// ditto
	HTTPClientResponse request(scope void delegate(HTTPClientRequest) requester)
	{
		bool close_conn;
		SysTime connected_time;
		bool has_body = doRequestWithRetry(requester, false, close_conn, connected_time);
		m_responding = true;
		auto res = new HTTPClientResponse(this, has_body, close_conn, () @trusted { return vibeThreadAllocator(); } (), connected_time);

		// proxy implementation
		if (res.headers.get("Proxy-Authenticate", null) !is null) {
			doProxyRequest(res, requester, close_conn, has_body);
		}

		return res;
	}

	private bool doRequestWithRetry(scope void delegate(HTTPClientRequest req) requester, bool confirmed_proxy_auth /* basic only */, out bool close_conn, out SysTime connected_time)
	{
		if (m_conn && m_conn.connected && connected_time > m_keepAliveLimit){
			logDebug("Disconnected to avoid timeout");
			disconnect();
		}

		// check if this isn't the first request on a connection
		bool is_persistent_request = m_conn && m_conn.connected;

		// retry the request if the connection gets closed prematurely and this is a persistent request
		bool has_body;
		foreach (i; 0 .. is_persistent_request ? 2 : 1) {
		 	connected_time = Clock.currTime(UTC());

			close_conn = false;
			has_body = doRequest(requester, close_conn, false, connected_time);

			logTrace("HTTP client waiting for response");
			if (!m_stream.empty) break;

			enforce(i != 1, "Second attempt to send HTTP request failed.");
		}
		return has_body;
	}

	private bool doRequest(scope void delegate(HTTPClientRequest req) requester, ref bool close_conn, bool confirmed_proxy_auth = false /* basic only */, SysTime connected_time = Clock.currTime(UTC()))
	{
		assert(!m_requesting, "Interleaved HTTP client requests detected!");
		assert(!m_responding, "Interleaved HTTP client request/response detected!");

		m_requesting = true;
		scope(exit) m_requesting = false;

		if (!m_conn || !m_conn.connected) {
			if (m_conn) {
				m_conn.close(); // make sure all resources are freed
				m_conn = TCPConnection.init;
			}

			if (m_settings.proxyURL.host !is null){

				enum AddressType {
					IPv4,
					IPv6,
					Host
				}

				static AddressType getAddressType(string host){
					import std.regex : regex, Captures, Regex, matchFirst;

					static IPv4Regex = regex(`^\s*((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))\s*$`, ``);
					static IPv6Regex = regex(`^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*$`, ``);

					if (!matchFirst(host, IPv4Regex).empty)
					{
						return AddressType.IPv4;
					}
					else if (!matchFirst(host, IPv6Regex).empty)
					{
						return AddressType.IPv6;
					}
					else
					{
						return AddressType.Host;
					}
				}

				import std.functional : memoize;
				alias findAddressType = memoize!getAddressType;

				bool use_dns;
				if (() @trusted { return findAddressType(m_settings.proxyURL.host); } () == AddressType.Host)
				{
					use_dns = true;
				}

				NetworkAddress proxyAddr = resolveHost(m_settings.proxyURL.host, m_settings.dnsAddressFamily, use_dns);
				proxyAddr.port = m_settings.proxyURL.port;
				m_conn = connectTCP(proxyAddr, m_settings.networkInterface);
			}
			else {
				version(UnixSocket)
				{
					import core.sys.posix.sys.un;
					import core.sys.posix.sys.socket;
					import std.regex : regex, Captures, Regex, matchFirst, ctRegex;
					import core.stdc.string : strcpy;

					NetworkAddress addr;
					if (m_server[0] == '/')
					{
						addr.family = AF_UNIX;
						sockaddr_un* s = addr.sockAddrUnix();
						enforce(s.sun_path.length > m_server.length, "Unix sockets cannot have that long a name.");
						s.sun_family = AF_UNIX;
						() @trusted { strcpy(cast(char*)s.sun_path.ptr,m_server.toStringz()); } ();
					} else
					{
						addr = resolveHost(m_server, m_settings.dnsAddressFamily);
						addr.port = m_port;
					}
					m_conn = connectTCP(addr, m_settings.networkInterface);
				} else
				{
					auto addr = resolveHost(m_server, m_settings.dnsAddressFamily);
					addr.port = m_port;
					m_conn = connectTCP(addr, m_settings.networkInterface);
				}
			}

			m_stream = m_conn;
			if (m_useTLS) {
				try m_tlsStream = createTLSStream(m_conn, m_tls, TLSStreamState.connecting, m_server, m_conn.remoteAddress);
				catch (Exception e) {
					m_conn.close();
					m_conn = TCPConnection.init;
					throw e;
				}
				m_stream = m_tlsStream;
			}
		}

		return () @trusted { // scoped
			auto req = scoped!HTTPClientRequest(m_stream, m_conn);
			if (m_useTLS)
				req.m_peerCertificate = m_tlsStream.peerCertificate;

			req.headers["User-Agent"] = m_userAgent;
			if (m_settings.proxyURL.host !is null){
				req.headers["Proxy-Connection"] = "keep-alive";
				if (confirmed_proxy_auth)
				{
					import std.base64;
					ubyte[] user_pass = cast(ubyte[])(m_settings.proxyURL.username ~ ":" ~ m_settings.proxyURL.password);

					req.headers["Proxy-Authorization"] = "Basic " ~ cast(string) Base64.encode(user_pass);
				}
			}
			else {
				req.headers["Connection"] = "keep-alive";
			}
			req.headers["Accept-Encoding"] = "gzip, deflate";
			req.headers["Host"] = m_server;
			requester(req);

			if (req.httpVersion == HTTPVersion.HTTP_1_0)
				close_conn = true;
			else  if (m_settings.proxyURL.host !is null)
				close_conn = req.headers.get("Proxy-Connection", "keep-alive") != "keep-alive";
			else
				close_conn = req.headers.get("Connection", "keep-alive") != "keep-alive";

			req.finalize();

			return req.method != HTTPMethod.HEAD;
		} ();
	}
}


/**
	Represents a HTTP client request (as sent to the server).
*/
final class HTTPClientRequest : HTTPRequest {
	private {
		InterfaceProxy!OutputStream m_bodyWriter;
		FreeListRef!ChunkedOutputStream m_chunkedStream;
		bool m_headerWritten = false;
		FixedAppender!(string, 22) m_contentLengthBuffer;
		TCPConnection m_rawConn;
		TLSCertificateInformation m_peerCertificate;
	}


	/// private
	this(InterfaceProxy!Stream conn, TCPConnection raw_conn)
	{
		super(conn);
		m_rawConn = raw_conn;
	}

	@property NetworkAddress localAddress() const { return m_rawConn.localAddress; }
	@property NetworkAddress remoteAddress() const { return m_rawConn.remoteAddress; }

	@property ref inout(TLSCertificateInformation) peerCertificate() inout { return m_peerCertificate; }

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

	/**
		Writes the whole request body at once using raw bytes.
	*/
	void writeBody(RandomAccessStream data)
	{
		writeBody(data, data.size - data.tell());
	}
	/// ditto
	void writeBody(InputStream data)
	{
		headers["Transfer-Encoding"] = "chunked";
		data.pipe(bodyWriter);
		finalize();
	}
	/// ditto
	void writeBody(InputStream data, ulong length)
	{
		headers["Content-Length"] = clengthString(length);
		data.pipe(bodyWriter, length);
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
		Writes the request body as JSON data.
	*/
	void writeJsonBody(T)(T data, bool allow_chunked = false)
	{
		import vibe.stream.wrapper : streamOutputRange;

		headers["Content-Type"] = "application/json";

		// set an explicit content-length field if chunked encoding is not allowed
		if (!allow_chunked) {
			import vibe.internal.rangeutil;
			long length = 0;
			auto counter = () @trusted { return RangeCounter(&length); } ();
			() @trusted { serializeToJson(counter, data); } ();
			headers["Content-Length"] = clengthString(length);
		}

		auto rng = streamOutputRange!1024(bodyWriter);
		() @trusted { serializeToJson(&rng, data); } ();
		rng.flush();
		finalize();
	}

	/** Writes the request body as form data.
	*/
	void writeFormBody(T)(T key_value_map)
	{
		import vibe.inet.webform : formEncode;
		import vibe.stream.wrapper : streamOutputRange;

		import vibe.internal.rangeutil;
		long length = 0;
		auto counter = () @trusted { return RangeCounter(&length); } ();
		counter.formEncode(key_value_map);
		headers["Content-Length"] = clengthString(length);
		headers["Content-Type"] = "application/x-www-form-urlencoded";
		auto dst = streamOutputRange!1024(bodyWriter);
		() @trusted { return &dst; } ().formEncode(key_value_map);
	}

	///
	unittest {
		void test(HTTPClientRequest req) {
			req.writeFormBody(["foo": "bar"]);
		}
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
	@property InterfaceProxy!OutputStream bodyWriter()
	{
		if (m_bodyWriter) return m_bodyWriter;

		assert(!m_headerWritten, "Trying to write request body after body was already written.");

		if ("Content-Length" !in headers && "Transfer-Encoding" !in headers
			&& headers.get("Connection", "") != "close")
		{
			headers["Transfer-Encoding"] = "chunked";
		}

		writeHeader();
		m_bodyWriter = m_conn;

		if (headers.get("Transfer-Encoding", null) == "chunked") {
			m_chunkedStream = createChunkedOutputStreamFL(m_bodyWriter);
			m_bodyWriter = m_chunkedStream;
		}

		return m_bodyWriter;
	}

	private void writeHeader()
	{
		import vibe.stream.wrapper;

		assert(!m_headerWritten, "HTTPClient tried to write headers twice.");
		m_headerWritten = true;

		auto output = streamOutputRange!1024(m_conn);

		formattedWrite(() @trusted { return &output; } (), "%s %s %s\r\n", httpMethodString(method), requestURL, getHTTPVersionString(httpVersion));
		logTrace("--------------------");
		logTrace("HTTP client request:");
		logTrace("--------------------");
		logTrace("%s", this);
		foreach (k, v; headers) {
			() @trusted { formattedWrite(&output, "%s: %s\r\n", k, v); } ();
			logTrace("%s: %s", k, v);
		}
		output.put("\r\n");
		logTrace("--------------------");
	}

	private void finalize()
	{
		// test if already finalized
		if (m_headerWritten && !m_bodyWriter)
			return;

		// force the request to be sent
		if (!m_headerWritten) writeHeader();
		else {
			bodyWriter.flush();
			if (m_chunkedStream) {
				m_bodyWriter.finalize();
				m_conn.flush();
			}
			m_bodyWriter = typeof(m_bodyWriter).init;
			m_conn = typeof(m_conn).init;
		}
	}

	private string clengthString(ulong len)
	{
		m_contentLengthBuffer.clear();
		() @trusted { formattedWrite(&m_contentLengthBuffer, "%s", len); } ();
		return () @trusted { return m_contentLengthBuffer.data; } ();
	}
}


/**
	Represents a HTTP client response (as received from the server).
*/
final class HTTPClientResponse : HTTPResponse {
	@safe:

	private {
		HTTPClient m_client;
		LockedConnection!HTTPClient lockedConnection;
		FreeListRef!LimitedInputStream m_limitedInputStream;
		FreeListRef!ChunkedInputStream m_chunkedInputStream;
		FreeListRef!ZlibInputStream m_zlibInputStream;
		FreeListRef!EndCallbackInputStream m_endCallback;
		InterfaceProxy!InputStream m_bodyReader;
		bool m_closeConn;
		int m_maxRequests;
	}

	/// Contains the keep-alive 'max' parameter, indicates how many requests a client can
	/// make before the server closes the connection.
	@property int maxRequests() const {
		return m_maxRequests;
	}

	/// private
	this(HTTPClient client, bool has_body, bool close_conn, IAllocator alloc, SysTime connected_time = Clock.currTime(UTC()))
	{
		m_client = client;
		m_closeConn = close_conn;

		scope(failure) finalize(true);

		// read and parse status line ("HTTP/#.# #[ $]\r\n")
		logTrace("HTTP client reading status line");
		string stln = () @trusted { return cast(string)client.m_stream.readLine(HTTPClient.maxHeaderLineLength, "\r\n", alloc); } ();
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
		parseRFC5322Header(client.m_stream, this.headers, HTTPClient.maxHeaderLineLength, alloc, false);

		logTrace("---------------------");
		logTrace("HTTP client response:");
		logTrace("---------------------");
		logTrace("%s", this);
		foreach (k, v; this.headers)
			logTrace("%s: %s", k, v);
		logTrace("---------------------");

		Duration server_timeout;
		bool has_server_timeout;
		if (auto pka = "Keep-Alive" in this.headers) {
			foreach(s; splitter(*pka, ',')){
				auto pair = s.splitter('=');
				auto name = pair.front.strip();
				pair.popFront();
				if (icmp(name, "timeout") == 0) {
					has_server_timeout = true;
					server_timeout = pair.front.to!int().seconds;
				} else if (icmp(name, "max") == 0) {
					m_maxRequests = pair.front.to!int();
				}
			}
		}
		Duration elapsed = Clock.currTime(UTC()) - connected_time;
		if (this.headers.get("Connection") == "close") {
			// this header will trigger m_client.disconnect() in m_client.doRequest() when it goes out of scope
		} else if (has_server_timeout && m_client.m_keepAliveTimeout > server_timeout) {
			m_client.m_keepAliveLimit = Clock.currTime(UTC()) + server_timeout - elapsed;
		} else if (this.httpVersion == HTTPVersion.HTTP_1_1) {
			m_client.m_keepAliveLimit = Clock.currTime(UTC()) + m_client.m_keepAliveTimeout;
		}

		if (!has_body) finalize();
	}

	~this()
	{
		debug if (m_client) { import std.stdio; writefln("WARNING: HTTPClientResponse not fully processed before being finalized"); }
	}

	/**
		An input stream suitable for reading the response body.
	*/
	@property InterfaceProxy!InputStream bodyReader()
	{
		if( m_bodyReader ) return m_bodyReader;

		assert (m_client, "Response was already read or no response body, may not use bodyReader.");

		// prepare body the reader
		if (auto pte = "Transfer-Encoding" in this.headers) {
			enforce(*pte == "chunked");
			m_chunkedInputStream = createChunkedInputStreamFL(m_client.m_stream);
			m_bodyReader = this.m_chunkedInputStream;
		} else if (auto pcl = "Content-Length" in this.headers) {
			m_limitedInputStream = createLimitedInputStreamFL(m_client.m_stream, to!ulong(*pcl));
			m_bodyReader = m_limitedInputStream;
		} else if (isKeepAliveResponse) {
			m_limitedInputStream = createLimitedInputStreamFL(m_client.m_stream, 0);
			m_bodyReader = m_limitedInputStream;
		} else {
			m_bodyReader = m_client.m_stream;
		}

		if( auto pce = "Content-Encoding" in this.headers ){
			if( *pce == "deflate" ){
				m_zlibInputStream = createDeflateInputStreamFL(m_bodyReader);
				m_bodyReader = m_zlibInputStream;
			} else if( *pce == "gzip" || *pce == "x-gzip"){
				m_zlibInputStream = createGzipInputStreamFL(m_bodyReader);
				m_bodyReader = m_zlibInputStream;
			}
			else enforce(*pce == "identity" || *pce == "", "Unsuported content encoding: "~*pce);
		}

		// be sure to free resouces as soon as the response has been read
		m_endCallback = createEndCallbackInputStreamFL(m_bodyReader, &this.finalize);
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
	void readRawBody(scope void delegate(scope InterfaceProxy!InputStream stream) @safe del)
	{
		assert(!m_bodyReader, "May not mix use of readRawBody and bodyReader.");
		del(interfaceProxy!InputStream(m_client.m_stream));
		finalize();
	}
	/// ditto
	static if (!is(InputStream == InterfaceProxy!InputStream))
	void readRawBody(scope void delegate(scope InputStream stream) @safe del)
	{
		import vibe.internal.interfaceproxy : asInterface;

		assert(!m_bodyReader, "May not mix use of readRawBody and bodyReader.");
		del(m_client.m_stream.asInterface!(.InputStream));
		finalize();
	}

	/**
		Reads the whole response body and tries to parse it as JSON.
	*/
	Json readJson(){
		auto bdy = bodyReader.readAllUTF8();
		return () @trusted { return parseJson(bdy); } ();
	}

	/**
		Reads and discards the response body.
	*/
	void dropBody()
	{
		if (m_client) {
			if( bodyReader.empty ){
				finalize();
			} else {
				bodyReader.pipe(nullSink);
				assert(!lockedConnection.__conn);
			}
		}
	}

	/**
		Forcefully terminates the connection regardless of the current state.

		Note that this will only actually disconnect if the request has not yet
		been fully processed. If the whole body was already read, the
		connection is not owned by the current request operation anymore and
		cannot be accessed. Use a "Connection: close" header instead in this
		case to let the server close the connection.
	*/
	void disconnect()
	{
		finalize(true);
	}

	/**
		Switches the connection to a new protocol and returns the resulting ConnectionStream.

		The caller caller gets ownership of the ConnectionStream and is responsible
		for closing it.

		Notice:
			When using the overload that returns a `ConnectionStream`, the caller
			must make sure that the stream is not used after the
			`HTTPClientRequest` has been destroyed.

		Params:
			new_protocol = The protocol to which the connection is expected to
				upgrade. Should match the Upgrade header of the request. If an
				empty string is passed, the "Upgrade" header will be ignored and
				should be checked by other means.
	*/
	ConnectionStream switchProtocol(string new_protocol)
	{
		enforce(statusCode == HTTPStatus.switchingProtocols, "Server did not send a 101 - Switching Protocols response");
		string *resNewProto = "Upgrade" in headers;
		enforce(resNewProto, "Server did not send an Upgrade header");
		enforce(!new_protocol.length || !icmp(*resNewProto, new_protocol),
			"Expected Upgrade: " ~ new_protocol ~", received Upgrade: " ~ *resNewProto);
		auto stream = createConnectionProxyStream!(typeof(m_client.m_stream), typeof(m_client.m_conn))(m_client.m_stream, m_client.m_conn);
		m_closeConn = true; // cannot reuse connection for further requests!
		return stream;
	}
	/// ditto
	void switchProtocol(string new_protocol, scope void delegate(ConnectionStream str) @safe del)
	{
		enforce(statusCode == HTTPStatus.switchingProtocols, "Server did not send a 101 - Switching Protocols response");
		string *resNewProto = "Upgrade" in headers;
		enforce(resNewProto, "Server did not send an Upgrade header");
		enforce(!new_protocol.length || !icmp(*resNewProto, new_protocol),
			"Expected Upgrade: " ~ new_protocol ~", received Upgrade: " ~ *resNewProto);
		auto stream = createConnectionProxyStream(m_client.m_stream, m_client.m_conn);
		scope (exit) () @trusted { destroy(stream); } ();
		m_closeConn = true;
		del(stream);
	}

	private @property isKeepAliveResponse()
	const {
		string conn;
		if (this.httpVersion == HTTPVersion.HTTP_1_0) {
			// Workaround for non-standard-conformant servers - for example see #1780
			auto pcl = "Content-Length" in this.headers;
			if (pcl) conn = this.headers.get("Connection", "close");
			else return false; // can't use keepalive when no content length is set
		}
		else conn = this.headers.get("Connection", "keep-alive");
		return icmp(conn, "close") != 0;
	}

	private void finalize()
	{
		finalize(m_closeConn);
	}

	private void finalize(bool disconnect)
	{
		// ignore duplicate and too early calls to finalize
		// (too early happesn for empty response bodies)
		if (!m_client) return;

		auto cli = m_client;
		m_client = null;
		cli.m_responding = false;
		destroy(m_zlibInputStream);
		destroy(m_chunkedInputStream);
		destroy(m_limitedInputStream);
		if (disconnect) cli.disconnect();
		destroy(lockedConnection);
	}
}

/** Returns clean host string. In case of unix socket it performs urlDecode on host. */
package auto getFilteredHost(URL url)
{
	version(UnixSocket)
	{
		import vibe.textfilter.urlencode : urlDecode;
		if (url.schema == "https+unix" || url.schema == "http+unix")
			return urlDecode(url.host);
		else
			return url.host;
	} else
		return url.host;
}

// This object is a placeholder and should to never be modified.
package @property const(HTTPClientSettings) defaultSettings()
@trusted {
	__gshared HTTPClientSettings ret = new HTTPClientSettings;
	return ret;
}
