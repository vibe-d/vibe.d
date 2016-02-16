import vibe.core.core;
import vibe.core.log : logInfo;
import vibe.core.net;
import core.time : msecs;
import std.datetime : Clock, UTC;

shared static this()
{
	auto udp = listenUDP(11429, "127.0.0.1");

	runTask({
		sleep(500.msecs);
		assert(false, "Receive call did not return in a timely manner. Killing process.");
	});

	runTask({
		auto start = Clock.currTime(UTC());
		try {
			udp.recv(100.msecs);
			assert(false, "Timeout did not occur.");
		} catch (Exception e) {
			auto duration = Clock.currTime(UTC()) - start;
			assert(duration >= 99.msecs, "Timeout occurred too early");
			assert(duration >= 99.msecs && duration < 150.msecs, "Timeout occurred too late.");
			logInfo("UDP receive timeout test was successful.");
			exitEventLoop();
		}
	});
}
