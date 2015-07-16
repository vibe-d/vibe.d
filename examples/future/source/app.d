import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import vibe.core.concurrency;
import core.time;


shared static this()
{
	runTask({
		auto val = async({
			logInfo("Starting to compute value.");
			sleep(500.msecs); // simulate some lengthy computation
			logInfo("Finished computing value.");
			return 32;
		});

		logInfo("Starting computation in main task");
		sleep(200.msecs); // simulate some lengthy computation
		logInfo("Finished computation in main task. Waiting for async value.");
		logInfo("Result: %s", val.getResult());
		exitEventLoop();
	});
}
