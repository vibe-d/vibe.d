module vibe.core.events.test;
import vibe.core.events.events;


void main() {

	import std.stdio;
	import etc.linux.memoryerror;
	static if (is(typeof(registerMemoryErrorHandler)))
		registerMemoryErrorHandler();
	TCPEventHandler evh;
	evh.fct = (AsyncTCPConnection conn, TCPEvent ev){
		final switch (ev) {
			case TCPEvent.CONNECT:
				writeln("!!Connected");
				conn.send(cast(ubyte[])"GET http://whereamirightnow.com/\nHost: whereamirightnow.com");
				break;
			case TCPEvent.READ:
				static ubyte[] bin = new ubyte[4092];
				while (true) {
					uint len = conn.recv(bin);
					writeln("!!Received " ~ len.to!string ~ " bytes");
					import std.file;
					File file = File("index.html", "a");
					if (len > 0)
						file.write(cast(string)bin[0..len]);
					if (len < 128)
						break;
				}

				break;
			case TCPEvent.WRITE:
				writeln("!!Write is ready");
				break;
			case TCPEvent.CLOSE:
				writeln("!!Disconnected");
				break;
			case TCPEvent.ERROR:
				writeln("!!Error!");
				break;
		}
		return;
	};
	import vibe.utils.memory;
	EventLoop evl = FreeListObjectAlloc!EventLoop.alloc();
	AsyncTCPConnection conn = FreeListObjectAlloc!AsyncTCPConnection.alloc(evl);

	evh.conn = conn;
	conn.peer = evl.resolveHost("whereamirightnow.com", 80);

	conn.run(evh);

	while(evl.loop()) continue;

	//writeln(evl.error);
}