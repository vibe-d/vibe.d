import vibe.d;

shared static this()
{
	runTask({
		auto udp_listener = listenUdp(1234);
		while(true){
			auto pack = udp_listener.recv();
			logInfo("Got packet: %s", cast(string)pack);
		}
	});
	
	runTask({
		auto udp_sender = listenUdp(0);
		udp_sender.connect("127.0.0.1", 1234);
		while(true){
			sleep(dur!"msecs"(500));
			logInfo("Sending packet...");
			udp_sender.send(cast(ubyte[])"Hello, World!");
		}
	});
}
