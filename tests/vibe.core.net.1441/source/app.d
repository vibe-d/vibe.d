import vibe.core.core;
import vibe.core.net;
import core.time : msecs;

shared static this()
{
	import vibe.core.log;
	bool done = false;
	listenTCP(11375,(conn){
		conn.write("foo");
		conn.close();
		done = true;
	});

	runTask({
		auto conn = connectTCP("127.0.0.1", 11375);
		conn.close();

		sleep(50.msecs);
		assert(done);

		exitEventLoop();
	});
}
