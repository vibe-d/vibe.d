import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import vibe.core.concurrency;
import core.time;


shared static this()
{
	auto t1 = runTask({
		while (true) {
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
				});
		}
	});

	auto t2 = runTask({
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
	});
}
