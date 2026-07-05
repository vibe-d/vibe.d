import vibe.core.core;
import vibe.core.net;
import vibe.core.log;
import vibe.core.stream : IOMode;
import vibe.db.mongo.connection;
import vibe.db.mongo.settings : MongoHost;
import vibe.data.bson;
import core.time;
import std.conv;

// A TCP proxy that forwards a mongo handshake verbatim, but corrupts the
// responseTo field of the SECOND server->client reply so recvMsg desyncs.
// Pump raw bytes from src to dst until either side closes.
void pumpRaw(TCPConnection src, TCPConnection dst) nothrow
{
	try
	{
		ubyte[4096] buffer;
		while (src.connected && dst.connected)
		{
			auto count = src.read(buffer[], IOMode.once);
			if (count == 0) break;
			dst.write(buffer[0 .. count]);
		}
	}
	catch (Exception) {}
	try dst.close();
	catch (Exception) {}
}

TCPListener startCorruptingProxy(ushort realPort)
{
	return listenTCP(0, (client) {
		try
		{
			auto upstream = connectTCP("127.0.0.1", realPort);

			// Pump client -> upstream raw (args avoid scoped-closure capture).
			runTask(&pumpRaw, client, upstream);

			int messageIndex;
			while (upstream.connected)
			{
				ubyte[4] lenBuf;
				upstream.read(lenBuf[], IOMode.all);
				int len = lenBuf[0] | (lenBuf[1] << 8) | (lenBuf[2] << 16) | (lenBuf[3] << 24);

				auto msg = new ubyte[len];
				msg[0 .. 4] = lenBuf;
				upstream.read(msg[4 .. $], IOMode.all);

				messageIndex++;
				if (messageIndex == 2)
					msg[8 .. 12] = cast(ubyte[])[0xEF, 0xBE, 0xAD, 0xDE];

				client.write(msg);
			}
		}
		catch (Exception) {}
		client.close();
	}, "127.0.0.1");
}

// A TCP proxy that forwards the handshake verbatim but, for the SECOND
// server->client message (the command reply), sends only a truncated prefix
// and closes the client socket so the driver's recv hits EOF mid-message.
TCPListener startTruncatingProxy(ushort realPort)
{
	return listenTCP(0, (client) {
		try
		{
			auto upstream = connectTCP("127.0.0.1", realPort);

			runTask(&pumpRaw, client, upstream);

			int messageIndex;
			while (upstream.connected)
			{
				ubyte[4] lenBuf;
				upstream.read(lenBuf[], IOMode.all);
				int len = lenBuf[0] | (lenBuf[1] << 8) | (lenBuf[2] << 16) | (lenBuf[3] << 24);

				auto msg = new ubyte[len];
				msg[0 .. 4] = lenBuf;
				upstream.read(msg[4 .. $], IOMode.all);

				messageIndex++;
				if (messageIndex == 2)
				{
					// Forward only the first 8 bytes of a header claiming `len`,
					// then close: recv for the rest of the header/body gets EOF.
					client.write(msg[0 .. 8]);
					break;
				}

				client.write(msg);
			}
		}
		catch (Exception) {}
		client.close();
	}, "127.0.0.1");
}

// A truncated reply (server closes the socket mid-message) must quarantine the
// connection: recv throws on the short read, and the C2 fix disconnects.
void runTruncatedReplyTest(ushort realPort)
{
	auto listener = startTruncatingProxy(realPort);
	ushort truncProxyPort = listener.bindAddress.port;

	auto conn = new MongoConnection("127.0.0.1", truncProxyPort);
	conn.connectToHost(MongoHost("127.0.0.1", truncProxyPort));

	bool threw;
	try
		conn.runCommand("admin", Bson(["ping": Bson(1)]));
	catch (Exception)
		threw = true;

	assert(threw, "a truncated reply makes runCommand throw");
	assert(!conn.connected,
		"after a truncated reply (socket closed mid-message), the connection must be quarantined (disconnected)");
}

// A clean command-failure (server returns a fully-read reply with ok != 1.0)
// must NOT quarantine the connection: the wire is healthy and the SAME
// connection must remain usable for the next command.
void runCommandFailureKeepsConnectionTest(ushort realPort)
{
	auto conn = new MongoConnection("127.0.0.1", realPort);
	conn.connectToHost(MongoHost("127.0.0.1", realPort));

	bool threw;
	try
		conn.runCommand("admin", Bson(["thisCommandDoesNotExist": Bson(1)]));
	catch (Exception)
		threw = true;

	assert(threw, "the server rejects an unknown command");
	assert(conn.connected,
		"a clean command-failure (ok != 1.0) must NOT quarantine the connection - the reply was fully read");

	auto pong = conn.runCommand("admin", Bson(["ping": Bson(1)]));
	assert(pong["ok"].get!double == 1.0,
		"the same connection is still usable for the next command after a logical command failure");
}

// A heap cell holding a "corrupt the command reply exactly once" flag, shared
// across every client connection the proxy accepts (the original poisoned
// connection AND the transparent reconnection).
final class CorruptOnceFlag
{
	bool corruptedOnce;
}

// A TCP proxy that corrupts the SECOND server->client message of the FIRST
// client connection only. The handshake is always forwarded verbatim; once one
// command reply has been corrupted, every later reply (including the
// reconnection's) is forwarded clean.
TCPListener startReuseProxy(ushort realPort, CorruptOnceFlag flag)
{
	return listenTCP(0, (client) {
		try
		{
			auto upstream = connectTCP("127.0.0.1", realPort);

			runTask(&pumpRaw, client, upstream);

			int messageIndex;
			while (upstream.connected)
			{
				ubyte[4] lenBuf;
				upstream.read(lenBuf[], IOMode.all);
				int len = lenBuf[0] | (lenBuf[1] << 8) | (lenBuf[2] << 16) | (lenBuf[3] << 24);

				auto msg = new ubyte[len];
				msg[0 .. 4] = lenBuf;
				upstream.read(msg[4 .. $], IOMode.all);

				messageIndex++;
				if (messageIndex == 2 && !flag.corruptedOnce)
				{
					msg[8 .. 12] = cast(ubyte[])[0xEF, 0xBE, 0xAD, 0xDE];
					flag.corruptedOnce = true;
				}

				client.write(msg);
			}
		}
		catch (Exception) {}
		client.close();
	}, "127.0.0.1");
}

// A connection quarantined by a wire desync must transparently recover: the
// next command on the SAME MongoConnection triggers ensureConnected() ->
// reconnect (a fresh handshake) and succeeds. The proxy corrupts exactly one
// command reply, so the first command desyncs and the reconnection is clean.
void runReuseAfterPoisonTest(ushort realPort)
{
	auto flag = new CorruptOnceFlag;
	auto listener = startReuseProxy(realPort, flag);
	ushort reuseProxyPort = listener.bindAddress.port;

	auto conn = new MongoConnection("127.0.0.1", reuseProxyPort);
	conn.connectToHost(MongoHost("127.0.0.1", reuseProxyPort));

	bool threw;
	try
		conn.runCommand("admin", Bson(["ping": Bson(1)]));
	catch (Exception)
		threw = true;

	assert(threw, "the corrupted reply throws");
	assert(!conn.connected, "the connection is quarantined after the desync");

	auto pong = conn.runCommand("admin", Bson(["ping": Bson(1)]));
	assert(pong["ok"].get!double == 1.0,
		"a quarantined connection transparently reconnects and the next command succeeds");
}

int main(string[] args)
{
	setLogLevel(LogLevel.diagnostic);

	if (args.length < 2)
	{
		logError("Usage: %s <real-mongo-port>", args[0]);
		return 1;
	}

	ushort realPort = args[1].to!ushort;

	int exitCode = 1;

	runTask(() nothrow {
		scope (exit) exitEventLoop();

		try
		{
			runCommandFailureKeepsConnectionTest(realPort);
			runTruncatedReplyTest(realPort);
			runReuseAfterPoisonTest(realPort);

			auto listener = startCorruptingProxy(realPort);
			ushort proxyPort = listener.bindAddress.port;

			auto conn = new MongoConnection("127.0.0.1", proxyPort);
			conn.connectToHost(MongoHost("127.0.0.1", proxyPort));

			bool threw;
			try
				conn.runCommand("admin", Bson(["ping": Bson(1)]));
			catch (Exception)
				threw = true;

			assert(threw, "a reply with a corrupted responseTo makes runCommand throw");
			assert(!conn.connected,
				"after a wire desync, the connection must be quarantined (disconnected), not left connected for reuse");

			exitCode = 0;
		}
		catch (Throwable t)
		{
			try logError("FAILED: %s", t.toString());
			catch (Exception) {}
			exitCode = 1;
		}
	});

	runEventLoop();
	return exitCode;
}
