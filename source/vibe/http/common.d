/**
	Common classes for HTTP clients and servers.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.common;

public import vibe.http.status;

import vibe.core.log;
import vibe.core.tcp;
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
	GET,
	HEAD,
	PUT,
	POST,
	PATCH,
	DELETE,
	OPTIONS,
	TRACE,
	CONNECT
}

string httpMethodString(HttpMethod m)
{
	static immutable strings = ["GET", "HEAD", "PUT", "POST", "PATCH", "DELETE", "OPTIONS", "TRACE", "CONNECT"];
	static assert(m.max+1 == strings.length);
	return strings[m];
}

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
	}
}

/**
	Represents an HTTP request made to a server.
*/
class HttpRequest {
	protected {
		Stream m_conn;
	}
	
	public {
		HttpVersion httpVersion = HttpVersion.HTTP_1_1;
		HttpMethod method = HttpMethod.GET;
		string url = "/";
		StrMapCI headers;
	}
	
	protected this(Stream conn)
	{
		m_conn = conn;
	}
	
	protected this()
	{
	}
	
	@property string host() const { auto ph = "Host" in headers; return ph ? *ph : null; }
	@property void host(string v) { headers["Host"] = v; }

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
		HttpVersion httpVersion = HttpVersion.HTTP_1_1;
		int statusCode = HttpStatus.OK;
		string statusPhrase;
		StrMapCI headers;
		Cookie[string] cookies;
	}

	@property string contentType() const { auto pct = "Content-Type" in headers; return pct ? *pct : "application/octet-stream"; }
	@property void contentType(string ct) { headers["Content-Type"] = ct; }
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
		bool m_empty = false;
		ulong m_bytesInCurrentChunk = 0;
	}

	this(InputStream stream)
	{
		assert(stream !is null);
		m_in = stream;
		readChunk();
	}

	@property bool empty() const { return m_empty; }

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
			enforce( !empty );
			enforce( m_bytesInCurrentChunk > 0 );

			auto sz = cast(size_t)min(m_bytesInCurrentChunk, dst.length);
			m_in.read(dst[0 .. sz]);
			dst = dst[sz .. $];
			m_bytesInCurrentChunk -= sz;

			if( m_bytesInCurrentChunk == 0 ){
				// skipp current chunk footer
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
			m_empty = true;

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
		Appender!(ubyte[]) m_buffer;
	}
	
	this(OutputStream stream) 
	{
		m_out = stream;
		m_buffer = appender!(ubyte[])();
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
			m_buffer.clear();
		}
		m_out.flush();
	}

	void finalize() {
		flush();
		m_out.write("0\r\n\r\n");
		m_out.flush();
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

	Cookie setValue(string value) { m_value = value; return this; }
	@property string value() { return m_value; }

	Cookie setDomain(string domain) { m_domain = domain; return this; }
	@property string domain() { return m_domain; }

	Cookie setPath(string path) { m_path = path; return this; }
	@property string path() { return m_path; }

	Cookie setExpire(string expires) { m_expires = expires; return this; }
	@property string expires() { return m_expires; }

	Cookie setMaxAge(long maxAge) { m_maxAge = maxAge; return this;}
	@property long maxAge() { return m_maxAge; }

	Cookie setSecure(bool enabled) { m_secure = enabled; return this; }
	@property bool isSecure() { return m_secure; }

	Cookie setHttpOnly(bool enabled) { m_httpOnly = enabled; return this; }
	@property bool isHttpOnly() { return m_httpOnly; }

}

/**
	Behaves like string[string] but case does not matter for the key.

	This kind of map is used for MIME headers (e.g. for HTTP), where the case of the key strings
	does not matter.

	Note that despite case not being relevant for matching keyse, iterating over the map will yield
	the original case of the key that was put in.
*/
struct StrMapCI {
	private {
		static struct Field { uint keyCheckSum; string key; string value; }
		Field[64] m_fields;
		size_t m_fieldCount = 0;
		Field[] m_extendedFields;
		static char[256] s_keyBuffer;
	}
	
	@property size_t length() const { return m_fieldCount + m_extendedFields.length; }

	void remove(string key){
		auto keysum = computeCheckSumI(key);
		auto idx = getIndex(m_fields[0 .. m_fieldCount], key, keysum);
		if( idx >= 0 ){
			removeFromArrayIdx(m_fields[0 .. m_fieldCount], idx);
			m_fieldCount--;
		} else {
			idx = getIndex(m_extendedFields, key, keysum);
			enforce(idx >= 0);
			removeFromArrayIdx(m_extendedFields, idx);
		}
	}

	string opIndex(string key){
		auto pitm = key in this;
		enforce(pitm !is null, "Accessing non-existent key '"~key~"'.");
		return *pitm;
	}
	string opIndexAssign(string val, string key){
		auto pitm = key in this;
		if( pitm ) *pitm = val;
		else if( m_fieldCount < m_fields.length ) m_fields[m_fieldCount++] = Field(computeCheckSumI(key), key, val);
		else m_extendedFields ~= Field(computeCheckSumI(key), key, val);
		return val;
	}

	inout(string)* opBinaryRight(string op)(string key) inout if(op == "in") {
		uint keysum = computeCheckSumI(key);
		auto idx = getIndex(m_fields[0 .. m_fieldCount], key, keysum);
		if( idx >= 0 ) return &m_fields[idx].value;
		idx = getIndex(m_extendedFields, key, keysum);
		if( idx >= 0 ) return &m_extendedFields[idx].value;
		return null;
	}

	bool opBinaryRight(string op)(string key) inout if(op == "!in") {
		return !(key in this);
	}

	int opApply(int delegate(ref string key, ref string val) del)
	{
		foreach( ref kv; m_fields[0 .. m_fieldCount] ){
			string kcopy = kv.key;
			if( auto ret = del(kcopy, kv.value) )
				return ret;
		}
		foreach( ref kv; m_extendedFields ){
			string kcopy = kv.key;
			if( auto ret = del(kcopy, kv.value) )
				return ret;
		}
		return 0;
	}

	int opApply(int delegate(ref string val) del)
	{
		foreach( ref kv; m_fields[0 .. m_fieldCount] ){
			if( auto ret = del(kv.value) )
				return ret;
		}
		foreach( ref kv; m_extendedFields ){
			if( auto ret = del(kv.value) )
				return ret;
		}
		return 0;
	}

	@property StrMapCI dup()
	const {
		StrMapCI ret;
		ret.m_fields[0 .. m_fieldCount] = m_fields[0 .. m_fieldCount];
		ret.m_fieldCount = m_fieldCount;
		ret.m_extendedFields = m_extendedFields.dup;
		return ret;
	}

	private ptrdiff_t getIndex(in Field[] map, string key, uint keysum)
	const {
		foreach( i, ref const(Field) entry; map ){
			if( entry.keyCheckSum != keysum ) continue;
			if( icmp2(entry.key, key) == 0 )
				return i;
		}
		return -1;
	}
	
	// very simple check sum function with a good chance to match
	// strings with different case equal
	private static uint computeCheckSumI(string s)
	{
		import std.uni;
		uint csum = 0;
		foreach( i; 0 .. s.length )
			csum += 357*(s[i]&0x1101_1111);
		return csum;
	}
}

void writeRFC822DateString(R)(ref R dst, SysTime time)
{
	assert(time.timezone == UTC());

	static immutable dayStrings = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
	static immutable monthStrings = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
	dst.put(dayStrings[time.dayOfWeek]);
	dst.put(", ");
	writeDecimal2(dst, time.day);
	dst.put(' ');
	dst.put(monthStrings[time.month-1]);
	dst.put(' ');
	writeDecimal(dst, time.year);
}

void writeRFC822TimeString(R)(ref R dst, SysTime time)
{
	assert(time.timezone == UTC());
	writeDecimal2(dst, time.hour);
	dst.put(':');
	writeDecimal2(dst, time.minute);
	dst.put(':');
	writeDecimal2(dst, time.second);
	dst.put(" GMT");
}

void writeRFC822DateTimeString(R)(ref R dst, SysTime time)
{
	writeRFC822DateString(dst, time);
	dst.put(' ');
	writeRFC822TimeString(dst, time);
}

string toRFC822TimeString(SysTime time)
{
	auto ret = new FixedAppender!(string, 12);
	writeRFC822TimeString(ret, time);
	return ret.data;
}

string toRFC822DateString(SysTime time)
{
	auto ret = new FixedAppender!(string, 16);
	writeRFC822DateString(ret, time);
	return ret.data;
}

string toRFC822DateTimeString(SysTime time)
{
	auto ret = new FixedAppender!(string, 29);
	writeRFC822DateTimeString(ret, time);
	return ret.data;
}

private void writeDecimal2(R)(ref R dst, uint n)
{
	auto d1 = n % 10;
	auto d2 = (n / 10) % 10;
	dst.put(cast(char)(d2 + '0'));
	dst.put(cast(char)(d1 + '0'));
}

private void writeDecimal(R)(ref R dst, uint n)
{
	if( n == 0 ){
		dst.put('0');
		return;
	}

	// determine all digits
	uint[10] digits;
	int i = 0;
	while( n > 0 ){
		digits[i++] = n % 10;
		n /= 10;
	}

	// write out the digits in reverse order
	while( i > 0 ) dst.put(cast(char)(digits[--i] + '0'));
}
