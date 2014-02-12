import std.functional;
import vibe.core.log;
import vibe.db.redis.redis;

void printReply(string channel, string message)
{
	logInfo("Received a message from channel %s: %s", channel, message);
}

shared static this()
{
	auto publisher = new RedisClient();
	auto subscriber = new RedisSubscriber(new RedisClient());

	subscriber.subscribe("test1", "test2");
	publisher.publish("test1", "Hello World!");
	publisher.publish("test2", "Hello from Channel 2");

	auto task = subscriber.listen(toDelegate(&printReply));
}
