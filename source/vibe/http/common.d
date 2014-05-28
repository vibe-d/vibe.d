/**
	Common classes for HTTP clients and servers.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.common;

public import vibe.http.status;

import vibe.core.log;
import vibe.core.net;
import vibe.inet.message;
import vibe.stream.operations;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.string;
import std.typecons;


enum HTTPVersion {
	HTTP_1_0,
	HTTP_1_1
}


enum HTTPMethod {
	// HTTP standard
	GET,
	HEAD,
	PUT,
	POST,
	PATCH,
	DELETE,
	OPTIONS,
	TRACE,
	CONNECT,
	
	// WEBDAV extensions
	COPY,
	LOCK,
	MKCOL,
	MOVE,
	PROPFIND,
	PROPPATCH,
	UNLOCK
}


/**
	Returns the string representation of the given HttpMethod.
*/
string httpMethodString(HTTPMethod m)
{
	return to!string(m);
}

/**
	Returns the HttpMethod value matching the given HTTP method string.
*/
HTTPMethod httpMethodFromString(string str)
{
	switch(str){
		default: throw new Exception("Invalid HTTP method: "~str);
		case "GET": return HTTPMethod.GET;
		case "HEAD": return HTTPMethod.HEAD;
		case "PUT": return HTTPMethod.PUT;
		case "POST": return HTTPMethod.POST;
		case "PATCH": return HTTPMethod.PATCH;
		case "DELETE": return HTTPMethod.DELETE;
		case "OPTIONS": return HTTPMethod.OPTIONS;
		case "TRACE": return HTTPMethod.TRACE;
		case "CONNECT": return HTTPMethod.CONNECT;
		case "COPY": return HTTPMethod.COPY;
		case "LOCK": return HTTPMethod.LOCK;
		case "MKCOL": return HTTPMethod.MKCOL;
		case "MOVE": return HTTPMethod.MOVE;
		case "PROPFIND": return HTTPMethod.PROPFIND;
		case "PROPPATCH": return HTTPMethod.PROPPATCH;
		case "UNLOCK": return HTTPMethod.UNLOCK;
	}
}

unittest 
{
	assert(httpMethodString(HTTPMethod.GET) == "GET");
	assert(httpMethodString(HTTPMethod.UNLOCK) == "UNLOCK");
	assert(httpMethodFromString("GET") == HTTPMethod.GET);
	assert(httpMethodFromString("UNLOCK") == HTTPMethod.UNLOCK);
}


/**
	Utility function that throws a HTTPStatusException if the _condition is not met.
*/
void enforceHTTP(T)(T condition, HTTPStatus statusCode, string message = null)
{
	enforce(condition, new HTTPStatusException(statusCode, message));
}


/**
	Represents an HTTP request made to a server.
*/
class HTTPRequest {
	protected {
		Stream m_conn;
	}
	
	public {
		/// The HTTP protocol version used for the request
		HTTPVersion httpVersion = HTTPVersion.HTTP_1_1;

		/// The HTTP _method of the request
		HTTPMethod method = HTTPMethod.GET;

		/** The request URL

			Note that the request URL usually does not include the global
			'http://server' part, but only the local path and a query string.
			A possible exception is a proxy server, which will get full URLs.
		*/
		string requestURL = "/";

		/// All request _headers
		InetHeaderMap headers;
	}
	
	protected this(Stream conn)
	{
		m_conn = conn;
	}
	
	protected this()
	{
	}

	public override string toString()
	{
		return httpMethodString(method) ~ " " ~ requestURL ~ " " ~ getHTTPVersionString(httpVersion);
	}

	/** Shortcut to the 'Host' header (always present for HTTP 1.1)
	*/
	@property string host() const { auto ph = "Host" in headers; return ph ? *ph : null; }
	/// ditto
	@property void host(string v) { headers["Host"] = v; }

	/** Returns the mime type part of the 'Content-Type' header.

		This function gets the pure mime type (e.g. "text/plain")
		without any supplimentary parameters such as "charset=...".
		Use contentTypeParameters to get any parameter string or
		headers["Content-Type"] to get the raw value.
	*/
	@property string contentType()
	const {
		auto pv = "Content-Type" in headers;
		if( !pv ) return null;
		auto idx = std.string.indexOf(*pv, ';');
		return idx >= 0 ? (*pv)[0 .. idx] : *pv;
	}
	/// ditto
	@property void contentType(string ct) { headers["Content-Type"] = ct; }

	/** Returns any supplementary parameters of the 'Content-Type' header.

		This is a semicolon separated ist of key/value pairs. Usually, if set,
		this contains the character set used for text based content types.
	*/
	@property string contentTypeParameters()
	const {
		auto pv = "Content-Type" in headers;
		if( !pv ) return null;
		auto idx = std.string.indexOf(*pv, ';');
		return idx >= 0 ? (*pv)[idx+1 .. $] : null;
	}

	/** Determines if the connection persists across requests.
	*/
	@property bool persistent() const 
	{
		auto ph = "connection" in headers;
		switch(httpVersion) {
			case HTTPVersion.HTTP_1_0:
				if (ph && toLower(*ph) == "keep-alive") return true;
				return false;
			case HTTPVersion.HTTP_1_1:
				if (ph && toLower(*ph) == "close") return false;
				return true;
			default: 
				return false;
		}
	}
}


/**
	Represents the HTTP response from the server back to the client.
*/
class HTTPResponse {
	public {
		/// The protocol version of the response - should not be changed
		HTTPVersion httpVersion = HTTPVersion.HTTP_1_1;

		/// The status code of the response, 200 by default
		int statusCode = HTTPStatus.OK;

		/** The status phrase of the response

			If no phrase is set, a default one corresponding to the status code will be used.
		*/
		string statusPhrase;

		/// The response header fields
		InetHeaderMap headers;

		/// All cookies that shall be set on the client for this request
		Cookie[string] cookies;
	}

	public override string toString()
	{
		auto app = appender!string();
		formattedWrite(app, "%s %d %s", getHTTPVersionString(this.httpVersion), this.statusCode, this.statusPhrase);
		return app.data;
	}

	/** Shortcut to the "Content-Type" header
	*/
	@property string contentType() const { auto pct = "Content-Type" in headers; return pct ? *pct : "application/octet-stream"; }
	/// ditto
	@property void contentType(string ct) { headers["Content-Type"] = ct; }
}


/**
	Respresents a HTTP response status.

	Throwing this exception from within a request handler will produce a matching error page.
*/
class HTTPStatusException : Exception {
	private {
		int m_status;
	}

	this(int status, string message = null, string file = __FILE__, int line = __LINE__, Throwable next = null)
	{
		super(message ? message : httpStatusText(status), file, line, next);
		m_status = status;
	}
	
	/// The HTTP status code
	@property int status() const { return m_status; }
}


final class MultiPart {
	string contentType;
	
	InputStream stream;
	//JsonValue json;
	string[string] form;
}

string getHTTPVersionString(HTTPVersion ver)
{
	final switch(ver){
		case HTTPVersion.HTTP_1_0: return "HTTP/1.0";
		case HTTPVersion.HTTP_1_1: return "HTTP/1.1";
	}
}


HTTPVersion parseHTTPVersion(ref string str)
{
	enforce(str.startsWith("HTTP/"));
	str = str[5 .. $];
	int majorVersion = parse!int(str);
	enforce(str.startsWith("."));
	str = str[1 .. $];
	int minorVersion = parse!int(str);
	
	enforce( majorVersion == 1 && (minorVersion == 0 || minorVersion == 1) );
	return minorVersion == 0 ? HTTPVersion.HTTP_1_0 : HTTPVersion.HTTP_1_1;
}


/**
	Takes an input stream that contains data in HTTP chunked format and outputs the raw data.
*/
final class ChunkedInputStream : InputStream {
	private {
		InputStream m_in;
		ulong m_bytesInCurrentChunk = 0;
	}

	this(InputStream stream)
	{
		assert(stream !is null);
		m_in = stream;
		readChunk();
	}

	@property bool empty() const { return m_bytesInCurrentChunk == 0; }

	@property ulong leastSize() const { return m_bytesInCurrentChunk; }

	@property bool dataAvailableForRead() { return m_bytesInCurrentChunk > 0 && m_in.dataAvailableForRead; }

	const(ubyte)[] peek()
	{
		auto dt = m_in.peek();
		return dt[0 .. min(dt.length, m_bytesInCurrentChunk)];
	}

	void read(ubyte[] dst)
	{
		enforce(!empty, "Read past end of chunked stream.");
		while( dst.length > 0 ){
			enforce(m_bytesInCurrentChunk > 0, "Reading past end of chunked HTTP stream.");

			auto sz = cast(size_t)min(m_bytesInCurrentChunk, dst.length);
			m_in.read(dst[0 .. sz]);
			dst = dst[sz .. $];
			m_bytesInCurrentChunk -= sz;

			if( m_bytesInCurrentChunk == 0 ){
				// skip current chunk footer and read next chunk
				ubyte[2] crlf;
				m_in.read(crlf);
				enforce(crlf[0] == '\r' && crlf[1] == '\n');
				readChunk();
			}
		}
	}

	private void readChunk()
	{
		assert(m_bytesInCurrentChunk == 0);
		// read chunk header
		logTrace("read next chunk header");
		auto ln = cast(string)m_in.readLine();
		logTrace("got chunk header: %s", ln);
		m_bytesInCurrentChunk = parse!ulong(ln, 16u);

		if( m_bytesInCurrentChunk == 0 ){
			// empty chunk denotes the end
			// skip final chunk footer
			ubyte[2] crlf;
			m_in.read(crlf);
			enforce(crlf[0] == '\r' && crlf[1] == '\n');
		}
	}
}


/**
	Outputs data to an output stream in HTTP chunked format.
*/
final class ChunkedOutputStream : OutputStream {
	private {
		OutputStream m_out;
		AllocAppender!(ubyte[]) m_buffer;
		size_t m_maxBufferSize = 512*1024;
		bool m_finalized = false;
	}
	
	this(OutputStream stream, Allocator alloc = defaultAllocator())
	{
		m_out = stream;
		m_buffer = AllocAppender!(ubyte[])(alloc);
	}

	/** Maximum buffer size used to buffer individual chunks.

		A size of zero means unlimited buffer size. Explicit flush is required
		in this case to empty the buffer.
	*/
	@property size_t maxBufferSize() const { return m_maxBufferSize; }
	/// ditto
	@property void maxBufferSize(size_t bytes) { m_maxBufferSize = bytes; if (m_buffer.data.length >= m_maxBufferSize) flush(); }

	void write(in ubyte[] bytes_)
	{
		assert(!m_finalized);
		const(ubyte)[] bytes = bytes_;
		while (bytes.length > 0) {
			auto sz = bytes.length;
			if (m_maxBufferSize > 0 && m_maxBufferSize < m_buffer.data.length + sz)
				sz = m_maxBufferSize - min(m_buffer.data.length, m_maxBufferSize);
			if (sz > 0) {
				m_buffer.put(bytes[0 .. sz]);
				bytes = bytes[sz .. $];
			}
			if (bytes.length > 0)
				flush();
		}
	}
	
	void write(InputStream data, ulong nbytes = 0)
	{
		assert(!m_finalized);
		if( m_buffer.data.length > 0 ) flush();
		if( nbytes == 0 ){
			while( !data.empty ){
				auto sz = data.leastSize;
				assert(sz > 0);
				writeChunkSize(sz);
				m_out.write(data, sz);
				m_out.write("\r\n");
				m_out.flush();
			}
		} else {
			writeChunkSize(nbytes);
			m_out.write(data, nbytes);
			m_out.write("\r\n");
			m_out.flush();
		}
	}

	void flush() 
	{
		assert(!m_finalized);
		auto data = m_buffer.data();
		if( data.length ){
			writeChunkSize(data.length);
			m_out.write(data);
			m_out.write("\r\n");
		}
		m_out.flush();
		m_buffer.reset(AppenderResetMode.reuseData);
	}

	void finalize()
	{
		if (m_finalized) return;
		flush();
		m_buffer.reset(AppenderResetMode.freeData);		
		m_finalized = true;
		m_out.write("0\r\n\r\n");
		m_out.flush();
	}
	private void writeChunkSize(long length)
	{
		formattedWrite(m_out, "%x\r\n", length);
	}
}

final class Cookie {
	private {
		string m_value;
		string m_domain;
		string m_path;
		string m_expires;
		long m_maxAge;
		bool m_secure;
		bool m_httpOnly; 
	}

	@property void value(string value) { m_value = value; }
	@property string value() const { return m_value; }

	@property void domain(string value) { m_domain = value; }
	@property string domain() const { return m_domain; }

	@property void path(string value) { m_path = value; }
	@property string path() const { return m_path; }

	@property void expires(string value) { m_expires = value; }
	@property string expires() const { return m_expires; }

	@property void maxAge(long value) { m_maxAge = value; }
	@property long maxAge() const { return m_maxAge; }

	@property void secure(bool value) { m_secure = value; }
	@property bool secure() const { return m_secure; }

	@property void httpOnly(bool value) { m_httpOnly = value; }
	@property bool httpOnly() const { return m_httpOnly; }
}


/** 
*/
struct CookieValueMap {
	struct Cookie {
		string name;
		string value;
	}

	private {
		Cookie[] m_entries;
	}

	string get(string name, string def_value = null)
	const {
		auto pv = name in this;
		if( !pv ) return def_value;
		return *pv;
	}

	string[] getAll(string name)
	const {
		string[] ret;
		foreach(c; m_entries)
			if( c.name == name )
				ret ~= c.value;
		return ret;
	}

	void opIndexAssign(string value, string name)
	{
		m_entries ~= Cookie(name, value);
	}

	string opIndex(string name)
	const {
		import core.exception : RangeError;
		auto pv = name in this;
		if( !pv ) throw new RangeError("Non-existent cookie: "~name);
		return *pv;
	}

	int opApply(scope int delegate(ref Cookie) del)
	{
		foreach(ref c; m_entries)
			if( auto ret = del(c) )
				return ret;
		return 0;
	}

	int opApply(scope int delegate(ref Cookie) del)
	const {
		foreach(Cookie c; m_entries)
			if( auto ret = del(c) )
				return ret;
		return 0;
	}

	int opApply(scope int delegate(ref string name, ref string value) del)
	{
		foreach(ref c; m_entries)
			if( auto ret = del(c.name, c.value) )
				return ret;
		return 0;
	}

	int opApply(scope int delegate(ref string name, ref string value) del)
	const {
		foreach(Cookie c; m_entries)
			if( auto ret = del(c.name, c.value) )
				return ret;
		return 0;
	}

	inout(string)* opBinaryRight(string op)(string name) inout if(op == "in")
	{
		foreach(c; m_entries)
			if( c.name == name )
				return &c.value;
		return null;
	}
}
