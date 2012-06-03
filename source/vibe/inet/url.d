/**
	URL parsing routines.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.url;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;

/**
	Represents a URL decomposed into its components.
*/
struct Url {
	private {
		string m_schema;
		string m_pathString;
		Path m_path;
		string m_host;
		ushort m_port;
		string m_username;
		string m_password;
		string m_queryString;
		string m_anchor;
	}

	this(string schema, string host, ushort port, Path path)
	{
		m_schema = schema;
		m_host = host;
		m_port = port;
		m_path = path;
		m_pathString = path.toString(true);
	}

	// TODO: additional validation required (e.g. valid host and user names and port)
	static Url parse(string str)
	{
		Url ret;

		enforce(str.length > 0, "Empty URL.");
		if( str[0] != '/' ){
			auto idx = str.countUntil(':');
			enforce(idx > 0, "No schema in URL:"~str);
			ret.m_schema = str[0 .. idx];
			str = str[idx+1 .. $];

			switch(ret.schema){
				case "http":
				case "https":
				case "ftp":
				case "spdy":
				case "sftp":
				case "file":
					// proto://server/path style
					enforce(str.startsWith("//"), "URL must start with proto://...");
					str = str[2 .. $];
					goto default;
				default:
					auto si = str.countUntil('/');
					if( si < 0 ) si = str.length;
					auto ai = str[0 .. si].countUntil('@');
					sizediff_t hs = 0;
					if( ai >= 0 ){
						hs = ai+1;
						auto ci = str[0 .. ai].countUntil(':');
						if( ci >= 0 ){
							ret.m_username = str[0 .. ci];
							ret.m_password = str[ci+1 .. ai];
						} else ret.m_username = str[0 .. ai];
						enforce(ret.m_username.length > 0, "Empty user name in URL.");
					}

					ret.m_host = str[hs .. si];
					auto pi = ret.host.countUntil(':');
					if(pi > 0) {
						enforce(pi < ret.m_host.length-1, "Empty port in URL.");
						ret.m_port = to!ushort(ret.m_host[pi+1..$]);
						ret.m_host = ret.host[0 .. pi];
					}

					enforce(ret.schema == "file" || ret.m_host.length > 0, "Empty server name in URL.");
					str = str[si .. $];
			}
		}

		ret.localURI = str;

		return ret;
	}

	/// The schema/protocol part of the URL
	@property string schema() const { return m_schema; }
	/// ditto
	@property void schema(string v) { m_schema = v; }

	/// The path part of the URL
	@property string pathString() const { return m_pathString; }
	/// ditto
	@property Path path() const { return m_path; }
	/// ditto
	@property void path(Path p)
	{
		m_path = p;
		auto pstr = p.toString();
		m_pathString = pstr;
	}

	/// The host part of the URL
	@property string host() const { return m_host; }
	/// ditto
	@property void host(string v) { m_host = v; }

	@property ushort port() const { return m_port; }
	@property port(ushort v) { m_port = v; }
	@property string username() const { return m_username; }
	@property void username(string v) { m_username = v; }
	@property string password() const { return m_password; }
	@property void password(string v) { m_password = v; }
	@property string queryString() const { return m_queryString; }
	@property void queryString(string v) { m_queryString = v; }
	@property string anchor() const { return m_anchor; }

	/// The path part plus query string and anchor
	@property string localURI()
	const { 
		auto str = appender!string();
		str.put(path.toString(true));
		if( queryString.length ) {
			str.put("&");
			str.put(queryString);
		} 
		if( anchor.length ) {
			str.put("#");
			str.put(anchor);
		}
		return str.data;
	}

	@property void localURI(string str)
	{
		auto ai = str.countUntil('#');
		if( ai >= 0 ){
			m_anchor = str[ai+1 .. $];
			str = str[0 .. ai];
		}

		auto qi = str.countUntil('?');
		if( qi >= 0 ){
			m_queryString = str[qi+1 .. $];
			str = str[0 .. qi];
		}

		m_pathString = str;
		m_path = Path(str);
	}

	@property Url parentUrl() const {
		Url ret;
		ret.schema = schema;
		ret.host = host;
		ret.port = port;
		ret.username = username;
		ret.password = password;
		ret.path = path.parentPath;
		return ret;
	}


	string toString()
	const {
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
		dst.put(host);
		dst.put(localURI);
 		return dst.data;
	}

	bool startsWith(const Url rhs) const {
		if( m_schema != rhs.m_schema ) return false;
		if( m_host != rhs.m_host ) return false;
		// FIXME: also consider user, port, querystring, anchor etc
		return path.startsWith(rhs.m_path);
	}

	Url opBinary(string OP)(Path rhs) const if( OP == "~" ) { return Url(m_schema, m_host, m_port, m_path ~ rhs); }
	Url opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { return Url(m_schema, m_host, m_port, m_path ~ rhs); }
	void opOpAssign(string OP)(Path rhs) if( OP == "~" ) { m_path ~= rhs; }
	void opOpAssign(string OP)(PathEntry rhs) if( OP == "~" ) { m_path ~= rhs; }

	bool opEquals(ref const Url rhs) const {
		if( m_schema != rhs.m_schema ) return false;
		if( m_host != rhs.m_host ) return false;
		if( m_path != rhs.m_path ) return false;
		return true;
	}

	int opCmp(ref const Url rhs) const {
		if( m_schema != rhs.m_schema ) return m_schema.cmp(rhs.m_schema);
		if( m_host != rhs.m_host ) return m_host.cmp(rhs.m_host);
		if( m_path != rhs.m_path ) return m_path.opCmp(rhs.m_path);
		return true;
	}
}

unittest {
	auto url = Url.parse("https://www.example.net/index.html");
	assert(url.schema == "https", url.schema);
	assert(url.host == "www.example.net", url.host);
	assert(url.path == Path("/index.html"), url.path.toString());
	
	url = Url.parse("http://jo.doe:password@sub.www.example.net:4711/sub2/index.html?query#anchor");
	assert(url.schema == "http", url.schema);
	assert(url.username == "jo.doe", url.username);
	assert(url.password == "password", url.password);
	assert(url.port == 4711, to!string(url.port));
	assert(url.host == "sub.www.example.net", url.host);
	assert(url.path.toString() == "/sub2/index.html", url.path.toString());
	assert(url.queryString == "query", url.queryString);
	assert(url.anchor == "anchor", url.anchor);
}

/**
	Represents an absolute or relative file system path.

	This struct allows to do safe operations on paths, such as concatenation and sub paths. Checks
	are done to disallow invalid operations such as concatenating two absolute paths. It also
	validates path strings and allows for easy checking of malicious relative paths.
*/
struct Path {
	private {
		immutable(PathEntry)[] m_nodes;
		bool m_absolute = false;
		bool m_endsWithSlash = false;
	}
	
	this(string pathstr)
	{
		m_absolute = (pathstr.startsWith("/") || pathstr.length >= 2 && pathstr[1] == ':');
		m_nodes = cast(immutable)splitPath(pathstr);
		assert(!pathstr.startsWith("/") || m_nodes[0].toString() == "");
		if( pathstr.startsWith("/") ) m_nodes = m_nodes[1 .. $];
		if( m_nodes.length > 0 && !m_nodes[$-1].toString().length ){
			m_endsWithSlash = true;
			m_nodes = m_nodes[0 .. $-1];
		}
		
		foreach( e; m_nodes ) assert(e.toString().length > 0);
	}
	
	this(immutable(PathEntry)[] nodes, bool absolute)
	{
		m_nodes = nodes;
		m_absolute = absolute;
	}
	
	this(PathEntry entry){
		m_nodes = [entry];
		m_absolute = false;
	}
	
	@property bool absolute() const { return m_absolute; }

	void normalize()
	{
		immutable(PathEntry)[] newnodes;
		foreach( n; m_nodes ){
			switch(n.toString()){
				default:
					newnodes ~= n;
					break;
				case ".": break;
				case "..":
					enforce(!m_absolute || newnodes.length > 0, "Path goes below root node.");
					if( newnodes.length > 0 && newnodes[$-1] != ".." ) newnodes = newnodes[0 .. $-1];
					else newnodes ~= n;
					break;
			}
		}
		m_nodes = newnodes;
	}
	
	string toString(bool in_url = false) const {
		if( m_nodes.empty ) return absolute ? "/" : "";
		
		Appender!string ret;
		
		// for absolute unix paths start with /
		if( in_url || absolute && !m_nodes[0].toString().endsWith(":") ) ret.put('/');
		
		foreach( i, f; m_nodes ){
			if( i > 0 ) ret.put('/');
			ret.put(f.toString());
		}

		if( m_nodes.length > 0 && m_endsWithSlash )
			ret.put('/');
		
		return ret.data;
	}
	
	string toNativeString() const {
		Appender!string ret;
		
		// for absolute unix paths start with /
		version(Posix) { if(absolute) ret.put('/'); }
		
		foreach( i, f; m_nodes ){
			version(Windows) { if( i > 0 ) ret.put('\\'); }
			version(Posix) { if( i > 0 ) ret.put('/'); }
			else { enforce("Unsupported OS"); }
			ret.put(f.toString());
		}
		
		if( m_nodes.length > 0 && m_endsWithSlash ){
			version(Windows) { ret.put('\\'); }
			version(Posix) { ret.put('/'); }
		}
		
		return ret.data;
	}
	
	bool startsWith(const Path rhs) const {
		if( rhs.m_nodes.length > m_nodes.length ) return false;
		foreach( i; 0 .. rhs.m_nodes.length )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return false;
		return true;
	}
	
	Path relativeTo(const Path parentPath) const {
		int nup = 0;
		while( parentPath.length > nup && !startsWith(parentPath[0 .. parentPath.length-nup]) ){
			nup++;
		}
		Path ret = Path(null, false);
		ret.m_endsWithSlash = true;
		foreach( i; 0 .. nup ) ret ~= "..";
		ret ~= Path(m_nodes[parentPath.length-nup .. $], false);
		return ret;
	}
	
	@property PathEntry head() const { enforce(m_nodes.length > 0); return m_nodes[$-1]; }
	@property Path parentPath() const { return this[0 .. length-1]; }
	@property immutable(PathEntry)[] nodes() const { return m_nodes; }
	@property size_t length() const { return m_nodes.length; }
	@property bool empty() const { return m_nodes.length == 0; }

	/// Determines if this path goes outside of its base path (i.e. begins with '..').
	@property bool external() const { return !m_absolute && m_nodes.length > 0 && m_nodes[0].m_name == ".."; }
		
	PathEntry opIndex(size_t idx) const { return m_nodes[idx]; }
	Path opSlice(size_t start, size_t end) const {
		auto ret = Path(m_nodes[start .. end], start == 0 ? absolute : false);
		if( end == m_nodes.length ) ret.m_endsWithSlash = m_endsWithSlash;
		return ret;
	}
	size_t opDollar(int dim)() const if(dim == 0) { return m_nodes.length; }
	
	
	Path opBinary(string OP)(const Path rhs) const if( OP == "~" ) {
		Path ret;
		ret.m_nodes = m_nodes;
		ret.m_absolute = m_absolute;
		ret.m_endsWithSlash = rhs.m_endsWithSlash;
		
		assert(!rhs.absolute);
		size_t idx = m_nodes.length;
		foreach(folder; rhs.m_nodes){
			switch(folder.toString()){
				default: ret.m_nodes = ret.m_nodes ~ folder; break;
				case ".": break;
				case "..":
					enforce(!ret.absolute || ret.m_nodes.length > 0, "Relative path goes below root node!");
					if( ret.m_nodes.length > 0 && ret.m_nodes[$-1].toString() != ".." )
						ret.m_nodes = ret.m_nodes[0 .. $-1];
					else ret.m_nodes = ret.m_nodes ~ folder;
					break;
			}
		}
		return ret;
	}
	
	Path opBinary(string OP)(string rhs) const if( OP == "~" ) { assert(rhs.length > 0); return opBinary!"~"(Path(rhs)); }
	Path opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { assert(rhs.toString().length > 0); return opBinary!"~"(Path(rhs)); }
	void opOpAssign(string OP)(string rhs) if( OP == "~" ) { assert(rhs.length > 0); opOpAssign!"~"(Path(rhs)); }
	void opOpAssign(string OP)(PathEntry rhs) if( OP == "~" ) { assert(rhs.toString().length > 0); opOpAssign!"~"(Path(rhs)); }
	void opOpAssign(string OP)(Path rhs) if( OP == "~" ) { auto p = this ~ rhs; m_nodes = p.m_nodes; m_endsWithSlash = rhs.m_endsWithSlash; }
	
	bool opEquals(ref const Path rhs) const {
		if( m_absolute != rhs.m_absolute ) return false;
		if( m_endsWithSlash != rhs.m_endsWithSlash ) return false;
		if( m_nodes.length != rhs.length ) return false;
		foreach( i; 0 .. m_nodes.length )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return false;
		return true;
	}

	int opCmp(ref const Path rhs) const {
		if( m_absolute != rhs.m_absolute ) return cast(int)m_absolute - cast(int)rhs.m_absolute;
		if( m_nodes.length != rhs.length ) return false;
		foreach( i; 0 .. min(m_nodes.length, rhs.m_nodes.length) )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return m_nodes[i].opCmp(rhs.m_nodes[i]);
		if( m_nodes.length > rhs.m_nodes.length ) return 1;
		if( m_nodes.length < rhs.m_nodes.length ) return -1;
		return 0;
	}
}

struct PathEntry {
	private {
		string m_name;
	}
	
	this(string str)
	{
		assert(str.countUntil('/') < 0 && str.countUntil('\\') < 0);
		m_name = str;
	}
	
	string toString() const { return m_name; }

	Path opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { return Path(cast(immutable)[this, rhs], false); }
	
	bool opEquals(ref const PathEntry rhs) const { return m_name == rhs.m_name; }
	bool opEquals(string rhs) const { return m_name == rhs; }
	int opCmp(ref const PathEntry rhs) const { return m_name.cmp(rhs.m_name); }
	int opCmp(string rhs) const { return m_name.cmp(rhs); }
}

private bool isValidFilename(string str)
{
	foreach( ch; str )
		if( ch == '/' || /*ch == ':' ||*/ ch == '\\' ) return false;
	return true;
}

/// Joins two path strings. subpath must be relative.
string joinPath(string basepath, string subpath)
{
	Path p1 = Path(basepath);
	Path p2 = Path(subpath);
	return (p1 ~ p2).toString();
}

/// Splits up a path string into its elements/folders
PathEntry[] splitPath(string path)
{
	if( path.empty ) return null;
	
	// count the number of path nodes
	size_t nelements = 0;
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' )
			nelements++;
	nelements++;
	
	// reserve space for the elements
	auto elements = new PathEntry[nelements];

	// read and return the elements
	size_t startidx = 0;
	size_t eidx = 0;
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' ){
			elements[eidx++] = PathEntry(path[startidx .. i]);
			startidx = i+1;
		}
	elements[eidx++] = PathEntry(path[startidx .. $]);
	assert(eidx == nelements);
	return elements;
}
