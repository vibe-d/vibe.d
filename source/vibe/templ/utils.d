/**
	Utility functions for dealing with templates.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.templ.utils;

import vibe.http.server;

import std.traits;
import std.typecons : Rebindable;


/**
	Allows to pass additional variables to a function that renders a templated page.

	This function is useful if you need to support additional layers of functionality that should
	be available to your views, such as authentication. This function allows to define variables
	that should be usable from templates using so called "injectors". Each injector is a template
	function that can add its own parameters.

	If you should need explicit access to one of the parameters of an upstream injector, you can use
	the InjectedParams!() template.

	NOTE: this function requires at least DMD 2.064, as it suffers from DMD BUG 2962/10086/10857.

	Examples:

		The following example will render the template "home.dt" and make the variables 'userinfo',
		'something_else' and 'message' available. Before the 'page' function is called,
		'authInjector' and 'somethingInjector' can process the request and decide what to do.

		---
		void authInjector(alias Next, Aliases...)(HTTPServerRequest req, HTTPServerResponse res)
		{
			string userinfo;
			// TODO: fill userinfo with content, throw an Unauthorized HTTP error etc.
			Next!(Aliases, userinfo)(req, res);
		}

		void somethingInjector(alias Next, Aliases...)(HTTPServerRequest req, HTTPServerResponse res)
		{
			string something_else;
			Next!(Aliases, something_else)(req, res);
		}

		void page(Aliases...)(HTTPServerRequest req, HTTPServerResponse res)
		{
			string message = "Welcome to the example page!"
			res.render!("home.dt", Aliases, message);
		}

		static this()
		{
			auto router = new URLRouter;
			router.get("/", inject!(page, authInjector, somethingInjector));
		} 
		---
*/
@property auto inject(alias Page, Injectors...)()
{
	return &injectReverse!(Injectors, reqInjector, Page);
}

/**
	Makes the variable aliases passed to one of the injectors of the inject!() template accessible
	to the local function.

	Examples:
		---
		void authInjector(alias Next, Aliases...)(HTTPServerRequest req, HTTPServerResponse res)
		{
			string userinfo;
			// TODO: fill userinfo with content, throw an Unauthorized HTTP error etc.
			Next!(Aliases, userinfo)(req, res);
		}

		void somethingInjector(alias Next, Aliases...)(HTTPServerRequest req, HTTPServerResponse res)
		{
			// access the userinfo variable:
			if( InjectedParams!Aliases.userinfo.length == 0 ) return;

			// it's also possible to declare a pseudo-
			// variable like this to access the parameters:
			InjectedParams!Aliases params;
			if( params.userinfo == "peter" )
				throw Exception("Not allowed!")

			Next!(Aliases)(req, res);
		}
		---
*/
struct InjectedParams(Aliases)
{
	mixin(localAliases(Aliases));
}

/// When mixed in, makes all ALIASES available in the local scope
template localAliases(int i, ALIASES...)
{
	static if( i < ALIASES.length ){
		enum string localAliases = "alias ALIASES["~cttostring(i)~"] "~__traits(identifier, ALIASES[i])~";\n"
			~localAliases!(i+1, ALIASES);
	} else {
		enum string localAliases = "";
	}
}

/// When mixed in, makes all ALIASES available in the local scope. Note that there must be a
/// Variant[] args__ available that matches TYPES_AND_NAMES
template localAliasesCompat(int i, TYPES_AND_NAMES...)
{
	import core.vararg;
	static if( i+1 < TYPES_AND_NAMES.length ){
		enum TYPE = "TYPES_AND_NAMES["~cttostring(i)~"]";
		enum NAME = TYPES_AND_NAMES[i+1];
		enum INDEX = cttostring(i/2);
		enum string localAliasesCompat = 
			"Rebindable2!("~TYPE~") "~NAME~";\n"~
			"if( _arguments["~INDEX~"] == typeid(Variant) )\n"~
			"\t"~NAME~" = *va_arg!Variant(_argptr).peek!("~TYPE~")();\n"~
			"else {\n"~
			"\tassert(_arguments["~INDEX~"] == typeid("~TYPE~"), \"Actual type for parameter "~NAME~" does not match template type.\");\n"~
			"\t"~NAME~" = va_arg!("~TYPE~")(_argptr);\n"~
			"}\n"~
			localAliasesCompat!(i+2, TYPES_AND_NAMES);
	} else {
		enum string localAliasesCompat = "";
	}
}

template Rebindable2(T)
{
	static if (is(T == class) || is(T == interface) || isArray!T) alias Rebindable2 = Rebindable!T;
	else alias Rebindable2 = Unqual!T;
}

/// private
package string cttostring(T)(T x)
{
	static if( is(T == string) ) return x;
	else static if( is(T : long) || is(T : ulong) ){
		Unqual!T tmp = x;
		string s;
		do {
			s = cast(char)('0' + (tmp%10)) ~ s;
			tmp /= 10;
		} while(tmp > 0);
		return s;
	} else {
		static assert(false, "Invalid type for cttostring: "~T.stringof);
	}
}

/// private
private template injectReverse(Injectors...)
{
	alias Injectors[0] First;
	alias Injectors[1 .. $] Rest;
	alias First!(Rest) injectReverse;
}

/// private
void reqInjector(alias Next, Vars...)(HTTPServerRequest req, HTTPServerResponse res)
{
	Next!(Vars, req)(req, res);
}
