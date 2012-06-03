/**
	Utility functions for dealing with templates.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.templ.utils;

/**
	Allows to pass additional variables to a function that renders a templated page.

	This function is useful if you need to support additional layers of functionality that should
	be available to your views, such as authentication. This function allows to define variables
	that should be usable from templates using so called "injectors". Each injector is a template
	function that can add its own parameters.

	NOTE: this function requires at least DMD 2.060, as it suffers from DMD BUG 2962.

	Examples:

		The following example will render the template "home.dt" and make the variables 'userinfo',
		'something_else' and 'message' available. Before the 'page' function is called,
		'authInjector' and 'somethingInjector' can process the request and decide what to do.

		---
		void authInjector(alias Next, Vars...)(HttpServerRequest req, HttpServerResponse res)
		{
			string userinfo;
			// TODO: fill userinfo with content, throw an Unauthorized HTTP error etc.
			Next!(Vars, userinfo)(req, res);
		}

		void somethingInjector(alias Next, Vars...)(HttpServerRequest req,
		HttpServerResponse res)
		{
			string something_else;
			Next!(Vars, something_else)(req, res);
		}

		void page(VARS...)(HttpServerRequest req, HttpServerResponse res)
		{
			string message = "Welcome to the example page!"
			res.render!("home.dt", VARS, message);
		}

		static this()
		{
			auto router = new UrlRouter;
			router.get("/", inject!(page, authInjector, somethingInjector));
		} 
		---
*/
@property auto inject(alias Page, Injectors...)()
{
	return &injectReverse!(Injectors, reqInjector, Page);
}

/// private
template injectReverse(Injectors...)
{
	alias Injectors[0] First;
	alias Injectors[1 .. $] Rest;
	alias First!(Rest) injectReverse;
}

/// private
void reqInjector(alias Next, Vars...)(HttpServerRequest req, HttpServerResponse res)
{
	Next!(Vars, req)(req, res);
}
