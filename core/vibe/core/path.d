/**
	Contains routines for high level path handling.

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.path;

import std.algorithm : canFind, min;
import std.array;
import std.conv;
import std.exception;
import std.string;


/** Computes the relative path from `base_path` to this path.

	Params:
		path = The destination path
		base_path = The path from which the relative path starts

	See_also: `relativeToWeb`
*/
Path relativeTo(Path path, Path base_path)
@safe{
	assert(path.absolute && base_path.absolute);
	version (Windows) {
		// a path such as ..\C:\windows is not valid, so force the path to stay absolute in this case
		if (path.absolute && !path.empty &&
			(path[0].toString().endsWith(":") && !base_path.startsWith(path[0 .. 1]) ||
			path[0] == "\\" && !base_path.startsWith(path[0 .. min(2, $)])))
		{
			return path;
		}
	}
	int nup = 0;
	while (base_path.length > nup && !path.startsWith(base_path[0 .. base_path.length-nup])) {
		nup++;
	}

	Path ret = Path(null, false);
	ret.m_endsWithSlash = true;
	foreach (i; 0 .. nup) ret ~= "..";
	ret ~= Path(path.nodes[base_path.length-nup .. $], false);
	ret.m_endsWithSlash = path.m_endsWithSlash;
	return ret;
}

///
unittest {
	assert(Path("/some/path").relativeTo(Path("/")) == Path("some/path"));
	assert(Path("/some/path/").relativeTo(Path("/some/other/path/")) == Path("../../path/"));
	assert(Path("/some/path/").relativeTo(Path("/some/other/path")) == Path("../../path/"));
}


/** Computes the relative path to this path from `base_path` using web path rules.

	The difference to `relativeTo` is that a path not ending in a slash
	will not be considered as a path to a directory and the parent path
	will instead be used.

	Params:
		path = The destination path
		base_path = The path from which the relative path starts

	See_also: `relativeTo`
*/
Path relativeToWeb(Path path, Path base_path)
@safe {
	if (!base_path.endsWithSlash) {
		if (base_path.length > 0) base_path = base_path[0 .. $-1];
		else base_path = Path("/");
	}
	return path.relativeTo(base_path);
}

///
unittest {
	assert(Path("/some/path").relativeToWeb(Path("/")) == Path("some/path"));
	assert(Path("/some/path/").relativeToWeb(Path("/some/other/path/")) == Path("../../path/"));
	assert(Path("/some/path/").relativeToWeb(Path("/some/other/path")) == Path("../path/"));
}


/// Forward compatibility alias for vibe-core
alias NativePath = Path;
/// ditto
alias PosixPath = Path;
/// ditto
alias WindowsPath = Path;
/// ditto
alias InetPath = Path;


/**
	Represents an absolute or relative file system path.

	This struct allows to do safe operations on paths, such as concatenation and sub paths. Checks
	are done to disallow invalid operations such as concatenating two absolute paths. It also
	validates path strings and allows for easy checking of malicious relative paths.
*/
struct Path {
@safe:
	/// Forward compatibility alias for vibe-core
	alias Segment = PathEntry;

	private {
		immutable(PathEntry)[] m_nodes;
		bool m_absolute = false;
		bool m_endsWithSlash = false;
	}

	hash_t toHash()
	const nothrow @trusted {
		hash_t ret;
		auto strhash = &typeid(string).getHash;
		try foreach (n; nodes) ret ^= strhash(&n.m_name);
		catch (Throwable) assert(false);
		if (m_absolute) ret ^= 0xfe3c1738;
		if (m_endsWithSlash) ret ^= 0x6aa4352d;
		return ret;
	}

	pure:

	/// Constructs a Path object by parsing a path string.
	this(string pathstr)
	{
		m_nodes = splitPath(pathstr);
		m_absolute = (pathstr.startsWith("/") || m_nodes.length > 0 && (m_nodes[0].toString().canFind(':') || m_nodes[0] == "\\"));
		m_endsWithSlash = pathstr.endsWith("/");
		version(Windows) m_endsWithSlash |= pathstr.endsWith(`\`);
	}

	/// Constructs a path object from a list of PathEntry objects.
	this(immutable(PathEntry)[] nodes, bool absolute)
	{
		m_nodes = nodes;
		m_absolute = absolute;
	}

	/// Constructs a relative path with one path entry.
	this(PathEntry entry)
	{
		m_nodes = [entry];
		m_absolute = false;
	}

	/// Determines if the path is absolute.
	@property bool absolute() const { return m_absolute; }

	/// Forward compatibility property for vibe-code
	@property auto bySegment()
	const @nogc {
		import std.range : chain;

		if (m_absolute) {
			static immutable emptyseg = [PathEntry("")];
			return chain(emptyseg[], nodes);
		} else {
			static immutable PathEntry[] noseg;
			return chain(noseg[], nodes);
		}
	}

	/// Resolves all '.' and '..' path entries as far as possible.
	void normalize()
	{
		immutable(PathEntry)[] newnodes;
		foreach( n; m_nodes ){
			switch(n.toString()){
				default:
					newnodes ~= n;
					break;
				case "", ".": break;
				case "..":
					enforce(!m_absolute || newnodes.length > 0, "Path goes below root node.");
					if( newnodes.length > 0 && newnodes[$-1] != ".." ) newnodes = newnodes[0 .. $-1];
					else newnodes ~= n;
					break;
			}
		}
		m_nodes = newnodes;
	}

	/// Converts the Path back to a string representation using slashes.
	string toString()
	const {
		if (m_nodes.empty)
			return absolute ? "/" : endsWithSlash ? "./" : "";

		Appender!string ret;

		// for absolute paths start with /
		if( absolute ) ret.put('/');

		foreach( i, f; m_nodes ){
			if( i > 0 ) ret.put('/');
			ret.put(f.toString());
		}

		if( m_nodes.length > 0 && m_endsWithSlash )
			ret.put('/');

		return ret.data;
	}

	/// Converts the Path object to a native path string (backslash as path separator on Windows).
	string toNativeString() nothrow
	const {
		Appender!string ret;

		// for absolute unix paths start with /
		version(Posix) { if (m_absolute) ret.put('/'); }

		foreach( i, f; m_nodes ){
			version(Windows) { if( i > 0 ) ret.put('\\'); }
			else version(Posix) { if( i > 0 ) ret.put('/'); }
			else static assert(false, "Unsupported OS");
			ret.put(f.toString());
		}

		if( m_nodes.length > 0 && m_endsWithSlash ){
			version(Windows) { ret.put('\\'); }
			version(Posix) { ret.put('/'); }
		}

		return ret.data;
	}

	/// Tests if `rhs` is an anchestor or the same as this path.
	bool startsWith(const Path rhs) const {
		if( rhs.m_nodes.length > m_nodes.length ) return false;
		foreach( i; 0 .. rhs.m_nodes.length )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return false;
		return true;
	}

	/// The last entry of the path
	@property ref immutable(PathEntry) head() const { enforce(m_nodes.length > 0); return m_nodes[$-1]; }

	/// The parent path
	@property Path parentPath() const { return this[0 .. length-1]; }

	/// The ist of path entries of which this path is composed
	@property immutable(PathEntry)[] nodes() const @nogc { return m_nodes; }

	/// The number of path entries of which this path is composed
	@property size_t length() const { return m_nodes.length; }

	/// True if the path contains no entries
	@property bool empty() const { return m_nodes.length == 0; }

	/// Determines if the path ends with a slash (i.e. is a directory)
	@property bool endsWithSlash() const { return m_endsWithSlash; }
	/// ditto
	@property void endsWithSlash(bool v) { m_endsWithSlash = v; }

	/// Determines if this path goes outside of its base path (i.e. begins with '..').
	@property bool external() const { return !m_absolute && m_nodes.length > 0 && m_nodes[0].m_name == ".."; }

	ref immutable(PathEntry) opIndex(size_t idx) const { return m_nodes[idx]; }
	Path opSlice(size_t start, size_t end) const {
		auto ret = Path(m_nodes[start .. end], start == 0 ? absolute : false);
		ret.m_endsWithSlash = end == m_nodes.length ? m_endsWithSlash : true;
		return ret;
	}
	size_t opDollar(int dim)() const if(dim == 0) { return m_nodes.length; }


	Path opBinary(string OP)(const Path rhs) const if( OP == "~" )
	{
		assert(!rhs.absolute, "Trying to append absolute path.");
		if (!rhs.length) return this;

		Path ret;
		ret.m_nodes = m_nodes;
		ret.m_absolute = m_absolute;
		ret.m_endsWithSlash = rhs.m_endsWithSlash;
		ret.normalize(); // needed to avoid "."~".." become "" instead of ".."

		foreach (folder; rhs.m_nodes) {
			switch (folder.toString()) {
				default: ret.m_nodes = ret.m_nodes ~ folder; break;
				case "", ".": break;
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

	Path opBinary(string OP)(string rhs) const if( OP == "~" ) { return opBinary!"~"(Path(rhs)); }
	Path opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { return opBinary!"~"(Path(rhs)); }
	void opOpAssign(string OP)(string rhs) if( OP == "~" ) { opOpAssign!"~"(Path(rhs)); }
	void opOpAssign(string OP)(PathEntry rhs) if( OP == "~" ) { opOpAssign!"~"(Path(rhs)); }
	void opOpAssign(string OP)(immutable(PathEntry)[] rhs) if( OP == "~" ) { opOpAssign!"~"(Path(rhs, false)); }
	void opOpAssign(string OP)(Path rhs) if( OP == "~" )
	{
		assert(!rhs.absolute, "Trying to append absolute path.");
		if (!rhs.length) return;
		auto p = this ~ rhs;
		m_nodes = p.m_nodes;
		m_endsWithSlash = rhs.m_endsWithSlash;
	}

	/// Tests two paths for equality using '=='.
	bool opEquals(ref const Path rhs) const {
		if( m_absolute != rhs.m_absolute ) return false;
		if( m_endsWithSlash != rhs.m_endsWithSlash ) return false;
		if( m_nodes.length != rhs.length ) return false;
		foreach( i; 0 .. m_nodes.length )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return false;
		return true;
	}
	/// ditto
	bool opEquals(const Path other) const { return opEquals(other); }

	int opCmp(ref const Path rhs) const {
		if( m_absolute != rhs.m_absolute ) return cast(int)m_absolute - cast(int)rhs.m_absolute;
		foreach( i; 0 .. min(m_nodes.length, rhs.m_nodes.length) )
			if( m_nodes[i] != rhs.m_nodes[i] )
				return m_nodes[i].opCmp(rhs.m_nodes[i]);
		if( m_nodes.length > rhs.m_nodes.length ) return 1;
		if( m_nodes.length < rhs.m_nodes.length ) return -1;
		return 0;
	}
}


unittest
{
	{
		auto unc = "\\\\server\\share\\path";
		auto uncp = Path(unc);
		uncp.normalize();
		version(Windows) assert(uncp.toNativeString() == unc);
		assert(uncp.absolute);
		assert(!uncp.endsWithSlash);
	}

	{
		auto abspath = "/test/path/";
		auto abspathp = Path(abspath);
		assert(abspathp.toString() == abspath);
		version(Windows) {} else assert(abspathp.toNativeString() == abspath);
		assert(abspathp.absolute);
		assert(abspathp.endsWithSlash);
		assert(abspathp.length == 2);
		assert(abspathp[0] == "test");
		assert(abspathp[1] == "path");
	}

	{
		auto relpath = "test/path/";
		auto relpathp = Path(relpath);
		assert(relpathp.toString() == relpath);
		version(Windows) assert(relpathp.toNativeString() == "test\\path\\");
		else assert(relpathp.toNativeString() == relpath);
		assert(!relpathp.absolute);
		assert(relpathp.endsWithSlash);
		assert(relpathp.length == 2);
		assert(relpathp[0] == "test");
		assert(relpathp[1] == "path");
	}

	{
		auto winpath = "C:\\windows\\test";
		auto winpathp = Path(winpath);
		assert(winpathp.toString() == "/C:/windows/test");
		version(Windows) assert(winpathp.toNativeString() == winpath);
		else assert(winpathp.toNativeString() == "/C:/windows/test");
		assert(winpathp.absolute);
		assert(!winpathp.endsWithSlash);
		assert(winpathp.length == 3);
		assert(winpathp[0] == "C:");
		assert(winpathp[1] == "windows");
		assert(winpathp[2] == "test");
	}

	{
		auto dotpath = "/test/../test2/././x/y";
		auto dotpathp = Path(dotpath);
		assert(dotpathp.toString() == "/test/../test2/././x/y");
		dotpathp.normalize();
		assert(dotpathp.toString() == "/test2/x/y");
	}

	{
		auto dotpath = "/test/..////test2//./x/y";
		auto dotpathp = Path(dotpath);
		assert(dotpathp.toString() == "/test/..////test2//./x/y");
		dotpathp.normalize();
		assert(dotpathp.toString() == "/test2/x/y");
	}

	{
		auto parentpath = "/path/to/parent";
		auto parentpathp = Path(parentpath);
		auto subpath = "/path/to/parent/sub/";
		auto subpathp = Path(subpath);
		auto subpath_rel = "sub/";
		assert(subpathp.relativeTo(parentpathp).toString() == subpath_rel);
		auto subfile = "/path/to/parent/child";
		auto subfilep = Path(subfile);
		auto subfile_rel = "child";
		assert(subfilep.relativeTo(parentpathp).toString() == subfile_rel);
	}

	{ // relative paths across Windows devices are not allowed
		version (Windows) {
			auto p1 = Path("\\\\server\\share"); assert(p1.absolute);
			auto p2 = Path("\\\\server\\othershare"); assert(p2.absolute);
			auto p3 = Path("\\\\otherserver\\share"); assert(p3.absolute);
			auto p4 = Path("C:\\somepath"); assert(p4.absolute);
			auto p5 = Path("C:\\someotherpath"); assert(p5.absolute);
			auto p6 = Path("D:\\somepath"); assert(p6.absolute);
			assert(p4.relativeTo(p5) == Path("../somepath"));
			assert(p4.relativeTo(p6) == Path("C:\\somepath"));
			assert(p4.relativeTo(p1) == Path("C:\\somepath"));
			assert(p1.relativeTo(p2) == Path("../share"));
			assert(p1.relativeTo(p3) == Path("\\\\server\\share"));
			assert(p1.relativeTo(p4) == Path("\\\\server\\share"));
		}
	}

	{ // relative path, trailing slash
		auto p1 = Path("/some/path");
		auto p2 = Path("/some/path/");
		assert(p1.relativeTo(p1).toString() == "");
		assert(p1.relativeTo(p2).toString() == "");
		assert(p2.relativeTo(p2).toString() == "./");
		assert(p2.relativeTo(p1).toString() == "./");
	}

	// trailing back-slash on Windows
	version(Windows)
	{
		auto winpath = "C:\\windows\\test\\";
		auto winpathp = Path(winpath);
		assert(winpathp.toNativeString() == winpath);
	}
}


unittest {
	import std.algorithm.comparison : equal;
	import std.range : only;

	assert(Path("/foo/").bySegment.equal(
		only(Path.Segment(""), Path.Segment("foo"))
	));
	assert(Path("foo/").bySegment.equal(
		only(Path.Segment("foo"))
	));
	version (Windows) {
		assert(Path("C:\\foo\\").bySegment.equal(
			only(Path.Segment(""), Path.Segment("C:"), Path.Segment("foo"))
		));
	}
}


struct PathEntry {
@safe: pure:

	private {
		string m_name;
	}

	static PathEntry validateFilename(string fname)
	{
		enforce(fname.indexOfAny("/\\") < 0, "File name contains forward or backward slashes: "~fname);
		return PathEntry(fname);
	}

	this(string str)
	{
		assert(!str.canFind('/') && (!str.canFind('\\') || str.length == 1), "Invalid path entry: " ~ str);
		m_name = str;
	}

	string toString() const nothrow { return m_name; }

	Path opBinary(string OP)(PathEntry rhs) const if( OP == "~" ) { return Path([this, rhs], false); }

	@property string name() const nothrow { return m_name; }

	bool opEquals(ref const PathEntry rhs) const { return m_name == rhs.m_name; }
	bool opEquals(PathEntry rhs) const { return m_name == rhs.m_name; }
	bool opEquals(string rhs) const { return m_name == rhs; }
	int opCmp(ref const PathEntry rhs) const { return m_name.cmp(rhs.m_name); }
	int opCmp(string rhs) const { return m_name.cmp(rhs); }
}

private bool isValidFilename(string str)
pure @safe {
	foreach( ch; str )
		if( ch == '/' || /*ch == ':' ||*/ ch == '\\' ) return false;
	return true;
}

/// Joins two path strings. subpath must be relative.
string joinPath(string basepath, string subpath)
pure @safe {
	Path p1 = Path(basepath);
	Path p2 = Path(subpath);
	return (p1 ~ p2).toString();
}

/// Splits up a path string into its elements/folders
PathEntry[] splitPath(string path)
pure @safe {
	if( path.startsWith("/") || path.startsWith("\\") ) path = path[1 .. $];
	if( path.empty ) return null;
	if( path.endsWith("/") || path.endsWith("\\") ) path = path[0 .. $-1];

	// count the number of path nodes
	size_t nelements = 0;
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' )
			nelements++;
	nelements++;

	// reserve space for the elements
	PathEntry[] storage;
	/*if (alloc) {
		auto mem = alloc.alloc(nelements * PathEntry.sizeof);
		mem[] = 0;
		storage = cast(PathEntry[])mem;
	} else*/ storage = new PathEntry[nelements];

	size_t startidx = 0;
	size_t eidx = 0;

	// detect UNC path
	if(path.startsWith("\\"))
	{
		storage[eidx++] = PathEntry(path[0 .. 1]);
		path = path[1 .. $];
	}

	// read and return the elements
	foreach( i, char ch; path )
		if( ch == '\\' || ch == '/' ){
			storage[eidx++] = PathEntry(path[startidx .. i]);
			startidx = i+1;
		}
	storage[eidx++] = PathEntry(path[startidx .. $]);
	assert(eidx == nelements);
	return storage;
}
