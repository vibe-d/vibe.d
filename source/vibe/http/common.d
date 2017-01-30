/**
	Common classes for HTTP clients and servers.

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.common;

public import vibe.http.status;

import vibe.core.log;
import vibe.core.net;
import vibe.inet.message;
import vibe.stream.operations;
import vibe.textfilter.urlencode : urlEncode, urlDecode;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.format;
import std.range : isOutputRange;
import std.string;
import std.typecons;


enum HTTPVersion {
	HTTP_1_0,
	HTTP_1_1
}


enum HTTPMethod {
	// HTTP standard, RFC 2616
	GET,
	HEAD,
	PUT,
	POST,
	PATCH,
	DELETE,
	OPTIONS,
	TRACE,
	CONNECT,

	// WEBDAV extensions, RFC 2518
	PROPFIND,
	PROPPATCH,
	MKCOL,
	COPY,
	MOVE,
	LOCK,
	UNLOCK,

	// Versioning Extensions to WebDAV, RFC 3253
	VERSIONCONTROL,
	REPORT,
	CHECKOUT,
	CHECKIN,
	UNCHECKOUT,
	MKWORKSPACE,
	UPDATE,
	LABEL,
	MERGE,
	BASELINECONTROL,
	MKACTIVITY,

	// Ordered Collections Protocol, RFC 3648
	ORDERPATCH,

	// Access Control Protocol, RFC 3744
	ACL
}


/**
	Returns the string representation of the given HttpMethod.
*/
string httpMethodString(HTTPMethod m)
{
	switch(m){
		case HTTPMethod.BASELINECONTROL: return "BASELINE-CONTROL";
		case HTTPMethod.VERSIONCONTROL: return "VERSION-CONTROL";
		default: return to!string(m);
	}
}

/**
	Returns the HttpMethod value matching the given HTTP method string.
*/
HTTPMethod httpMethodFromString(string str)
{
	switch(str){
		default: throw new Exception("Invalid HTTP method: "~str);
		// HTTP standard, RFC 2616
		case "GET": return HTTPMethod.GET;
		case "HEAD": return HTTPMethod.HEAD;
		case "PUT": return HTTPMethod.PUT;
		case "POST": return HTTPMethod.POST;
		case "PATCH": return HTTPMethod.PATCH;
		case "DELETE": return HTTPMethod.DELETE;
		case "OPTIONS": return HTTPMethod.OPTIONS;
		case "TRACE": return HTTPMethod.TRACE;
		case "CONNECT": return HTTPMethod.CONNECT;

		// WEBDAV extensions, RFC 2518
		case "PROPFIND": return HTTPMethod.PROPFIND;
		case "PROPPATCH": return HTTPMethod.PROPPATCH;
		case "MKCOL": return HTTPMethod.MKCOL;
		case "COPY": return HTTPMethod.COPY;
		case "MOVE": return HTTPMethod.MOVE;
		case "LOCK": return HTTPMethod.LOCK;
		case "UNLOCK": return HTTPMethod.UNLOCK;

		// Versioning Extensions to WebDAV, RFC 3253
		case "VERSION-CONTROL": return HTTPMethod.VERSIONCONTROL;
		case "REPORT": return HTTPMethod.REPORT;
		case "CHECKOUT": return HTTPMethod.CHECKOUT;
		case "CHECKIN": return HTTPMethod.CHECKIN;
		case "UNCHECKOUT": return HTTPMethod.UNCHECKOUT;
		case "MKWORKSPACE": return HTTPMethod.MKWORKSPACE;
		case "UPDATE": return HTTPMethod.UPDATE;
		case "LABEL": return HTTPMethod.LABEL;
		case "MERGE": return HTTPMethod.MERGE;
		case "BASELINE-CONTROL": return HTTPMethod.BASELINECONTROL;
		case "MKACTIVITY": return HTTPMethod.MKACTIVITY;

		// Ordered Collections Protocol, RFC 3648
		case "ORDERPATCH": return HTTPMethod.ORDERPATCH;

		// Access Control Protocol, RFC 3744
		case "ACL": return HTTPMethod.ACL;
	}
}

unittest
{
	assert(httpMethodString(HTTPMethod.GET) == "GET");
	assert(httpMethodString(HTTPMethod.UNLOCK) == "UNLOCK");
	assert(httpMethodString(HTTPMethod.VERSIONCONTROL) == "VERSION-CONTROL");
	assert(httpMethodString(HTTPMethod.BASELINECONTROL) == "BASELINE-CONTROL");
	assert(httpMethodFromString("GET") == HTTPMethod.GET);
	assert(httpMethodFromString("UNLOCK") == HTTPMethod.UNLOCK);
	assert(httpMethodFromString("VERSION-CONTROL") == HTTPMethod.VERSIONCONTROL);
}


/**
	Utility function that throws a HTTPStatusException if the _condition is not met.
*/
T enforceHTTP(T)(T condition, HTTPStatus statusCode, lazy string message = null, string file = __FILE__, typeof(__LINE__) line = __LINE__)
{
	return enforce(condition, new HTTPStatusException(statusCode, message, file, line));
}

/**
	Utility function that throws a HTTPStatusException with status code "400 Bad Request" if the _condition is not met.
*/
T enforceBadRequest(T)(T condition, lazy string message = null, string file = __FILE__, typeof(__LINE__) line = __LINE__)
{
	return enforceHTTP(condition, HTTPStatus.badRequest, message, file, line);
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
				if (ph && toLower(*ph) != "keep-alive") return false;
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

	this(int status, string message = null, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(message != "" ? message : httpStatusText(status), file, line, next);
		m_status = status;
	}

	/// The HTTP status code
	@property int status() const { return m_status; }

	string debugMessage;
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
	enforceBadRequest(str.startsWith("HTTP/"));
	str = str[5 .. $];
	int majorVersion = parse!int(str);
	enforceBadRequest(str.startsWith("."));
	str = str[1 .. $];
	int minorVersion = parse!int(str);

	enforceBadRequest( majorVersion == 1 && (minorVersion == 0 || minorVersion == 1) );
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
		enforceBadRequest(!empty, "Read past end of chunked stream.");
		while( dst.length > 0 ){
			enforceBadRequest(m_bytesInCurrentChunk > 0, "Reading past end of chunked HTTP stream.");

			auto sz = cast(size_t)min(m_bytesInCurrentChunk, dst.length);
			m_in.read(dst[0 .. sz]);
			dst = dst[sz .. $];
			m_bytesInCurrentChunk -= sz;

			if( m_bytesInCurrentChunk == 0 ){
				// skip current chunk footer and read next chunk
				ubyte[2] crlf;
				m_in.read(crlf);
				enforceBadRequest(crlf[0] == '\r' && crlf[1] == '\n');
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
			enforceBadRequest(crlf[0] == '\r' && crlf[1] == '\n');
		}
	}
}


/**
	Outputs data to an output stream in HTTP chunked format.
*/
final class ChunkedOutputStream : OutputStream {
	alias ChunkExtensionCallback = string delegate(in ubyte[] data);
	private {
		OutputStream m_out;
		AllocAppender!(ubyte[]) m_buffer;
		size_t m_maxBufferSize = 4*1024;
		bool m_finalized = false;
		ChunkExtensionCallback m_chunkExtensionCallback = null;
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

	/** A delegate used to specify the extensions for each chunk written to the underlying stream.
	 	
	 	The delegate has to be of type `string delegate(in const(ubyte)[] data)` and gets handed the
	 	data of each chunk before it is written to the underlying stream. If it's return value is non-empty,
	 	it will be added to the chunk's header line.

	 	The returned chunk extension string should be of the format `key1=value1;key2=value2;[...];keyN=valueN`
	 	and **not contain any carriage return or newline characters**.

	 	Also note that the delegate should accept the passed data through a scoped argument. Thus, **no references
	 	to the provided data should be stored in the delegate**. If the data has to be stored for later use,
	 	it needs to be copied first.
	 */
	@property ChunkExtensionCallback chunkExtensionCallback() const { return m_chunkExtensionCallback; }
	/// ditto
	@property void chunkExtensionCallback(ChunkExtensionCallback cb) { m_chunkExtensionCallback = cb; }

	private void append(scope void delegate(scope ubyte[] dst) del, size_t nbytes)
	{
		assert(del !is null);
		auto sz = nbytes;
		if (m_maxBufferSize > 0 && m_maxBufferSize < m_buffer.data.length + sz)
			sz = m_maxBufferSize - min(m_buffer.data.length, m_maxBufferSize);

		if (sz > 0)
		{
			m_buffer.reserve(sz);
			m_buffer.append((scope ubyte[] dst) {
					debug assert(dst.length >= sz);
					del(dst[0..sz]);
					return sz;
				});
		}
	}

	void write(in ubyte[] bytes_)
	{
		assert(!m_finalized);
		const(ubyte)[] bytes = bytes_;
		while (bytes.length > 0) {
			append((scope ubyte[] dst) {
					auto n = dst.length;
					dst[] = bytes[0..n];
					bytes = bytes[n..$];
				}, bytes.length);
			if (bytes.length > 0)
				flush();
		}
	}

	void write(InputStream data, ulong nbytes = 0)
	{
		assert(!m_finalized);
		if( m_buffer.data.length > 0 ) flush();
		if( nbytes == 0 ) {
			while( !data.empty ) {
				auto sz = data.leastSize;
				assert(sz > 0);
				write(data,sz);
			}
		} else {
			while(nbytes > 0)
			{
				append((scope ubyte[] dst) {
						nbytes -= dst.length;
						data.read(dst);
					}, min(nbytes, size_t.max));
				if (nbytes > 0)
					flush();
			}
		}
	}

	void flush()
	{
		assert(!m_finalized);
		auto data = m_buffer.data();
		if( data.length ){
			writeChunk(data);
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
		writeChunk([]);
		m_out.flush();
	}

	private void writeChunk(in ubyte[] data)
	{
		import vibe.stream.wrapper;
		auto rng = StreamOutputRange(m_out);
		formattedWrite(&rng, "%x", data.length);
		if (m_chunkExtensionCallback !is null)
		{
			rng.put(';');
			auto extension = m_chunkExtensionCallback(data);
			assert(!extension.startsWith(';'));
			debug assert(extension.indexOf('\r') < 0);
			debug assert(extension.indexOf('\n') < 0);
			rng.put(extension);
		}
		rng.put("\r\n");
		rng.put(data);
		rng.put("\r\n");
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

	enum Encoding {
		url,
		raw,
		none = raw
	}

	@property void value(string value) { m_value = urlEncode(value); }
	@property string value() const { return urlDecode(m_value); }

	@property void rawValue(string value) { m_value = value; }
	@property string rawValue() const { return m_value; }

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

	void setValue(string value, Encoding encoding)
	{
		final switch (encoding) {
			case Encoding.url: m_value = urlEncode(value); break;
			case Encoding.none: validateValue(value); m_value = value; break;
		}
	}

	void writeString(R)(R dst, string name)
		if (isOutputRange!(R, char))
	{
		import vibe.textfilter.urlencode;
		dst.put(name);
		dst.put('=');
		validateValue(this.value);
		dst.put(this.value);
		if (this.domain && this.domain != "") {
			dst.put("; Domain=");
			dst.put(this.domain);
		}
		if (this.path != "") {
			dst.put("; Path=");
			dst.put(this.path);
		}
		if (this.expires != "") {
			dst.put("; Expires=");
			dst.put(this.expires);
		}
		if (this.maxAge) dst.formattedWrite("; Max-Age=%s", this.maxAge);
		if (this.secure) dst.put("; Secure");
		if (this.httpOnly) dst.put("; HttpOnly");
	}

	private static void validateValue(string value)
	{
		enforce(!value.canFind(';') && !value.canFind('"'));
	}
}

unittest {
	import std.exception : assertThrown;

	auto c = new Cookie;
	c.value = "foo";
	assert(c.value == "foo");
	assert(c.rawValue == "foo");

	c.value = "foo$";
	assert(c.value == "foo$");
	assert(c.rawValue == "foo%24", c.rawValue);

	c.value = "foo&bar=baz?";
	assert(c.value == "foo&bar=baz?");
	assert(c.rawValue == "foo%26bar%3Dbaz%3F", c.rawValue);

	c.setValue("foo%", Cookie.Encoding.raw);
	assert(c.rawValue == "foo%");
	assertThrown(c.value);

	assertThrown(c.setValue("foo;bar", Cookie.Encoding.raw));
}


/**
*/
struct CookieValueMap {
	struct Cookie {
		/// Name of the cookie
		string name;

		/// The raw cookie value as transferred over the wire
		string rawValue;

		this(string name, string value, .Cookie.Encoding encoding = .Cookie.Encoding.url)
		{
			this.name = name;
			this.setValue(value, encoding);
		}

		/// Treats the value as URL encoded
		string value() const { return urlDecode(rawValue); }
		/// ditto
		void value(string val) { rawValue = urlEncode(val); }

		/// Sets the cookie value, applying the specified encoding.
		void setValue(string value, .Cookie.Encoding encoding = .Cookie.Encoding.url)
		{
			final switch (encoding) {
				case .Cookie.Encoding.none: this.rawValue = value; break;
				case .Cookie.Encoding.url: this.rawValue = urlEncode(value); break;
			}
		}
	}

	private {
		Cookie[] m_entries;
	}

	auto length(){ 
		return m_entries.length;
	}

	string get(string name, string def_value = null)
	const {
		foreach (ref c; m_entries)
			if (c.name == name)
				return c.value;
		return def_value;
	}

	string[] getAll(string name)
	const {
		string[] ret;
		foreach(c; m_entries)
			if( c.name == name )
				ret ~= c.value;
		return ret;
	}

	void add(string name, string value, .Cookie.Encoding encoding = .Cookie.Encoding.url){
		m_entries ~= Cookie(name, value, encoding);
	}

	void opIndexAssign(string value, string name)
	{
		m_entries ~= Cookie(name, value);
	}

	string opIndex(string name)
	const {
		import core.exception : RangeError;
		foreach (ref c; m_entries)
			if (c.name == name)
				return c.value;
		throw new RangeError("Non-existent cookie: "~name);
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

	int opApply(scope int delegate(string name, string value) del)
	{
		foreach(ref c; m_entries)
			if( auto ret = del(c.name, c.value) )
				return ret;
		return 0;
	}

	int opApply(scope int delegate(string name, string value) del)
	const {
		foreach(Cookie c; m_entries)
			if( auto ret = del(c.name, c.value) )
				return ret;
		return 0;
	}

	auto opBinaryRight(string op)(string name) if(op == "in")
	{
		return Ptr(&this, name);
	}

	auto opBinaryRight(string op)(string name) const if(op == "in")
	{
		return const(Ptr)(&this, name);
	}

	private static struct Ref {
		private {
			CookieValueMap* map;
			string name;
		}

		@property string get() const { return (*map)[name]; }
		void opAssign(string newval) {
			foreach (ref c; *map)
				if (c.name == name) {
					c.value = newval;
					return;
				}
			assert(false);
		}
		alias get this;
	}
	private static struct Ptr {
		private {
			CookieValueMap* map;
			string name;
		}
		bool opCast() const {
			foreach (ref c; map.m_entries)
				if (c.name == name)
					return true;
			return false;
		}
		inout(Ref) opUnary(string op : "*")() inout { return inout(Ref)(map, name); }
	}
}

unittest {
	CookieValueMap m;
	m["foo"] = "bar;baz%1";
	assert(m["foo"] == "bar;baz%1");

	m["foo"] = "bar";
	assert(m.getAll("foo") == ["bar;baz%1", "bar"]);

	assert("foo" in m);
	if (auto val = "foo" in m) {
		assert(*val == "bar;baz%1");
	} else assert(false);
	*("foo" in m) = "baz";
	assert(m["foo"] == "baz");
}
