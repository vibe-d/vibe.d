import core.time;
import std.functional;
import vibe.core.core;
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
	sleep(1.seconds()); // give subscribe a chance to do it's job
	publisher.publish("test1", "Hello World!");
	publisher.publish("test2", "Hello from Channel 2");

	auto task = subscriber.listen(toDelegate(&printReply));

	runTask({
		subscriber.subscribe("test-fiber");
		publisher.publish("test-fiber", "Hello from the Fiber!");
		subscriber.unsubscribe();
	});
}
