/**
	Contains common functionality for the REST and WEB interface generators.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/
module vibe.web.common;

import vibe.http.common;
import vibe.data.json;

static import std.utf;
static import std.string;


/**
	Adjusts the naming convention for a given function name to the specified style.

	The input name is assumed to be in lowerCamelCase (D-style) or PascalCase. Acronyms
	(e.g. "HTML") should be written all caps
*/
string adjustMethodStyle(string name, MethodStyle style)
{
	if (!name.length) {
		return "";
	}

	import std.uni;

	final switch(style) {
		case MethodStyle.unaltered:
			return name;
		case MethodStyle.camelCase:
			size_t i = 0;
			foreach (idx, dchar ch; name) {
				if (isUpper(ch)) {
					i = idx;
				}
				else break;
			}
			if (i == 0) {
				std.utf.decode(name, i);
				return std.string.toLower(name[0 .. i]) ~ name[i .. $];
			} else {
				std.utf.decode(name, i);
				if (i < name.length) {
					return std.string.toLower(name[0 .. i-1]) ~ name[i-1 .. $];
				}
				else {
					return std.string.toLower(name);
				}
			}
		case MethodStyle.pascalCase:
			size_t idx = 0;
			std.utf.decode(name, idx);
			return std.string.toUpper(name[0 .. idx]) ~ name[idx .. $];
		case MethodStyle.lowerCase:
			return std.string.toLower(name);
		case MethodStyle.upperCase:
			return std.string.toUpper(name);
		case MethodStyle.lowerUnderscored:
		case MethodStyle.upperUnderscored:
			string ret;
			size_t start = 0, i = 0;
			while (i < name.length) {
				// skip acronyms
				while (i < name.length && (i+1 >= name.length || (name[i+1] >= 'A' && name[i+1] <= 'Z'))) {
					std.utf.decode(name, i);
				}

				// skip the main (lowercase) part of a word
				while (i < name.length && !(name[i] >= 'A' && name[i] <= 'Z')) {
					std.utf.decode(name, i);
				}

				// add a single word
				if( ret.length > 0 ) {
					ret ~= "_";
				}
				ret ~= name[start .. i];

				// quick skip the capital and remember the start of the next word
				start = i;
				if (i < name.length) {
					std.utf.decode(name, i);
				}
			}
			if (i < name.length) {
				ret ~= "_" ~ name[start .. $];
			}
			return style == MethodStyle.lowerUnderscored ? 
				std.string.toLower(ret) : std.string.toUpper(ret);
	}
}

unittest
{
	assert(adjustMethodStyle("methodNameTest", MethodStyle.unaltered) == "methodNameTest");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.camelCase) == "methodNameTest");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.pascalCase) == "MethodNameTest");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.lowerCase) == "methodnametest");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.upperCase) == "METHODNAMETEST");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.lowerUnderscored) == "method_name_test");
	assert(adjustMethodStyle("methodNameTest", MethodStyle.upperUnderscored) == "METHOD_NAME_TEST");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.unaltered) == "MethodNameTest");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.camelCase) == "methodNameTest");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.pascalCase) == "MethodNameTest");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.lowerCase) == "methodnametest");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.upperCase) == "METHODNAMETEST");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.lowerUnderscored) == "method_name_test");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.upperUnderscored) == "METHOD_NAME_TEST");
	assert(adjustMethodStyle("Q", MethodStyle.lowerUnderscored) == "q");
	assert(adjustMethodStyle("getHTML", MethodStyle.lowerUnderscored) == "get_html");
	assert(adjustMethodStyle("getHTMLEntity", MethodStyle.lowerUnderscored) == "get_html_entity");
	assert(adjustMethodStyle("ID", MethodStyle.lowerUnderscored) == "id");
	assert(adjustMethodStyle("ID", MethodStyle.pascalCase) == "ID");
	assert(adjustMethodStyle("ID", MethodStyle.camelCase) == "id");
	assert(adjustMethodStyle("IDTest", MethodStyle.lowerUnderscored) == "id_test");
	assert(adjustMethodStyle("IDTest", MethodStyle.pascalCase) == "IDTest");
	assert(adjustMethodStyle("IDTest", MethodStyle.camelCase) == "idTest");
}


/**
	User Defined Attribute interface to force specific HTTP method in REST interface
	for function in question. Usual URL generation rules are still applied so if there
	are any "get", "query" or similar prefixes, they are filtered out.

	Example:
	---
	interface IAPI
	{
		// Will be "POST /info" instead of default "GET /info"
		@method(HTTPMethod.POST) getInfo();
	}
	---	
 */
MethodAttribute method(HTTPMethod data)
{
	if (!__ctfe)
		assert(false);
	return MethodAttribute(data);
}

/**
	User Defined Attribute interface to force specific URL path n REST interface
	for function in question. Path attribute is relative though, not absolute.

	Example:
	---
	interface IAPI
	{
		@path("info2") getInfo();
	}
	
	// ...
	
	shared static this()
	{
		registerRestInterface!IAPI(new URLRouter(), new API(), "/root/");
		// now IAPI.getInfo is tied to "GET /root/info2"
	}
	---	
*/
PathAttribute path(string data)
{
	if (!__ctfe)
		assert(false);
	return PathAttribute(data);
}


/**
	UDA to define root URL prefix for annotated REST interface.
	Empty path means deducing prefix from interface type name (see also rootPathFromName)
 */
RootPathAttribute rootPath(string path)
{
	return RootPathAttribute(path);
}
///
unittest
{
	import vibe.http.router;
	import vibe.web.rest;

	@rootPath("/oops")
	interface IAPI
	{
		int getFoo();
	}

	class API : IAPI
	{
		int getFoo()
		{
			return 42;
		}
	}

	auto router = new URLRouter();
	registerRestInterface(router, new API());
	auto routes= router.getAllRoutes();

	assert(routes[0].pattern == "/oops/foo" && routes[0].method == HTTPMethod.GET);
}


/**
	Convenience alias
 */
@property RootPathAttribute rootPathFromName()
{
	return RootPathAttribute("");
}
///
unittest
{
	import vibe.http.router;
	import vibe.web.rest;

	@rootPathFromName
	interface IAPI
	{
		int getFoo();
	}

	class API : IAPI
	{
		int getFoo()
		{
			return 42;
		}
	}

	auto router = new URLRouter();
	registerRestInterface(router, new API());
	auto routes= router.getAllRoutes();

	assert(routes[0].pattern == "/iapi/foo" && routes[0].method == HTTPMethod.GET);
}


/// private
struct MethodAttribute
{
	HTTPMethod data;
	alias data this;
}

/// private
deprecated alias OverriddenMethod = MethodAttribute;

/// private
struct PathAttribute
{
	string data;
	alias data this;
}

/// private
deprecated alias OverriddenPath = PathAttribute;

/// private
struct RootPathAttribute
{
	string data;
	alias data this;
}

/// private
deprecated alias RootPath = RootPathAttribute;


/**
	Determines the naming convention of an identifier.
*/
enum MethodStyle
{
	/// Special value for free-style conventions
	unaltered,
	/// camelCaseNaming
	camelCase,
	/// PascalCaseNaming
	pascalCase,
	/// lowercasenaming
	lowerCase,
	/// UPPERCASENAMING
	upperCase,
	/// lower_case_naming
	lowerUnderscored,
	/// UPPER_CASE_NAMING
	upperUnderscored,
	
	/// deprecated
	Unaltered = unaltered,
	/// deprecated
	CamelCase = camelCase,
	/// deprecated
	PascalCase = pascalCase,
	/// deprecated
	LowerCase = lowerCase,
	/// deprecated
	UpperCase = upperCase,
	/// deprecated
	LowerUnderscored = lowerUnderscored,
	/// deprecated
	UpperUnderscored = upperUnderscored,
}


/**
	Uses given function symbol to determine which HTTP method and
	what URL path should be used to access it in REST API.

	Is designed for CTFE usage and will assert at run time.

	Returns:
		Tuple of three elements:
			* flag "was UDA used to override path"
			* HTTPMethod extracted
			* url path extracted
 */
auto extractHTTPMethodAndName(alias Func)()
{   
	if (!__ctfe)
		assert(false);

	struct HandlerMeta
	{
		bool hadPathUDA;
		HTTPMethod method;
		string url;
	}

	import vibe.internal.meta.uda : findFirstUDA;
	import vibe.internal.meta.traits : isPropertySetter,
		isPropertyGetter;
	import std.algorithm : startsWith;
	import std.typecons : Nullable;
	
	immutable httpMethodPrefixes = [
		HTTPMethod.GET    : [ "get", "query" ],
		HTTPMethod.PUT    : [ "put", "set" ],
		HTTPMethod.PATCH  : [ "update", "patch" ],
		HTTPMethod.POST   : [ "add", "create", "post" ],
		HTTPMethod.DELETE : [ "remove", "erase", "delete" ],
	];
	
	string name = __traits(identifier, Func);
	alias typeof(&Func) T;

	Nullable!HTTPMethod udmethod;
	Nullable!string udurl;

	// Cases may conflict and are listed in order of priority

	// Workaround for Nullable incompetence
	enum uda1 = findFirstUDA!(MethodAttribute, Func);
	enum uda2 = findFirstUDA!(PathAttribute, Func);

	static if (uda1.found) {
		udmethod = uda1.value;
	}
	static if (uda2.found) {
		udurl = uda2.value;
	}

	// Everything is overriden, no further analysis needed
	if (!udmethod.isNull() && !udurl.isNull()) {
		return HandlerMeta(true, udmethod.get(), udurl.get());
	}
	
	// Anti-copy-paste delegate
	typeof(return) udaOverride( HTTPMethod method, string url ){
		return HandlerMeta(
			!udurl.isNull(),
			udmethod.isNull() ? method : udmethod.get(), 
			udurl.isNull() ? url : udurl.get()
		);
	}
	
	if (isPropertyGetter!T) {
		return udaOverride(HTTPMethod.GET, name);
	}
	else if(isPropertySetter!T) {
		return udaOverride(HTTPMethod.PUT, name);
	}
	else {
		foreach (method, prefixes; httpMethodPrefixes) {
			foreach (prefix; prefixes) {
				if (name.startsWith(prefix)) {
					string tmp = name[prefix.length..$];
					return udaOverride(method, tmp);
				}
			}
		}
		
		if (name == "index")
			return udaOverride(HTTPMethod.GET, "");
		else
			return udaOverride(HTTPMethod.POST, name);
	}
}

unittest
{
	interface Sample
	{
		string getInfo();
		string updateDescription();
		
		@method(HTTPMethod.DELETE)
		string putInfo();
		
		@path("matters")
		string getMattersnot();
		
		@path("compound/path") @method(HTTPMethod.POST)
		string mattersnot();
	}
	
	enum ret1 = extractHTTPMethodAndName!(Sample.getInfo);
	static assert (ret1.hadPathUDA == false);
	static assert (ret1.method == HTTPMethod.GET);
	static assert (ret1.url == "Info");
	enum ret2 = extractHTTPMethodAndName!(Sample.updateDescription);
	static assert (ret2.hadPathUDA == false);
	static assert (ret2.method == HTTPMethod.PATCH);
	static assert (ret2.url == "Description");
	enum ret3 = extractHTTPMethodAndName!(Sample.putInfo);
	static assert (ret3.hadPathUDA == false);
	static assert (ret3.method == HTTPMethod.DELETE);
	static assert (ret3.url == "Info");
	enum ret4 = extractHTTPMethodAndName!(Sample.getMattersnot);
	static assert (ret4.hadPathUDA == true);
	static assert (ret4.method == HTTPMethod.GET);
	static assert (ret4.url == "matters");
	enum ret5 = extractHTTPMethodAndName!(Sample.mattersnot);
	static assert (ret5.hadPathUDA == true);
	static assert (ret5.method == HTTPMethod.POST);
	static assert (ret5.url == "compound/path");
}


// concatenates two URL parts avoiding any duplicate slashes
// in resulting URL. `trailing` defines of result URL must
// end with slash
package string concatURL(string prefix, string url, bool trailing = false)
{
	import std.algorithm : startsWith, endsWith;

	auto pre = prefix.endsWith("/");
	auto post = url.startsWith("/");

	if (!url.length) return trailing && !pre ? prefix ~ "/" : prefix;

	auto suffix = trailing && !url.endsWith("/") ? "/" : null;

	if (pre) {
		// "/" is ASCII, so can just slice
		if (post) return prefix ~ url[1 .. $] ~ suffix;
		else return prefix ~ url ~ suffix;
	} else {
		if (post) return prefix ~ url ~ suffix;
		else return prefix ~ "/" ~ url ~ suffix;
	}
}

unittest {
	assert(concatURL("/test/", "/it/", false) == "/test/it/");
	assert(concatURL("/test", "it/", false) == "/test/it/");
	assert(concatURL("/test", "it", false) == "/test/it");
	assert(concatURL("/test", "", false) == "/test");
	assert(concatURL("/test/", "", false) == "/test/");
	assert(concatURL("/test/", "/it/", true) == "/test/it/");
	assert(concatURL("/test", "it/", true) == "/test/it/");
	assert(concatURL("/test", "it", true) == "/test/it/");
	assert(concatURL("/test", "", true) == "/test/");
	assert(concatURL("/test/", "", true) == "/test/");
}

/** 
 	Respresents a Rest error response
*/
class RestException : HTTPStatusException {
	private {
		Json m_jsonResult;
	}
	
	///
	this(int status, Json jsonResult, string file = __FILE__, int line = __LINE__, Throwable next = null)
	{
		if (jsonResult.type == Json.Type.Object && jsonResult.statusMessage.type == Json.Type.String) {
			super(status, jsonResult.statusMessage.get!string, file, line, next);
		}
		else {
			super(status, httpStatusText(status) ~ " (" ~ jsonResult.toString() ~ ")", file, line, next);
		}
		
		m_jsonResult = jsonResult;
	}
	
	/// The HTTP status code
	@property const(Json) jsonResult() const { return m_jsonResult; }
}
