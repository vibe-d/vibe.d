import vibe.core.core;
import vibe.core.net;
import core.time : msecs;

shared static this()
{
	listenTCP(11375,(conn){
		auto td = runTask({
			ubyte [3] buf;
			try {
				conn.read(buf);
				assert(false, "Expected read() to throw an exception.");
			} catch (Exception) {} // expected
		});
		conn.close();
	});

	runTask({
		auto conn = connectTCP("127.0.0.1", 11375);
		conn.write("a");
		conn.close();

		conn = connectTCP("127.0.0.1", 11375);
		conn.close();

		sleep(50.msecs);
		exitEventLoop();
	});
}
