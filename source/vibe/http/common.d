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


enum HttpVersion {
	HTTP_1_0,
	HTTP_1_1
}

enum HttpMethod {
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
string httpMethodString(HttpMethod m)
{
	return to!string(m);
}

/**
	Returns the HttpMethod value matching the given HTTP method string.
*/
HttpMethod httpMethodFromString(string str)
{
	switch(str){
		default: throw new Exception("Invalid HTTP method: "~str);
		case "GET": return HttpMethod.GET;
		case "HEAD": return HttpMethod.HEAD;
		case "PUT": return HttpMethod.PUT;
		case "POST": return HttpMethod.POST;
		case "PATCH": return HttpMethod.PATCH;
		case "DELETE": return HttpMethod.DELETE;
		case "OPTIONS": return HttpMethod.OPTIONS;
		case "TRACE": return HttpMethod.TRACE;
		case "CONNECT": return HttpMethod.CONNECT;
		case "COPY": return HttpMethod.COPY;
		case "LOCK": return HttpMethod.LOCK;
		case "MKCOL": return HttpMethod.MKCOL;
		case "MOVE": return HttpMethod.MOVE;
		case "PROPFIND": return HttpMethod.PROPFIND;
		case "PROPPATCH": return HttpMethod.PROPPATCH;
		case "UNLOCK": return HttpMethod.UNLOCK;
	}
}

unittest 
{
	assert(httpMethodString(HttpMethod.GET) == "GET");
	assert(httpMethodString(HttpMethod.UNLOCK) == "UNLOCK");
	assert(httpMethodFromString("GET") == HttpMethod.GET);
	assert(httpMethodFromString("UNLOCK") == HttpMethod.UNLOCK);
}


/**
	Utility function that throws a HttpStatusException if the _condition is not met.
*/
void enforceHttp(T)(T condition, HttpStatus statusCode, string message = null)
{
	enforce(condition, new HttpStatusException(statusCode, message));
}


/**
	Represents an HTTP request made to a server.
*/
class HttpRequest {
	protected {
		Stream m_conn;
	}
	
	public {
		/// The HTTP protocol version used for the request
		HttpVersion httpVersion = HttpVersion.HTTP_1_1;

		/// The HTTP _method of the request
		HttpMethod method = HttpMethod.GET;

		/** The request URL

			Note that the request URL usually does not include the global
			'http://server' part, but only the local path and a query string.
			A possible exception is a proxy server, which will get full URLs.
		*/
		string requestUrl = "/";

		/// Please use requestUrl instead.
		deprecated("Please use requestUrl instead.") alias requestUrl url;

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
			case HttpVersion.HTTP_1_0:
				if (ph && toLower(*ph) == "keep-alive") return true;
				return false;
			case HttpVersion.HTTP_1_1:
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
class HttpResponse {
	public {
		/// The protocol version of the response - should not be changed
		HttpVersion httpVersion = HttpVersion.HTTP_1_1;

		/// The status code of the response, 200 by default
		int statusCode = HttpStatus.OK;

		/** The status phrase of the response

			If no phrase is set, a default one corresponding to the status code will be used.
		*/
		string statusPhrase;

		/// The response header fields
		InetHeaderMap headers;

		/// All cookies that shall be set on the client for this request
		Cookie[string] cookies;
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
class HttpStatusException : Exception {
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


class MultiPart {
	string contentType;
	
	InputStream stream;
	//JsonValue json;
	string[string] form;
}

string getHttpVersionString(HttpVersion ver)
{
	final switch(ver){
		case HttpVersion.HTTP_1_0: return "HTTP/1.0";
		case HttpVersion.HTTP_1_1: return "HTTP/1.1";
	}
}

HttpVersion parseHttpVersion(ref string str)
{
	enforce(str.startsWith("HTTP/"));
	str = str[5 .. $];
	int majorVersion = parse!int(str);
	enforce(str.startsWith("."));
	str = str[1 .. $];
	int minorVersion = parse!int(str);
	
	enforce( majorVersion == 1 && (minorVersion == 0 || minorVersion == 1) );
	return minorVersion == 0 ? HttpVersion.HTTP_1_0 : HttpVersion.HTTP_1_1;
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

	@property bool dataAvailableForRead() { return m_in.dataAvailableForRead; }

	const(ubyte)[] peek()
	{
		auto dt = m_in.peek();
		return dt[0 .. min(dt.length, m_bytesInCurrentChunk)];
	}

	void read(ubyte[] dst)
	{
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
		// read chunk header
		logTrace("read next chunk header");
		auto ln = m_in.readLine();
		ulong sz = toImpl!ulong(cast(string)ln, 16u);
		m_bytesInCurrentChunk = sz;

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
	}
	
	this(OutputStream stream, Allocator alloc = defaultAllocator())
	{
		m_out = stream;
		m_buffer = AllocAppender!(ubyte[])(alloc);
	}

	void write(in ubyte[] bytes, bool do_flush = true)
	{
		m_buffer.put(bytes);
		if( do_flush ) flush();
	}
	
	void write(InputStream data, ulong nbytes = 0, bool do_flush = true)
	{
		if( m_buffer.data.length > 0 ) flush();
		if( nbytes == 0 ){
			while( !data.empty ){
				writeChunkSize(data.leastSize);
				m_out.write(data, data.leastSize, false);
				m_out.write("\r\n", do_flush);
			}
		} else {
			writeChunkSize(nbytes);
			m_out.write(data, nbytes, false);
			m_out.write("\r\n", do_flush);
		}
	}

	void flush() 
	{
		auto data = m_buffer.data();
		if( data.length ){
			writeChunkSize(data.length);
			m_out.write(data, false);
			m_out.write("\r\n");
		}
		m_out.flush();
		m_buffer.reset(AppenderResetMode.reuseData);
	}

	void finalize() {
		flush();
		m_out.write("0\r\n\r\n");
		m_out.flush();
		m_buffer.reset(AppenderResetMode.freeData);
	}
	private void writeChunkSize(long length) {
		m_out.write(format("%x\r\n", length), false);
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


	/// Deprecated compatibility aliases
	deprecated("Please use secure instead.") alias secure isSecure;
	// ditto
	deprecated("Please use httpOnly instead.") alias httpOnly isHttpOnly;
	// ditto
	deprecated("Please use the 'value' property instead.") Cookie setValue(string value) { m_value = value; return this; }
	/// ditto
	deprecated("Please use the 'domain' property instead.") Cookie setDomain(string domain) { m_domain = domain; return this; }
	/// ditto
	deprecated("Please use the 'path' property instead.") Cookie setPath(string path) { m_path = path; return this; }
	/// ditto
	deprecated("Please use the 'expire' property instead.") Cookie setExpire(string expires) { m_expires = expires; return this; }
	/// ditto
	deprecated("Please use the 'maxAge' property instead.") Cookie setMaxAge(long maxAge) { m_maxAge = maxAge; return this;}
	/// ditto
	deprecated("Please use the 'secure' property instead.") Cookie setSecure(bool enabled) { m_secure = enabled; return this; }
	/// ditto
	deprecated("Please use the 'httpOnly' property instead.") Cookie setHttpOnly(bool enabled) { m_httpOnly = enabled; return this; }
}

/// Compatibility alias for vibe.inet.message.InetHeaderMap
deprecated("please use vibe.inet.message.InetHeaderMap instead.")
alias InetHeaderMap StrMapCI;


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