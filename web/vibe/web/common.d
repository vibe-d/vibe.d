/**
	Contains common functionality for the REST and WEB interface generators.

	Copyright: © 2012-2017 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Михаил Страшун
*/
module vibe.web.common;

import vibe.http.common;
import vibe.http.server : HTTPServerRequest;
import vibe.data.json;
import vibe.internal.meta.uda : onlyAsUda, UDATuple;
import vibe.web.internal.rest.common : ParameterKind;

import std.meta : AliasSeq;
static import std.utf;
static import std.string;
import std.traits : getUDAs, ReturnType;
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

	string separate(char separator, bool upper_case)
	{
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
				ret ~= separator;
			}
			ret ~= name[start .. i];

			// quick skip the capital and remember the start of the next word
			start = i;
			if (i < name.length) {
				std.utf.decode(name, i);
			}
		}
		if (start < name.length) {
			ret ~= separator ~ name[start .. $];
		}
		return upper_case ? std.string.toUpper(ret) : std.string.toLower(ret);
	}

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
		case MethodStyle.lowerUnderscored: return separate('_', false);
		case MethodStyle.upperUnderscored: return separate('_', true);
		case MethodStyle.lowerDashed: return separate('-', false);
		case MethodStyle.upperDashed: return separate('-', true);
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
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.lowerDashed) == "method-name-test");
	assert(adjustMethodStyle("MethodNameTest", MethodStyle.upperDashed) == "METHOD-NAME-TEST");
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

    ///
	this (int status, string result, string file = __FILE__, int line = __LINE__,
		Throwable next = null) @safe
	{
		Json jsonResult = Json.emptyObject;
		jsonResult["statusMessage"] = result;
		this(status, jsonResult, file, line);
	}

	///
	this (int status, Json jsonResult, string file = __FILE__, int line = __LINE__,
		Throwable next = null) @safe
	{
		if (jsonResult.type == Json.Type.object && jsonResult["statusMessage"].type == Json.Type.string) {
			super(status, jsonResult["statusMessage"].get!string, file, line, next);
		}
		else {
			super(status, httpStatusText(status) ~ " (" ~ jsonResult.toString() ~ ")", file, line, next);
		}

		m_jsonResult = jsonResult;
	}

	/// The result text reported to the client
	@property inout(Json) jsonResult () inout nothrow pure @safe @nogc
	{
		return m_jsonResult;
	}
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


/** UDA for using a custom serializer for the method return value.

	Instead of using the default serializer (JSON), this allows to define
	custom serializers. Multiple serializers can be specified and will be
	matched against the `Accept` header of the HTTP request.

	Params:
		serialize = An alias to a generic function taking an output range as
			its first argument and the value to be serialized as its second
			argument. The result of the serialization is written byte-wise into
			the output range.
		deserialize = An alias to a generic function taking a forward range
			as its first argument and a reference to the value that is to be
			deserialized.
		content_type = The MIME type of the serialized representation.
*/
alias resultSerializer(alias serialize, alias deserialize, string content_type)
	= ResultSerializer!(serialize, deserialize, content_type);

///
unittest {
	import std.bitmanip : bigEndianToNative, nativeToBigEndian;

	interface MyRestInterface {
		static struct Point {
			int x, y;
		}

		static void serialize(R, T)(ref R output_range, const ref T value)
		{
			static assert(is(T == Point)); // only Point supported in this example
			output_range.put(nativeToBigEndian(value.x));
			output_range.put(nativeToBigEndian(value.y));
		}

		static T deserialize(T, R)(R input_range)
		{
			static assert(is(T == Point)); // only Point supported in this example
			T ret;
			ubyte[4] xbuf, ybuf;
			input_range.takeExactly(4).copy(xbuf[]);
			input_range.takeExactly(4).copy(ybuf[]);
			ret.x = bigEndianToNative!int(xbuf);
			ret.y = bigEndianToNative!int(ybuf);
			return ret;
		}

		// serialize as binary data in network byte order
		@resultSerializer!(serialize, deserialize, "application/binary")
		Point getPoint();
	}
}

/// private
struct ResultSerializer(alias ST, alias DT, string ContentType) {
	enum contentType = ContentType;
	alias serialize = ST;
	alias deserialize = DT;
}


package void defaultSerialize (alias P, T, RT) (ref RT output_range, const scope ref T value)
{
	static struct R {
		typeof(output_range) underlying;
		void put(char ch) { underlying.put(ch); }
		void put(scope const(char)[] ch) { underlying.put(cast(const(ubyte)[])ch); }
	}
	auto dst = R(output_range);
	// NOTE: serializeWithPolicy does not take value as scope due to issues
	//       deeply buried in the standard library
	() @trusted { return value; } ().serializeWithPolicy!(JsonStringSerializer!R, P) (dst);
}

package T defaultDeserialize (alias P, T, R) (R input_range)
{
	return deserializeWithPolicy!(JsonStringSerializer!(typeof(std.string.assumeUTF(input_range))), P, T)
		(std.string.assumeUTF(input_range));
}

package alias DefaultSerializerT = ResultSerializer!(
	defaultSerialize, defaultDeserialize, "application/json; charset=UTF-8");


/// Convenience template to get all the ResultSerializers for a function
package template ResultSerializersT(alias func) {
	alias DefinedSerializers = getUDAs!(func, ResultSerializer);
	static if (DefinedSerializers.length)
		alias ResultSerializersT = DefinedSerializers;
	else
		alias ResultSerializersT = AliasSeq!(DefaultSerializerT);
}

///
package template SerPolicyT (Iface)
{
	static if (getUDAs!(Iface, SerPolicy).length)
	{
		alias SerPolicyT = getUDAs!(Iface, SerPolicy)[0];
	}
	else
	{
		alias SerPolicyT = SerPolicy!DefaultPolicy;
	}
}

///
package struct SerPolicy (alias PolicyTemplatePar)
{
	alias PolicyTemplate = PolicyTemplatePar;
}

///
public alias serializationPolicy (Args...) = SerPolicy!(Args);

unittest
{
	import vibe.data.serialization : Base64ArrayPolicy;
	import std.array : appender;
	import std.conv : to;

	struct X
	{
		string name = "test";
		ubyte[] arr = [138, 245, 231, 234, 142, 132, 142];
	}
	X x;

	// Interface using Base64 array serialization
	@serializationPolicy!(Base64ArrayPolicy)
	interface ITestBase64
	{
		@safe X getTest();
	}

	alias serPolicyFound = SerPolicyT!ITestBase64;
	alias resultSerializerFound = ResultSerializersT!(ITestBase64.getTest)[0];

	// serialization test with base64 encoding
	auto output = appender!string();

	resultSerializerFound.serialize!(serPolicyFound.PolicyTemplate)(output, x);
	auto serialized = output.data;
	assert(serialized == `{"name":"test","arr":"ivXn6o6Ejg=="}`,
			"serialization is not correct, produced: " ~ serialized);

	// deserialization test with base64 encoding
	auto deserialized = serialized.deserializeWithPolicy!(JsonStringSerializer!string, serPolicyFound.PolicyTemplate, X)();
	assert(deserialized.name == "test", "deserialization of `name` is not correct, produced: " ~ deserialized.name);
	assert(deserialized.arr == [138, 245, 231, 234, 142, 132, 142],
			"deserialization of `arr` is not correct, produced: " ~ to!string(deserialized.arr));

	// Interface NOT using Base64 array serialization
	interface ITestPlain
	{
		@safe X getTest();
	}

	alias plainSerPolicyFound = SerPolicyT!ITestPlain;
	alias plainResultSerializerFound = ResultSerializersT!(ITestPlain.getTest)[0];

	// serialization test without base64 encoding
	output = appender!string();
	plainResultSerializerFound.serialize!(plainSerPolicyFound.PolicyTemplate)(output, x);
	serialized = output.data;
	assert(serialized == `{"name":"test","arr":[138,245,231,234,142,132,142]}`,
			"serialization is not correct, produced: " ~ serialized);

	// deserialization test without base64 encoding
	deserialized = serialized.deserializeWithPolicy!(JsonStringSerializer!string, plainSerPolicyFound.PolicyTemplate, X)();
	assert(deserialized.name == "test", "deserialization of `name` is not correct, produced: " ~ deserialized.name);
	assert(deserialized.arr == [138, 245, 231, 234, 142, 132, 142],
			"deserialization of `arr` is not correct, produced: " ~ to!string(deserialized.arr));
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
 * There are currently two kinds of symbol to do this: `viaBody` and `bodyParam`.
 * `viaBody` should be applied to the parameter itself, while `bodyParam`
 * is applied to the function.
 * `bodyParam` was introduced long before the D language for UDAs on parameters
 * (introduced in DMD v2.082.0), and will be deprecated in a future release.
 *
 * Params:
 *   identifier = The name of the parameter to customize. A compiler error will be issued on mismatch.
 *   field = The name of the field in the JSON object.
 *
 * ----
 * void ship(@viaBody("package") int pack);
 * // The server will receive the following body for a call to ship(42):
 * // { "package": 42 }
 * ----
 */
WebParamAttribute viaBody(string field = null)
@safe {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.body_, null, field);
}

/// Ditto
WebParamAttribute bodyParam(string identifier, string field) @safe
in {
	assert(field.length > 0, "fieldname can't be empty.");
}
do
{
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.body_, identifier, field);
}

/// ditto
WebParamAttribute bodyParam(string identifier)
@safe {
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
 * There are currently two kinds of symbol to do this: `viaHeader` and `headerParam`.
 * `viaHeader` should be applied to the parameter itself, while `headerParam`
 * is applied to the function.
 * `headerParam` was introduced long before the D language for UDAs on parameters
 * (introduced in DMD v2.082.0), and will be deprecated in a future release.
 *
 * Params:
 *   identifier = The name of the parameter to customize. A compiler error will be issued on mismatch.
 *   field = The name of the header field to use (e.g: 'Accept', 'Content-Type'...).
 *
 * ----
 * // The server will receive the content of the "Authorization" header.
 * void login(@viaHeader("Authorization") string auth);
 * ----
 */
WebParamAttribute viaHeader(string field)
@safe {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.header, null, field);
}

/// Ditto
WebParamAttribute headerParam(string identifier, string field)
@safe {
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
 * There are currently two kinds of symbol to do this: `viaQuery` and `queryParam`.
 * `viaQuery` should be applied to the parameter itself, while `queryParam`
 * is applied to the function.
 * `queryParam` was introduced long before the D language for UDAs on parameters
 * (introduced in DMD v2.082.0), and will be deprecated in a future release.
 *
 * Params:
 *   identifier = The name of the parameter to customize. A compiler error will be issued on mismatch.
 *   field = The field name to use.
 *
 * ----
 * // For a call to postData("D is awesome"), the server will receive the query:
 * // POST /data?test=%22D is awesome%22
 * void postData(@viaQuery("test") string data);
 * ----
 */
WebParamAttribute viaQuery(string field)
@safe {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.query, null, field);
}

/// Ditto
WebParamAttribute queryParam(string identifier, string field)
@safe {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(ParameterKind.query, identifier, field);
}


/** Declares a parameter to be transmitted via the HTTP status code or phrase.

	This attribute can be applied to one or two `out` parameters of type
	`HTTPStatus`/`int` or `string`. The values of those parameters correspond
	to the HTTP status code or phrase, depending on the type.
*/
enum viaStatus = WebParamAttribute(ParameterKind.status);


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
	/// lower-case-naming
	lowerDashed,
	/// UPPER-CASE-NAMING
	upperDashed,
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
			!(is(EL == struct) &&
					!is(typeof(EL.fromString(string.init))) &&
					!is(typeof(EL.fromStringValidate(string.init, null))) &&
					!is(typeof(EL.fromISOExtString(string.init))));

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
				err.text = "Missing array form field entry.";
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

unittest { // complex array parameters
	import vibe.http.server;
	import vibe.inet.url;

	static struct S {
		int a, b;
	}

	S[] arr;
	ParamError err;

	// d style
	auto req = createTestHTTPServerRequest(URL("http://localhost/route?arr[0].a=1&arr[0].b=2"));
	auto result = req.readFormParamRec(arr, "arr", false, NestedNameStyle.d, err);
	assert(result == ParamResult.ok);
	assert(arr == [S(1, 2)]);

	// underscore style
	req = createTestHTTPServerRequest(URL("http://localhost/route?arr_0_a=1&arr_0_b=2"));
	result = req.readFormParamRec(arr, "arr", false, NestedNameStyle.underscore, err);
	assert(result == ParamResult.ok);
	assert(arr == [S(1, 2)]);
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
			dst.setVoid(res.get);
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
	static assert(!__traits(compiles, { bool[] barr; ParamError err;readFormParamRec(HTTPServerRequest.init, barr, "f", true, NestedNameStyle.d, err); }));
	static assert(__traits(compiles, { bool[2] barr; ParamError err;readFormParamRec(HTTPServerRequest.init, barr, "f", true, NestedNameStyle.d, err); }));

	enum Test: string {	a = "AAA", b="BBB" }
	static assert(__traits(compiles, { Test barr; ParamError err;readFormParamRec(HTTPServerRequest.init, barr, "f", true, NestedNameStyle.d, err); }));
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
