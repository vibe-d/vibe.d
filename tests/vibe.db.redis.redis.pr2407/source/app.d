import vibe.db.redis.redis;
import vibe.core.core;
import vibe.core.log;

enum redisPort = 16379;

void main()
{
	runTask(&redisServerMock);
	runTask(&listenRedis);
	runApplication();
}

void redisServerMock()
{
	listenTCP(redisPort, (conn) {
		conn.write("*3\r\n$9\r\nsubscribe\r\n$4\r\ntest\r\n:1\r\n");
		conn.write("*3\r\n$7\r\nmessage\r\n$4\r\ntest\r\n$5\r\nhello\r\n");

		// server terminates unexpectedly
		conn.close();
	});
}

void listenRedis()
{
	auto redis = connectRedis("127.0.0.1", redisPort);
	auto subs = redis.createSubscriber();
	subs.subscribe("test");

	logInfo("subscribed");

	auto task = subs.listen((string channel, string message) {
		logInfo("received message on %s: %s", channel, message);
	});
	task.join();

	logInfo("done listening");
	exitEventLoop();
}
