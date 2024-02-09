module tests;

import vibe.core.core;
import vibe.d;

import core.stdc.stdlib;

import std.stdio;

struct TestStruct {int i;}

interface IService
{
@safe:
	@safe TestStruct getTest(int sleepsecs);
	@safe TestStruct getTest2(int sleepsecs);
}

class Service : IService
{
	@safe TestStruct getTestImpl(int sleep_msecs)
	{
		sleep(sleep_msecs.msecs);
		TestStruct test_struct = {sleep_msecs};
		return test_struct;
	}

	@safe TestStruct getTest(int sleep_msecs)
	{
		return getTestImpl(sleep_msecs);
	}

	@safe TestStruct getTest2(int sleep_msecs)
	{
		return getTestImpl(sleep_msecs);
	}
}

void main()
{
	setLogLevel(LogLevel.trace);
	auto settings_server = new HTTPServerSettings;
	settings_server.port = 5000;
	settings_server.bindAddresses = ["127.0.0.1"];
	auto router = new URLRouter;
	router.registerRestInterface(new Service);
	auto server_addr = listenHTTP(settings_server, router);

	runTask({
		scope (exit) exitEventLoop(true);
		try {
			auto settings = new RestInterfaceSettings();
			settings.httpClientSettings = new HTTPClientSettings();
			settings.httpClientSettings.readTimeout = 1.seconds;
			settings.baseURL = URL("http://127.0.0.1:5000/");
			auto service_client = new RestInterfaceClient!IService(settings);
			try {service_client.getTest(2000);} catch (Exception e) {}
			sleep(1200.msecs);
			auto result = service_client.getTest2(500);
			writeln("result:", result);
			assert(result.i == 500);
		} catch (Exception e) assert(false, e.msg);
	});

	runApplication();
	return;
}
