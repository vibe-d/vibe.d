import vibe.core.core;
import vibe.core.log;
import vibe.core.net;
import vibe.stream.operations;
import core.time;
import std.datetime : StopWatch;

enum Test {
  receive,
  receiveExisting,
  timeout,
  noTimeout,
  close
}

void test1()
{
	Test test;
	Task lt;

	auto l = listenTCP(0, (conn) {
		lt = Task.getThis();
		try {
			while (!conn.empty) {
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
					case Test.close:
						assert(conn.waitForData(2.seconds) == false);
						assert(cast(Duration)sw.peek < 2.seconds); // connection should be closed instantly
						assert(conn.empty);
						conn.close();
						assert(!conn.connected);
						return;
				}
				conn.write("ok\r\n");
			}
		} catch (Exception e) {
			assert(false, e.msg);
		}
	}, "127.0.0.1");
	scope (exit) l.stopListening;

	auto conn = connectTCP(l.bindAddress);

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

	test = Test.close;
	conn.write("next\r\n");
	assert(conn.readLine() == "continue");
	conn.close();

	lt.join();
}

void test2()
{
	Task lt;
	logInfo("Perform test \"disconnect with pending data\"");
	auto l = listenTCP(0, (conn) {
		try {
			lt = Task.getThis();
			sleep(1.seconds);
			StopWatch sw;
			sw.start();
			try {
				assert(conn.waitForData() == true);
				assert(cast(Duration)sw.peek < 500.msecs); // waitForData should return immediately
				assert(conn.dataAvailableForRead);
				assert(conn.readAll() == "test");
				conn.close();
			} catch (Exception e) {
				assert(false, "Failed to read pending data: " ~ e.msg);
			}
		} catch (Exception e) {
			assert(false, e.msg);
		}
	}, "127.0.0.1");
	scope (exit) l.stopListening;

	auto conn = connectTCP(l.bindAddress);
	conn.write("test");
	conn.close();

	sleep(100.msecs);

	assert(lt != Task.init);
	lt.join();
}

void test()
{
	test1();
	test2();
	exitEventLoop();
}

void main()
{
	import std.functional : toDelegate;
	runTask(toDelegate(&test));
	runEventLoop();
}
