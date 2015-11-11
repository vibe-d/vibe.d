import vibe.core.core;
import vibe.core.log;
import vibe.core.net;
import vibe.stream.operations;
import core.time;
import std.datetime : StopWatch;

enum port = 12675;

enum Test {
  receive,
  receiveExisting,
  timeout,
  noTimeout,
  noTimeoutCompat,
  close
}

void test()
{
	scope (failure) assert(false);

	Test test;

	listenTCP(port, (conn) {
		while (conn.connected) {
			assert(conn.readLine() == "next");
			auto curtest = test;
			conn.write("continue\r\n");
			logInfo("Perform test %s", curtest);
			StopWatch sw;
			sw.start();
			final switch (curtest) {
				case Test.receive:
					assert(conn.waitForData(2.seconds) == true);
					assert(cast(Duration)sw.peek < 2.seconds); // should receive something instantly
					assert(conn.readLine() == "receive");
					break;
				case Test.receiveExisting:
					assert(conn.waitForData(2.seconds) == true);
					// TODO: validate that waitForData didn't yield!
					assert(cast(Duration)sw.peek < 2.seconds); // should receive something instantly
					assert(conn.readLine() == "receiveExisting");
					break;
				case Test.timeout:
					assert(conn.waitForData(2.seconds) == false);
					assert(cast(Duration)sw.peek > 1900.msecs); // should wait for at least 2 seconds
					assert(conn.connected);
					break;
				case Test.noTimeout:
					assert(conn.waitForData(Duration.max) == true);
					assert(cast(Duration)sw.peek > 2.seconds); // data only sent after 3 seconds
					assert(conn.readLine() == "noTimeout");
					break;
				case Test.noTimeoutCompat:
					assert(conn.waitForData(0.seconds) == true);
					assert(cast(Duration)sw.peek > 2.seconds); // data only sent after 3 seconds
					assert(conn.readLine() == "noTimeoutCompat");
					break;
				case Test.close:
					assert(conn.waitForData(2.seconds) == false);
					assert(cast(Duration)sw.peek < 2.seconds); // connection should be closed instantly
					assert(!conn.connected);
					return;
			}
			conn.write("ok\r\n");
		}
	}, "127.0.0.1");

	auto conn = connectTCP("127.0.0.1", port);

	test = Test.receive;
	conn.write("next\r\n");
	assert(conn.readLine() == "continue");
	conn.write("receive\r\n");
	assert(conn.readLine() == "ok");

	test = Test.receiveExisting;
	conn.write("next\r\nreceiveExisting\r\n");
	assert(conn.readLine() == "continue");
	assert(conn.readLine() == "ok");

	test = Test.timeout;
	conn.write("next\r\n");
	assert(conn.readLine() == "continue");
	sleep(3.seconds);
	assert(conn.readLine() == "ok");

	test = Test.noTimeout;
	conn.write("next\r\n");
	assert(conn.readLine() == "continue");
	sleep(3.seconds);
	conn.write("noTimeout\r\n");
	assert(conn.readLine() == "ok");

	test = Test.noTimeoutCompat;
	conn.write("next\r\n");
	assert(conn.readLine() == "continue");
	sleep(3.seconds);
	conn.write("noTimeoutCompat\r\n");
	assert(conn.readLine() == "ok");

	test = Test.close;
	conn.write("next\r\n");
	assert(conn.readLine() == "continue");
	conn.close();

	exitEventLoop();
}

void main()
{
	import std.functional : toDelegate;
	runTask(toDelegate(&test));
	runEventLoop();
}
