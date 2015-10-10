import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import vibe.core.net;

import core.time;


shared static this()
{
	runTask({
		auto udp_listener = listenUDP(1234);
		while (true) {
			auto pack = udp_listener.recv();
			logInfo("Got packet: %s", cast(string)pack);
		}
	});

	runTask({
		auto udp_sender = listenUDP(0);
		udp_sender.connect("127.0.0.1", 1234);
		while (true) {
			sleep(dur!"msecs"(500));
			logInfo("Sending packet...");
			udp_sender.send(cast(ubyte[])"Hello, World!");
		}
	});
}
