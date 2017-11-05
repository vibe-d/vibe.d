/// Requires redis service running on localhost with default port

module app;

import vibe.core.core;
import vibe.core.log;
import vibe.db.redis.redis;
import core.time;
import std.algorithm : sort, equal;
import std.exception : assertThrown;

void runTest()
{
	//setLogLevel(LogLevel.trace);
	/* open a redis server locally to run these tests
	 * Windows download link: https://github.com/MSOpenTech/redis/releases
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
		db.deleteAll();

		assert(db.setNX("setNXTest","foo", 30.seconds));
		assert(!db.setNX("setNXTest","foo", 30.seconds));
		assert(db.setNX("setNXTest2","foo"));
		assert(!db.setNX("setNXTest2","foo"));
		assert(db.setXX("setNXTest2","foo"));
		assert(!db.setXX("setXXTestNegative","foo"));

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
		assert(db.get("test1") == "test1");
		assert(db.get("test2") == "test2");
		assert(db.get("test3") == "test3");
		assert(db.get("test4") == "test4");
		assert(db.get("test5") == "test5");
		assert(db.get("test6") == "test6");
		assert(db.get("test7") == "test7");
		assert(db.get("test8") == "test8");
		assert(db.get("test9") == "test9");
		assert(db.get("test10") == "0");

		db.del("saddTests");
		db.sadd("saddTests", "item1");
		db.sadd("saddTests", "item2");
		assert(sort(db.smembers("saddTests").array).equal(["item1", "item2"]));

		db.zadd("zaddTests", 0.5, "a", 1.0, "b", 2.0, "c", 1.5, "d");
		assert(db.zrangeByScore("zaddTests", 0.5, 1.5).equal(["a", "b", "d"]));
		assert(db.zrangeByScore!(string, "()")("zaddTests", 0.5, 1.5).equal(["b"]));
		assert(db.zrangeByScore!(string, "[)")("zaddTests", 0.5, 1.5).equal(["a", "b"]));
		assert(db.zrangeByScore!(string, "(]")("zaddTests", 0.5, 1.5).equal(["b", "d"]));

		db.append("test1", "test1append");
		db.append("test2", "test2append");
		assert(db.get!string("test1") == "test1test1append");
		assert(db.get!string("test2") == "test2test2append");

		db.incr("test10");
		assert(db.get!long("test10") == 1);

		db.del("test1", "test2","test3","test4","test5","test6","test7","test8","test9","test10");
		db.del("saddTests", "zaddTests");

		db.srem("test1", "test1append");
		db.srem("test2", "test2append");

		assert(db.smembers("test1").empty);
		assert(db.smembers("test2").empty);
		assert(!db.smembers("test1").hasNext());

		// test blpop
		assert(db.blpop("nonexistent", 1).isNull());
		db.lpush("test_list", "foo");
		assert(db.blpop("test_list", 1).get() == tuple("test_list", "foo"));
		db.del("test_list");
	}

	testLocking(redis.getDatabase(0));

	RedisSubscriber sub;
	{
		RedisSubscriber scoped = redis.createSubscriber();
		sub = scoped;
		sleep(50.msecs);
	}
	import std.datetime;

	assert(!sub.isListening);
	sub.listen((string channel, string msg){
		logInfo("LISTEN Recv Channel: %s, Message: %s", channel, msg);
		logInfo("LISTEN Recv Time: %s", Clock.currTime());
	});
	assert(sub.isListening);
	sub.subscribe("SomeChannel");
	sub.subscribe("SomeChannel");
	sub.subscribe("SomeChannel");
	sleep(100.msecs);

	redis.getDatabase(0).publish("SomeChannel", "Messageeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");

	logInfo("PUBLISH Sent: %s", Clock.currTime());
	sleep(100.msecs);

	sub.unsubscribe("SomeChannel");
	sub.unsubscribe("SomeChannel");
	sub.unsubscribe("SomeChannel");
	sub.bstop();
	logInfo("LISTEN Stopped");
	assert(!sub.isListening);
	redis.getDatabase(0).publish("SomeChannel", "Messageeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee");

	assertThrown(redis.getDatabase(0).eval("foo!!!", null));
	assert(redis.getDatabase(0).get("test1") == "");

	logInfo("Redis Test Succeeded.");
}

void testLocking(RedisDatabase _db)
{
	logInfo("run lock test...");

	import vibe.db.redis.idioms;

	auto lock = RedisLock(_db,"lock_key");

	auto testMethod = {
		foreach(i; 0..100)
		{
			lock.performLocked({
				assert(_db.setNX("lockedWriteTest","foo"));
				assert(1 == _db.del("lockedWriteTest"));
			});
		}
	};

	auto t1 = runTask(testMethod);
	auto t2 = runTask(testMethod);

	t1.join();
	t2.join();

	logInfo("lock test finished");
}

int main()
{
	int ret = 0;
	runTask({
		try runTest();
		catch (Throwable th) {
			logError("Test failed: %s", th.msg);
			logDiagnostic("Full error: %s", th);
			ret = 1;
		} finally exitEventLoop(true);
	});
	runEventLoop();
	return ret;
}
