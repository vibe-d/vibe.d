/**
 * Implements REST specific functionalities shared between the client and server.
 *
 * This module is private and should not be imported from outside of Vibe.d
 *
 * Copyright: © 2015 RejectedSoftware e.K.
 * License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
 * Authors: Mathias Lang
 */
module vibe.web.internal.rest;

import vibe.web.common;
import vibe.data.json;

import std.algorithm;
import std.traits;
import std.typetuple;

static if (__VERSION__ >= 2067)
	mixin("package (vibe.web):");

/**
 * Check that the interface is valid.
 *
 * Every checks on the correctness of the interface should be put in checkRestInterface,
 * which allows to have consistent errors in the server and client.
 */
string getInterfaceValidationError(I)()
out (result) { assert((result is null) == !result.length); }
body {
	// The hack parameter is to kill "Statement is not reachable" warnings.
	string validateMethod(alias Func)(bool hack = true) {
		import vibe.internal.meta.uda;
		import std.string : format;

		static assert(is(FunctionTypeOf!Func), "Internal error");

		if (!__ctfe)
			assert(false, "Internal error");

		enum FuncId = (fullyQualifiedName!I~ "." ~ __traits(identifier, Func));
		alias PT = ParameterTypeTuple!Func;
		static if (!__traits(compiles, ParameterIdentifierTuple!Func)) {
			if (hack) return "%s: A parameter has no name.".format(FuncId);
			alias PN = TypeTuple!("-DummyInvalid-");
		} else
			alias PN = ParameterIdentifierTuple!Func;
		alias WPAT = UDATuple!(WebParamAttribute, Func);

		// Check if there is no orphan UDATuple (e.g. typo while writing the name of the parameter).
		foreach (i, uda; WPAT) {
			// Note: static foreach gets unrolled, generating multiple nested sub-scope.
			// The spec / DMD doesn't like when you have the same symbol in those,
			// leading to wrong codegen / wrong template being reused.
			// That's why those templates need different names.
			// See DMD bug #9748.
			mixin(GenOrphan!(i).Decl);
			// template CmpOrphan(string name) { enum CmpOrphan = (uda.identifier == name); }
			static if (!anySatisfy!(mixin(GenOrphan!(i).Name), PN)) {
				return "%s: No parameter '%s' (referenced by attribute @%sParam)"
					.format(FuncId, uda.identifier, uda.origin);
			}
		}

		foreach (i, P; PT) {
			static if (!PN[i].length)
				return "%s: Parameter %d has no name."
					.format(FuncId, i);
			// Check for multiple origins
			static if (WPAT.length) {
				// It's okay to reuse GenCmp, as the order of params won't change.
				// It should/might not be reinstantiated by the compiler.
				mixin(GenCmp!("Loop", i, PN[i]).Decl);
				alias WPA = Filter!(mixin(GenCmp!("Loop", i, PN[i]).Name), WPAT);
				static if (WPA.length > 1)
					return "%s: Parameter '%s' has multiple @*Param attributes on it."
						.format(FuncId, PN[i]);
			}
		}

		// Check for @path(":name")
		enum pathAttr = findFirstUDA!(PathAttribute, Func);
		static if (pathAttr.found) {
			static if (!pathAttr.value.length) {
				if (hack)
					return "%s: Path is null or empty".format(FuncId);
			} else {
				import std.algorithm : canFind, splitter;
				// splitter doesn't work with alias this ?
				auto str = pathAttr.value.startsWith("/") ? pathAttr.value[1 .. $] : pathAttr.value.data;
				auto sp = str.splitter('/');
				foreach (elem; sp) {
					if (!elem.length)
						return "%s: Path '%s' contains empty entries.".format(FuncId, pathAttr.value);

					if (elem[0] == ':') {
						// typeof(PN) is void when length is 0.
						static if (!PN.length) {
							if (hack)
								return "%s: Path contains '%s', but no parameter '_%s' defined."
									.format(FuncId, elem, elem[1..$]);
						} else {
							if (![PN].canFind("_"~elem[1..$]))
								return "%s: Path contains '%s', but no parameter '_%s' defined."
									.format(FuncId, elem, elem[1..$]);
							elem = elem[1..$];
						}
					}
				}
				// TODO: Check for validity of the subpath.
			}
		}
		return null;
	}

	if (!__ctfe)
		assert(false, "Internal error");
	foreach (method; __traits(allMembers, I)) {
		// WORKAROUND #1045 / @@BUG14375@@
		static if (method.length != 0)
			foreach (overload; MemberFunctionsTuple!(I, method)) {
				static if (validateMethod!(overload)())
					return validateMethod!(overload)();
			}
	}
	return null;
}

// Test detection of user typos (e.g., if the attribute is on a parameter that doesn't exist).
unittest {
	enum msg = "No parameter 'ath' (referenced by attribute @HeaderParam)";

	interface ITypo {
		@headerParam("ath", "Authorization") // mistyped parameter name
		string getResponse(string auth);
	}
	enum err = getInterfaceValidationError!ITypo;
	static assert(err !is null && stripTestIdent(err) == msg,
		"Expected validation error for getResponse, got "~err);
}

// Multiple origin for a parameter
unittest {
	enum msg = "Parameter 'arg1' has multiple @*Param attributes on it.";

	interface IMultipleOrigin {
		@headerParam("arg1", "Authorization") @bodyParam("arg1", "Authorization")
		string getResponse(string arg1, int arg2);
	}
	enum err = getInterfaceValidationError!IMultipleOrigin;
	static assert(err !is null && stripTestIdent(err) == msg, err);
}

// Missing parameter name
unittest {
	static if (__VERSION__ < 2067)
		enum msg = "A parameter has no name.";
	else
		enum msg = "Parameter 0 has no name.";

	interface IMissingName1 {
		string getResponse(string = "troublemaker");
	}
	interface IMissingName2 {
		string getResponse(string);
	}
	enum err1 = getInterfaceValidationError!IMissingName1;
	static assert(err1 !is null && stripTestIdent(err1) == msg, err1);
	enum err2 = getInterfaceValidationError!IMissingName2;
	static assert(err2 !is null && stripTestIdent(err2) == msg, err2);
}

// Issue 949
unittest {
	enum msg = "Path contains ':owner', but no parameter '_owner' defined.";

	@path("/repos/")
	interface IGithubPR {
		@path(":owner/:repo/pulls")
		string getPullRequests(string owner, string repo);
	}
	enum err = getInterfaceValidationError!IGithubPR;
	static assert(err !is null && stripTestIdent(err) == msg, err);
}

// Issue 1017
unittest {
	interface TestSuccess { @path("/") void test(); }
	interface TestFail { @path("//") void test(); }
	static assert(getInterfaceValidationError!TestSuccess is null);
	static assert(stripTestIdent(getInterfaceValidationError!TestFail)
		== "Path '//' contains empty entries.");
}

unittest {
	interface NullPath  { @path(null) void test(); }
	interface ExplicitlyEmptyPath { @path("") void test(); }
	static assert(stripTestIdent(getInterfaceValidationError!NullPath)
				  == "Path is null or empty");
	static assert(stripTestIdent(getInterfaceValidationError!ExplicitlyEmptyPath)
				  == "Path is null or empty");

	// Note: Implicitly empty path are valid:
	// interface ImplicitlyEmptyPath { void get(); }
}

private string stripTestIdent(string msg) {
	static if (__VERSION__ <= 2066) {
		import vibe.utils.string;
		auto idx = msg.indexOfCT(": ");
	} else {
		import std.string;
		auto idx = msg.indexOf(": ");
	}
	return idx >= 0 ? msg[idx+2 .. $] : msg;
}

// Workarounds @@DMD:9748@@, and maybe more
template GenCmp(string name, int id, string cmpTo) {
	import std.string : format;
	import std.conv : to;
	enum Decl = q{
		template %1$s(alias uda) {
			enum %1$s = (uda.identifier == "%2$s");
		}
	}.format(Name, cmpTo);
	enum Name = name~to!string(id);
}

// Ditto
template GenOrphan(int id) {
	import std.string : format;
	import std.conv : to;
	enum Decl = q{
		template %1$s(string name) {
			enum %1$s = (uda.identifier == name);
		}
	}.format(Name);
	enum Name = "OrphanCheck"~to!string(id);
}

string stripTUnderscore(Settings)(string name, Settings settings)
{
	if ((settings is null || settings.stripTrailingUnderscore)
		&& name.endsWith("_"))
		return name[0 .. $-1];
		else return name;
}

string stripTUnderscore()(string name, typeof(null))
{
	return name.endsWith("_") ? name[0 .. $-1] : name;
}


string toRestString(Json value)
{
	import std.conv;
	switch (value.type) {
	default: return value.toString();
	case Json.Type.Bool: return value.get!bool ? "true" : "false";
	case Json.Type.Int: return to!string(value.get!long);
	case Json.Type.Float: return to!string(value.get!double);
	case Json.Type.String: return value.get!string;
	}
}

T fromRestString(T)(string value)
{
	import std.conv : ConvException;
	import vibe.web.common : HTTPStatusException, HTTPStatus;
	try {
		static if (isInstanceOf!(Nullable, T)) return T(fromRestString!(typeof(T.init.get()))(value));
		else static if (is(T == bool)) return value == "true";
		else static if (is(T : int)) return to!T(value);
		else static if (is(T : double)) return to!T(value); // FIXME: formattedWrite(dst, "%.16g", json.get!double);
		else static if (is(string : T)) return value;
		else static if (__traits(compiles, T.fromISOExtString("hello"))) return T.fromISOExtString(value);
		else static if (__traits(compiles, T.fromString("hello"))) return T.fromString(value);
		else return deserializeJson!T(parseJson(value));
	} catch (ConvException e) {
		throw new HTTPStatusException(HTTPStatus.badRequest, e.msg);
	}
}
