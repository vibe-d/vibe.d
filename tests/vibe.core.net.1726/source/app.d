import vibe.core.core;
import vibe.core.net;
import core.time : msecs;
import vibe.core.log;

ubyte[] buf;

void performTest(bool reverse)
{
	auto l = listenTCP(0, (conn) {
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
			sleep(reverse ? 100.msecs : 20.msecs); // give the connection time to establish
			try {
				conn.write(buf);
				assert(false, "Expected write() to throw an exception.");
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
		logInfo("Test has finished successfully.");
		exitEventLoop();
	}, "127.0.0.1");

	runTask({
		try {
			auto conn = connectTCP(l.bindAddress);
			sleep(reverse ? 20.msecs : 100.msecs);
			conn.close();
		} catch (Exception e) assert(false, e.msg);
	});

	runEventLoop();

	l.stopListening();
}

void main()
{
	setTimer(10000.msecs, { assert(false, "Test has hung."); });
	buf = new ubyte[512*1024*1024];

	performTest(false);
	performTest(true);
}
