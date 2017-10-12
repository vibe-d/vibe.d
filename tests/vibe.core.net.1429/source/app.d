import vibe.core.core;
import vibe.core.log : logInfo;
import vibe.core.net;
import core.time : msecs;
import std.datetime : Clock, UTC;

shared static this()
{
	runTask({
		sleep(500.msecs);
		assert(false, "Receive call did not return in a timely manner. Killing process.");
	});

	runTask({
		auto udp = listenUDP(11429, "127.0.0.1");
		auto start = Clock.currTime(UTC());
		try {
			udp.recv(100.msecs);
			assert(false, "Timeout did not occur.");
		} catch (Exception e) {
			logInfo("Exception received: %s", e.msg);
			auto duration = Clock.currTime(UTC()) - start;
			assert(duration >= 99.msecs, "Timeout occurred too early ("~duration.toString~").");
			assert(duration >= 99.msecs && duration < 150.msecs, "Timeout occurred too late ("~duration.toString~").");
			logInfo("UDP receive timeout test was successful.");
			exitEventLoop();
		}
	});
}
