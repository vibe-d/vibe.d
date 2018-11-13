/* This example module consists from several small example REST interfaces.
 * Features are not grouped by topic but by common their are needed. Each example
 * introduces few new more advanced features. Sometimes registration code in module constructor
 * is also important, it is then mentioned in example comment explicitly.
 */

import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import vibe.data.json;
import vibe.http.router;
import vibe.http.server;
import vibe.web.rest;
import vibe.web.web;

import std.typecons : Nullable;
import core.time;


interface Test1API
{
	string getSomeInfo();
}

abstract class BaseMiddleware : IMiddleware
{
	TestContext ctx;

	this(TestContext ctx)
	{
		this.ctx = ctx;
	}
}

// A middleware that log client address.
final class LogIpMiddleware : BaseMiddleware
{
	this(TestContext ctx) { super(ctx); }

	bool run(HTTPServerRequest req, HTTPServerResponse res) @safe
	{
		ctx.runList ~= LogIpMiddleware.stringof;
		logInfo(req.clientAddress.toAddressString());
		return true;
	}
}

// A middleware to ban client by ip.
final class IpBanMiddleware : BaseMiddleware
{
	this(TestContext ctx) { super(ctx); }

	bool run(HTTPServerRequest req, HTTPServerResponse res) @safe
	{
		ctx.runList ~= IpBanMiddleware.stringof;
		if (req.clientAddress.toAddressString() == "127.0.0.1")
			throw new HTTPStatusException(403);
		return true;
	}
}

final class FooMiddleware : BaseMiddleware
{
	this(TestContext ctx) { super(ctx); }

	bool run(HTTPServerRequest req, HTTPServerResponse res) @safe
	{
		ctx.runList ~= FooMiddleware.stringof;
		return true;
	}
}

final class TestContext
{
	string[] runList;
}

class Test1 : WebController, Test1API
{
	this(TestContext testCtx)
	{
		registerMiddleware(new LogIpMiddleware(testCtx));
		registerMiddleware(new IpBanMiddleware(testCtx));
		registerMiddleware(new FooMiddleware(testCtx));
	}

	override: // usage of this handy D feature is highly recommended
		string getSomeInfo()
		{
			return "Some Info!";
		}
}

@path("web")
class Test2 : WebController, Test1API
{
	this(TestContext testCtx)
	{
		registerMiddleware(new LogIpMiddleware(testCtx));
		registerMiddleware(new IpBanMiddleware(testCtx));
		registerMiddleware(new FooMiddleware(testCtx));
	}

	string getSomeInfo()
	{
		return "Some Info!";
	}
}


void runTests(string url, TestContext ctx)
{
	import std.exception;

	// Test1
	{
		ctx.runList = [];
		auto api = new RestInterfaceClient!Test1API(url);

		assertThrown!RestException(api.getSomeInfo());
		assert(ctx.runList == [LogIpMiddleware.stringof, IpBanMiddleware.stringof]);
	}
	// Test2
	{
		ctx.runList = [];
		auto api = new RestInterfaceClient!Test1API(url ~ "/web");

		assertThrown!RestException(api.getSomeInfo());
		assert(ctx.runList == [LogIpMiddleware.stringof, IpBanMiddleware.stringof]);
	}
}

shared static this()
{
	// Registering our REST services in router
	auto router = new URLRouter;
	auto testCtx = new TestContext();

	router.registerRestInterface(new Test1(testCtx));
	router.registerWebInterface(new Test2(testCtx));

	auto settings = new HTTPServerSettings();
	settings.port = 0;
	settings.bindAddresses = ["127.0.0.1"];
	immutable serverAddr = listenHTTP(settings, router).bindAddresses[0];

	runTask({
		try {
			runTests("http://" ~ serverAddr.toString, testCtx);
			logInfo("Success.");
		} catch (Exception e) {
			import core.stdc.stdlib : exit;
			import std.encoding : sanitize;
			logError("Fail: %s", e.toString().sanitize);
			exit(1);
		} finally {
			exitEventLoop(true);
		}
	});
}
