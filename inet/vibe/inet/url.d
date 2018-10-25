/**
	URL parsing routines.

	Copyright: © 2012-2017 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.url;

public import vibe.core.path;

import vibe.textfilter.urlencode;
import vibe.utils.string;

import std.array;
import std.conv;
import std.exception;
import std.string;
import std.traits : isInstanceOf;


/**
	Represents a URL decomposed into its components.
*/
struct URL {
@safe:
	private {
		string m_schema;
		string m_pathString;
		string m_host;
		ushort m_port;
		string m_username;
		string m_password;
		string m_queryString;
		string m_anchor;
	}

	/// Constructs a new URL object from its components.
	this(string schema, string host, ushort port, InetPath path)
	{
		m_schema = schema;
		m_host = host;
		m_port = port;
		version (Have_vibe_core) m_pathString = path.toString();
		else m_pathString = urlEncode(path.toString(), "/");
	}
	/// ditto
	this(string schema, InetPath path)
	{
		this(schema, null, 0, path);
	}

	version (Have_vibe_core) {
		/// ditto
		this(string schema, string host, ushort port, PosixPath path)
		{
			this(schema, host, port, cast(InetPath)path);
		}
		/// ditto
		this(string schema, PosixPath path)
		{
			this(schema, null, 0, cast(InetPath)path);
		}
		/// ditto
		this(string schema, string host, ushort port, WindowsPath path)
		{
			this(schema, host, port, cast(InetPath)path);
		}
		/// ditto
		this(string schema, WindowsPath path)
		{
			this(schema, null, 0, cast(InetPath)path);
		}
	}

	/** Constructs a URL from its string representation.

		TODO: additional validation required (e.g. valid host and user names and port)
	*/
	this(string url_string)
	{
		auto str = url_string;
		enforce(str.length > 0, "Empty URL.");
		if( str[0] != '/' ){
			auto idx = str.indexOfCT(':');
			enforce(idx > 0, "No schema in URL:"~str);
			m_schema = str[0 .. idx];
			str = str[idx+1 .. $];
			bool requires_host = false;

			if (isDoubleSlashSchema(m_schema)) {
				// proto://server/path style
				enforce(str.startsWith("//"), "URL must start with proto://...");
				requires_host = true;
				str = str[2 .. $];
			}

			auto si = str.indexOfCT('/');
			if( si < 0 ) si = str.length;
			auto ai = str[0 .. si].indexOfCT('@');
			sizediff_t hs = 0;
			if( ai >= 0 ){
				hs = ai+1;
				auto ci = str[0 .. ai].indexOfCT(':');
				if( ci >= 0 ){
					m_username = str[0 .. ci];
					m_password = str[ci+1 .. ai];
				} else m_username = str[0 .. ai];
				enforce(m_username.length > 0, "Empty user name in URL.");
			}

			m_host = str[hs .. si];

			auto findPort ( string src )
			{
				auto pi = src.indexOfCT(':');
				if(pi > 0) {
					enforce(pi < src.length-1, "Empty port in URL.");
					m_port = to!ushort(src[pi+1..$]);
				}
				return pi;
			}


			auto ip6 = m_host.indexOfCT('[');
			if (ip6 == 0) { // [ must be first char
				auto pe = m_host.indexOfCT(']');
				if (pe > 0) {
					findPort(m_host[pe..$]);
					m_host = m_host[1 .. pe];
				}
			}
			else {
				auto pi = findPort(m_host);
				if(pi > 0) {
					m_host = m_host[0 .. pi];
				}
			}

			enforce(!requires_host || m_schema == "file" || m_host.length > 0,
					"Empty server name in URL.");
			str = str[si .. $];
		}

		this.localURI = str;
	}
	/// ditto
	static URL parse(string url_string)
	{
		return URL(url_string);
	}
	/// ditto
	static URL fromString(string url_string)
	{
		return URL(url_string);
	}

	invariant()
	{
		assert(isURLEncoded(m_pathString), "Wrong URL encoding of '"~m_pathString~"'");
	}

	/// The schema/protocol part of the URL
	@property string schema() const { return m_schema; }
	/// ditto
	@property void schema(string v) { m_schema = v; }

	/// The url encoded path part of the URL
	@property string pathString() const { return m_pathString; }

	/// Set the path part of the URL. It should be properly encoded.
	@property void pathString(string s)
	{
		enforce(isURLEncoded(s), "Wrong URL encoding of the path string '"~s~"'");
		m_pathString = s;
	}

	/// The path part of the URL
	@property InetPath path() const {
		version (Have_vibe_core)
			return InetPath(m_pathString);
		else
			return Path(urlDecode(m_pathString));
	}
	version (Have_vibe_core) {
		/// ditto
		@property void path(Path)(Path p)
			if (isInstanceOf!(GenericPath, Path))
		{
			m_pathString = (cast(InetPath)p).toString();
		}
	} else {
		/// ditto
		@property void path(Path p)
		{
			m_pathString = p.toString().urlEncode("/");
		}
	}

	/// The host part of the URL (depends on the schema)
	@property string host() const { return m_host; }
	/// ditto
	@property void host(string v) { m_host = v; }

	/// The port part of the URL (optional)
	@property ushort port() const { return m_port ? m_port : defaultPort(m_schema); }
	/// ditto
	@property port(ushort v) { m_port = v; }

	/// Get the default port for the given schema or 0
	static ushort defaultPort(string schema) {
		switch(schema){
			default:
			case "file": return 0;
			case "http": return 80;
			case "https": return 443;
			case "ftp": return 21;
			case "spdy": return 443;
			case "sftp": return 22;
		}
	}
	/// ditto
	ushort defaultPort() const {
		return defaultPort(m_schema);
	}

	/// The user name part of the URL (optional)
	@property string username() const { return m_username; }
	/// ditto
	@property void username(string v) { m_username = v; }

	/// The password part of the URL (optional)
	@property string password() const { return m_password; }
	/// ditto
	@property void password(string v) { m_password = v; }

	/// The query string part of the URL (optional)
	@property string queryString() const { return m_queryString; }
	/// ditto
	@property void queryString(string v) { m_queryString = v; }

	/// The anchor part of the URL (optional)
	@property string anchor() const { return m_anchor; }

	/// The path part plus query string and anchor
	@property string localURI()
	const {
		auto str = appender!string();
		// m_pathString is already encoded
		str.put(m_pathString);
		if( queryString.length ) {
			str.put("?");
			str.put(queryString);
		}
		if( anchor.length ) {
			str.put("#");
			str.put(anchor);
		}
		return str.data;
	}
	/// ditto
	@property void localURI(string str)
	{
		auto ai = str.indexOfCT('#');
		if( ai >= 0 ){
			m_anchor = str[ai+1 .. $];
			str = str[0 .. ai];
		} else m_anchor = null;

		auto qi = str.indexOfCT('?');
		if( qi >= 0 ){
			m_queryString = str[qi+1 .. $];
			str = str[0 .. qi];
		} else m_queryString = null;

		this.pathString = str;
	}

	/// The URL to the parent path with query string and anchor stripped.
	@property URL parentURL() const {
		URL ret;
		ret.schema = schema;
		ret.host = host;
		ret.port = port;
		ret.username = username;
		ret.password = password;
		ret.path = path.parentPath;
		return ret;
	}

	/// Converts this URL object to its string representation.
	string toString()
	const {
		import std.format;
		auto dst = appender!string();
		dst.put(schema);
		dst.put(":");
		if (isDoubleSlashSchema(schema))
			dst.put("//");
		if (m_username.length || m_password.length) {
			dst.put(username);
			dst.put(':');
			dst.put(password);
			dst.put('@');
		}

		import std.algorithm : canFind;
		auto ipv6 = host.canFind(":");

		if ( ipv6 ) dst.put('[');
		dst.put(host);
		if ( ipv6 ) dst.put(']');

		if( m_port > 0 ) formattedWrite(dst, ":%d", m_port);
		dst.put(localURI);
		return dst.data;
	}

	bool startsWith(const URL rhs) const {
		if( m_schema != rhs.m_schema ) return false;
		if( m_host != rhs.m_host ) return false;
		// FIXME: also consider user, port, querystring, anchor etc
		version (Have_vibe_core)
			return this.path.bySegment.startsWith(rhs.path.bySegment);
		else return this.path.startsWith(rhs.path);
	}

	URL opBinary(string OP, Path)(Path rhs) const if (OP == "~" && isAnyPath!Path) { return URL(m_schema, m_host, m_port, this.path ~ rhs); }
	URL opBinary(string OP, Path)(Path.Segment rhs) const if (OP == "~" && isAnyPath!Path) { return URL(m_schema, m_host, m_port, this.path ~ rhs); }
	void opOpAssign(string OP, Path)(Path rhs) if (OP == "~" && isAnyPath!Path) { this.path = this.path ~ rhs; }
	void opOpAssign(string OP, Path)(Path.Segment rhs) if (OP == "~" && isAnyPath!Path) { this.path = this.path ~ rhs; }

	/// Tests two URLs for equality using '=='.
	bool opEquals(ref const URL rhs) const {
		if( m_schema != rhs.m_schema ) return false;
		if( m_host != rhs.m_host ) return false;
		if( m_pathString != rhs.m_pathString ) return false;
		return true;
	}
	/// ditto
	bool opEquals(const URL other) const { return opEquals(other); }

	int opCmp(ref const URL rhs) const {
		if( m_schema != rhs.m_schema ) return m_schema.cmp(rhs.m_schema);
		if( m_host != rhs.m_host ) return m_host.cmp(rhs.m_host);
		if( m_pathString != rhs.m_pathString ) return cmp(m_pathString, rhs.m_pathString);
		return true;
	}
}

private enum isAnyPath(P) = is(P == InetPath) || is(P == PosixPath) || is(P == WindowsPath);

private bool isDoubleSlashSchema(string schema)
@safe nothrow @nogc {
	switch (schema) {
		case "ftp", "http", "https", "http+unix", "https+unix":
		case "spdy", "sftp", "ws", "wss", "file", "redis", "tcp":
			return true;
		default:
			return false;
	}
}

unittest { // IPv6
	auto urlstr = "http://[2003:46:1a7b:6c01:64b:80ff:fe80:8003]:8091/abc";
	auto url = URL.parse(urlstr);
	assert(url.schema == "http", url.schema);
	assert(url.host == "2003:46:1a7b:6c01:64b:80ff:fe80:8003", url.host);
	assert(url.port == 8091);
	assert(url.path == InetPath("/abc"), url.path.toString());
	assert(url.toString == urlstr);

	url.host = "abcd:46:1a7b:6c01:64b:80ff:fe80:8abc";
	urlstr = "http://[abcd:46:1a7b:6c01:64b:80ff:fe80:8abc]:8091/abc";
	assert(url.toString == urlstr);
}


unittest {
	auto urlstr = "https://www.example.net/index.html";
	auto url = URL.parse(urlstr);
	assert(url.schema == "https", url.schema);
	assert(url.host == "www.example.net", url.host);
	assert(url.path == InetPath("/index.html"), url.path.toString());
	assert(url.port == 443);
	assert(url.toString == urlstr);

	urlstr = "http://jo.doe:password@sub.www.example.net:4711/sub2/index.html?query#anchor";
	url = URL.parse(urlstr);
	assert(url.schema == "http", url.schema);
	assert(url.username == "jo.doe", url.username);
	assert(url.password == "password", url.password);
	assert(url.port == 4711, to!string(url.port));
	assert(url.host == "sub.www.example.net", url.host);
	assert(url.path.toString() == "/sub2/index.html", url.path.toString());
	assert(url.queryString == "query", url.queryString);
	assert(url.anchor == "anchor", url.anchor);
	assert(url.toString == urlstr);
}

unittest { // issue #1044
	URL url = URL.parse("http://example.com/p?query#anchor");
	assert(url.schema == "http");
	assert(url.host == "example.com");
	assert(url.port == 80);
	assert(url.queryString == "query");
	assert(url.anchor == "anchor");
	assert(url.pathString == "/p");
	url.localURI = "/q";
	assert(url.schema == "http");
	assert(url.host == "example.com");
	assert(url.queryString == "");
	assert(url.anchor == "");
	assert(url.pathString == "/q");
	url.localURI = "/q?query";
	assert(url.schema == "http");
	assert(url.host == "example.com");
	assert(url.queryString == "query");
	assert(url.anchor == "");
	assert(url.pathString == "/q");
	url.localURI = "/q#anchor";
	assert(url.schema == "http");
	assert(url.host == "example.com");
	assert(url.queryString == "");
	assert(url.anchor == "anchor");
	assert(url.pathString == "/q");
}

//websocket unittest
unittest {
	URL url = URL("ws://127.0.0.1:8080/echo");
	assert(url.host == "127.0.0.1");
	assert(url.port == 8080);
	assert(url.localURI == "/echo");
}

unittest {
	auto p = PosixPath("/foo bar/boo oom/");
	URL url = URL("http", "example.com", 0, p); // constructor test
	assert(url.path == cast(InetPath)p);
	url.path = p;
	assert(url.path == cast(InetPath)p);					   // path assignement test
	assert(url.pathString == "/foo%20bar/boo%20oom/");
	assert(url.toString() == "http://example.com/foo%20bar/boo%20oom/");
	url.pathString = "/foo%20bar/boo%2foom/";
	assert(url.pathString == "/foo%20bar/boo%2foom/");
	assert(url.toString() == "http://example.com/foo%20bar/boo%2foom/");
}

unittest {
	auto url = URL("http://example.com/some%2bpath");
	assert((cast(PosixPath)url.path).toString() == "/some+path", url.path.toString());
}

unittest {
	assert(URL("file:///test").pathString == "/test");
	assert(URL("file:///test").port == 0);
	assert(URL("file:///test").path.toString() == "/test");
	assert(URL("file://test").host == "test");
	assert(URL("file://test").pathString() == "");
	assert(URL("file://./test").host == ".");
	assert(URL("file://./test").pathString == "/test");
	assert(URL("file://./test").path.toString() == "/test");
}

unittest { // issue #1318
	try {
		URL("http://something/inval%id");
		assert(false, "Expected to throw an exception.");
	} catch (Exception e) {}
}

unittest {
	assert(URL("http+unix://%2Fvar%2Frun%2Fdocker.sock").schema == "http+unix");
	assert(URL("https+unix://%2Fvar%2Frun%2Fdocker.sock").schema == "https+unix");
	assert(URL("http+unix://%2Fvar%2Frun%2Fdocker.sock").host == "%2Fvar%2Frun%2Fdocker.sock");
	assert(URL("http+unix://%2Fvar%2Frun%2Fdocker.sock").pathString == "");
	assert(URL("http+unix://%2Fvar%2Frun%2Fdocker.sock/container/json").pathString == "/container/json");
	auto url = URL("http+unix://%2Fvar%2Frun%2Fdocker.sock/container/json");
	assert(URL(url.toString()) == url);
}

unittest {
	import vibe.data.serialization;
	static assert(isStringSerializable!URL);
}

unittest { // issue #1732
	auto url = URL("tcp://0.0.0.0:1234");
	url.port = 4321;
	assert(url.toString == "tcp://0.0.0.0:4321", url.toString);
}

unittest { // host name role in file:// URLs
	auto url = URL.parse("file:///foo/bar");
	assert(url.host == "");
	assert(url.path == InetPath("/foo/bar"));
	assert(url.toString() == "file:///foo/bar");

	url = URL.parse("file://foo/bar/baz");
	assert(url.host == "foo");
	assert(url.path == InetPath("/bar/baz"));
	assert(url.toString() == "file://foo/bar/baz");
}
