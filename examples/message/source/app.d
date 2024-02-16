module app;

import vibe.core.core;
import vibe.core.log;
import vibe.core.concurrency;
import core.time;

int main(string[] args)
{
	auto t1 = runTask({
		while (true) {
			logDebug("receive1");
			try receive(
				(string msg) {
					logInfo("Received string message: %s", msg);
				},
				(int msg) {
					logInfo("Received int message: %s", msg);
				});
			catch (Exception e) assert(false, e.msg);
			logDebug("receive2");
			try receive(
				(double msg) {
					logInfo("Received double: %s", msg);
				},
				(int a, int b, int c) {
					logInfo("Received iii: %s %s %s", a, b, c);
				});
			catch (Exception e) assert(false, e.msg);
		}
	});

	auto t2 = runTask(() nothrow {
		sleepUninterruptible(1.seconds());
		logInfo("send Hello World");
		try t1.send("Hello, World!");
		catch (Exception e) assert(false, e.msg);

		sleepUninterruptible(1.seconds());
		logInfo("send int 1");
		try t1.send(1);
		catch (Exception e) assert(false, e.msg);

		sleepUninterruptible(1.seconds());
		logInfo("send double 1.2");
		try t1.send(1.2);
		catch (Exception e) assert(false, e.msg);

		sleepUninterruptible(1.seconds());
		logInfo("send int 2");
		try t1.send(2);
		catch (Exception e) assert(false, e.msg);

		sleepUninterruptible(1.seconds());
		logInfo("send 3xint 1 2 3");
		try t1.send(1, 2, 3);
		catch (Exception e) assert(false, e.msg);

		sleepUninterruptible(1.seconds());
		logInfo("send string Bye bye");
		try t1.send("Bye bye");
		catch (Exception e) assert(false, e.msg);
	});

	return runApplication(&args);
}
