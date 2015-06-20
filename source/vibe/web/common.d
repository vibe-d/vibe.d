/**
	Contains common functionality for the REST and WEB interface generators.

	Copyright: © 2012-2014 RejectedSoftware e.K.
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
    Attribute to define the content type for methods.

    This currently applies only to methods returning an $(D InputStream) or
    $(D ubyte[]).
*/
ContentTypeAttribute contentType(string data)
{
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
{
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
{
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return PathAttribute(data);
}

///
unittest {
	@path("/foo")
	interface IAPI
	{
		@path("info2") string getInfo();
	}

	class API : IAPI {
		string getInfo() { return "Hello, World!"; }
	}

	void test()
	{
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


/**
	Scheduled for deprecation - use @$(D path) instead.

	See_Also: $(D path)
 */
PathAttribute rootPath(string path)
{
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return PathAttribute(path);
}


/// Convenience alias to generate a name from the interface's name.
@property PathAttribute rootPathFromName()
{
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return PathAttribute("");
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

/// private
package struct PathAttribute
{
	string data;
	alias data this;
}

/// Private struct describing the origin of a parameter (Query, Header, Body).
package struct WebParamAttribute {
	enum Origin {
		Body,
		Header,
		Query,
	}

	Origin origin;
	/// Parameter name
	string identifier;
	/// The meaning of this field depends on the origin.
	string field;
}

/**
 * Declare that a parameter will be transmitted to the API through the body.
 *
 * It will be serialized as part of a JSON object.
 * The serialization format is currently not customizable.
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
WebParamAttribute bodyParam(string identifier, string field) {
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(WebParamAttribute.Origin.Body, identifier, field);
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
{
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(WebParamAttribute.Origin.Header, identifier, field);
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
{
	if (!__ctfe)
		assert(false, onlyAsUda!__FUNCTION__);
	return WebParamAttribute(WebParamAttribute.Origin.Query, identifier, field);
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


// Little wrapper for Nullable!T to enable more comfortable initialization.
/// private
struct NullableW(T) {
	Nullable!T storage;
	alias storage this;

	this(typeof(null)) {}
	this(T val) { storage = val; }
}

/// private
template isNullable(T) {
	import std.traits;
	enum isNullable = isInstanceOf!(Nullable, T) || isInstanceOf!(NullableW, T);
}

static assert(isNullable!(Nullable!int));
static assert(isNullable!(NullableW!int));


// NOTE: dst is assumed to be uninitialized
package bool readFormParamRec(T)(scope HTTPServerRequest req, ref T dst, string fieldname, bool required)
{
	import std.string;
	import std.traits;
	import std.typecons;
	import vibe.data.serialization;

	static if (isDynamicArray!T && !isSomeString!T) {
		alias EL = typeof(T.init[0]);
		size_t idx = 0;
		dst = T.init;
		while (true) {
			EL el = void;
			if (!readFormParamRec(req, el, format("%s_%s", fieldname, idx), false))
				break;
			dst ~= el;
			idx++;
		}
	} else static if (isNullable!T) {
		typeof(dst.get()) el = void;
		if (readFormParamRec(req, el, fieldname, false))
			dst.setVoid(el);
		else dst.setVoid(T.init);
	} else static if (is(T == struct) && !is(typeof(T.fromString(string.init))) && !is(typeof(T.fromStringValidate(string.init, null)))) {
		foreach (m; __traits(allMembers, T))
			if (!readFormParamRec(req, __traits(getMember, dst, m), fieldname~"_"~m, required))
				return false;
	} else static if (is(T == bool)) {
		dst = (fieldname in req.form) !is null || (fieldname in req.query) !is null;
	} else if (auto pv = fieldname in req.form) dst.setVoid((*pv).webConvTo!T);
	else if (auto pv = fieldname in req.query) dst.setVoid((*pv).webConvTo!T);
	else if (required) throw new HTTPStatusException(HTTPStatus.badRequest, "Missing parameter "~fieldname);
	else return false;
	return true;
}

package T webConvTo(T)(string str)
{
	import std.conv;
	import std.exception;
	string error;
	static if (is(typeof(T.fromStringValidate(str, &error)))) {
		static assert(is(typeof(T.fromStringValidate(str, &error)) == Nullable!T));
		auto ret = T.fromStringValidate(str, &error);
		enforceBadRequest(!ret.isNull(), error); // TODO: refactor internally to work without exceptions
		return ret.get();
	} else static if (is(typeof(T.fromString(str)))) {
		static assert(is(typeof(T.fromString(str)) == T));
		return T.fromString(str);
	} else return str.to!T();
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
