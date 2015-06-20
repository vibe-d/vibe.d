/**
 * Implements REST client private functions and types.
 *
 * This module is private and should not be imported from outside of Vibe.d
 *
 * Copyright: © 2015 RejectedSoftware e.K.
 * License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
 * Authors: Mathias Lang
 */
module vibe.web.internal.rest_client;

import vibe.web.common;
import vibe.http.client;
import vibe.web.internal.rest;
import vibe.web.internal.routes;
import vibe.core.log;
import vibe.internal.meta.uda;
import vibe.data.json;
import std.algorithm;
import std.traits;
import std.typetuple;

static if (__VERSION__ >= 2067)
	mixin("package (vibe.web):");

mixin template RestClientMethods(I) if (is(I == interface)) {
	mixin RestClientMethods_MemberImpl!(__traits(allMembers, I));
}

// Poor men's `foreach (method; __traits(allMembers, I))`
// The only way to emulate a foreach in a mixin template is to mixin a recursion
// of that template.
mixin template RestClientMethods_MemberImpl(Members...) {
	import std.traits : MemberFunctionsTuple;
	static assert (Members.length > 0);
	// WORKAROUND #1045 / @@BUG14375@@
	static if (Members[0].length != 0) {
		private alias Ovrlds = MemberFunctionsTuple!(I, Members[0]);
		// Members can be declaration / fields.
		static if (Ovrlds.length > 0) {
			mixin RestClientMethods_OverloadImpl!(Ovrlds);
		}
	}
	static if (Members.length > 1) {
		mixin RestClientMethods_MemberImpl!(Members[1..$]);
	}
}

// Poor men's foreach (overload; MemberFunctionsTuple!(I, method))
mixin template RestClientMethods_OverloadImpl(Overloads...) {
	import vibe.internal.meta.codegen : CloneFunction;
	static assert (Overloads.length > 0);
	//pragma(msg, "===== Body for: "~__traits(identifier, Overloads[0])~" =====");
	//pragma(msg, genClientBody!(Overloads[0]));
	mixin CloneFunction!(Overloads[0], genClientBody!(Overloads[0])());
	static if (Overloads.length > 1) {
		mixin RestClientMethods_OverloadImpl!(Overloads[1..$]);
	}
}

string genClientBody(alias Func)() {
	import std.conv;
	import std.string : format;
	import vibe.internal.meta.funcattr : IsAttributedParameter;

	alias FT = FunctionTypeOf!Func;
	alias RT = ReturnType!FT;
	alias PTT = ParameterTypeTuple!Func;
	alias ParamNames = ParameterIdentifierTuple!Func;
	alias WPAT = UDATuple!(WebParamAttribute, Func);

	enum meta = extractHTTPMethodAndName!(Func, false)();
	enum FuncId = __traits(identifier, Func);

	// NB: block formatting is coded in dependency order, not in 1-to-1 code flow order
	static if (is(RT == interface)) {
		return q{ return m_%sImpl; }.format(RT.stringof);
	} else {
		string ret;
		string param_handling_str;
		string url_prefix = `""`;
		// Those store the way parameter should be handled afterward.
		// A parameter that bears doesn't a WebParamAttribute (which documents origin explicitly)
		// will be stored in defaultParamCTMap. Else, it will either go to headers__ (via request_str),
		// or queryParamCTMap / bodyParamCTMap, and be passed to genQuery / genBody just before calling request.
		// Note: The key is the HTTP parameter name, and the value the parameter *identifier*.
		// Ex: @queryParam("llama", "alpaca") void postSpit(string llama) => queryParamCTMap["alpaca"] = "llama";
		string[string] defaultParamCTMap;
		string[string] queryParamCTMap;
		string[string] bodyParamCTMap;

		// Block 2
		foreach (i, PT; PTT){
			// Check origin of parameter
			mixin(GenCmp!("ClientFilter", i, ParamNames[i]).Decl);

			// legacy :id special case, left for backwards-compatibility reasons
			static if (i == 0 && ParamNames[0] == "id") {
				static if (is(PT == Json))
					url_prefix = q{urlEncode(id.toString())~"/"};
				else
					url_prefix = q{urlEncode(toRestString(serializeToJson(id)))~"/"};
			} else static if (anySatisfy!(mixin(GenCmp!("ClientFilter", i, ParamNames[i]).Name), WPAT)) {
				alias PWPAT = Filter!(mixin(GenCmp!("ClientFilter", i, ParamNames[i]).Name), WPAT);
				static if (PWPAT[0].origin == WebParamAttribute.Origin.Header)
					param_handling_str ~= format(q{headers__["%s"] = to!string(%s);}, PWPAT[0].field, PWPAT[0].identifier);
				else static if (PWPAT[0].origin == WebParamAttribute.Origin.Query)
					queryParamCTMap[PWPAT[0].field] = PWPAT[0].identifier;
				else static if (PWPAT[0].origin == WebParamAttribute.Origin.Body)
					bodyParamCTMap[PWPAT[0].field] = PWPAT[0].identifier;
				else
					static assert (0, "Internal error: Unknown WebParamAttribute.Origin in REST client code generation.");
			} else static if (!ParamNames[i].startsWith("_")
					  && !IsAttributedParameter!(Func, ParamNames[i])) {
				// underscore parameters are sourced from the HTTPServerRequest.params map or from url itself
				defaultParamCTMap[stripTUnderscore(ParamNames[i], null)] = ParamNames[i];
			}
		}

		// Block 3
		string request_str;

		static if (!meta.hadPathUDA) {
			request_str = q{
				if (m_settings.stripTrailingUnderscore && url__.endsWith("_"))
					url__ = url__[0 .. $-1];
				url__ = %s ~ adjustMethodStyle(url__, m_methodStyle);
			}.format(url_prefix);
		} else {
			import std.array : split;
			auto parts = meta.url.split("/");
			request_str ~= `url__ = ` ~ url_prefix;
			foreach (i, p; parts) {
				if (i > 0) {
					request_str ~= `~ "/"`;
				}
				bool match = false;
				if (p.startsWith(":")) {
					foreach (pn; ParamNames) {
						if (pn.startsWith("_") && p[1 .. $] == pn[1 .. $]) {
							request_str ~= q{ ~ urlEncode(toRestString(serializeToJson(%s)))}.format(pn);
							match = true;
							break;
						}
					}
				}

				if (!match) {
					request_str ~= `~ "` ~ p ~ `"`;
				}
			}

			request_str ~= ";\n";
		}

		request_str ~= q{
			// By default for GET / HEAD, params are send via the query string.
			static if (HTTPMethod.%1$s == HTTPMethod.GET || HTTPMethod.%1$s == HTTPMethod.HEAD) {
				auto jret__ = request(HTTPMethod.%1$s, url__ , headers__, genQuery(%2$s%5$s%3$s), genBody(%4$s));
			} else {
				// Otherwise, they're send as a Json object via the body.
				auto jret__ = request(HTTPMethod.%1$s, url__ , headers__, genQuery(%3$s), genBody(%2$s%6$s%4$s));
			}

		}.format(to!string(meta.method),
			 paramCTMap(defaultParamCTMap), paramCTMap(queryParamCTMap), paramCTMap(bodyParamCTMap), // params map
			 (defaultParamCTMap.length && queryParamCTMap.length) ? ", " : "", // genQuery(%2$s, %3$s);
			 (defaultParamCTMap.length && bodyParamCTMap.length) ? ", " : ""); // genBody(%2$s, %4$s);

		static if (!is(RT == void)) {
			request_str ~= q{
				typeof(return) ret__;
				deserializeJson(ret__, jret__);
				return ret__;
			};
		}

		// Block 1
		ret ~= q{
			InetHeaderMap headers__;
			string url__ = "%s";
			%s
			%s
		}.format(meta.url, param_handling_str, request_str);
		return ret;
	}
}

// Small helper for client code generation
string paramCTMap(string[string] params)
{
	import std.array : appender, join;
	if (!__ctfe)
		assert (false, "This helper is only supposed to be called for codegen in RestClientInterface.");
	auto app = appender!(string[]);
	foreach (key, val; params) {
		app ~= "\""~key~"\"";
		app ~= val;
	}
	return app.data.join(", ");
}

string generateRestInterfaceSubInterfaces(I)()
{
	if (!__ctfe)
		assert (false);

	import std.algorithm : canFind;
	import std.string : format;

	string ret;
	string[] tps; // list of already processed interface types

	foreach (method; __traits(allMembers, I)) {
		// WORKAROUND #1045 / @@BUG14375@@
		static if (method.length != 0)
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			alias FT = FunctionTypeOf!overload;
			alias PTT = ParameterTypeTuple!FT;
			alias RT = ReturnType!FT;

			static if (is(RT == interface)) {
				static assert (
					PTT.length == 0,
					"Interface getters may not have parameters."
				);

				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof ~ "Impl";
					ret ~= q{
						alias RestInterfaceClient!(%s) %s;
					}.format(fullyQualifiedName!RT, implname);
					ret ~= q{
						private %1$s m_%1$s;
					}.format(implname);
					ret ~= "\n";
				}
			}
		}
	}
	return ret;
}

string generateRestInterfaceSubInterfaceInstances(I)()
{
	if (!__ctfe)
		assert (false);

	import std.string : format;
	import std.algorithm : canFind;

	string ret;
	string[] tps; // list of of already processed interface types

	foreach (method; __traits(allMembers, I)) {
		// WORKAROUND #1045 / @@BUG14375@@
		static if (method.length != 0)
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			alias FT = FunctionTypeOf!overload;
			alias PTT = ParameterTypeTuple!FT;
			alias RT = ReturnType!FT;

			static if (is(RT == interface)) {
				static assert (
					PTT.length == 0,
					"Interface getters may not have parameters."
				);

				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof ~ "Impl";

					enum meta = extractHTTPMethodAndName!(overload, false)();

					ret ~= q{
						auto settings_%1$s = m_settings.dup;
						settings_%1$s.baseURL.path
							= m_baseURL.path ~ (%3$s
									    ? "%2$s/"
									    : (adjustMethodStyle(stripTUnderscore("%2$s", settings), m_methodStyle) ~ "/"));
						m_%1$s = new %1$s(settings_%1$s);
					}.format(
						 implname,
						 meta.url,
						 meta.hadPathUDA
					);
					ret ~= "\n";
				}
			}
		}
	}

	return ret;
}

string generateRestInterfaceSubInterfaceRequestFilter(I)()
{
	if (!__ctfe)
		assert (false);

	import std.string : format;
	import std.algorithm : canFind;

	string ret;
	string[] tps; // list of already processed interface types

	foreach (method; __traits(allMembers, I)) {
		// WORKAROUND #1045 / @@BUG14375@@
		static if (method.length != 0)
		foreach (overload; MemberFunctionsTuple!(I, method)) {

			alias FT = FunctionTypeOf!overload;
			alias PTT = ParameterTypeTuple!FT;
			alias RT = ReturnType!FT;

			static if (is(RT == interface)) {
				static assert (
					PTT.length == 0,
					"Interface getters may not have parameters."
				);

				if (!tps.canFind(RT.stringof)) {
					tps ~= RT.stringof;
					string implname = RT.stringof ~ "Impl";

					ret ~= q{
						m_%s.requestFilter = m_requestFilter;
					}.format(implname);
					ret ~= "\n";
				}
			}
		}
	}
	return ret;
}

string generateModuleImports(I)()
{
	if (!__ctfe)
		assert (false);

	import vibe.internal.meta.codegen : getRequiredImports;
	import std.algorithm : map;
	import std.array : join;

	auto modules = getRequiredImports!I();
	return join(map!(a => "static import " ~ a ~ ";")(modules), "\n");
}

version(unittest)
{
	private struct Aggregate { }
	private interface Interface
	{
		Aggregate[] foo();
	}
}

unittest
{
	enum imports = generateModuleImports!Interface;
	static assert (imports == "static import "~__MODULE__~";");
}
