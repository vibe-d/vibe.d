/// Requires mongo service running on localhost with default port
/// Uses test database

module app;

import vibe.vibe;

void runTest()
{
	import std.stdio;
	/* open a redis server locally to run these tests
	 * Windows download link: https://raw.github.com/MSOpenTech/redis/2.8.4_msopen/bin/release/redis-2.8.4.zip
	 * Linux: use "yum install redis" on RHEL or "apt-get install redis" on Debian-like
*/
	RedisClient m_RedisDB = new RedisClient();
	m_RedisDB.setEX("test1", 1000, "test1");
	m_RedisDB.setEX("test2", 1000, "test2");
	m_RedisDB.setEX("test3", 1000, "test3");
	m_RedisDB.setEX("test4", 1000, "test4");
	m_RedisDB.setEX("test5", 1000, "test5");
	m_RedisDB.setEX("test6", 1000, "test6");
	m_RedisDB.setEX("test7", 1000, "test7");
	m_RedisDB.setEX("test8", 1000, "test8");
	m_RedisDB.setEX("test9", 1000, "test9");
	m_RedisDB.setEX("test10", 1000, "0");
	m_RedisDB.del("saddTests");
	m_RedisDB.sadd("saddTests", "item1");
	m_RedisDB.sadd("saddTests", "item2");
	
	
	assert(m_RedisDB.get!string("test1") == "test1");
	m_RedisDB.get!string("test2");
	m_RedisDB.get!string("test3");
	m_RedisDB.get!string("test4");
	m_RedisDB.get!string("test5");
	m_RedisDB.get!string("test6");
	m_RedisDB.get!string("test7");
	m_RedisDB.get!string("test8");
	m_RedisDB.get!string("test9");
	m_RedisDB.get!string("test10");
	m_RedisDB.append("test1", "test1append");
	m_RedisDB.append("test2", "test2append");
	m_RedisDB.get!string("test1");
	m_RedisDB.get!string("test2");
	m_RedisDB.incr("test10");
	
	m_RedisDB.del("test1", "test2","test3","test4","test5","test6","test7","test8","test9","test10");
	
	m_RedisDB.srem("test1", "test1append");
	m_RedisDB.srem("test2", "test2append");
	m_RedisDB.smembers("test1");
	m_RedisDB.smembers("test2");
	writeln("Redis Test Succeeded.");

	exitEventLoop(true);
}

int main()
{
	setLogLevel(LogLevel.info);
	runTask(toDelegate(&runTest));
	return runEventLoop();
}
