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
		bool quit = false;

		auto wtask = runTask({
			while (!quit && conn.connected) {
				conn.write("Hello, World!\r\n");
				sleep(2.seconds());
			}
		});

		auto rtask = runTask({
			while (!quit && conn.connected) {
				auto ln = cast(string)conn.readLine();
				if (ln == "quit") quit = true;
				else logInfo("Got line: %s", ln);
			}
		});

		// wait for the tasks to finish
		rtask.join();
		wtask.join();

		// if the connection is still alive, reacquire and close it
		if (conn.connected)
			conn.close();
	});
}
