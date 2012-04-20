module examples.redis;

import vibe.d;
import vibe.log;
import vibe.db.redis.redis;


static this() {
	setLogLevel(LogLevel.Info);

	runTask({
		auto redis = new RedisClient();
		redis.connect();
		redis.setBit("test", 15, true);
		logInfo("Result: %s", redis.getBit("test", 15));
	});
}