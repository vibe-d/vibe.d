import vibe.core.log;
import vibe.db.redis.redis;

void main()
{
	auto redis = new RedisClient();
	redis.setBit("test", 15, true);
	logInfo("Result: %s", redis.getBit("test", 15));
}