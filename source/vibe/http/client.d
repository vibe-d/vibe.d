/**
	A simple HTTP/1.1 client implementation.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.client;

public import vibe.core.net;
public import vibe.http.common;

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

import std.array;
import std.conv;
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

	The 'requester' parameter allows to customize the request and to specify the request body for
	non-GET requests.
*/
HttpClientResponse requestHttp(string url, scope void delegate(scope HttpClientRequest req) requester = null)
{
	return requestHttp(Url.parse(url), requester);
}
/// ditto
HttpClientResponse requestHttp(Url url, scope void delegate(scope HttpClientRequest req) requester = null)
{
	enforce(url.schema == "http" || url.schema == "https", "Url schema must be http(s).");
	enforce(url.host.length > 0, "Url must contain a host name.");

	bool ssl = url.schema == "https";
	auto cli = connectHttp(url.host, url.port, ssl);
	auto res = cli.request((req){
			req.requestUrl = url.localURI;
			req.headers["Host"] = url.host;
			if( requester ) requester(req);
		});

	// make sure the connection stays locked if the body still needs to be read
	if( res.m_client ) res.lockedConnection = cli;

	logTrace("Returning HttpClientResponse for conn %s", cast(void*)res.lockedConnection.__conn);
	return res;
}
/// ditto
void requestHttp(string url, scope void delegate(scope HttpClientRequest req) requester, scope void delegate(scope HttpClientResponse req) responder)
{
	requestHttp(Url(url), requester, responder);
}
/// ditto
void requestHttp(Url url, scope void delegate(scope HttpClientRequest req) requester, scope void delegate(scope HttpClientResponse req) responder)
{
	enforce(url.schema == "http" || url.schema == "https", "Url schema must be http(s).");
	enforce(url.host.length > 0, "Url must contain a host name.");

	bool ssl = url.schema == "https";
	auto cli = connectHttp(url.host, url.port, ssl);
	cli.request((scope req){
			req.requestUrl = url.localURI;
			req.headers["Host"] = url.host;
			if( requester ) requester(req);
		}, responder);
}


/**
	Returns a HttpClient proxy that is connected to the specified host.

	Internally, a connection pool is used to reuse already existing connections.
*/
auto connectHttp(string host, ushort port = 0, bool ssl = false)
{
	static struct ConnInfo { string host; ushort port; bool ssl; }
	static ConnectionPool!HttpClient[ConnInfo] s_connections;
	if( port == 0 ) port = ssl ? 443 : 80;
	auto ckey = ConnInfo(host, port, ssl);

	ConnectionPool!HttpClient pool;
	if( auto pcp = ckey in s_connections )
		pool = *pcp;
	else {
		pool = new ConnectionPool!HttpClient({
				auto ret = new HttpClient;
				ret.connect(host, port, ssl);
				return ret;
			});
		s_connections[ckey] = pool;
	}

	return pool.lockConnection();
}


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

class HttpClient : EventedObject {
	enum maxHttpHeaderLineLength = 4096;
	deprecated enum MaxHttpHeaderLineLength = maxHttpHeaderLineLength;

	private {
		string m_server;
		ushort m_port;
		TcpConnection m_conn;
		Stream m_stream;
		SslContext m_ssl;
		static __gshared m_userAgent = "vibe.d/"~VibeVersionString~" (HttpClient, +http://vibed.org/)";
		bool m_requesting = false, m_responding = false;
		SysTime m_keepAliveLimit; 
		int m_timeout;
	}

	static void setUserAgentString(string str) { m_userAgent = str; }
	
	void acquire() { if( m_conn && m_conn.connected) m_conn.acquire(); }
	void release() { if( m_conn && m_conn.connected ) m_conn.release(); }
	bool isOwner() { return m_conn ? m_conn.isOwner() : true; }

	void connect(string server, ushort port = 80, bool ssl = false)
	{
		assert(port != 0);
		m_conn = null;
		m_server = server;
		m_port = port;
		m_ssl = ssl ? new SslContext() : null;
	}

	void disconnect()
	{
		if( m_conn){
			if (m_conn.connected){
				m_stream.finalize();
				m_conn.close();
			}
			if (m_stream !is m_conn){
				destroy(m_stream);
				m_stream = null;
			}
			destroy(m_conn);
			m_conn = null;
		}
	}

	void request(scope void delegate(scope HttpClientRequest req) requester, scope void delegate(scope HttpClientResponse) responder)
	{
		//auto request_allocator = scoped!PoolAllocator(1024, defaultAllocator());
		//scope(exit) request_allocator.reset();
		auto request_allocator = defaultAllocator();

		bool has_body = doRequest(requester);
		m_responding = true;
		auto res = scoped!HttpClientResponse(this, has_body, request_allocator);
		scope(exit){
			res.dropBody();
			assert(!m_responding, "Still in responding state after dropping the response body!?");
			if (res.headers.get("Connection") == "close")
				disconnect();
		}
		responder(res);
	}

	HttpClientResponse request(scope void delegate(HttpClientRequest) requester)
	{
		bool has_body = doRequest(requester);
		m_responding = true;
		return new HttpClientResponse(this, has_body);
	}

	private bool doRequest(scope void delegate(HttpClientRequest req) requester)
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
			m_conn = connectTcp(m_server, m_port);
			m_stream = m_conn;
			if( m_ssl ) m_stream = new SslStream(m_conn, m_ssl, SslStreamState.Connecting);

			now = Clock.currTime(UTC());
		}

		m_keepAliveLimit = now;

		auto req = scoped!HttpClientRequest(m_stream);
		req.headers["User-Agent"] = m_userAgent;
		req.headers["Connection"] = "keep-alive";
		req.headers["Accept-Encoding"] = "gzip, deflate";
		req.headers["Host"] = m_server;
		requester(req);
		req.finalize();

		return req.method != HttpMethod.HEAD;
	}
}

final class HttpClientRequest : HttpRequest {
	private {
		OutputStream m_bodyWriter;
		bool m_headerWritten = false;
		FixedAppender!(string, 22) m_contentLengthBuffer;
	}

	/// private
	this(Stream conn)
	{
		super(conn);
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
		Writes the response body as form data.
	*/
	void writeFormBody(in string[string] form)
	{
		assert(false, "TODO");
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
		assert(!m_headerWritten, "HttpClient tried to write headers twice.");
		m_headerWritten = true;

		auto app = appender!string();
		app.reserve(512);
		formattedWrite(app, "%s %s %s\r\n", httpMethodString(method), requestUrl, getHttpVersionString(httpVersion));
		logTrace("--------------------");
		logTrace("HTTP client request:");
		logTrace("--------------------");
		logTrace("%s %s %s", httpMethodString(method), requestUrl, getHttpVersionString(httpVersion));
		foreach( k, v; headers ){
			formattedWrite(app, "%s: %s\r\n", k, v);
			logTrace("%s: %s", k, v);
		}
		app.put("\r\n");
		m_conn.write(app.data, false);
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

final class HttpClientResponse : HttpResponse {
	private {
		HttpClient m_client;
		LockedConnection!HttpClient lockedConnection;
		FreeListRef!LimitedInputStream m_limitedInputStream;
		FreeListRef!ChunkedInputStream m_chunkedInputStream;
		FreeListRef!GzipInputStream m_gzipInputStream;
		FreeListRef!DeflateInputStream m_deflateInputStream;
		FreeListRef!EndCallbackInputStream m_endCallback;
		InputStream m_bodyReader;
	}

	/// private
	this(HttpClient client, bool has_body, Allocator alloc = defaultAllocator())
	{
		m_client = client;

		scope(failure) finalize();

		// read and parse status line ("HTTP/#.# #[ $]\r\n")
		logTrace("HTTP client reading status line");
		string stln = cast(string)client.m_stream.readLine(HttpClient.maxHttpHeaderLineLength, "\r\n", alloc);
		logTrace("stln: %s", stln);
		this.httpVersion = parseHttpVersion(stln);
		enforce(stln.startsWith(" "));
		stln = stln[1 .. $];
		this.statusCode = parse!int(stln);
		if( stln.length > 0 ){
			enforce(stln.startsWith(" "));
			stln = stln[1 .. $];
			this.statusPhrase = stln;
		}
		
		// read headers until an empty line is hit
		parseRfc5322Header(client.m_stream, this.headers, HttpClient.maxHttpHeaderLineLength, alloc);

		logTrace("---------------------");
		logTrace("HTTP client response:");
		logTrace("---------------------");
		logTrace("%s %s", getHttpVersionString(this.httpVersion), this.statusCode);
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
		assert (!m_client, "Stale HTTP response is finalized!");
		if( m_client ){
			logDebug("Warning: dropping unread body.");
			dropBody();
		}
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
		Provides an unsafe maeans to read raw data from the connection.

		No transfer decoding and no content decoding is done on the data.

		Not that the provided delegate is required to consume the whole stream,
		as the state of the response is unknown after raw bytes have been
		taken.
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

	private void finalize()
	{
		// ignore duplicate and too early calls to finalize
		// (too early happesn for empty response bodies)
		if( !m_client ) return;
		m_client.m_responding = false;
		m_client = null;
		destroy(m_deflateInputStream);
		destroy(m_gzipInputStream);
		destroy(m_chunkedInputStream);
		destroy(m_limitedInputStream);
		destroy(lockedConnection);
	}
}

private NullOutputStream s_sink;

static this() { s_sink = new NullOutputStream; }