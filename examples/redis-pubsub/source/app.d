import vibe.core.log;
import vibe.db.redis.redis;

void main()
{
	auto publisher = new RedisClient();
	auto subscriber = new RedisClient();

	subscriber.subscribe("test1", "test2");
	publisher.publish("test1", "Hello World!");
	publisher.publish("test2", "Hello from Channel 2");

	while(1) {
		auto reply = subscriber.listen;
		while(reply.hasNext) {
			if(reply.next!string == "message") {
				auto channel = subscriber.listen.next!string;
				auto message = subscriber.listen.next!string;
				logInfo("%s: %s", channel, message);
			}
		}
	}
}
