import vibe.core.concurrency;
import vibe.core.core;
import vibe.core.log;
import core.time : msecs;
import std.functional : toDelegate;

void test()
{
	auto t = runTask({
		bool gotit;
		receive((int i) { assert(i == 10); gotit = true; });
		assert(gotit);
		sleep(10.msecs);
	});

	t.tid.send(10);
	t.tid.send(11); // never received
	t.join();

	// ensure that recycled fibers will get a clean message queue
	auto t2 = runTask({
		bool gotit;
		receive((int i) { assert(i == 12); gotit = true; });
		assert(gotit);
	});
	t2.tid.send(12);
	t2.join();

	// test worker tasks
	auto t3 = runWorkerTaskH({
		bool gotit;
		receive((int i) { assert(i == 13); gotit = true; });
		assert(gotit);
	});

	t3.tid.send(13);
	sleep(10.msecs);

	logInfo("Success.");

	exitEventLoop(true);
}

shared static this()
{
setLogFormat(FileLogger.Format.threadTime, FileLogger.Format.threadTime);
	runTask(toDelegate(&test));
}


