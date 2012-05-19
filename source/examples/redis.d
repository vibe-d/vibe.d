import vibe.d;

import vibe.db.redis.redis;


static this()
{
	runTask({
		auto redis = new RedisClient();
		redis.connect();
		redis.setBit("test", 15, true);
		logInfo("Result: %s", redis.getBit("test", 15));
	});
}