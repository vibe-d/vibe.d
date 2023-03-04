module app;

import vibe.core.core;
import vibe.core.log;
import vibe.db.redis.redis;

import std.functional;

import core.time;

void printReply(string channel, string message) @safe nothrow
{
	logInfo("Received a message from channel %s: %s", channel, message);
}

RedisSubscriber subscriber;

int main(string[] args)
{
	auto publisher = new RedisClient();
	subscriber = publisher.createSubscriber();

	subscriber.subscribe("test1", "test2");
	auto task = subscriber.listen(toDelegate(&printReply));
	publisher.getDatabase(0).publish("test1", "Hello World!");
	publisher.getDatabase(0).publish("test2", "Hello from Channel 2");

	auto taskHandler = runTask({
		try {
			subscriber.subscribe("test-fiber");
			publisher.getDatabase(0).publish("test-fiber", "Hello from the Fiber!");
			subscriber.unsubscribe();
		} catch (Exception e) assert(false, e.msg);
	});

	return runApplication(&args);
}
