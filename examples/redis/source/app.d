import vibe.core.log;
import vibe.db.redis.redis;

void main()
{
	auto redis = new RedisClient();
	redis.getDatabase(0).setBit("test", 15, true);
	logInfo("Result: %s", redis.getDatabase(0).getBit("test", 15));
}
