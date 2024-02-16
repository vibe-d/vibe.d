import vibe.appmain;
import vibe.core.core;
import vibe.core.log;
import vibe.core.net;

import core.time;

int main(string[] args)
{
	auto t1Hansler = runTask(() nothrow {
		try {
			auto udp_listener = listenUDP(1234);
			while (true) {
				auto pack = udp_listener.recv();
				logInfo("Got packet: %s", cast(string)pack);
			}
		} catch (Exception e) assert(false, e.msg);
	});

	auto t2Handler = runTask(() nothrow {
		try {
			auto udp_sender = listenUDP(0);
			udp_sender.connect("127.0.0.1", 1234);
			while (true) {
				sleep(dur!"msecs"(500));
				logInfo("Sending packet...");
				udp_sender.send(cast(ubyte[])"Hello, World!");
			}
		} catch (Exception e) assert(false, e.msg);
	});

	return runApplication(&args);
}
