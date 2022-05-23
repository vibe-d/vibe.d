/**
	URL parsing routines.

	Copyright: © 2012-2017 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.url;

public import vibe.core.path;

import vibe.textfilter.urlencode;
import vibe.utils.string;

import std.array;
import std.algorithm;
import std.conv;
import std.exception;
import std.string;
import std.traits : isInstanceOf;
import std.ascii : isAlpha, isASCII, toLower;
import std.uri: encode;

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
		string m_text;
	}

	/// Constructs a new URL object from its components.
	this(string schema, string host, ushort port, InetPath path) pure nothrow
	in {
		assert(isValidSchema(schema), "Invalid URL schema name: " ~ schema);
		assert(host.length == 0 || isValidHostName(host), "Invalid URL host name: " ~ host);
	}
	do {
		Parts p;
		p.isCommonInternetSchema = host.length || port != 0;
		p.schema = schema;
		p.host = host;
		p.port = port;
		p.path = path.toString;
		this(p);
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
		auto str = url_string;
		enforce(str.length > 0, "Empty URL.");
		if (str[0] != '/') {
			auto idx = str.indexOf(':');
			enforce(idx > 0, "No schema in URL:"~str);

			enforce(str[0].isAlpha,
				"Schema must start with an alphabetical char, found: " ~
				str[0 .. idx]);

			str = str[idx+1 .. $];
		}

		InetPath(url_string.extractPath);

		// TODO: perform more URL syntax validation!

		m_text = url_string;
	}

	private this(string url_string, bool encoded)
	{
		if (encoded) this(url_string);
		else {
			Parts p;
			p.isCommonInternetSchema = url_string.extractIsCommonInternetSchema;
			p.schema = url_string.extractSchema;
			p.username = url_string.extractUsername;
			p.password = url_string.extractPassword;
			p.host = url_string.extractHost;
			p.port = url_string.extractPort;
			p.path = url_string.extractPath;
			p.query = url_string.extractQuery;
			p.anchor = url_string.extractAnchor;

			if (p.host !is null)
				p.host = p.host.splitter('.').map!(punyEncode).join('.');
			p.path = p.path.encode;
			if (p.query !is null) p.query = p.query.encode;
			if (p.anchor !is null) p.anchor = p.anchor.encode;

			this(p);
		}
	}
	/// ditto
	static URL parse(string url_string)
	{
		return URL(url_string);
	}

	private this(Parts parts)
	pure nothrow {
		m_text = parts.toURL();
	}

	static URL fromString(string url_string)
	{
		return URL(url_string);
	}

	/// The schema/protocol part of the URL
	@property string schema() const nothrow @nogc { return m_text.extractSchema; }
	/// ditto
	@property void schema(string v) { auto p = this.parts; p.schema = v; this.parts = p; }

	/// The url encoded path part of the URL
	@property string pathString() const nothrow @nogc { return m_text.extractPath; }

	/// Set the path part of the URL. It should be properly encoded.
	@property void pathString(string s)
	{
		enforce(isURLEncoded(s), "Wrong URL encoding of the path string '"~s~"'");
		auto p = this.parts;
		p.path = s;
		this.parts = p;
	}

	/// The path part of the URL
	@property InetPath path() const nothrow @nogc { return InetPath.fromTrustedString(this.pathString); }
	/// ditto
	@property void path(InetPath v) nothrow { auto p = this.parts; p.path = v.toString(); this.parts = p; }
	/// ditto
	@property void path(Path)(Path p)
		if (isInstanceOf!(GenericPath, Path) && !is(Path == InetPath))
	{
		this.path = cast(InetPath)p;
	}

	/// The host part of the URL (depends on the schema)
	@property string host() const pure nothrow @nogc { return m_text.extractHost; }
	/// ditto
	@property void host(string v) { auto p = this.parts; p.host = v; this.parts = p; }

	/// The port part of the URL (optional)
	@property ushort rawPort() const nothrow @nogc { return m_text.extractPort; }

	/// The port part of the URL (optional)
	@property ushort port() const nothrow { if (auto p = this.rawPort) return p; return defaultPort(this.schema); }
	/// ditto
	@property port(ushort v) nothrow { auto p = this.parts; p.port = v; this.parts = p; }

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
		return defaultPort(this.schema);
	}

	/// The user name part of the URL (optional)
	@property string username() const nothrow @nogc { return m_text.extractUsername; }
	/// ditto
	@property void username(string v) { auto p = this.parts; p.username = v; this.parts = p; }

	/// The password part of the URL (optional)
	@property string password() const nothrow @nogc { return m_text.extractPassword; }
	/// ditto
	@property void password(string v) { auto p = this.parts; p.password = v; this.parts = p; }

	/// The query string part of the URL (optional)
	@property string queryString() const nothrow @nogc { return m_text.extractQuery; }
	/// ditto
	@property void queryString(string v) { auto p = this.parts; p.query = v; this.parts = p; }

	/// The anchor part of the URL (optional)
	@property string anchor() const nothrow @nogc { return m_text.extractAnchor; }

	/// The path part plus query string and anchor
	@property string localURI()
	const nothrow {
		auto str = appender!string();
		str.put(this.pathString);
		if (auto q = this.queryString) {
			str.put("?");
			str.put(q);
		}
		if (auto a = this.anchor) {
			str.put("#");
			str.put(a);
		}
		return str.data;
	}
	/// ditto
	@property void localURI(string str)
	{
		auto p = this.parts;

		auto ai = str.indexOf('#');
		if (ai >= 0) {
			p.anchor = str[ai+1 .. $];
			str = str[0 .. ai];
		} else p.anchor = null;

		auto qi = str.indexOf('?');
		if (qi >= 0) {
			p.query = str[qi+1 .. $];
			str = str[0 .. qi];
		} else p.query = null;

		p.path = str;

		this.parts = p;
	}

	/// The URL to the parent path with query string and anchor stripped.
	@property URL parentURL()
	const {
		auto p = this.parts;
		p.path = InetPath(p.path).parentPath.toString();
		return URL(p);
	}

	/// Converts this URL object to its string representation.
	string toString()
	const nothrow @nogc {
		return m_text;
	}

	/// Ditto
	void toString(OutputRange) (ref OutputRange dst)
	const {
		dst.put(m_text);
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

		auto p = this.parts;
		
		// Lowercase host and schema
		p.schema = p.schema.toLower();
		p.host = p.host.toLower();

		// Remove default port
		if (p.port == URL.defaultPort(p.schema))
			p.port = 0;

		// Normalize percent encoding, decode unreserved or uppercase hex
		p.query = normalize_percent_encoding(p.query);
		p.anchor = normalize_percent_encoding(p.anchor);

		// Normalize path (first remove dot segments then normalize path segments)
		p.path = InetPath(InetPath.fromTrustedString(p.path).normalized.bySegment2.map!(
				n => InetPath.Segment2.fromTrustedEncodedString(normalize_percent_encoding(n.encodedName))
			).array).toString;

		// Add trailing slash to empty path
		if (p.path.length == 0 || isDirectory) {
			if (!p.path.endsWith("/"))
				p.path ~= "/";
		}

		this.parts = p;
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
		if (this.schema != rhs.schema) return false;
		if (this.host != rhs.host) return false;
		// FIXME: also consider user, port, querystring, anchor etc
		static if (is(InetPath.Segment2))
			return this.path.bySegment2.startsWith(rhs.path.bySegment2);
		else return this.path.bySegment.startsWith(rhs.path.bySegment);
	}

	URL opBinary(string OP, Path)(Path rhs) const if (OP == "~" && isAnyPath!Path) { URL ret = this; ret.path = this.path ~ rhs; return ret; }
	URL opBinary(string OP, Path)(Path.Segment rhs) const if (OP == "~" && isAnyPath!Path) { URL ret = this; ret.path = this.path ~ rhs; return ret; }
	void opOpAssign(string OP, Path)(Path rhs) if (OP == "~" && isAnyPath!Path) { this.path = this.path ~ rhs; }
	void opOpAssign(string OP, Path)(Path.Segment rhs) if (OP == "~" && isAnyPath!Path) { this.path = this.path ~ rhs; }
	static if (is(InetPath.Segment2) && !is(InetPath.Segment2 == InetPath.Segment)) {
		URL opBinary(string OP, Path)(Path.Segment2 rhs) const if (OP == "~" && isAnyPath!Path) { return URL(m_schema, m_host, m_port, this.path ~ rhs); }
		void opOpAssign(string OP, Path)(Path.Segment2 rhs) if (OP == "~" && isAnyPath!Path) { this.path = this.path ~ rhs; }
	}

	/// Tests two URLs for equality using '=='.
	bool opEquals(ref const URL rhs)
	const nothrow {
		if (this.schema != rhs.schema) return false;
		if (this.host != rhs.host) return false;
		if (this.path != rhs.path) return false;
		if (this.port != rhs.port) return false;
		return true;
	}
	/// ditto
	bool opEquals(const URL other) const nothrow { return opEquals(other); }

	int opCmp(ref const URL rhs) const nothrow {
		if (this.schema != rhs.schema) return this.schema.cmp(rhs.schema);
		if (this.host != rhs.host) return this.host.cmp(rhs.host);
		if (this.pathString != rhs.pathString) return cmp(this.pathString, rhs.pathString);
		return true;
	}

	private @property Parts parts()
	const nothrow {
		Parts ret;
		ret.isCommonInternetSchema = m_text.extractIsCommonInternetSchema;
		ret.schema = m_text.extractSchema;
		ret.username = m_text.extractUsername;
		ret.password = m_text.extractPassword;
		ret.host = m_text.extractHost;
		ret.port = m_text.extractPort;
		ret.path = m_text.extractPath;
		ret.query = m_text.extractQuery;
		ret.anchor = m_text.extractAnchor;
		return ret;
	}

	private @property parts(Parts v)
	nothrow {
		m_text = URL(v).m_text;
	}

	private static struct Parts {
		bool isCommonInternetSchema;
		string schema;
		string username;
		string password;
		string host;
		ushort port;
		string path;
		string query;
		string anchor;

		string toURL()
		const @safe pure nothrow {
			import std.format : formattedWrite;

			auto app = appender!string;
			app.put(this.schema);
			app.put(':');
			if (this.isCommonInternetSchema)
				app.put("//");

			if (this.username.length || this.password.length) {
				app.put(this.username);
				if (this.password.length)
				{
					app.put(':');
					app.put(this.password);
				}
				app.put('@');
			}

			if (this.host.length) {
				if (this.host.representation.canFind(':')) {
					app.put('[');
					app.put(this.host);
					app.put(']');
				} else app.put(this.host);
				if (this.port != 0) {
					try app.formattedWrite(":%s", this.port);
					catch (Exception e) assert(false, e.msg);
				}
			}

			app.put(this.path);

			if (this.query !is null) {
				app.put('?');
				app.put(this.query);
			}

			if (this.anchor !is null) {
				app.put('#');
				app.put(this.anchor);
			}

			return app.data;
		}
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

@safe @nogc unittest { // test @nogc and CTFE-ability
	static immutable url = URL("http://example.com/");
	static assert(url.toString() == "http://example.com/");
	assert(url.schema == "http");
	assert(url.host == "example.com");
	assert(url.path == InetPath.fromTrustedString("/"));
	assert(url.toString() == "http://example.com/");
}

unittest { // IPv6
	auto urlstr = "http://[2003:46:1a7b:6c01:64b:80ff:fe80:8003]:8091/abc";
	auto url = URL.parse(urlstr);
	assert(url.schema == "http", url.schema);
	assert(url.host == "2003:46:1a7b:6c01:64b:80ff:fe80:8003", url.host);
	assert(url.port == 8091);
	assert(url.pathString == "/abc", url.pathString());
	assert(url.path == InetPath("/abc"), url.path().toString);
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

private string extractSchema(string uri)
@safe pure nothrow @nogc {
	if (uri.length == 0) return null;
	assert(isAlpha(uri[0]), "Invalid URI");

	auto cidx = uri.indexOf(':');
	assert(cidx >= 0, "Invalid URI");

	return uri[0 .. cidx];
}

unittest {
	assert(extractSchema("") is null);
	assert(extractSchema("http://example.com/") == "http");
	assert(extractSchema("http://example.com:80/") == "http");
	assert(extractSchema("http://") == "http");
	assert(extractSchema("foo+bar:") == "foo+bar");
}

private bool extractIsCommonInternetSchema(string uri)
@safe pure nothrow @nogc {
	auto sidx = uri.indexOf('/');
	if (sidx < 0) return false;

	uri = uri[sidx+1 .. $];
	if (!uri.length || uri[0] != '/') return false;
	return true;
}

unittest {
	assert(!extractIsCommonInternetSchema(""));
	assert(extractIsCommonInternetSchema("http://example.com/"));
	assert(!extractIsCommonInternetSchema("mongodb:foo"));
	assert(extractIsCommonInternetSchema("file:///foo"));
}

private string extractUsername(string uri)
@safe pure nothrow @nogc {
	auto sidx = uri.indexOf('/');
	if (sidx < 0) return null;

	uri = uri[sidx+1 .. $];
	if (!uri.length || uri[0] != '/') return null;
	uri = uri[1 .. $];

	sidx = uri.indexOf('@');
	if (sidx < 0) return null;

	uri = uri[0 .. sidx];

	auto pidx = uri.indexOf(':');
	if (pidx < 0) return uri;
	return uri[0 .. pidx];
}

unittest {
	assert(extractUsername("") is null);
	assert(extractUsername("http://example.com/") is null);
	assert(extractUsername("http://example.com:80/") is null);
	assert(extractUsername("http://user:pass@example.com") == "user");
	assert(extractUsername("http://user@example.com:80") == "user");
}


private string extractPassword(string uri)
@safe pure nothrow @nogc {
	auto sidx = uri.indexOf('/');
	if (sidx < 0) return null;

	uri = uri[sidx+1 .. $];
	if (!uri.length || uri[0] != '/') return null;
	uri = uri[1 .. $];

	sidx = uri.indexOf('@');
	if (sidx < 0) return null;

	uri = uri[0 .. sidx];

	auto pidx = uri.indexOf(':');
	if (pidx < 0) return null;
	return uri[pidx+1 .. $];
}

unittest {
	assert(extractPassword("") is null);
	assert(extractPassword("http://example.com/") is null);
	assert(extractPassword("http://example.com:80/") is null);
	assert(extractPassword("http://user:pass@example.com") == "pass");
	assert(extractPassword("http://user:@example.com") !is null);
	assert(extractPassword("http://user:@example.com") == "");
	assert(extractPassword("http://user@example.com:80") is null);
}

private string extractHost(string uri)
@safe pure nothrow @nogc {
	auto sidx = uri.indexOf('/');
	if (sidx < 0) return null;

	uri = uri[sidx+1 .. $];
	if (!uri.length || uri[0] != '/') return null;
	uri = uri[1 .. $];

	sidx = vibe.utils.string.indexOfAny(uri, "/?#");
	if (sidx >= 0) uri = uri[0 .. sidx];

	auto aidx = uri.indexOf('@');
	if (aidx >= 0) uri = uri[aidx+1 .. $];

	if (uri.startsWith("[")) {
		auto ccidx = uri.indexOf("]");
		if (ccidx >= 0) return uri[1 .. ccidx];
		return null; // ?
	}

	auto pidx = uri.indexOf(':');
	if (pidx < 0) return uri;
	return uri[0 .. pidx];
}

unittest {
	assert(extractHost("http://[::1]/") == "::1");
	assert(extractHost("http://example.com/") == "example.com");
	assert(extractHost("http://example.com:80/") == "example.com");
	assert(extractHost("http://example.com") == "example.com");
	assert(extractHost("http://example.com:80") == "example.com");
	assert(extractHost("http://example.com?") == "example.com");
	assert(extractHost("http://example.com:80?") == "example.com");
	assert(extractHost("http://user:pass@example.com") == "example.com");
	assert(extractHost("http://user@example.com:80") == "example.com");
	assert(extractHost("file:///foo") == "");
	assert(extractHost("file:///foo") !is null);
	assert(extractHost("file:foo") is null);
}

private ushort extractPort(string uri)
@safe pure nothrow @nogc {
	auto sidx = uri.indexOf('/');
	if (sidx < 0) return 0;

	uri = uri[sidx+1 .. $];
	if (!uri.length || uri[0] != '/') return 0;
	uri = uri[1 .. $];

	sidx = vibe.utils.string.indexOfAny(uri, "/?#");
	if (sidx >= 0) uri = uri[0 .. sidx];

	auto aidx = uri.indexOf('@');
	if (aidx >= 0) uri = uri[aidx+1 .. $];

	if (uri.startsWith("[")) {
		auto ccidx = uri.indexOf("]");
		if (ccidx >= 0) uri = uri[ccidx+1 .. $];
	}

	auto pidx = uri.indexOf(':');
	if (pidx < 0) return 0;
	uri = uri[pidx+1 .. $];

	return uri.parseInteger10(ushort.max);
}

unittest {
	assert(extractPort("http://[::1]/") == 0);
	assert(extractPort("http://[::1]:80/") == 80);
	assert(extractPort("http://example.com/") == 0);
	assert(extractPort("http://example.com:80/") == 80);
	assert(extractPort("http://example.com") == 0);
	assert(extractPort("http://example.com:80") == 80);
	assert(extractPort("http://example.com?") == 0);
	assert(extractPort("http://example.com:80?") == 80);
	assert(extractPort("http://user:pass@example.com")== 0);
	assert(extractPort("http://user:pass@example.com:80") == 80);
}

private string extractPath(string uri)
@safe pure nothrow @nogc {
	auto sidx = uri.indexOf('/');
	if (sidx < 0) return null;
	uri = uri[sidx .. $];

	if (uri.startsWith("//")) {
		uri = uri[2 .. $];
		sidx = uri.indexOf('/');
		if (sidx < 0) return null;
		uri = uri[sidx .. $];
	}

	auto qaidx = vibe.utils.string.indexOfAny(uri, "?#");
	if (qaidx >= 0) uri = uri[0 .. qaidx];

	return uri;
}

unittest {
	assert(extractPath("http://example.com/") == "/");
	assert(extractPath("http://example.com/#") == "/");
	assert(extractPath("http://example.com:80/") == "/");
	assert(extractPath("http://example.com?foo") == "");
	assert(extractPath("http://example.com#foo") == "");
	assert(extractPath("http://example.com/bar/#foo") == "/bar/");
	assert(extractPath("http:/bar/#foo") == "/bar/");
}

private string extractQuery(string uri)
@safe pure nothrow @nogc {
	auto sidx = uri.indexOf('?');
	if (sidx < 0) return null;

	uri = uri[sidx+1 .. $];

	auto aidx = uri.indexOf('#');
	if (aidx >= 0) uri = uri[0 .. aidx];

	return uri;
}

unittest {
	assert(extractQuery("http://example.com/") is null);
	assert(extractQuery("http://example.com/?") !is null);
	assert(extractQuery("http://example.com/?") == "");
	assert(extractQuery("http://example.com/#") is null);
	assert(extractQuery("http://example.com/?#") == "");
	assert(extractQuery("http://example.com/?foo&bar#") == "foo&bar");
}

private string extractAnchor(string uri)
@safe pure nothrow @nogc {
	auto sidx = uri.indexOf('#');
	if (sidx < 0) return null;

	return uri[sidx+1 .. $];
}

unittest {
	assert(extractAnchor("http://example.com/") is null);
	assert(extractAnchor("http://example.com/?") is null);
	assert(extractAnchor("http://example.com/#") !is null);
	assert(extractAnchor("http://example.com/#") == "");
	assert(extractAnchor("http://example.com/?#") == "");
	assert(extractAnchor("http://example.com/?foo&bar#baz") == "baz");
}
