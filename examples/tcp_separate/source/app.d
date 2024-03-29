module app;

import vibe.core.core;
import vibe.core.log : logError, logInfo;
import vibe.core.net : TCPConnection, listenTCP;
import vibe.stream.operations : readLine;

import core.time;

int main(string[] args)
{
	// shows how to handle reading and writing of the TCP connection
	// in separate tasks
	auto listener = listenTCP(7000, (conn) {
		auto wtask = runTask!TCPConnection((conn) {
			try {
				while (conn.connected) {
					conn.write("Hello, World!\r\n");
					sleep(2.seconds());
				}
			} catch (Exception e) {
				logError("Failed to write to client: %s", e.msg);
				conn.close();
			}
		}, conn);

		try {
			while (!conn.empty) {
				auto ln = cast(const(char)[])conn.readLine();
				if (ln == "quit") {
					logInfo("Client wants to quit.");
					break;
				} else logInfo("Got line: %s", ln);
			}
		} catch (Exception e) {
			logError("Failed to read from client: %s", e.msg);
		}

		conn.close();
	});

	return runApplication(&args);
}
