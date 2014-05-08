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
		auto db = redis.getDatabase(0);
		db.setEX("test1", 1000, "test1");
		db.setEX("test2", 1000, "test2");
		db.setEX("test3", 1000, "test3");
		db.setEX("test4", 1000, "test4");
		db.setEX("test5", 1000, "test5");
		db.setEX("test6", 1000, "test6");
		db.setEX("test7", 1000, "test7");
		db.setEX("test8", 1000, "test8");
		db.setEX("test9", 1000, "test9");
		db.setEX("test10", 1000, "0");
		db.del("saddTests");
		db.sadd("saddTests", "item1");
		db.sadd("saddTests", "item2");
		
		
		assert(db.get!string("test1") == "test1");
		db.get!string("test2");
		db.get!string("test3");
		db.get!string("test4");
		db.get!string("test5");
		db.get!string("test6");
		db.get!string("test7");
		db.get!string("test8");
		db.get!string("test9");
		db.get!string("test10");
		db.append("test1", "test1append");
		db.append("test2", "test2append");
		db.get!string("test1");
		db.get!string("test2");
		db.incr("test10");
		
		db.del("test1", "test2","test3","test4","test5","test6","test7","test8","test9","test10");
		
		db.srem("test1", "test1append");
		db.srem("test2", "test2append");
		
		db.smembers("test1");
	
		db.smembers("test2");
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
	redis.getDatabase(0).publish("SomeChannel", "Messageeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
	sub.unsubscribe("SomeChannel");
	auto stopped = sub.bstop();
	logInfo("LISTEN Stopped: %s", stopped.to!string);
	assert(!sub.isListening);
	redis.getDatabase(0).publish("SomeChannel", "Messageeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");
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
