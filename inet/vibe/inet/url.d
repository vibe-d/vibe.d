/**
	URL parsing routines.

	Copyright: © 2012-2017 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.url;

public import vibe.core.path;

import vibe.textfilter.urlencode;

import std.array;
import std.algorithm;
import std.conv;
import std.exception;
import std.string;
import std.traits : isInstanceOf;
import std.ascii : isAlpha, isASCII, toLower;
import std.uri: decode, encode;

import core.checkedint : addu;


/** Parses a user-provided URL with relaxed rules.

	Unlike `URL.parse`, this allows the URL to use special characters as part of
	the host name and path, automatically employing puny code or percent-encoding
	to convert this to a valid URL.

	Params:
		url = String representation of the URL
		default_schema = If `url` does not contain a schema name, the URL parser
			may choose to use this schema instead. A browser might use "http" or
			"https", for example.
*/
URL parseUserURL(string url, string default_schema)
{
	if (default_schema.length && !url.startsWith("/") && !url.canFind("://"))
		url = default_schema ~ "://" ~ url;

	return URL(url, false).normalized;
}

unittest {
	// special characters in path
	auto url = parseUserURL("http://example.com/hello-🌍", "foo");
	assert(url.pathString == "/hello-%F0%9F%8C%8D");
	url = parseUserURL("http://example.com/안녕하세요-세계", "foo");
	assert(url.pathString == "/%EC%95%88%EB%85%95%ED%95%98%EC%84%B8%EC%9A%94-%EC%84%B8%EA%B3%84");
	// special characters in host name
	url = parseUserURL("http://hello-🌍.com/", "foo");
	assert(url.host == "xn--hello--8k34e.com");
	url = parseUserURL("http://hello-🌍.com:8080/", "foo");
	assert(url.host == "xn--hello--8k34e.com");
	url = parseUserURL("http://i-❤-이모티콘.io", "foo");
	assert(url.host == "xn--i---5r6aq903fubqabumj4g.io");
	url = parseUserURL("https://hello🌍.i-❤-이모티콘.com", "foo");
	assert(url.host == "xn--hello-oe93d.xn--i---5r6aq903fubqabumj4g.com");
	// default schema addition
	assert(parseUserURL("example.com/foo/bar", "sftp") == URL("sftp://example.com/foo/bar"));
	assert(parseUserURL("example.com:1234", "https") == URL("https://example.com:1234/"));
}


/**
	Represents a URL decomposed into its components.
*/
struct URL {
@safe:
	private {
		string m_schema;
		InetPath m_path;
		string m_host;
		ushort m_port;
		string m_username;
		string m_password;
		string m_queryString;
		string m_anchor;
	}

	/// Constructs a new URL object from its components.
	this(string schema, string host, ushort port, InetPath path) pure nothrow
	in {
		assert(isValidSchema(schema), "Invalid URL schema name: " ~ schema);
		assert(host.length == 0 || isValidHostName(host), "Invalid URL host name: " ~ host);
	}
	do {
		m_schema = schema;
		m_host = host;
		m_port = port;
		m_path = path;
	}
	/// ditto
	this(string schema, InetPath path) pure nothrow
	in { assert(isValidSchema(schema)); }
	do {
		this(schema, null, 0, path);
	}
	/// ditto
	this(string schema, string host, ushort port, PosixPath path) pure nothrow
	in {
		assert(isValidSchema(schema));
		assert(host.length == 0 || isValidHostName(host));
	}
	do {
		InetPath ip;
		try ip = cast(InetPath)path;
		catch (Exception e) assert(false, e.msg); // InetPath should be able to capture all paths
		this(schema, host, port, ip);
	}
	/// ditto
	this(string schema, PosixPath path) pure nothrow
	in { assert(isValidSchema(schema)); }
	do {
		this(schema, null, 0, path);
	}
	/// ditto
	this(string schema, string host, ushort port, WindowsPath path) pure nothrow
	in {
		assert(isValidSchema(schema));
		assert(host.length == 0 || isValidHostName(host));
	}
	do {
		InetPath ip;
		try ip = cast(InetPath)path;
		catch (Exception e) assert(false, e.msg); // InetPath should be able to capture all paths
		this(schema, host, port, ip);
	}
	/// ditto
	this(string schema, WindowsPath path) pure nothrow
	in { assert(isValidSchema(schema)); }
	do {
		this(schema, null, 0, path);
	}

	/** Constructs a "file:" URL from a native file system path.

		Note that the path must be absolute. On Windows, both, paths starting
		with a drive letter and UNC paths are supported.
	*/
	this(WindowsPath path) pure
	{
		import std.algorithm.iteration : map;
		import std.range : chain, only, repeat;

		enforce(path.absolute, "Only absolute paths can be converted to a URL.");

		// treat UNC paths properly
		if (path.startsWith(WindowsPath(`\\`))) {
			static if (is(InetPath.Segment2)) {
				auto segs = path.bySegment2;
			} else {
				auto segs = path.bySegment;
			}
			segs.popFront();
			segs.popFront();
			auto host = segs.front.name;
			segs.popFront();

			InetPath ip;
			static if (is(InetPath.Segment2)) {
				ip = InetPath(only(InetPath.Segment2.fromTrustedString("", '/'))
					.chain(segs.map!(s => cast(InetPath.Segment2)s)));
			} else {
				ip = InetPath(only(InetPath.Segment("", '/'))
					.chain(segs.map!(s => cast(InetPath.Segment)s)));
			}

			this("file", host, 0, ip);
		} else this("file", host, 0, cast(InetPath)path);
	}
	/// ditto
	this(PosixPath path) pure
	{
		enforce(path.absolute, "Only absolute paths can be converted to a URL.");

		this("file", null, 0, cast(InetPath)path);
	}

	/** Constructs a URL from its string representation.

		TODO: additional validation required (e.g. valid host and user names and port)
	*/
	this(string url_string)
	{
		this(url_string, true);
	}

	private this(string url_string, bool encoded)
	{
		auto str = url_string;
		enforce(str.length > 0, "Empty URL.");
		if( str[0] != '/' ){
			auto idx = str.indexOf(':');
			enforce(idx > 0, "No schema in URL:"~str);
			m_schema = str[0 .. idx];
			enforce(m_schema[0].isAlpha,
					"Schema must start with an alphabetical char, found: " ~
					m_schema[0]);
			str = str[idx+1 .. $];
			bool requires_host = false;

			if (str.startsWith("//")) {
				// proto://server/path style
				requires_host = true;
				str = str[2 .. $];
			}

			auto si = str.indexOf('/');
			if( si < 0 ) si = str.length;
			auto ai = str[0 .. si].indexOf('@');
			sizediff_t hs = 0;
			if( ai >= 0 ){
				hs = ai+1;
				auto ci = str[0 .. ai].indexOf(':');
				if( ci >= 0 ){
					m_username = str[0 .. ci];
					m_password = str[ci+1 .. ai];
				} else m_username = str[0 .. ai];
				enforce(m_username.length > 0, "Empty user name in URL.");
			}

			m_host = str[hs .. si];

			auto findPort ( string src )
			{
				auto pi = src.indexOf(':');
				if(pi > 0) {
					enforce(pi < src.length-1, "Empty port in URL.");
					m_port = to!ushort(src[pi+1..$]);
				}
				return pi;
			}


			auto ip6 = m_host.indexOf('[');
			if (ip6 == 0) { // [ must be first char
				auto pe = m_host.indexOf(']');
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
				if (!encoded)
					m_host = m_host.splitter('.').map!(punyEncode).join('.');
			}

			enforce(!requires_host || m_schema == "file" || m_host.length > 0,
					"Empty server name in URL.");
			str = str[si .. $];
		}

		this.localURI = (encoded) ? str : str.encode;
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

	/// The schema/protocol part of the URL
	@property string schema() const nothrow { return m_schema; }
	/// ditto
	@property void schema(string v) { m_schema = v; }

	/// The url encoded path part of the URL
	@property string pathString() const nothrow { return m_path.toString; }

	/// Set the path part of the URL. It should be properly encoded.
	@property void pathString(string s)
	{
		enforce(isURLEncoded(s), "Wrong URL encoding of the path string '"~s~"'");
		m_path = InetPath(s);
	}

	/// The path part of the URL
	@property InetPath path() const nothrow { return m_path; }
	/// ditto
	@property void path(InetPath p)
	nothrow {
		m_path = p;
	}
	/// ditto
	@property void path(Path)(Path p)
		if (isInstanceOf!(GenericPath, Path) && !is(Path == InetPath))
	{
		m_path = cast(InetPath)p;
	}

	/// The host part of the URL (depends on the schema)
	@property string host() const pure nothrow { return m_host; }
	/// ditto
	@property void host(string v) { m_host = v; }

	/// The port part of the URL (optional)
	@property ushort port() const nothrow { return m_port ? m_port : defaultPort(m_schema); }
	/// ditto
	@property port(ushort v) nothrow { m_port = v; }

	/// Get the default port for the given schema or 0
	static ushort defaultPort(string schema)
	nothrow {
		import core.atomic : atomicLoad;
		import std.uni : toLower;

		string lowerschema;

		try
			lowerschema = schema.toLower();
		catch (Exception e)
			assert(false, e.msg);
		
		if (auto set = atomicLoad(map_commonInternetSchemas))
			if (set.contains(lowerschema))
				return set.get(lowerschema);

		return 0;
	}
	/// ditto
	ushort defaultPort()
	const nothrow {
		return defaultPort(m_schema);
	}

	/// The user name part of the URL (optional)
	@property string username() const nothrow { return m_username; }
	/// ditto
	@property void username(string v) { m_username = v; }

	/// The password part of the URL (optional)
	@property string password() const nothrow { return m_password; }
	/// ditto
	@property void password(string v) { m_password = v; }

	/// The query string part of the URL (optional)
	@property string queryString() const nothrow { return m_queryString; }
	/// ditto
	@property void queryString(string v) { m_queryString = v; }

	/// The anchor part of the URL (optional)
	@property string anchor() const nothrow { return m_anchor; }

	/// The path part plus query string and anchor
	@property string localURI()
	const nothrow {
		auto str = appender!string();
		str.put(m_path.toString);
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
		auto ai = str.indexOf('#');
		if( ai >= 0 ){
			m_anchor = str[ai+1 .. $];
			str = str[0 .. ai];
		} else m_anchor = null;

		auto qi = str.indexOf('?');
		if( qi >= 0 ){
			m_queryString = str[qi+1 .. $];
			str = str[0 .. qi];
		} else m_queryString = null;

		this.pathString = str;
	}

	/// The URL to the parent path with query string and anchor stripped.
	@property URL parentURL()
	const {
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
	const nothrow {
		auto dst = appender!string();
		try this.toString(dst);
		catch (Exception e) assert(false, e.msg);
		return dst.data;
	}

	/// Ditto
	void toString(OutputRange) (ref OutputRange dst) const {
		import std.format;
		dst.put(schema);
		dst.put(":");
		if (isCommonInternetSchema(schema))
			dst.put("//");
		if (m_username.length || m_password.length) {
			dst.put(username);
			if (m_password.length)
			{
				dst.put(':');
				dst.put(password);
			}
			dst.put('@');
		}

		import std.algorithm : canFind;
		auto ipv6 = host.canFind(":");

		if ( ipv6 ) dst.put('[');
		dst.put(host);
		if ( ipv6 ) dst.put(']');

		if (m_port > 0)
			formattedWrite(dst, ":%d", m_port);

		dst.put(localURI);
	}

	/** Converts a "file" URL back to a native file system path.
	*/
	NativePath toNativePath()
	const {
		import std.algorithm.iteration : map;
		import std.range : dropOne;

		enforce(this.schema == "file", "Only file:// URLs can be converted to a native path.");

		version (Windows) {
			if (this.host.length) {
				static if (is(NativePath.Segment2)) {
					auto p = NativePath(this.path
							.bySegment2
							.dropOne
							.map!(s => cast(WindowsPath.Segment2)s)
						);
				} else {
					auto p = NativePath(this.path
							.bySegment
							.dropOne
							.map!(s => cast(WindowsPath.Segment)s)
						);
				}
				return NativePath.fromTrustedString(`\\`~this.host) ~ p;
			}
		}

		return cast(NativePath)this.path;
	}

	/// Decode percent encoded triplets for unreserved or convert to uppercase
	private string normalize_percent_encoding(scope const(char)[] input)
	{
		auto normalized = appender!string;
		normalized.reserve(input.length);

		for (size_t i = 0; i < input.length; i++)
		{
			const char c = input[i];
			if (c == '%')
			{
				if (input.length < i + 3)
					assert(false, "Invalid percent encoding");
				
				char conv = cast(char) input[i + 1 .. i + 3].to!ubyte(16);
				switch (conv)
				{
					case 'A': .. case 'Z':
					case 'a': .. case 'z':
					case '0': .. case '9':
					case '-': case '.': case '_': case '~':
						normalized ~= conv; // Decode unreserved
						break;
					default:
						normalized ~= input[i .. i + 3].toUpper(); // Uppercase HEX
						break;
				}

				i += 2;
			}
			else
				normalized ~= c;
		}

		return normalized.data;
	}

	/**
	  * Normalize the content of this `URL` in place
	  *
	  * Normalization can be used to create a more consistent and human-friendly
	  * string representation of the `URL`.
	  * The list of transformations applied in the process of normalization is as follows:
			- Converting schema and host to lowercase
			- Removing port if it is the default port for schema
			- Removing dot segments in path
			- Converting percent-encoded triplets to uppercase
			- Adding slash when path is empty
			- Adding slash to path when path represents a directory
			- Decoding percent encoded triplets for unreserved characters
				A-Z a-z 0-9 - . _ ~ 

		Params:
			isDirectory = Path of the URL represents a directory, if one is 
			not already present, a trailing slash will be appended when `true`
	*/
	void normalize(bool isDirectory = false)
	{
		import std.uni : toLower;
		
		// Lowercase host and schema
		this.m_schema = this.m_schema.toLower();
		this.m_host = this.m_host.toLower();

		// Remove default port
		if (this.m_port == URL.defaultPort(this.m_schema))
			this.m_port = 0;

		// Normalize percent encoding, decode unreserved or uppercase hex
		this.m_queryString = normalize_percent_encoding(this.m_queryString);
		this.m_anchor = normalize_percent_encoding(this.m_anchor);

		// Normalize path (first remove dot segments then normalize path segments)
		this.m_path = InetPath(this.m_path.normalized.bySegment2.map!(
				n => InetPath.Segment2.fromTrustedEncodedString(normalize_percent_encoding(n.encodedName))
			).array);

		// Add trailing slash to empty path
		if (this.m_path.empty || isDirectory)
			this.m_path.endsWithSlash = true;		
	}

	/** Returns the normalized form of the URL.

		See `normalize` for a full description.
	*/
	URL normalized()
	const {
		URL ret = this;
		ret.normalize();
		return ret;
	}

	bool startsWith(const URL rhs)
	const nothrow {
		if( m_schema != rhs.m_schema ) return false;
		if( m_host != rhs.m_host ) return false;
		// FIXME: also consider user, port, querystring, anchor etc
		static if (is(InetPath.Segment2))
			return this.path.bySegment2.startsWith(rhs.path.bySegment2);
		else return this.path.bySegment.startsWith(rhs.path.bySegment);
	}

	URL opBinary(string OP, Path)(Path rhs) const if (OP == "~" && isAnyPath!Path) { return URL(m_schema, m_host, m_port, this.path ~ rhs); }
	URL opBinary(string OP, Path)(Path.Segment rhs) const if (OP == "~" && isAnyPath!Path) { return URL(m_schema, m_host, m_port, this.path ~ rhs); }
	void opOpAssign(string OP, Path)(Path rhs) if (OP == "~" && isAnyPath!Path) { this.path = this.path ~ rhs; }
	void opOpAssign(string OP, Path)(Path.Segment rhs) if (OP == "~" && isAnyPath!Path) { this.path = this.path ~ rhs; }
	static if (is(InetPath.Segment2) && !is(InetPath.Segment2 == InetPath.Segment)) {
		URL opBinary(string OP, Path)(Path.Segment2 rhs) const if (OP == "~" && isAnyPath!Path) { return URL(m_schema, m_host, m_port, this.path ~ rhs); }
		void opOpAssign(string OP, Path)(Path.Segment2 rhs) if (OP == "~" && isAnyPath!Path) { this.path = this.path ~ rhs; }
	}

	/// Tests two URLs for equality using '=='.
	bool opEquals(ref const URL rhs)
	const nothrow {
		if (m_schema != rhs.m_schema) return false;
		if (m_host != rhs.m_host) return false;
		if (m_path != rhs.m_path) return false;
		if (m_port != rhs.m_port) return false;
		return true;
	}
	/// ditto
	bool opEquals(const URL other) const nothrow { return opEquals(other); }

	int opCmp(ref const URL rhs) const nothrow {
		if (m_schema != rhs.m_schema) return m_schema.cmp(rhs.m_schema);
		if (m_host != rhs.m_host) return m_host.cmp(rhs.m_host);
		if (m_path != rhs.m_path) return cmp(m_path.toString, rhs.m_path.toString);
		return true;
	}
}

bool isValidSchema(string schema)
@safe pure nothrow {
	if (schema.length < 1) return false;

	foreach (char ch; schema) {
		switch (ch) {
			default: return false;
			case 'a': .. case 'z': break;
			case 'A': .. case 'Z': break;
			case '0': .. case '9': break;
			case '+', '.', '-': break;
		}
	}

	return true;
}

unittest {
	assert(isValidSchema("http+ssh"));
	assert(isValidSchema("http"));
	assert(!isValidSchema("http/ssh"));
	assert(isValidSchema("HTtp"));
}


bool isValidHostName(string name)
@safe pure nothrow {
	import std.algorithm.iteration : splitter;
	import std.string : representation;

	// According to RFC 1034
	if (name.length < 1) return false;
	if (name.length > 255) return false;
	foreach (seg; name.representation.splitter('.')) {
		if (seg.length < 1) return false;
		if (seg.length > 63) return false;
		if (seg[0] == '-') return false;

		foreach (char ch; seg) {
			switch (ch) {
				default: return false;
				case 'a': .. case 'z': break;
				case 'A': .. case 'Z': break;
				case '0': .. case '9': break;
				case '-': break;
			}
		}
	}
	return true;
}

unittest {
	assert(isValidHostName("foo"));
	assert(isValidHostName("foo-"));
	assert(isValidHostName("foo.bar"));
	assert(isValidHostName("foo.bar-baz"));
	assert(isValidHostName("foo1"));
	assert(!isValidHostName("-foo"));
}


private enum isAnyPath(P) = is(P == InetPath) || is(P == PosixPath) || is(P == WindowsPath);

private shared immutable(SchemaDefaultPortMap)* map_commonInternetSchemas;

shared static this() {
	auto initial_schemas = new SchemaDefaultPortMap;
	initial_schemas.add("file", 0);
	initial_schemas.add("tcp", 0);
	initial_schemas.add("ftp", 21);
	initial_schemas.add("sftp", 22);
	initial_schemas.add("http", 80);
	initial_schemas.add("https", 443);
	initial_schemas.add("http+unix", 80);
	initial_schemas.add("https+unix", 443);
	initial_schemas.add("spdy", 443);
	initial_schemas.add("ws", 80);
	initial_schemas.add("wss", 443);
	initial_schemas.add("redis", 6379);
	initial_schemas.add("rtsp", 554);
	initial_schemas.add("rtsps", 322);

	map_commonInternetSchemas = cast(immutable)initial_schemas;
}

deprecated("Use the overload that accepts a `ushort port` as second argument")
void registerCommonInternetSchema(string schema)
{
    registerCommonInternetSchema(schema, 0);
}

/** Adds the name of a schema to be treated as double-slash style.

	Params:
		schema = Name of the schema
		port = Default port for the schema

	See_also: `isCommonInternetSchema`, RFC 1738 Section 3.1
*/
void registerCommonInternetSchema(string schema, ushort port)
@trusted nothrow {
	import core.atomic : atomicLoad, cas;
	import std.uni : toLower;

	string lowerschema;
	try {
		lowerschema = schema.toLower();
	} catch (Exception e) {
		assert(false, e.msg);
	}

	assert(lowerschema.length < 128, "Only schemas with less than 128 characters are supported");

	while (true) {
		auto olds = atomicLoad(map_commonInternetSchemas);
		auto news = olds ? olds.dup : new SchemaDefaultPortMap;
		news.add(lowerschema, port);
		static if (__VERSION__ < 2094) {
			// work around bogus shared violation error on earlier versions of Druntime
			if (cas(cast(shared(SchemaDefaultPortMap*)*)&map_commonInternetSchemas, cast(shared(SchemaDefaultPortMap)*)olds, cast(shared(SchemaDefaultPortMap)*)news))
				break;
		} else {
			if (cas(&map_commonInternetSchemas, olds, cast(immutable)news))
				break;
		}
	}
}


/** Determines whether an URL schema is double-slash based.

	Double slash based schemas are of the form `schema://[host]/<path>`
	and are parsed differently compared to generic schemas, which are simply
	parsed as `schema:<path>`.

	Built-in recognized double-slash schemas: ftp, http, https,
	http+unix, https+unix, spdy, sftp, ws, wss, file, redis, tcp,
	rtsp, rtsps

	See_also: `registerCommonInternetSchema`, RFC 1738 Section 3.1
*/
bool isCommonInternetSchema(string schema)
@safe nothrow @nogc {
	import core.atomic : atomicLoad;
	char[128] buffer;

	if (schema.length >= 128) return false;

	foreach (ix, char c; schema)
	{
		if (!isASCII(c)) return false;
		buffer[ix] = toLower(c);
	}

	scope lowerschema = buffer[0 .. schema.length];

	return () @trusted {
		auto set = atomicLoad(map_commonInternetSchemas);
		return set ? set.contains(cast(string) lowerschema) : false;
	} ();
}

unittest {
	assert(isCommonInternetSchema("http"));
	assert(isCommonInternetSchema("HTtP"));
	assert(URL.defaultPort("http") == 80);
	assert(!isCommonInternetSchema("foobar"));
	registerCommonInternetSchema("fooBar", 2522);
	assert(isCommonInternetSchema("foobar"));
	assert(isCommonInternetSchema("fOObAR"));
	assert(URL.defaultPort("foobar") == 2522);
	assert(URL.defaultPort("fOObar") == 2522);

	assert(URL.defaultPort("unregistered") == 0);
}


private struct SchemaDefaultPortMap {
	ushort[string] m_data;

	void add(string str, ushort port) @safe nothrow { m_data[str] = port; }
	bool contains(string str) const @safe nothrow @nogc { return !!(str in m_data); }
	ushort get(string str) const @safe nothrow { return m_data[str]; }
	SchemaDefaultPortMap* dup() const @safe nothrow {
		auto ret = new SchemaDefaultPortMap;
		foreach (s; m_data.byKeyValue) ret.add(s.key, s.value);
		return ret;
	}
}

// Puny encoding
private {
	/** Bootstring parameters for Punycode
		These parameters are designed for Unicode

		See also: RFC 3492 Section 5
	*/
	enum uint base = 36;
	enum uint tmin = 1;
	enum uint tmax = 26;
	enum uint skew = 38;
	enum uint damp = 700;
	enum uint initial_bias = 72;
	enum uint initial_n = 128;

	/*	Bias adaptation

		See also: RFC 3492 Section 6.1
	*/
	uint punyAdapt (uint pdelta, int numpoints, bool firsttime)
	@safe @nogc nothrow pure {
		uint delta = firsttime ? pdelta / damp : pdelta / 2;
		delta += delta / numpoints;
		uint k = 0;

		while (delta > ((base - tmin) * tmax) / 2)
		{
			delta /= (base - tmin);
			k += base;
		}

		return k + (((base - tmin + 1) * delta) / (delta + skew));
	}

	/*	Converts puny digit-codes to code point

		See also: RFC 3492 Section 5
	*/
	dchar punyDigitToCP (uint digit)
	@safe @nogc nothrow pure {
		return cast(dchar) (digit + 22 + 75 * (digit < 26));
	}

	/*	Encodes `input` with puny encoding
		
		If input is all characters below `initial_n`
		input is returned as is.

		See also: RFC 3492 Section 6.3
	*/
	string punyEncode (in string input)
	@safe {
		uint n = initial_n;
		uint delta = 0;
		uint bias = initial_bias;
		uint h;
		uint b;
		dchar m = dchar.max; // minchar
		bool delta_overflow;
		
		uint input_len = 0;
		auto output = appender!string();
		
		output.put("xn--");

		foreach (dchar cp; input)
		{
			if (cp <= initial_n)
			{
				output.put(cast(char) cp);
				h += 1;
			}
			// Count length of input as code points, `input.length` counts bytes
			input_len += 1;
		}

		b = h;
		if (b == input_len)
			return input; // No need to puny encode

		if (b > 0)
			output.put('-');

		while (h < input_len)
		{
			m = dchar.max;
			foreach (dchar cp; input)
			{
				if (n <= cp && cp < m)
					m = cp;
			}

			assert(m != dchar.max, "Punyencoding failed, cannot find code point");

			delta = addu(delta, ((m - n) * (h + 1)), delta_overflow);
			assert(!delta_overflow, "Punyencoding failed, delta overflow");

			n = m;

			foreach (dchar cp; input)
			{
				if (cp < n)
					delta += 1;

				if (cp == n)
				{
					uint q = delta;
					uint k = base;

					while (true)
					{
						uint t;
						if (k <= bias /* + tmin */)
							t = tmin;
						else if (k >=  bias + tmax)
							t = tmax;
						else
							t = k - bias;

						if (q < t) break;

						output.put(punyDigitToCP(t + ((q - t) % (base - t))));
						q = (q - t) / (base - t);
						k += base;
					}
					output.put(punyDigitToCP(q));
					bias = punyAdapt(delta, h + 1, h == b);
					delta = 0;
					h += 1;
				}
			}
			delta += 1;
			n += 1;
		}

		return output.data;
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

//rtsp unittest
unittest {
	URL url = URL("rtsp://127.0.0.1:554/echo");
	assert(url.host == "127.0.0.1");
	assert(url.port == 554);
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
	URL url = URL("http://user:password@example.com");
	assert(url.toString() == "http://user:password@example.com");

	url = URL("http://user@example.com");
	assert(url.toString() == "http://user@example.com");
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

unittest { // native path <-> URL conversion
	import std.exception : assertThrown;

	auto url = URL(NativePath("/foo/bar"));
	assert(url.schema == "file");
	assert(url.host == "");
	assert(url.path == InetPath("/foo/bar"));
	assert(url.toNativePath == NativePath("/foo/bar"));

	assertThrown(URL("http://example.org/").toNativePath);
	assertThrown(URL(NativePath("foo/bar")));
}

unittest { // URL Normalization
	auto url = URL.parse("http://example.com/foo%2a");
	assert(url.normalized.toString() == "http://example.com/foo%2A");

	url = URL.parse("HTTP://User@Example.COM/Foo");
	assert(url.normalized.toString() == "http://User@example.com/Foo");
	
	url = URL.parse("http://example.com/%7Efoo");
	assert(url.normalized.toString() == "http://example.com/~foo");
	
	url = URL.parse("http://example.com/foo/./bar/baz/../qux");
	assert(url.normalized.toString() == "http://example.com/foo/bar/qux");
	
	url = URL.parse("http://example.com");
	assert(url.normalized.toString() == "http://example.com/");
	
	url = URL.parse("http://example.com:80/");
	assert(url.normalized.toString() == "http://example.com/");

	url = URL.parse("hTTPs://examPLe.COM:443/my/path");
	assert(url.normalized.toString() == "https://example.com/my/path");

	url = URL.parse("http://example.com/foo");
	url.normalize(true);
	assert(url.toString() == "http://example.com/foo/");
}

version (Windows) unittest { // Windows drive letter paths
	auto url = URL(WindowsPath(`C:\foo`));
	assert(url.schema == "file");
	assert(url.host == "");
	assert(url.path == InetPath("/C:/foo"));
	auto p = url.toNativePath;
	p.normalize();
	assert(p == WindowsPath(`C:\foo`));
}

version (Windows) unittest { // UNC paths
	auto url = URL(WindowsPath(`\\server\share\path`));
	assert(url.schema == "file");
	assert(url.host == "server");
	assert(url.path == InetPath("/share/path"));

	auto p = url.toNativePath;
	p.normalize(); // convert slash to backslash if necessary
	assert(p == WindowsPath(`\\server\share\path`));
}

unittest {
	assert((URL.parse("http://example.com/foo") ~ InetPath("bar")).toString()
		== "http://example.com/foo/bar");
	assert((URL.parse("http://example.com/foo") ~ InetPath.Segment("bar")).toString()
		== "http://example.com/foo/bar");

	URL url = URL.parse("http://example.com/");
	url ~= InetPath("foo");
	url ~= InetPath.Segment("bar");
	assert(url.toString() == "http://example.com/foo/bar");
}

unittest {
	assert(URL.parse("foo:/foo/bar").toString() == "foo:/foo/bar");
	assert(URL.parse("foo:/foo/bar").path.toString() == "/foo/bar");
	assert(URL.parse("foo:foo/bar").toString() == "foo:foo/bar");
}
