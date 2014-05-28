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
import vibe.stream.ssl;
import vibe.stream.operations;
import vibe.stream.zlib;
import vibe.utils.array;
import vibe.utils.memory;

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
			if (url.localURI.length)
				req.requestURL = url.localURI;
			req.headers["Host"] = url.host;
			if ("authorization" !in req.headers && url.username != "") {
				import std.base64;
				string pwstr = url.username ~ ":" ~ url.password;
				req.headers["Authorization"] = "Basic " ~ 
					cast(string)Base64.encode(cast(ubyte[])pwstr);
			}
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
			if (url.localURI.length)
				req.requestURL = url.localURI;
			req.headers["Host"] = url.host;
			if ("authorization" !in req.headers && url.username != "") {
				import std.base64;
				string pwstr = url.username ~ ":" ~ url.password;
				req.headers["Authorization"] = "Basic " ~ 
					cast(string)Base64.encode(cast(ubyte[])pwstr);
			}
			if( requester ) requester(req);
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
				req.writeJsonBody(["name": "My Name"]);
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
auto connectHTTP(string host, ushort port = 0, bool ssl = false)
{
	static struct ConnInfo { string host; ushort port; bool ssl; }
	static FixedRingBuffer!(Tuple!(ConnInfo, ConnectionPool!HTTPClient), 16) s_connections;
	if( port == 0 ) port = ssl ? 443 : 80;
	auto ckey = ConnInfo(host, port, ssl);

	ConnectionPool!HTTPClient pool;
	foreach (c; s_connections)
		if (c[0].host == host && c[0].port == port && c[0].ssl == ssl)
			pool = c[1];
	
	if (!pool) {
		logDebug("Create HTTP client pool %s:%s %s", host, port, ssl);
		pool = new ConnectionPool!HTTPClient({
				auto ret = new HTTPClient;
				ret.connect(host, port, ssl);
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
	Implementation of a HTTP 1.0/1.1 client with keep-alive support.

	Note that it is usually recommended to use requestHTTP for making requests as that will use a
	pool of HTTPClient instances to keep the number of connection establishments low while not
	blocking requests from different tasks.
*/
final class HTTPClient {
	enum maxHeaderLineLength = 4096;

	private {
		string m_server;
		ushort m_port;
		TCPConnection m_conn;
		Stream m_stream;
		SSLContext m_ssl;
		static __gshared m_userAgent = "vibe.d/"~VibeVersionString~" (HTTPClient, +http://vibed.org/)";
		static __gshared void function(SSLContext) ms_sslSetup;
		bool m_requesting = false, m_responding = false;
		SysTime m_keepAliveLimit; 
		int m_timeout;
	}

	/**
		Sets the default user agent string for new HTTP requests.
	*/
	static void setUserAgentString(string str) { m_userAgent = str; }

	/**
		Sets a callback that will be called for every SSL context that is created.

		Setting such a callback is useful for adjusting the validation parameters
		of the SSL context.
	*/
	static void setSSLSetupCallback(void function(SSLContext) func) { ms_sslSetup = func; }
	
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
		if (ssl) {
			m_ssl = createSSLContext(SSLContextKind.client);
			// this will be changed to trustedCert once a proper root CA store is available by default
			m_ssl.peerValidationMode = SSLPeerValidationMode.none;
			if (ms_sslSetup) ms_sslSetup(m_ssl);
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
		version (VibeManualMemoryManagement) {
			scope request_allocator = new PoolAllocator(1024, defaultAllocator());
			scope(exit) request_allocator.reset();
		} else auto request_allocator = defaultAllocator();

		bool close_conn = false;
		bool has_body = doRequest(requester, &close_conn);
		m_responding = true;
		auto res = scoped!HTTPClientResponse(this, has_body, close_conn, request_allocator);
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
			if (user_exception || m_responding) {
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
		bool close_conn = false;
		bool has_body = doRequest(requester, &close_conn);
		m_responding = true;
		return new HTTPClientResponse(this, has_body, close_conn);
	}

	private bool doRequest(scope void delegate(HTTPClientRequest req) requester, bool* close_conn)
	{
		assert(!m_requesting, "Interleaved HTTP client requests detected!");
		assert(!m_responding, "Interleaved HTTP client request/response detected!");

		m_requesting = true;
		scope(exit) m_requesting = false;

		auto now = Clock.currTime(UTC());

		if (now > m_keepAliveLimit){
			logDebug("Disconnected to avoid timeout");
			disconnect();
		}

		if (!m_conn || !m_conn.connected) {
			if (m_conn) m_conn.close(); // make sure all resources are freed
			m_conn = connectTCP(m_server, m_port);
			m_stream = m_conn;
			if (m_ssl) m_stream = createSSLStream(m_conn, m_ssl, SSLStreamState.connecting, m_server, m_conn.remoteAddress);

			now = Clock.currTime(UTC());
		}

		m_keepAliveLimit = now;

		auto req = scoped!HTTPClientRequest(m_stream, m_conn.localAddress);
		req.headers["User-Agent"] = m_userAgent;
		req.headers["Connection"] = "keep-alive";
		req.headers["Accept-Encoding"] = "gzip, deflate";
		req.headers["Host"] = m_server;
		requester(req);
		*close_conn = req.headers.get("Connection", "keep-alive") != "keep-alive";
		req.finalize();

		return req.method != HTTPMethod.HEAD;
	}
}


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
		Writes the response body as JSON data.
	*/
	void writeJsonBody(T)(T data)
	{
		headers["Transfer-Encoding"] = "chunked";
		headers["Content-Type"] = "application/json";
		serializeToJson(bodyWriter, data);
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
		import vibe.stream.wrapper;

		assert(!m_headerWritten, "HTTPClient tried to write headers twice.");
		m_headerWritten = true;

		auto output = StreamOutputRange(m_conn);

		formattedWrite(&output, "%s %s %s\r\n", httpMethodString(method), requestURL, getHTTPVersionString(httpVersion));
		logTrace("--------------------");
		logTrace("HTTP client request:");
		logTrace("--------------------");
		logTrace("%s", this);
		foreach( k, v; headers ){
			formattedWrite(&output, "%s: %s\r\n", k, v);
			logTrace("%s: %s", k, v);
		}
		output.put("\r\n");
		logTrace("--------------------");
	}

	private void finalize()
	{
		// test if already finalized
		if( m_headerWritten && !m_bodyWriter )
			return;

		// force the request to be sent
		if( !m_headerWritten ) bodyWriter();

		m_bodyWriter.flush();
		if (m_bodyWriter !is m_conn) {
			m_bodyWriter.finalize();
			m_conn.flush();
		}
		m_bodyWriter = null;
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
		FreeListRef!LimitedInputStream m_limitedInputStream;
		FreeListRef!ChunkedInputStream m_chunkedInputStream;
		FreeListRef!GzipInputStream m_gzipInputStream;
		FreeListRef!DeflateInputStream m_deflateInputStream;
		FreeListRef!EndCallbackInputStream m_endCallback;
		InputStream m_bodyReader;
		bool m_closeConn;
	}

	/// private
	this(HTTPClient client, bool has_body, bool close_conn, Allocator alloc = defaultAllocator())
	{
		m_client = client;
		m_closeConn = close_conn;

		scope(failure) finalize(true);

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
		parseRFC5322Header(client.m_stream, this.headers, HTTPClient.maxHeaderLineLength, alloc, false);

		logTrace("---------------------");
		logTrace("HTTP client response:");
		logTrace("---------------------");
		logTrace("%s", this);
		foreach (k, v; this.headers)
			logTrace("%s: %s", k, v);
		logTrace("---------------------");

		int max = 2;
		if (auto pka = "Keep-Alive" in this.headers) {
			foreach(s; splitter(*pka, ',')){
				auto pair = s.splitter('=');
				auto name = pair.front.strip();
				pair.popFront();
				if (icmp(name, "timeout") == 0) {
					m_client.m_timeout = pair.front.to!int();
				} else if (icmp(name, "max") == 0) {
					max = pair.front.to!int();
				}
			}
		}

		if (this.headers.get("Connection") == "close") {
			// do nothing, forcing disconnect() before next request
		} else if (m_client.m_timeout > 0 && max > 1) {
			m_client.m_keepAliveLimit += (m_client.m_timeout - 2).seconds;
		} else if (this.httpVersion == HTTPVersion.HTTP_1_1) {
			m_client.m_keepAliveLimit += 60.seconds;
		}

		if (!has_body) finalize();
	}

	~this()
	{
		debug if (m_client) assert(false);
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
		auto bdy = bodyReader.readAllUTF8();
		return parseJson(bdy);
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
		destroy(m_deflateInputStream);
		destroy(m_gzipInputStream);
		destroy(m_chunkedInputStream);
		destroy(m_limitedInputStream);
		if (disconnect) cli.disconnect();
		destroy(lockedConnection);
	}
}


private __gshared NullOutputStream s_sink;

shared static this()
{
	s_sink = new NullOutputStream;
}
