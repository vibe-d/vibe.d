/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.vibe;

void runTest()
{
	/* open a redis server locally to run these tests
	 * Windows download link: https://raw.github.com/MSOpenTech/redis/2.8.4_msopen/bin/release/redis-2.8.4.zip
	 * Linux: use "yum install redis" on RHEL or "apt-get install redis" on Debian-like
	*/
	RedisClient redis;
	try redis = new RedisClient();
	catch (Exception) {
		logInfo("Failed to connect to local Redis server. Skipping test.");
		return;
	}
	{
		redis.setEX("test1", 1000, "test1");
		redis.setEX("test2", 1000, "test2");
		redis.setEX("test3", 1000, "test3");
		redis.setEX("test4", 1000, "test4");
		redis.setEX("test5", 1000, "test5");
		redis.setEX("test6", 1000, "test6");
		redis.setEX("test7", 1000, "test7");
		redis.setEX("test8", 1000, "test8");
		redis.setEX("test9", 1000, "test9");
		redis.setEX("test10", 1000, "0");
		redis.del("saddTests");
		redis.sadd("saddTests", "item1");
		redis.sadd("saddTests", "item2");
		
		
		assert(redis.get!string("test1") == "test1");
		redis.get!string("test2");
		redis.get!string("test3");
		redis.get!string("test4");
		redis.get!string("test5");
		redis.get!string("test6");
		redis.get!string("test7");
		redis.get!string("test8");
		redis.get!string("test9");
		redis.get!string("test10");
		redis.append("test1", "test1append");
		redis.append("test2", "test2append");
		redis.get!string("test1");
		redis.get!string("test2");
		redis.incr("test10");
		
		redis.del("test1", "test2","test3","test4","test5","test6","test7","test8","test9","test10");
		
		redis.srem("test1", "test1append");
		redis.srem("test2", "test2append");
		
		redis.smembers("test1");
	
		redis.smembers("test2");
	}
	RedisSubscriber sub = new RedisSubscriber(redis);
	import std.datetime;

	assert(!sub.isListening);
	sub.listen((string channel, string msg){
		logInfo("LISTEN Recv Channel: %s, Message: %s", channel.to!string, msg.to!string);
		logInfo("LISTEN Recv Time: %s", Clock.currTime().toString());
	});

	assert(sub.isListening);
	sub.subscribe("SomeChannel");

	logInfo("PUBLISH Sent: %s", Clock.currTime().toString());
	redis.publish("SomeChannel", "Messageeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
	sub.unsubscribe("SomeChannel");
	auto stopped = sub.bstop();
	logInfo("LISTEN Stopped: %s", stopped.to!string);
	assert(!sub.isListening);
	redis.publish("SomeChannel", "Messageeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
	sleep(1.seconds);
	logInfo("Redis Test Succeeded.");
}

int main()
{
	int ret = 0;
	setLogLevel(LogLevel.info);
	runTask({
		runTest();
		exitEventLoop(true);
	});
	runEventLoop();
	return ret;
}
