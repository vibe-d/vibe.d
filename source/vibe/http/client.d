/**
	A simple HTTP/1.1 client implementation.

	Copyright: © 2012-2013 RejectedSoftware e.K.
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
import vibe.stream.ssl;
import vibe.stream.operations;
import vibe.stream.zlib;
import vibe.utils.array;
import vibe.utils.memory;

import core.exception : AssertError;
import std.array;
import std.conv;
import std.exception;
import std.format;
import std.string;
import std.typecons;
import std.datetime;
import std.uri;


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Performs a HTTP request on the specified URL.

	The requester parameter allows to customize the request and to specify the request body for
	non-GET requests before it is sent. A response object is then returned or passed to the
	responder callback synchronously.

	Note that it is highly recommended to use one of the overloads that take a responder callback,
	as they can avoid some memory allocations and are safe against accidentially leaving stale
	response objects (objects whose response body wasn't fully read). For the returning overloads
	of the function it is recommended to put a $(D scope(exit)) right after the call in which
	HTTPClientResponse.dropBody is called to avoid this.
*/
HTTPClientResponse requestHTTP(string url, scope void delegate(scope HTTPClientRequest req) requester = null)
{
	return requestHTTP(URL.parse(url), requester);
}
/// ditto
HTTPClientResponse requestHTTP(URL url, scope void delegate(scope HTTPClientRequest req) requester = null)
{
	enforce(url.schema == "http" || url.schema == "https", "URL schema must be http(s).");
	enforce(url.host.length > 0, "URL must contain a host name.");

	bool ssl = url.schema == "https";
	auto cli = connectHTTP(url.host, url.port, ssl);
	auto res = cli.request((req){
			req.requestURL = url.localURI;
			req.headers["Host"] = url.host;
			if( requester ) requester(req);
		});

	// make sure the connection stays locked if the body still needs to be read
	if( res.m_client ) res.lockedConnection = cli;

	logTrace("Returning HTTPClientResponse for conn %s", cast(void*)res.lockedConnection.__conn);
	return res;
}
/// ditto
void requestHTTP(string url, scope void delegate(scope HTTPClientRequest req) requester, scope void delegate(scope HTTPClientResponse req) responder)
{
	requestHTTP(URL(url), requester, responder);
}
/// ditto
void requestHTTP(URL url, scope void delegate(scope HTTPClientRequest req) requester, scope void delegate(scope HTTPClientResponse req) responder)
{
	enforce(url.schema == "http" || url.schema == "https", "URL schema must be http(s).");
	enforce(url.host.length > 0, "URL must contain a host name.");

	bool ssl = url.schema == "https";
	auto cli = connectHTTP(url.host, url.port, ssl);
	cli.request((scope req){
			req.requestURL = url.localURI;
			req.headers["Host"] = url.host;
			if( requester ) requester(req);
		}, responder);
}

/// Deprecated compatibility alias
deprecated("Please use requestHTTP instead.") alias requestHttp = requestHTTP;


/**
	Returns a HttpClient proxy object that is connected to the specified host.

	Internally, a connection pool is used to reuse already existing connections. Note that
	usually requestHTTP should be used for making requests instead of manually using a
	HTTPClient to do so.
*/
auto connectHTTP(string host, ushort port = 0, bool ssl = false)
{
	static struct ConnInfo { string host; ushort port; bool ssl; }
	static ConnectionPool!HTTPClient[ConnInfo] s_connections;
	if( port == 0 ) port = ssl ? 443 : 80;
	auto ckey = ConnInfo(host, port, ssl);

	ConnectionPool!HTTPClient pool;
	if( auto pcp = ckey in s_connections )
		pool = *pcp;
	else {
		pool = new ConnectionPool!HTTPClient({
				auto ret = new HTTPClient;
				ret.connect(host, port, ssl);
				return ret;
			});
		s_connections[ckey] = pool;
	}

	return pool.lockConnection();
}

/// Deprecated compatibility alias
deprecated("Please use connectHTTP instead.") alias connectHttp = connectHTTP;


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/**
	Implementation of a HTTP 1.0/1.1 client with keep-alive support.

	Note that it is usually recommended to use requestHTTP for making requests as that will use a
	pool of HTTPClient instances to keep the number of connection establishments low while not
	blocking requests from different tasks.
*/
class HTTPClient : EventedObject {
	enum maxHeaderLineLength = 4096;

	/// Deprecated compatibility alias
	deprecated("Please use maxHeaderLineLength instead.") enum maxHttpHeaderLineLength = maxHeaderLineLength;

	private {
		string m_server;
		ushort m_port;
		TCPConnection m_conn;
		Stream m_stream;
		SSLContext m_ssl;
		static __gshared m_userAgent = "vibe.d/"~VibeVersionString~" (HTTPClient, +http://vibed.org/)";
		bool m_requesting = false, m_responding = false;
		SysTime m_keepAliveLimit; 
		int m_timeout;
	}

	/**
		Sets the default user agent string for new HTTP requests.
	*/
	static void setUserAgentString(string str) { m_userAgent = str; }
	
	/**
		Connects to a specific server.

		This method may only be called if any previous connection has been closed.
	*/
	void connect(string server, ushort port = 80, bool ssl = false)
	{
		assert(m_conn is null);
		assert(port != 0);
		disconnect();
		m_conn = null;
		m_server = server;
		m_port = port;
		m_ssl = ssl ? new SSLContext() : null;
	}

	/**
		Forcefully closes the TCP connection.

		Before calling this method, be sure that no request is currently being processed.
	*/
	void disconnect()
	{
		if (m_conn) {
			if (m_conn.connected) {
				m_stream.finalize();
				m_conn.close();
			}
			if (m_stream !is m_conn) {
				destroy(m_stream);
				m_stream = null;
			}
			destroy(m_conn);
			m_conn = null;
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
		//auto request_allocator = scoped!PoolAllocator(1024, defaultAllocator());
		//scope(exit) request_allocator.reset();
		auto request_allocator = defaultAllocator();

		bool has_body = doRequest(requester);
		m_responding = true;
		auto res = scoped!HTTPClientResponse(this, has_body, request_allocator);
		scope(exit){
			res.dropBody();
			assert(!m_responding, "Still in responding state after dropping the response body!?");
			if (res.headers.get("Connection") == "close")
				disconnect();
		}
		responder(res);
	}
	/// ditto
	HTTPClientResponse request(scope void delegate(HTTPClientRequest) requester)
	{
		bool has_body = doRequest(requester);
		m_responding = true;
		return new HTTPClientResponse(this, has_body);
	}

	private bool doRequest(scope void delegate(HTTPClientRequest req) requester)
	{
		assert(!m_requesting && !m_responding, "Interleaved request detected!");
		m_requesting = true;
		scope(exit) m_requesting = false;

		auto now = Clock.currTime(UTC());

		if (now > m_keepAliveLimit){
			logDebug("Disconnected to avoid timeout");
			disconnect();
		}

		if( !m_conn || !m_conn.connected ){
			m_conn = connectTCP(m_server, m_port);
			m_stream = m_conn;
			if( m_ssl ) m_stream = new SSLStream(m_conn, m_ssl, SSLStreamState.connecting);

			now = Clock.currTime(UTC());
		}

		m_keepAliveLimit = now;

		auto req = scoped!HTTPClientRequest(m_stream, m_conn.localAddress);
		req.headers["User-Agent"] = m_userAgent;
		req.headers["Connection"] = "keep-alive";
		req.headers["Accept-Encoding"] = "gzip, deflate";
		req.headers["Host"] = m_server;
		requester(req);
		req.finalize();

		return req.method != HTTPMethod.HEAD;
	}
}

/// Deprecated compatibility alias
deprecated("Please use HTTPClient instead.") alias HttpClient = HTTPClient;


/**
	Represents a HTTP client request (as sent to the server).
*/
final class HTTPClientRequest : HTTPRequest {
	private {
		OutputStream m_bodyWriter;
		bool m_headerWritten = false;
		FixedAppender!(string, 22) m_contentLengthBuffer;
		NetworkAddress m_localAddress;
	}

	

	/// private
	this(Stream conn, NetworkAddress local_addr)
	{
		super(conn);
		m_localAddress = local_addr;
	}

	@property NetworkAddress localAddress() const { return m_localAddress; }

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
	void writeBody(ubyte[] data, string content_type = null)
	{
		if( content_type ) headers["Content-Type"] = content_type;
		headers["Content-Length"] = clengthString(data.length);
		bodyWriter.write(data);
		finalize();
	}

	/**
		Writes the response body as form data.
	*/
	void writeFormBody(in string[string] form)
	{
		auto formBody = appender!string();
		foreach(k, v; form) formBody.put("&" ~ encode(k) ~ "=" ~ encode(v));
		headers["Content-Type"] = "application/x-www-form-urlencoded";
		headers["Content-Length"] = clengthString(formBody.data.length - 1);
		bodyWriter.write(formBody.data[1..$]);
		finalize();
	}

	/**
		Writes the response body as JSON data.
	*/
	void writeJsonBody(T)(T data)
	{
		// TODO: avoid building up a string!
		writeBody(cast(ubyte[])serializeToJson(data).toString(), "application/json");
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
		if( m_bodyWriter ) return m_bodyWriter;
		assert(!m_headerWritten, "Trying to write request body after body was already written.");
		writeHeader();
		m_bodyWriter = m_conn;

		if( headers.get("Transfer-Encoding", null) == "chunked" )
			m_bodyWriter = new ChunkedOutputStream(m_bodyWriter);

		return m_bodyWriter;
	}

	private void writeHeader()
	{
		assert(!m_headerWritten, "HTTPClient tried to write headers twice.");
		m_headerWritten = true;

		auto app = appender!string();
		app.reserve(512);
		formattedWrite(app, "%s %s %s\r\n", httpMethodString(method), requestURL, getHTTPVersionString(httpVersion));
		logTrace("--------------------");
		logTrace("HTTP client request:");
		logTrace("--------------------");
		logTrace("%s %s %s", httpMethodString(method), requestURL, getHTTPVersionString(httpVersion));
		foreach( k, v; headers ){
			formattedWrite(app, "%s: %s\r\n", k, v);
			logTrace("%s: %s", k, v);
		}
		app.put("\r\n");
		m_conn.write(app.data);
		logTrace("--------------------");
	}

	private void finalize()
	{
		// test if already finalized
		if( m_headerWritten && !m_bodyWriter )
			return;

		// force the request to be sent
		if( !m_headerWritten ) bodyWriter();

		if( m_bodyWriter !is m_conn ) m_bodyWriter.finalize();
		else m_bodyWriter.flush();
		m_conn.flush();
		m_bodyWriter = null;
	}

	private string clengthString(ulong len)
	{
		m_contentLengthBuffer.clear();
		formattedWrite(&m_contentLengthBuffer, "%s", len);
		return m_contentLengthBuffer.data;
	}
}

/// Deprecated compatibility alias
deprecated("Please use HTTPClientRequest instead.") alias HttpClientRequest = HTTPClientRequest;


/**
	Represents a HTTP client response (as received from the server).
*/
final class HTTPClientResponse : HTTPResponse {
	private {
		__gshared Rebindable!(immutable(AssertError)) ms_staleResponseError;
		HTTPClient m_client;
		LockedConnection!HTTPClient lockedConnection;
		FreeListRef!LimitedInputStream m_limitedInputStream;
		FreeListRef!ChunkedInputStream m_chunkedInputStream;
		FreeListRef!GzipInputStream m_gzipInputStream;
		FreeListRef!DeflateInputStream m_deflateInputStream;
		FreeListRef!EndCallbackInputStream m_endCallback;
		InputStream m_bodyReader;
	}

	/// private
	this(HTTPClient client, bool has_body, shared(Allocator) alloc = defaultAllocator())
	{
		m_client = client;

		scope(failure) finalize();

		// read and parse status line ("HTTP/#.# #[ $]\r\n")
		logTrace("HTTP client reading status line");
		string stln = cast(string)client.m_stream.readLine(HTTPClient.maxHeaderLineLength, "\r\n", alloc);
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
		parseRFC5322Header(client.m_stream, this.headers, HTTPClient.maxHeaderLineLength, alloc);

		logTrace("---------------------");
		logTrace("HTTP client response:");
		logTrace("---------------------");
		logTrace("%s %s", getHTTPVersionString(this.httpVersion), this.statusCode);
		foreach (k, v; this.headers)
			logTrace("%s: %s", k, v);
		logTrace("---------------------");

		if (auto pka = "Keep-Alive" in headers) {
			foreach(s; split(*pka, ",")){
				auto pair = s.split("=");
				if (icmp(pair[0].strip(), "timeout")) {
					m_client.m_timeout = pair[1].to!int();
					break;
				}
			}
		}

		m_client.m_keepAliveLimit += dur!"seconds"(m_client.m_timeout - 2);

		if (!has_body) finalize();
	}

	~this()
	{
		if (m_client) throw ms_staleResponseError.get;
	}

	/**
		An input stream suitable for reading the response body.
	*/
	@property InputStream bodyReader()
	{
		if( m_bodyReader ) return m_bodyReader;

		assert (m_client, "Response was already read or no response body, may not use bodyReader.");

		// prepare body the reader
		if( auto pte = "Transfer-Encoding" in this.headers ){
			enforce(*pte == "chunked");
			m_chunkedInputStream = FreeListRef!ChunkedInputStream(m_client.m_stream);
			m_bodyReader = this.m_chunkedInputStream;
		} else if( auto pcl = "Content-Length" in this.headers ){
			m_limitedInputStream = FreeListRef!LimitedInputStream(m_client.m_stream, to!ulong(*pcl));
			m_bodyReader = m_limitedInputStream;
		} else {
			m_limitedInputStream = FreeListRef!LimitedInputStream(m_client.m_stream, 0);
			m_bodyReader = m_limitedInputStream;
		}

		if( auto pce = "Content-Encoding" in this.headers ){
			if( *pce == "deflate" ){
				m_deflateInputStream = FreeListRef!DeflateInputStream(m_bodyReader);
				m_bodyReader = m_deflateInputStream;
			} else if( *pce == "gzip" ){
				m_gzipInputStream = FreeListRef!GzipInputStream(m_bodyReader);
				m_bodyReader = m_gzipInputStream;
			}
			else enforce(false, "Unsuported content encoding: "~*pce);
		}

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
		del(m_client.m_stream);
		finalize();
	}

	/**
		Reads the whole response body and tries to parse it as JSON.
	*/
	Json readJson(){
		auto bdy = bodyReader.readAll();
		auto str = cast(string)bdy;
		return parseJson(str);
	}

	/**
		Reads and discards the response body.
	*/
	void dropBody()
	{
		if( m_client ){
			if( bodyReader.empty ){
				finalize();
			} else {
				s_sink.write(bodyReader);
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

	private void finalize()
	{
		finalize(false);
	}

	private void finalize(bool disconnect)
	{
		// ignore duplicate and too early calls to finalize
		// (too early happesn for empty response bodies)
		if (!m_client) return;

		auto cli = m_client;
		m_client = null;
		cli.m_responding = false;
		destroy(m_deflateInputStream);
		destroy(m_gzipInputStream);
		destroy(m_chunkedInputStream);
		destroy(m_limitedInputStream);
		if (disconnect) cli.disconnect();
		destroy(lockedConnection);
	}
}

/// Deprecated compatibility alias
deprecated("Please use HTTPClientResponse instead.") alias HttpClientResponse = HTTPClientResponse;


private NullOutputStream s_sink;

shared static this()
{
	HTTPClientResponse.ms_staleResponseError = cast(immutable)new AssertError("Stale HTTP response detected. Use .dropBody() or the scoped version of requestHTTP.");
}

static this()
{
	s_sink = new NullOutputStream;
}
