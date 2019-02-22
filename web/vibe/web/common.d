/**
	Contains common functionality for the REST and WEB interface generators.

	Copyright: © 2012-2017 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/
module vibe.web.common;

import vibe.http.common;
import vibe.http.server : HTTPServerRequest;
import vibe.data.json;
import vibe.internal.meta.uda : onlyAsUda;

static import std.utf;
static import std.string;
import std.typecons : Nullable;


/**
	Adjusts the naming convention for a given function name to the specified style.

	The input name is assumed to be in lowerCamelCase (D-style) or PascalCase. Acronyms
	(e.g. "HTML") should be written all caps
*/
string adjustMethodStyle(string name, MethodStyle style)
@safe {
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
			if (start < name.length) {
				ret ~= "_" ~ name[start .. $];
			}
			return style == MethodStyle.lowerUnderscored ?
				std.string.toLower(ret) : std.string.toUpper(ret);
	}
}

@safe unittest
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
	assert(adjustMethodStyle("anyA", MethodStyle.lowerUnderscored) == "any_a", adjustMethodStyle("anyA", MethodStyle.lowerUnderscored));
}


/**
	Determines the HTTP method and path for a given function symbol.

	The final method and path are determined from the function name, as well as
	any $(D @method) and $(D @path) attributes that may be applied to it.

	This function is designed for CTFE usage and will assert at run time.

	Returns:
		A tuple of three elements is returned:
		$(UL
			$(LI flag "was UDA used to override path")
			$(LI $(D HTTPMethod) extracted)
			$(LI URL path extracted)
		)
 */
auto extractHTTPMethodAndName(alias Func, bool indexSpecialCase)()
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

	enum name = __traits(identifier, Func);
	alias T = typeof(&Func);

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
				import std.uni : isLower;
				if (name.startsWith(prefix) && (name.length == prefix.length || !name[prefix.length].isLower)) {
					string tmp = name[prefix.length..$];
					return udaOverride(method, tmp.length ? tmp : "/");
				}
			}
		}

		static if (indexSpecialCase && name == "index") {
			return udaOverride(HTTPMethod.GET, "/");
		} else
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

		string get();

		string posts();

		string patches();
	}

	enum ret1 = extractHTTPMethodAndName!(Sample.getInfo, false,);
	static assert (ret1.hadPathUDA == false);
	static assert (ret1.method == HTTPMethod.GET);
	static assert (ret1.url == "Info");
	enum ret2 = extractHTTPMethodAndName!(Sample.updateDescription, false);
	static assert (ret2.hadPathUDA == false);
	static assert (ret2.method == HTTPMethod.PATCH);
	static assert (ret2.url == "Description");
	enum ret3 = extractHTTPMethodAndName!(Sample.putInfo, false);
	static assert (ret3.hadPathUDA == false);
	static assert (ret3.method == HTTPMethod.DELETE);
	static assert (ret3.url == "Info");
	enum ret4 = extractHTTPMethodAndName!(Sample.getMattersnot, false);
	static assert (ret4.hadPathUDA == true);
	static assert (ret4.method == HTTPMethod.GET);
	static assert (ret4.url == "matters");
	enum ret5 = extractHTTPMethodAndName!(Sample.mattersnot, false);
	static assert (ret5.hadPathUDA == true);
	static assert (ret5.method == HTTPMethod.POST);
	static assert (ret5.url == "compound/path");
	enum ret6 = extractHTTPMethodAndName!(Sample.get, false);
	static assert (ret6.hadPathUDA == false);
	static assert (ret6.method == HTTPMethod.GET);
	static assert (ret6.url == "/");
	enum ret7 = extractHTTPMethodAndName!(Sample.posts, false);
	static assert(ret7.hadPathUDA == false);
	static assert(ret7.method == HTTPMethod.POST);
	static assert(ret7.url == "posts");
	enum ret8 = extractHTTPMethodAndName!(Sample.patches, false);
	static assert(ret8.hadPathUDA == false);
	static assert(ret8.method == HTTPMethod.POST);
	static assert(ret8.url == "patches");
}


/**
    Attribute to define the content type for methods.

    This currently applies only to methods returning an $(D InputStream) or
    $(D ubyte[]).
*/
ContentTypeAttribute contentType(string data)
@safe {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return ContentTypeAttribute(data);
}


/**
	Attribute to force a specific HTTP method for an interface method.

	The usual URL generation rules are still applied, so if there
	are any "get", "query" or similar prefixes, they are filtered out.
 */
MethodAttribute method(HTTPMethod data)
@safe {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return MethodAttribute(data);
}

///
unittest {
	interface IAPI
	{
		// Will be "POST /info" instead of default "GET /info"
		@method(HTTPMethod.POST) string getInfo();
	}
}


/**
	Attibute to force a specific URL path.

	This attribute can be applied either to an interface itself, in which
	case it defines the root path for all methods within it,
	or on any function, in which case it defines the relative path
	of this method.
	Path are always relative, even path on interfaces, as you can
	see in the example below.

	See_Also: $(D rootPathFromName) for automatic name generation.
*/
PathAttribute path(string data)
@safe {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return PathAttribute(data);
}

///
@safe unittest {
	@path("/foo")
	interface IAPI
	{
		@path("info2") string getInfo() @safe;
	}

	class API : IAPI {
		string getInfo() @safe { return "Hello, World!"; }
	}

	void test()
	@safe {
		import vibe.http.router;
		import vibe.web.rest;

		auto router = new URLRouter;

		// Tie IAPI.getInfo to "GET /root/foo/info2"
		router.registerRestInterface!IAPI(new API(), "/root/");

		// Or just to "GET /foo/info2"
		router.registerRestInterface!IAPI(new API());

		// ...
	}
}


/// Convenience alias to generate a name from the interface's name.
@property PathAttribute rootPathFromName()
@safe {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return PathAttribute("");
}
///
@safe unittest
{
	import vibe.http.router;
	import vibe.web.rest;

	@rootPathFromName
	interface IAPI
	{
		int getFoo() @safe;
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


/**
	Methods marked with this attribute will not be treated as web endpoints.

	This attribute enables the definition of public methods that do not take
	part in the interface genration process.
*/
@property NoRouteAttribute noRoute()
{
	import vibe.web.common : onlyAsUda;
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return NoRouteAttribute.init;
}

///
unittest {
	interface IAPI {
		// Accessible as "GET /info"
		string getInfo();

		// Not accessible over HTTP
		@noRoute
		int getFoo();
	}
}


/**
 	Respresents a Rest error response
*/
class RestException : HTTPStatusException {
	private {
		Json m_jsonResult;
	}

	@safe:

	///
	this(int status, Json jsonResult, string file = __FILE__, int line = __LINE__, Throwable next = null)
	{
		if (jsonResult.type == Json.Type.Object && jsonResult["statusMessage"].type == Json.Type.String) {
			super(status, jsonResult["statusMessage"].get!string, file, line, next);
		}
		else {
			super(status, httpStatusText(status) ~ " (" ~ jsonResult.toString() ~ ")", file, line, next);
		}

		m_jsonResult = jsonResult;
	}

	/// The HTTP status code
	@property const(Json) jsonResult() const { return m_jsonResult; }
}

/// private
package struct ContentTypeAttribute
{
	string data;
	alias data this;
}

/// private
package struct MethodAttribute
{
	HTTPMethod data;
	alias data this;
}

/**
 * This struct contains the name of a route specified by the `path` function.
 */
struct PathAttribute
{
	/// The specified path
	string data;
	alias data this;
}

/// private
package struct NoRouteAttribute {}

/**
 * This struct contains a mapping between the name used by HTTP (field)
 * and the parameter (identifier) name of the function.
 */
public struct WebParamAttribute {
	import vibe.web.internal.rest.common : ParameterKind;

	/// The type of the WebParamAttribute
	ParameterKind origin;
	/// Parameter name (function parameter name).
	string identifier;
	/// The meaning of this field depends on the origin. (HTTP request name)
	string field;
}


/**
 * Declare that a parameter will be transmitted to the API through the body.
 *
 * It will be serialized as part of a JSON object.
 * The serialization format is currently not customizable.
 * If no fieldname is given, the entire body is serialized into the object.
 *
 * Params:
 * - identifier: The name of the parameter to customize. A compiler error will be issued on mismatch.
 * - field: The name of the field in the JSON object.
 *
 * ----
 * @bodyParam("pack", "package")
 * void ship(int pack);
 * // The server will receive the following body for a call to ship(42):
 * // { "package": 42 }
 * ----
 */
WebParamAttribute bodyParam(string identifier, string field) @safe
in {
	assert(field.length > 0, "fieldname can't be empty.");
}
body
{
	import vibe.web.internal.rest.common : ParameterKind;
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.body_, identifier, field);
}

/// ditto
WebParamAttribute bodyParam(string identifier)
@safe {
	import vibe.web.internal.rest.common : ParameterKind;
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.body_, identifier, "");
}

/**
 * Declare that a parameter will be transmitted to the API through the headers.
 *
 * If the parameter is a string, or any scalar type (float, int, char[], ...), it will be send as a string.
 * If it's an aggregate, it will be serialized as JSON.
 * However, passing aggregate via header isn't a good practice and should be avoided for new production code.
 *
 * Params:
 * - identifier: The name of the parameter to customize. A compiler error will be issued on mismatch.
 * - field: The name of the header field to use (e.g: 'Accept', 'Content-Type'...).
 *
 * ----
 * // The server will receive the content of the "Authorization" header.
 * @headerParam("auth", "Authorization")
 * void login(string auth);
 * ----
 */
WebParamAttribute headerParam(string identifier, string field)
@safe {
	import vibe.web.internal.rest.common : ParameterKind;
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.header, identifier, field);
}

/**
 * Declare that a parameter will be transmitted to the API through the query string.
 *
 * It will be serialized as part of a JSON object, and will go through URL serialization.
 * The serialization format is not customizable.
 *
 * Params:
 * - identifier: The name of the parameter to customize. A compiler error will be issued on mismatch.
 * - field: The field name to use.
 *
 * ----
 * // For a call to postData("D is awesome"), the server will receive the query:
 * // POST /data?test=%22D is awesome%22
 * @queryParam("data", "test")
 * void postData(string data);
 * ----
 */
WebParamAttribute queryParam(string identifier, string field)
@safe {
	import vibe.web.internal.rest.common : ParameterKind;
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.query, identifier, field);
}

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


/// Speficies how D fields are mapped to form field names
enum NestedNameStyle {
	underscore, /// Use underscores to separate fields and array indices
	d           /// Use native D style and separate fields by dots and put array indices into brackets
}


// concatenates two URL parts avoiding any duplicate slashes
// in resulting URL. `trailing` defines of result URL must
// end with slash
package string concatURL(string prefix, string url, bool trailing = false)
@safe {
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

@safe unittest {
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


/// private
template isNullable(T) {
	import std.traits;
	enum isNullable = isInstanceOf!(Nullable, T);
}

static assert(isNullable!(Nullable!int));

package struct ParamError {
	string field;
	string text;
	string debugText;
}

package enum ParamResult {
	ok,
	skipped,
	error
}

// maximum array index in the parameter fields.
private enum MAX_ARR_INDEX = 0xffff;

// handle the actual data inside the parameter
private ParamResult processFormParam(T)(scope string data, string fieldname, ref T dst, ref ParamError err)
{
	static if (is(T == bool))
	{
		// getting here means the item is present, set to true.
		dst = true;
		return ParamResult.ok;
	}
	else
	{
		if (!data.webConvTo(dst, err)) {
			err.field = fieldname;
			return ParamResult.error;
		}
		return ParamResult.ok;
	}
}

// NOTE: dst is assumed to be uninitialized
package ParamResult readFormParamRec(T)(scope HTTPServerRequest req, ref T dst, string fieldname, bool required, NestedNameStyle style, ref ParamError err)
{
	import std.traits;
	import std.typecons;
	import vibe.data.serialization;
	import std.algorithm : startsWith;

	static if (isStaticArray!T || (isDynamicArray!T && !isSomeString!(OriginalType!T))) {
		alias EL = typeof(T.init[0]);
		enum isSimpleElement = !(isDynamicArray!EL && !isSomeString!(OriginalType!EL)) &&
			!isStaticArray!EL &&
			!(is(T == struct) &&
					!is(typeof(T.fromString(string.init))) &&
					!is(typeof(T.fromStringValidate(string.init, null))) &&
					!is(typeof(T.fromISOExtString(string.init))));

		static if (isStaticArray!T)
		{
			bool[T.length] seen;
		}
		else
		{
			static assert(!is(EL == bool),
			  "Boolean arrays are not allowed, because their length cannot " ~
			  "be uniquely determined. Use a static array instead.");
			// array to check for duplicates
			dst = T.init;
			bool[] seen;
		}
		// process the items in the order they appear.
		char indexSep = style == NestedNameStyle.d ? '[' : '_';
		const minLength = fieldname.length + (style == NestedNameStyle.d ? 2 : 1);
		const indexTrailer = style == NestedNameStyle.d ? "]" : "";

		ParamResult processItems(DL)(DL dlist)
		{
			foreach (k, v; dlist.byKeyValue)
			{
				if (k.length < minLength)
					// sanity check to prevent out of bounds
					continue;
				if (k.startsWith(fieldname) && k[fieldname.length] == indexSep)
				{
					// found a potential match
					string key = k[fieldname.length + 1 .. $];
					size_t idx;
					if (key == indexTrailer)
					{
						static if (isSimpleElement)
						{
							// this is a non-indexed array item. Find an empty slot, or expand the array
							import std.algorithm : countUntil;
							idx = seen[].countUntil(false);
							static if (isStaticArray!T)
							{
								if (idx == size_t.max)
								{
									// ignore extras, and we know there are no more matches to come.
									break;
								}
							}
							else if (idx == size_t.max)
							{
								// append to the end.
								idx = dst.length;
							}
						}
						else
						{
							// not valid for non-simple elements.
							continue;
						}
					}
					else
					{
						import std.conv;
						idx = key.parse!size_t;
						static if (isStaticArray!T)
						{
							if (idx >= T.length)
								// keep existing behavior, ignore extras
								continue;
						}
						else if (idx > MAX_ARR_INDEX)
						{
							// Getting a bit large, we don't want to allow DOS attacks.
							err.field = k;
							err.text = "Maximum index exceeded";
							return ParamResult.error;
						}
						static if (isSimpleElement)
						{
							if (key != indexTrailer)
								// this can't be a match, simple elements are parsed from
								// the string, there should be no more to the key.
								continue;
						}
						else
						{
							// ensure there's more than just the index trailer
							if (key.length == indexTrailer.length || !key.startsWith(indexTrailer))
								// not a valid entry. ignore this entry to preserve existing behavior.
								continue;
						}
					}

					static if (!isStaticArray!T)
					{
						// check to see if we need to expand the array
						if (dst.length <= idx)
						{
							dst.length = idx + 1;
							seen.length = idx + 1;
						}
					}

					if (seen[idx])
					{
						// don't store it twice
						continue;
					}
					seen[idx] = true;

					static if (isSimpleElement)
					{
						auto result = processFormParam(v, k, dst[idx], err);
					}
					else
					{
						auto subFieldname = k[0 .. $ - key.length + indexTrailer.length];
						auto result = readFormParamRec(req, dst[idx], subFieldname, true, style, err);
					}
					if (result != ParamResult.ok)
						return result;
				}
			}

			return ParamResult.ok;
		}

		if (processItems(req.form) == ParamResult.error)
			return ParamResult.error;
		if (processItems(req.query) == ParamResult.error)
			return ParamResult.error;

		// make sure all static array items have been seen
		static if (isStaticArray!T)
		{
			import std.algorithm : countUntil;
			auto notSeen = seen[].countUntil(false);
			if (notSeen != -1)
			{
				err.field = style.getArrayFieldName(fieldname, notSeen);
				err.text = "Missing form field.";
				return ParamResult.error;
			}
		}
	} else static if (isNullable!T) {
		typeof(dst.get()) el = void;
		auto r = readFormParamRec(req, el, fieldname, false, style, err);
		final switch (r) {
			case ParamResult.ok: dst.setVoid(el); break;
			case ParamResult.skipped: dst.setVoid(T.init); break;
			case ParamResult.error: return ParamResult.error;
		}
	} else static if (is(T == struct) &&
		!is(typeof(T.fromString(string.init))) &&
		!is(typeof(T.fromStringValidate(string.init, null))) &&
		!is(typeof(T.fromISOExtString(string.init))))
	{
		foreach (m; __traits(allMembers, T)) {
			auto r = readFormParamRec(req, __traits(getMember, dst, m), style.getMemberFieldName(fieldname, m), required, style, err);
			if (r != ParamResult.ok)
				return r; // FIXME: in case of errors the struct will be only partially initialized! All previous fields should be deinitialized first.
		}
	} else static if (is(T == bool)) {
		dst = (fieldname in req.form) !is null || (fieldname in req.query) !is null;
	} else if (auto pv = fieldname in req.form) {
		if (!(*pv).webConvTo(dst, err)) {
			err.field = fieldname;
			return ParamResult.error;
		}
	} else if (auto pv = fieldname in req.query) {
		if (!(*pv).webConvTo(dst, err)) {
			err.field = fieldname;
			return ParamResult.error;
		}
	} else if (required) {
		err.field = fieldname;
		err.text = "Missing form field.";
		return ParamResult.error;
	}
	else return ParamResult.skipped;

	return ParamResult.ok;
}

// test new array mechanisms
unittest {
	import vibe.http.server;
	import vibe.inet.url;

	auto req = createTestHTTPServerRequest(URL("http://localhost/route?arr_0=1&arr_2=2&arr_=3"));
	int[] arr;
	ParamError err;
	auto result = req.readFormParamRec(arr, "arr", false, NestedNameStyle.underscore, err);
	assert(result == ParamResult.ok);
	assert(arr == [1,3,2]);

	// try with static array
	int[3] staticarr;
	result = req.readFormParamRec(staticarr, "arr", false, NestedNameStyle.underscore, err);
	assert(result == ParamResult.ok);
	assert(staticarr == [1,3,2]);

	// d style
	req = createTestHTTPServerRequest(URL("http://localhost/route?arr[2]=1&arr[0]=2&arr[]=3"));
	result = req.readFormParamRec(arr, "arr", false, NestedNameStyle.d, err);
	assert(result == ParamResult.ok);
	assert(arr == [2,3,1]);

	result = req.readFormParamRec(staticarr, "arr", false, NestedNameStyle.d, err);
	assert(result == ParamResult.ok);
	assert(staticarr == [2,3,1]);

	// try nested arrays
	req = createTestHTTPServerRequest(URL("http://localhost/route?arr[2][]=1&arr[0][]=2&arr[1][]=3&arr[0][]=4"));
	int[][] arr2;
	result = req.readFormParamRec(arr2, "arr", false, NestedNameStyle.d, err);
	assert(result == ParamResult.ok);
	assert(arr2 == [[2,4],[3],[1]]);

	int[][2] staticarr2;
	result = req.readFormParamRec(staticarr2, "arr", false, NestedNameStyle.d, err);
	assert(result == ParamResult.ok);
	assert(staticarr2 == [[2,4],[3]]);

	// bug with key length
	req = createTestHTTPServerRequest(URL("http://localhost/route?arr=1"));
	result = req.readFormParamRec(arr, "arr", false, NestedNameStyle.d, err);
	assert(result == ParamResult.ok);
	assert(arr.length == 0);
}

package bool webConvTo(T)(string str, ref T dst, ref ParamError err)
nothrow {
	import std.conv;
	import std.exception;
	try {
		static if (is(typeof(T.fromStringValidate(str, &err.text)))) {
			static assert(is(typeof(T.fromStringValidate(str, &err.text)) == Nullable!T));
			auto res = T.fromStringValidate(str, &err.text);
			if (res.isNull()) return false;
			dst.setVoid(res);
		} else static if (is(typeof(T.fromString(str)))) {
			static assert(is(typeof(T.fromString(str)) == T));
			dst.setVoid(T.fromString(str));
		} else static if (is(typeof(T.fromISOExtString(str)))) {
			static assert(is(typeof(T.fromISOExtString(str)) == T));
			dst.setVoid(T.fromISOExtString(str));
		} else {
			dst.setVoid(str.to!T());
		}
	} catch (Exception e) {
		import vibe.core.log : logDebug;
		import std.encoding : sanitize;
		err.text = e.msg;
		debug try logDebug("Error converting web field: %s", e.toString().sanitize);
		catch (Exception) {}
		return false;
	}
	return true;
}

// properly sets an uninitialized variable
package void setVoid(T, U)(ref T dst, U value)
{
	import std.traits;
	static if (hasElaborateAssign!T) {
		static if (is(T == U)) {
			(cast(ubyte*)&dst)[0 .. T.sizeof] = (cast(ubyte*)&value)[0 .. T.sizeof];
			typeid(T).postblit(&dst);
		} else {
			static T init = T.init;
			(cast(ubyte*)&dst)[0 .. T.sizeof] = (cast(ubyte*)&init)[0 .. T.sizeof];
			dst = value;
		}
	} else dst = value;
}

unittest {
	static assert(!__traits(compiles, { bool[] barr; ParamError err;readFormParamRec(null, barr, "f", true, NestedNameStyle.d, err); }));
	static assert(__traits(compiles, { bool[2] barr; ParamError err;readFormParamRec(null, barr, "f", true, NestedNameStyle.d, err); }));

	enum Test: string {	a = "AAA", b="BBB" }
	static assert(__traits(compiles, { Test barr; ParamError err;readFormParamRec(null, barr, "f", true, NestedNameStyle.d, err); }));
}

private string getArrayFieldName(T)(NestedNameStyle style, string prefix, T index)
{
	import std.format : format;
	final switch (style) {
		case NestedNameStyle.underscore: return format("%s_%s", prefix, index);
		case NestedNameStyle.d: return format("%s[%s]", prefix, index);
	}
}

private string getMemberFieldName(NestedNameStyle style, string prefix, string member)
@safe {
	import std.format : format;
	final switch (style) {
		case NestedNameStyle.underscore: return format("%s_%s", prefix, member);
		case NestedNameStyle.d: return format("%s.%s", prefix, member);
	}
}
