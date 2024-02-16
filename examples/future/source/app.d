module app;

import vibe.core.core;
import vibe.core.core;
import vibe.core.log;
import vibe.core.concurrency;
import core.time;

int main(string[] args)
{
	auto taskHandler = runTask({
		auto val = async({
			logInfo("Starting to compute value.");
			sleepUninterruptible(500.msecs); // simulate some lengthy computation
			logInfo("Finished computing value.");
			return 32;
		});

		logInfo("Starting computation in main task");
		sleepUninterruptible(200.msecs); // simulate some lengthy computation
		logInfo("Finished computation in main task. Waiting for async value.");
		logInfo("Result: %s", val.getResult());
		exitEventLoop();
	});

	return runApplication(&args);
}
