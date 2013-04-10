import vibe.appmain;
import vibe.core.core : runTask, sleep;
import vibe.core.log : logInfo;
import vibe.core.net : listenTCP;
import vibe.stream.operations : readLine;

import core.time;


shared static this()
{
	// shows how to handle reading and writing of the TCP connection
	// in separate tasks
	listenTCP(7000, (conn){
		// release ownership of the connection, so that other tasks
		// can acquire it
		conn.release();

		bool quit = false;

		auto wtask = runTask({
			// acquire just the write end of the connection
			auto writer = conn.acquireWriter();
			scope(exit) conn.releaseWriter();
			while (!quit && conn.connected) {
				writer.write("Hello, World!\r\n");
				sleep(2.seconds());
			}
		});

		auto rtask = runTask({
			// acquire just the read end of the connection
			auto reader = conn.acquireReader();
			scope(exit) conn.releaseReader();
			while (!quit && conn.connected) {
				auto ln = cast(string)reader.readLine();
				if (ln == "quit") quit = true;
				else logInfo("Got line: %s", ln);
			}
		});

		rtask.join();
		wtask.join();

		// if the connection is still alive, reacquire and close it
		if (conn.connected) {
			conn.acquire();
			conn.close();
		}
	});
}
