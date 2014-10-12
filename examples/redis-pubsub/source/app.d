import core.time;
import std.functional;
import vibe.core.core;
import vibe.core.log;
import vibe.db.redis.redis;

void printReply(string channel, string message)
{
	logInfo("Received a message from channel %s: %s", channel, message);
}

RedisSubscriber subscriber;

shared static this()
{
	auto publisher = new RedisClient();
	subscriber = publisher.createSubscriber();

	subscriber.subscribe("test1", "test2");
	auto task = subscriber.listen(toDelegate(&printReply));
	publisher.getDatabase(0).publish("test1", "Hello World!");
	publisher.getDatabase(0).publish("test2", "Hello from Channel 2");


	runTask({
		subscriber.subscribe("test-fiber");
		publisher.getDatabase(0).publish("test-fiber", "Hello from the Fiber!");
		subscriber.unsubscribe();
	});
}
