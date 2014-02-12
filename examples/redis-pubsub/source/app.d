import vibe.core.log;
import vibe.db.redis.redis;

void printReply(string channel, string message)
{
	logInfo("Received a message from channel %s: %s", channel, message);
}

void main()
{
	auto publisher = new RedisClient();
	auto subscriber = new RedisClient();

	subscriber.subscribe("test1", "test2");
	publisher.publish("test1", "Hello World!");
	publisher.publish("test2", "Hello from Channel 2");

	subscriber.listen(&printReply);
}
