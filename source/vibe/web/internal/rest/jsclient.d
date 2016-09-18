/**
	Internal module with functions to generate JavaScript REST interfaces.

	Copyright: © 2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.internal.rest.jsclient;

import vibe.web.rest;

import std.conv : to;


/**
	Generates JavaScript code suitable for accessing a REST interface using XHR.
*/
/*package(vibe.web.web)*/ void generateInterface(TImpl, R)(ref R output, string name, RestInterfaceSettings settings,
		string baseIndent="", string indentStep = "    ", bool child=false)
{
	// TODO: handle attributed parameters and filter out internal parameters that have no path placeholder assigned to them

	import std.format : formattedWrite;
	import std.string : toUpper;
	import std.traits : FunctionTypeOf, ReturnType;
	import vibe.data.json : Json, serializeToJson;
	import vibe.internal.meta.uda;
	import vibe.http.common : HTTPMethod;
	import vibe.web.internal.rest.common;
	import vibe.web.common;

	auto intf = RestInterface!TImpl(settings, true);

	output.formattedWrite("%s%s%s = new function() {\n", baseIndent, child ? "this." : "", name.length ? name : intf.I.stringof);

	auto indent = baseIndent ~ indentStep;
	auto inner1 = indent ~ indentStep;
	auto inner2 = inner1 ~ indentStep;

	output.put(indent ~ "var toRestString = function(v) { return v; }\n");

	foreach (i, SI; intf.SubInterfaceTypes) {
		output.put("\n");
		output.generateInterface!SI(__traits(identifier, intf.SubInterfaceFunctions[i]),
				intf.subInterfaces[i].settings, indent, indentStep, true);
	}

	foreach (i, F; intf.RouteFunctions) {
		alias FT = FunctionTypeOf!F;
		auto route = intf.routes[i];

		// function signature
		output.put("\n");
		output.formattedWrite("%sthis.%s = function(", indent, route.functionName);
		foreach (j, param; route.parameters) {
			output.put(param.name);
			output.put(", ");
		}
		static if (!is(ReturnType!FT == void)) output.put("on_result, ");

		output.put("on_error) {\n");

		// url assembly
		output.put(inner1 ~ "var url = ");
		if (route.pathHasPlaceholders) {
			output.serializeToJson(intf.baseURL);
			foreach (p; route.pathParts) {
				output.put(" + ");
				if (!p.isParameter) output.serializeToJson(p.text);
				else output.formattedWrite("encodeURIComponent(toRestString(%s))", p.text);
			}
		} else {
			import std.algorithm;
			auto rpn = route.parameters.map!"a.name".filter!(a=>a[0]=='_').map!"a[1..$]";
			if (rpn.save.count == 0)
				output.formattedWrite("%s", Json(concatURL(intf.baseURL, route.pattern.dup)));
			else {
				import std.array;
				char[] sink = route.pattern.dup;
				foreach (param; rpn)
					sink = replace(sink, ":" ~ param, "${_" ~ param ~ "}");
				output.formattedWrite("`%s`", concatURL(intf.baseURL, sink.idup)); // use `` instead ""
			}
		}
		output.put(";\n");

		// query parameters
		if (route.queryParameters.length) {
			output.put(inner1 ~ "url = url");
			foreach (j, p; route.queryParameters)
				output.formattedWrite(" + \"%s%s=\" + encodeURIComponent(toRestString(%s))",
					j == 0 ? '?' : '&', p.fieldName, p.name);
			output.put(";\n");
		}

		// body parameters
		if (route.bodyParameters.length) {
			output.put(inner1 ~ "var postbody = {\n");
			foreach (p; route.bodyParameters)
				output.formattedWrite("%s%s: toRestString(%s),\n", inner2, Json(p.fieldName), p.name);
			output.put(inner1 ~ "};\n");
		}

		// XHR setup
		output.put(inner1 ~ "var xhr = new XMLHttpRequest();\n");
		output.formattedWrite("%sxhr.open('%s', url, true);\n", inner1, route.method.to!string.toUpper);
		static if (!is(ReturnType!FT == void)) {
			output.put(inner1 ~ "xhr.onload = function () {\n");
			output.put(inner2 ~ "if (this.status >= 400) { if (on_error) on_error(JSON.parse(this.responseText)); else console.log(this.responseText); }\n");
			output.put(inner2 ~ "else on_result(JSON.parse(this.responseText));\n");
			output.put(inner1 ~ "};\n");
		}

		// header parameters
		foreach (p; route.headerParameters)
			output.formattedWrite("%sxhr.setRequestHeader(%s, %s);\n", inner1, Json(p.fieldName), p.name);

		// submit request
		if (route.method == HTTPMethod.GET || !route.bodyParameters.length)
			output.put(inner1 ~ "xhr.send();\n");
		else {
			output.put(inner1 ~ "xhr.setRequestHeader('Content-Type', 'application/json');\n");
			output.put(inner1 ~ "xhr.send(JSON.stringify(postbody));\n");
		}

		output.put(indent ~ "}\n");
	}

	output.put(baseIndent ~ "}\n");
}

version (unittest) {
	interface IDUMMY { void test(int dummy); }
	class DUMMY : IDUMMY { void test(int) {} }
	private void dummy()
	{
		import std.array;
		auto app = appender!string();
		app.generateInterface!DUMMY(null, null);
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
	app.generateInterface!I(null, settings);
	assert(app.data.canFind("this.test1 = function(on_result, on_error)"));
	assert(app.data.find("this.test1 = function").canFind("xhr.onload ="));
	assert(app.data.canFind("this.test2 = function(on_error)"));
	assert(!app.data.find("this.test2 = function").canFind("xhr.onload ="));
}
