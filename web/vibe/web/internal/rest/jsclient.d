/**
	Internal module with functions to generate JavaScript REST interfaces.

	Copyright: © 2015-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.internal.rest.jsclient;

import vibe.inet.url : URL;
import vibe.web.rest;

import std.conv : to;

///
class JSRestClientSettings
{
	///
	string indentStep;
	///
	string name;

	///
	@property JSRestClientSettings dup()
	const {
		auto ret = new JSRestClientSettings;
		ret.indentStep = this.indentStep;
		ret.name = this.name;
		return ret;
	}
}

/**
	Generates JavaScript code suitable for accessing a REST interface using XHR.
*/
/*package(vibe.web.web)*/ void generateInterface(TImpl, R)(ref R output, RestInterfaceSettings settings,
		JSRestClientSettings jsgenset, bool parent)
{
	static void fmtParam(F)(ref F f, ref const PathPart p)
	{
		if (!p.isParameter) f.serializeToJson(p.text);
		else f.formattedWrite("toRestString(%s)", p.text);
	}
	// TODO: handle attributed parameters and filter out internal parameters that have no path placeholder assigned to them

	import std.format : formattedWrite;
	import std.string : toUpper, strip, splitLines;
	import std.traits : FunctionTypeOf, ReturnType;
	import std.algorithm : filter, map;
	import std.array : replace;
	import std.typecons : tuple;

	import vibe.data.json : Json, serializeToJson;
	import vibe.internal.meta.uda;
	import vibe.http.common : HTTPMethod;
	import vibe.web.internal.rest.common;
	import vibe.web.common;

	auto intf = RestInterface!TImpl(settings, true);

	auto fout = indentSink(output, jsgenset.indentStep);

	fout.formattedWrite("%s%s = new function() {\n", parent ? "" : "this.",
			jsgenset.name.length ? jsgenset.name : intf.I.stringof);

	if (parent) {
		auto lns = `
			var toRestString = function(v) {
				var res;
				switch(typeof(v)) {
					case "object": res = JSON.stringify(v); break;
					default: res = v;
				}
				return encodeURIComponent(res);
			}`;
		foreach(ln; lns.splitLines.map!(a=>a.strip ~ "\n"))
			fout.put(ln);
	}

	foreach (i, SI; intf.SubInterfaceTypes) {
		fout.put("\n");
		auto chset = jsgenset.dup;
		chset.name = __traits(identifier, intf.SubInterfaceFunctions[i]);
		fout.generateInterface!SI(intf.subInterfaces[i].settings, chset, false);
	}

	foreach (i, F; intf.RouteFunctions) {
		alias FT = FunctionTypeOf!F;
		auto route = intf.routes[i];

		// function signature
		fout.put("\n");
		fout.formattedWrite("this.%s = function(", route.functionName);
		foreach (j, param; route.parameters) {
			fout.put(param.name);
			fout.put(", ");
		}
		static if (!is(ReturnType!FT == void)) fout.put("on_result, ");

		fout.put("on_error) {\n");

		// url assembly
		fout.put("var url = ");
		if (route.pathHasPlaceholders) {
			auto burl = URL(intf.baseURL);
			if (burl.host.length) {
				// extract the server part of the URL
				burl.pathString = "/";
				fout.serializeToJson(burl.toString()[0 .. $-1]);
				fout.put(" + ");
			}
			// and then assemble the full path piece-wise

			// if route.pathHasPlaceholders no need to check route.fullPathParts.length
			// because it fills in module vibe.web.internal.rest.common at 208 line only
			fmtParam(fout, route.fullPathParts[0]);
			foreach (p; route.fullPathParts[1..$]) {
				fout.put(" + ");
				fmtParam(fout, p);
			}
		} else {
			fout.formattedWrite(`"%s"`, concatURL(intf.baseURL, route.pattern));
		}
		fout.put(";\n");

		// query parameters
		if (route.queryParameters.length) {
			fout.put("url = url");
			foreach (j, p; route.queryParameters)
				fout.formattedWrite(" + \"%s%s=\" + toRestString(%s)",
					j == 0 ? '?' : '&', p.fieldName, p.name);
			fout.put(";\n");
		}

		// body parameters
		if (route.wholeBodyParameter.name.length) {
			fout.formattedWrite("var bostbody = %s;\n", route.wholeBodyParameter.name);
		} else if (route.bodyParameters.length) {
			fout.put("var postbody = {\n");
			foreach (p; route.bodyParameters)
				fout.formattedWrite("%s: %s,\n", Json(p.fieldName), p.name);
			fout.put("};\n");
		}

		// XHR setup
		fout.put("var xhr = new XMLHttpRequest();\n");
		fout.formattedWrite("xhr.open('%s', url, true);\n", route.method.to!string.toUpper);
		fout.put("xhr.onload = function () {\n");
		fout.put("if (this.status >= 400) { if (on_error) on_error(JSON.parse(this.responseText)); else console.log(this.responseText); }\n");
		static if (!is(ReturnType!FT == void)) {
			fout.put("else on_result(JSON.parse(this.responseText));\n");
		}
		fout.put("};\n");

		// error handling
		fout.put("xhr.onerror = function (e) { if (on_error) on_error(e); else console.log(\"XHR request failed\"); }\n");

		// header parameters
		foreach (p; route.headerParameters)
			fout.formattedWrite("xhr.setRequestHeader(%s, %s);\n", Json(p.fieldName), p.name);

		// submit request
		if (route.method == HTTPMethod.GET || !route.bodyParameters.length)
			fout.put("xhr.send();\n");
		else {
			fout.put("xhr.setRequestHeader('Content-Type', 'application/json');\n");
			fout.put("xhr.send(JSON.stringify(postbody));\n");
		}
		fout.put("}\n");
	}
	fout.put("}\n");
}

version (unittest) {
	interface IDUMMY { void test(int dummy); }
	class DUMMY : IDUMMY { void test(int) {} }
	private void dummy()
	{
		import std.array;
		auto app = appender!string();
		app.generateInterface!DUMMY(null, null, true);
	}
}

unittest { // issue #1293
	import std.algorithm : canFind, find;
	import std.array : appender;
	import vibe.inet.url;

	interface S {
		void test();
	}

	interface I {
		@property S s();
		int test1();
		void test2();
	}
	auto settings = new RestInterfaceSettings;
	settings.baseURL = URL("http://localhost/");
	auto app = appender!string();
	auto jsgenset = new JSRestClientSettings;
	app.generateInterface!I(settings, jsgenset, true);
	assert(app.data.canFind("this.s = new function()"));
	assert(app.data.canFind("this.test1 = function(on_result, on_error)"));
	assert(app.data.find("this.test1 = function").canFind("on_result("));
	assert(app.data.canFind("this.test2 = function(on_error)"));
	assert(!app.data.find("this.test2 = function").canFind("on_result("));
}

private auto indentSink(O)(ref O output, string step)
{
	static struct IndentSink(R)
	{
		import std.string : strip;
		import std.algorithm : joiner;
		import std.range : repeat;

		R* base;
		string indent;
		size_t level, tempLevel;
		alias orig this;

		this(R* base, string indent)
		{
			this.base = base;
			this.indent = indent;
		}

		void pushIndent()
		{
			level++;
			tempLevel++;
		}

		void popIndent()
		{
			if (!level) return;

			level--;
			if (tempLevel)
				tempLevel = level;
		}

		void postPut(const(char)[] s)
		{
			auto ss = s.strip;
			if (ss.length && ss[$-1] == '{')
				pushIndent();

			if (s.length && s[$-1] == '\n')
				tempLevel = level;
		}

		void prePut(const(char)[] s)
		{
			auto ss = s.strip;
			if (ss.length && ss[0] == '}')
				popIndent();

			orig.put(indent.repeat(tempLevel).joiner());
			tempLevel = 0;
		}

		void put(const(char)[] s) { prePut(s); orig.put(s); postPut(s); }

		void put(char c) { prePut([c]); orig.put(c); postPut([c]); }

		void formattedWrite(Args...)(string fmt, Args args)
		{
			import std.format : formattedWrite;

			prePut(fmt);
			orig.formattedWrite(fmt, args);
			postPut(fmt);
		}

		ref R orig() @property { return *base; }
	}

	static if (is(typeof(output.prePut)) && is(typeof(output.postPut))) // is IndentSink
		return output;
	else
		return IndentSink!O(&output, step);
}

unittest {
	import std.array : appender;
	import std.format : formattedWrite;
	import std.algorithm : equal;

	auto buf = appender!string();
	auto ind = indentSink(buf, "\t");
	ind.put("class A {\n");
	ind.put("int func() { return 12; }\n");

	auto ind2 = indentSink(ind, "    "); // return itself, not override indentStep

	ind2.formattedWrite("void %s(%-(%s, %)) {\n", "func2", ["int a", "float b", "char c"]);
	ind2.formattedWrite("if (%s == %s) {\n", "a", "0");
	ind2.put("action();\n");
	ind2.put("}\n");
	ind2.put("}\n");
	ind.put("}\n");

	auto res = "class A {\n\tint func() { return 12; }\n\tvoid func2(int a, float b, char c) {\n\t\t" ~
		"if (a == 0) {\n\t\t\taction();\n\t\t}\n\t}\n}\n";

	assert(equal(res, buf.data));
}
