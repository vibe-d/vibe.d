import vibe.vibe;

import vibe.db.redis.redis;

void main()
{
	auto redis = new RedisClient();
	redis.connect();
	redis.setBit("test", 15, true);
	logInfo("Result: %s", redis.getBit("test", 15));
}