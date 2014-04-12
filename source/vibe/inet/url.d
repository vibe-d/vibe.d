/**
	URL parsing routines.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.url;

public import vibe.inet.path;

import vibe.textfilter.urlencode;
import vibe.utils.string;

import std.array;
import std.conv;
import std.exception;
import std.string;


/**
	Represents a URL decomposed into its components.
*/
struct URL {
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
	this(string schema, string host, ushort port, Path path)
	{
		m_schema = schema;
		m_host = host;
		m_port = port;
		m_pathString = path.toString();
	}
	/// ditto
	this(string schema, Path path)
	{
		this(schema, null, 0, path);
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

			switch(m_schema){
				case "http":
				case "https":
				case "ftp":
				case "spdy":
				case "sftp":
				case "file":
					// proto://server/path style
					enforce(str.startsWith("//"), "URL must start with proto://...");
					requires_host = true;
					str = str[2 .. $];
					goto default;
				default:
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
					auto pi = m_host.indexOfCT(':');
					if(pi > 0) {
						enforce(pi < m_host.length-1, "Empty port in URL.");
						m_port = to!ushort(m_host[pi+1..$]);
						m_host = m_host[0 .. pi];
					}

					enforce(!requires_host || m_schema == "file" || m_host.length > 0,
							"Empty server name in URL.");
					str = str[si .. $];
			}
		}

		this.localURI = str;
	}
	/// ditto
	static URL parse(string url_string)
	{
		return URL(url_string);
	}

	/// The schema/protocol part of the URL
	@property string schema() const { return m_schema; }
	/// ditto
	@property void schema(string v) { m_schema = v; }

	/// The path part of the URL in the original string form
	@property string pathString() const { return m_pathString; }

	/// The path part of the URL
	@property Path path() const { return Path(urlDecode(m_pathString)); }
	/// ditto
	@property void path(Path p)
	{
		auto pstr = p.toString();
		m_pathString = urlEncode(pstr);
	}

	/// The host part of the URL (depends on the schema)
	@property string host() const { return m_host; }
	/// ditto
	@property void host(string v) { m_host = v; }

	/// The port part of the URL (optional)
	@property ushort port() const { return m_port; }
	/// ditto
	@property port(ushort v) { m_port = v; }

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
		str.reserve(m_pathString.length + 2 + queryString.length + anchor.length);
		filterURLEncode(str, path.toString(), "/");
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
		}

		auto qi = str.indexOfCT('?');
		if( qi >= 0 ){
			m_queryString = str[qi+1 .. $];
			str = str[0 .. qi];
		}

		m_pathString = str;
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
		switch(schema){
			default: break;
			case "file":
			case "http":
			case "https":
			case "ftp":
			case "spdy":
			case "sftp":
				dst.put("//");
				break;
		}
		if (m_username.length || m_password.length) {
			dst.put(username);
			dst.put(':');
			dst.put(password);
			dst.put('@');
		}
		dst.put(host);
		if( m_port > 0 ) formattedWrite(dst, ":%d", m_port);
		dst.put(localURI);
		return dst.data;
	}

	bool startsWith(const URL rhs) const {
		if( m_schema != rhs.m_schema ) return false;
		if( m_host != rhs.m_host ) return false;
		// FIXME: also consider user, port, querystring, anchor etc
		return this.path.startsWith(rhs.path);
	}

	URL opBinary(string OP)(Path rhs) const if( OP == "~" ) { return URL(m_schema, m_host, m_port, this.path ~ rhs); }
	URL opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { return URL(m_schema, m_host, m_port, this.path ~ rhs); }
	void opOpAssign(string OP)(Path rhs) if( OP == "~" ) { this.path = this.path ~ rhs; }
	void opOpAssign(string OP)(PathEntry rhs) if( OP == "~" ) { this.path = this.path ~ rhs; }

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


unittest {
	auto urlstr = "https://www.example.net/index.html";
	auto url = URL.parse(urlstr);
	assert(url.schema == "https", url.schema);
	assert(url.host == "www.example.net", url.host);
	assert(url.path == Path("/index.html"), url.path.toString());
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
