import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import std.concurrency;
import core.atomic;
import core.time;
import core.stdc.stdlib : exit;

__gshared Tid t1, t2;
shared watchdog_count = 0;

shared static this()
{
	t1 = spawn({
		// ensure that asynchronous operations run in parallel to receive()
		int wc = 0;
		runTask({ while (true) { sleep(250.msecs); wc++; logInfo("Watchdog receiver %s", wc); } });

		bool finished = false;
		try while (!finished) {
			logDebug("receive1");
			receive(
				(string msg) {
					logInfo("Received string message: %s", msg);
				},
				(int msg) {
					logInfo("Received int message: %s", msg);
				});
			logDebug("receive2");
			receive(
				(double msg) {
					logInfo("Received double: %s", msg);
				},
				(int a, int b, int c) {
					logInfo("Received iii: %s %s %s", a, b, c);

					if (a == 1 && b == 2 && c == 3)
						finished = true;
				});
		}
		catch (Exception e) assert(false, "Receiver thread failed: "~e.msg);

		logInfo("Receive loop finished.");
		if (wc < 6*4-1) {
			logError("Receiver watchdog failure.");
			exit(1);
		}
		logInfo("Exiting normally");
	});

	t2 = spawn({
		scope (failure) assert(false);
		sleep(1.seconds());
		logInfo("send Hello World");
		t1.send("Hello, World!");

		sleep(1.seconds());
		logInfo("send int 1");
		t1.send(1);

		sleep(1.seconds());
		logInfo("send double 1.2");
		t1.send(1.2);

		sleep(1.seconds());
		logInfo("send int 2");
		t1.send(2);

		sleep(1.seconds());
		logInfo("send 3xint 1 2 3");
		t1.send(1, 2, 3);

		sleep(1.seconds());
		logInfo("send string Bye bye");
		t1.send("Bye bye");

		sleep(100.msecs);
		logInfo("Exiting.");
		exitEventLoop(true);
	});
}
