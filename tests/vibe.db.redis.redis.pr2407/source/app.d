import vibe.db.redis.redis;
import vibe.core.core;
import vibe.core.log;
import vibe.core.concurrency;

void main()
{
	auto task = runTask(&listenRedis);
	runTask(&redisServerMock, task);
	runApplication();
}

void redisServerMock(Task task)
nothrow {
	try {
		auto listener = listenTCP(0, (conn) {
			scope(failure) assert(0); // for @nothrow

			// accept subscription
			conn.write("*3\r\n$9\r\nsubscribe\r\n$4\r\ntest\r\n:1\r\n");
			// send a pubsub message
			conn.write("*3\r\n$7\r\nmessage\r\n$4\r\ntest\r\n$5\r\nhello\r\n");
			// server terminates unexpectedly
			conn.close();
		}, "127.0.0.1");

		task.send(listener.bindAddress.port);
	} catch (Exception e) assert(false, e.msg);
}

void listenRedis()
nothrow {
	try {
		auto redisPort = receiveOnly!ushort();

		auto redis = connectRedis("127.0.0.1", redisPort);
		auto subs = redis.createSubscriber();
		subs.subscribe("test");

		logInfo("subscribed");

		auto task = subs.listen((string channel, string message) {
			logInfo("received message on %s: %s", channel, message);
		});
		task.join();
	} catch (Exception e) assert(false, e.msg);

	logInfo("done listening");
	exitEventLoop();
}
