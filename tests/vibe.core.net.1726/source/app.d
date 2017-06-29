import vibe.core.core;
import vibe.core.net;
import core.time : msecs;
import vibe.core.log;

shared static this()
{
	bool done = false;
	auto buf = new ubyte[512*1024*1024];

	listenTCP(11375,(conn) {
		bool read_ex = false;
		bool write_ex = false;
		auto rt = runTask!TCPConnection((conn) {
			try {
				conn.read(buf);
				assert(false, "Expected read() to throw an exception.");
			} catch (Exception) {
				read_ex = true;
				conn.close();
				logInfo("read out");
			} // expected
		}, conn);
		auto wt = runTask!TCPConnection((conn) {
			sleep(1.msecs); // give the connection time to establish
			try {
				conn.write(buf);
				assert(false, "Expected read() to throw an exception.");
			} catch (Exception) {
				write_ex = true;
				conn.close();
				logInfo("write out");
			} // expected
		}, conn);

		rt.join();
		wt.join();
		assert(read_ex, "No read exception thrown");
		assert(write_ex, "No write exception thrown");
		exitEventLoop();
	}, "127.0.0.1");

	runTask({
		try {
			auto conn = connectTCP("127.0.0.1", 11375);
			sleep(10.msecs);
			conn.close();
		} catch (Exception e) assert(false, e.msg);
	});

	setTimer(2000.msecs, {
		assert(false, "Test has hung.");
	});
}
