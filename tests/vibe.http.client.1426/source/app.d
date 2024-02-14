import vibe.core.core;
import vibe.core.net;
import vibe.http.client;
import vibe.stream.operations;

/// Workaround segv caused by parallel GC
extern(C) __gshared string[] rt_options = [ "gcopt=parallel:0" ];

int main ()
{
	immutable serverAddr = listenTCP(0, (TCPConnection c) @safe nothrow {
		try {
			// skip request
			c.readUntil(cast(immutable(ubyte)[])"\r\n\r\n");
			c.write("HTTP/1.1 200 OK\r\nConnection: Close\r\n\r\nqwerty");
		} catch (Exception e) assert(0, e.msg);
	}, "127.0.0.1").bindAddress;

	runTask({
		try requestHTTP("http://" ~ serverAddr.toString,
			(scope req) {},
			(scope res) {
				assert(res.bodyReader.readAllUTF8() == "qwerty");
			}
		);
		catch (Exception e) assert(false, e.msg);
		exitEventLoop();
	});
    return runEventLoop();
}
