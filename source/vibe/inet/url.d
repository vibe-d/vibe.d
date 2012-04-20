/**
	URL parsing routines.

	Copyright: © 2012 Sönke Ludwig
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
	string schema;
	Path path;
	string host;
	ushort port;
	string username;
	string password;
	string querystring;
	string anchor;
	string localURI;

	// TODO: additional validation required (e.g. valid host and user names and port)
	static Url parse(string str)
	{
		Url ret;

		enforce(str.length > 0, "Empty URL.");
		if( str[0] != '/' ){
			auto idx = str.countUntil(':');
			enforce(idx > 0, "No schema in URL:"~str);
			ret.schema = str[0 .. idx];
			str = str[idx+1 .. $];

			switch(ret.schema){
				case "http":
				case "https":
				case "ftp":
				case "spdy":
				case "sftp":
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
							ret.username = str[0 .. ci];
							ret.password = str[ci+1 .. ai];
						} else ret.username = str[0 .. ai];
						enforce(ret.username.length > 0, "Empty user name in URL.");
					}

					ret.host = str[hs .. si];
					auto pi = ret.host.countUntil(':');
					if(pi > 0) {
						ret.port = to!ushort(ret.host[pi+1..$]);
						ret.host = ret.host[0 .. pi];
					}

					enforce(ret.host.length > 0, "Empty server name in URL.");
					str = str[si .. $];
			}
		}

		ret.localURI = str;

		auto ai = str.countUntil('#');
		if( ai >= 0 ){
			ret.anchor = str[ai+1 .. $];
			str = str[0 .. ai];
		}

		auto qi = str.countUntil('?');
		if( qi >= 0 ){
			ret.querystring = str[qi+1 .. $];
			str = str[0 .. qi];
		}

		ret.path = Path(str);

		return ret;
	}

	string toString()
	const {
		auto dst = appender!string();
		dst.put(schema);
		dst.put(":");
		switch(schema){
			default: break;
			case "http":
			case "https":
			case "ftp":
			case "spdy":
			case "sftp":
				dst.put("//");
				break;
		}
		dst.put(path.toString());
		if( querystring.length ){
			dst.put('?');
			dst.put(querystring);
		}

		if( anchor.length ){
			dst.put('#');
			dst.put(anchor);
		}
		return dst.data;
	}
}

unittest {
	auto url = Url.parse("https://www.example.net/index.html");
	assert(url.schema == "https", url.schema);
	assert(url.host == "www.example.net", url.host);
	assert(url.path == "/index.html", url.path);
	
	url = Url.parse("http://jo.doe:password@sub.www.example.net:4711/sub2/index.html?query#anchor");
	assert(url.schema == "http", url.schema);
	assert(url.username == "jo.doe", url.username);
	assert(url.password == "password", url.password);
	assert(url.port == "4711", url.port);
	assert(url.host == "sub.www.example.net", url.host);
	assert(url.path == "/sub2/index.html", url.path);
	assert(url.querystring == "query", url.querystring);
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
	}
	
	this(string pathstr)
	{
		m_absolute = (pathstr.startsWith("/") || pathstr.length >= 2 && pathstr[1] == ':');
		m_nodes = cast(immutable)splitPath(pathstr);
		assert(!pathstr.startsWith("/") || m_nodes[0].toString() == "");
		if( pathstr.startsWith("/") ) m_nodes = m_nodes[1 .. $];
		
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
	
	string toString() const {
		if( m_nodes.empty ) return absolute ? "/" : "";
		
		Appender!string ret;
		
		// for absolute unix paths start with /
		if( absolute && !m_nodes[0].toString().endsWith(":") ) ret.put('/');
		
		foreach( i, f; m_nodes ){
			if( i > 0 ) ret.put('/');
			ret.put(f.toString());
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
	Path opSlice(size_t start, size_t end) const { return Path(m_nodes[start .. end], start == 0 ? absolute : false); }
	size_t opDollar(int dim)() const if(dim == 0) { return m_nodes.length; }
	
	
	Path opBinary(string OP)(const Path rhs) const if( OP == "~" ) {
		Path ret;
		ret.m_nodes = m_nodes;
		ret.m_absolute = m_absolute;
		
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
	void opOpAssign(string OP)(Path rhs) if( OP == "~" ) { auto p = this ~ rhs; m_nodes = p.m_nodes; }
	
	bool opEquals(ref const Path rhs) const {
		if( m_absolute != rhs.m_absolute ) return false;
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
	int opCmp(ref const PathEntry rhs) const { return m_name.cmp(rhs.m_name); }
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
	if( path[$-1] != '/' && path[$-1] != '\\' ) nelements++;
	
	// reserve space for the elements
	PathEntry[] elements;
	elements.reserve(nelements);

	// read and return the elements
	size_t startidx = 0;
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' ){
			elements ~= PathEntry(path[startidx .. i]);
			startidx = i+1;
		}
	if( startidx < path.length ) elements ~= PathEntry(path[startidx .. $]);
	return elements;
}
