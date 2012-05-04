/**
	Common classes for HTTP clients and servers.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.common;

public import vibe.http.status;

import vibe.core.log;
import vibe.core.tcp;

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

/**
	Represents an HTTP request made to a server.
*/
class HttpRequest {
	protected {
		TcpConnection m_conn;
	}
	
	public {
		HttpVersion httpVersion = HttpVersion.HTTP_1_1;
		string method = "GET";
		string url = "/";
		StrMapCI headers;
	}
	
	protected this(TcpConnection conn)
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

	ubyte[] readLine(size_t max_bytes, string line_sep = "\r\n")
	{
		return readLineDefault(max_bytes, line_sep);
	}

	ubyte[] readAll(size_t max_bytes = 0) { return readAllDefault(max_bytes); }


	private void readChunk()
	{
		// read chunk header
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
		m_out.finalize();
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
		Tuple!(string, string)[string] m_map;
	}

	void remove(string key){
		m_map.remove(toLower(key));
	}

	string opIndex(string key){
		auto pv = toLower(key) in m_map;
		enforce(pv !is null, "Accessing non-existant key '"~key~"'.");
		return (*pv)[1];
	}
	string opIndexAssign(string val, string key){ m_map[toLower(key)] = tuple(key, val); return val; }

	inout(string)* opBinaryRight(string op)(string key) inout if(op == "in") {
		auto p = toLower(key) in m_map;
		if( p is null ) return null;
		return &(*p)[1];
	}

	bool opBinaryRight(string op)(string key) inout if(op == "!in") {
		return toLower(key) !in m_map;
	}

	int opApply(int delegate(ref string key, ref string val) del)
	{
		foreach( ref kv; m_map ){
			string kcopy = kv[0];
			if( auto ret = del(kcopy, kv[1]) )
				return ret;
		}
		return 0;
	}

	int opApply(int delegate(ref string val) del)
	{
		foreach( ref kv; m_map ){
			if( auto ret = del(kv[1]) )
				return ret;
		}
		return 0;
	}

	@property StrMapCI dup()
	const {
		StrMapCI ret;
		foreach( v; m_map ) ret[v[0]] = v[1];
		return ret;
	}
}

string toRFC822DateTimeString(SysTime time)
{
	assert(time.timezone == UTC());
	auto ret = appender!string();
	static immutable dayStrings = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
	static immutable monthStrings = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
	formattedWrite(ret, "%s, %02d %s %d %02d:%02d:%02d %s", dayStrings[time.dayOfWeek],
		time.day, monthStrings[time.month-1], time.year, time.hour, time.minute, time.second, "GMT");
	return ret.data;
}

string toRFC822TimeString(SysTime time)
{
	assert(time.timezone == UTC());
	auto ret = appender!string();
	formattedWrite(ret, "%02d:%02d:%02d %s", time.hour, time.minute, time.second, "GMT");
	return ret.data;
}

string toRFC822DateString(SysTime time)
{
	assert(time.timezone == UTC());
	auto ret = appender!string();
	static immutable dayStrings = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
	static immutable monthStrings = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
	formattedWrite(ret, "%s, %02d %s %d", dayStrings[time.dayOfWeek],
		time.day, monthStrings[time.month-1], time.year);
	return ret.data;
}

