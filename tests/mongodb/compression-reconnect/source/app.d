import vibe.core.core;
import vibe.core.net;
import vibe.core.log;
import vibe.core.stream : IOMode;
import vibe.db.mongo.connection;
import vibe.db.mongo.settings : MongoClientSettings, MongoHost, Compressor;
import vibe.data.bson;
import core.time;
import std.algorithm : canFind;
import std.conv;

enum int OP_MSG = 2013;
enum int OP_COMPRESSED = 2012;

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

// Shared, heap-allocated record so the @safe nothrow listener callback can
// mutate it across every accepted client connection. opcodesPerConnection[i]
// holds the opcodes of client->upstream messages of the i-th connection.
final class Recorder
{
	int[][] opcodesPerConnection;
}

// A transparent TCP proxy to the real mongo that records the opcode of every
// client->upstream message, grouped per client connection.
TCPListener startRecordingProxy(ushort realPort, Recorder recorder)
{
	return listenTCP(0, (TCPConnection client) nothrow @safe {
		try
		{
			auto upstream = connectTCP("127.0.0.1", realPort);

			recorder.opcodesPerConnection ~= (int[]).init;
			size_t connectionIndex = recorder.opcodesPerConnection.length - 1;

			runTask(&pumpRaw, upstream, client);

			while (client.connected)
			{
				ubyte[4] lenBuf;
				client.read(lenBuf[], IOMode.all);
				int len = lenBuf[0] | (lenBuf[1] << 8) | (lenBuf[2] << 16) | (lenBuf[3] << 24);

				auto msg = new ubyte[len];
				msg[0 .. 4] = lenBuf;
				client.read(msg[4 .. $], IOMode.all);

				int opcode = msg[12] | (msg[13] << 8) | (msg[14] << 16) | (msg[15] << 24);
				recorder.opcodesPerConnection[connectionIndex] ~= opcode;

				upstream.write(msg);
			}
		}
		catch (Exception) {}
		try client.close();
		catch (Exception) {}
	}, "127.0.0.1");
}

// A reconnect handshake carries the speculative-auth SCRAM payload and MUST be
// sent uncompressed (OP_MSG). The bug: m_negotiatedCompressor is never reset at
// the start of connectToHost, so after a disconnect the reconnect handshake is
// wrongly sent OP_COMPRESSED, which the compression spec forbids.
void runReconnectHandshakeUncompressedTest(ushort realPort)
{
	auto recorder = new Recorder;
	auto listener = startRecordingProxy(realPort, recorder);
	ushort proxyPort = listener.bindAddress.port;

	auto settings = new MongoClientSettings();
	settings.hosts ~= MongoHost("127.0.0.1", proxyPort);
	settings.compressors = [Compressor.zlib];

	auto conn = new MongoConnection(settings);
	conn.connectToHost(MongoHost("127.0.0.1", proxyPort));       // connection 1: handshake (OP_MSG)
	conn.runCommand("admin", Bson(["ping": Bson(1)]));           // connection 1: a COMPRESSED command (proves zlib negotiated)
	conn.disconnect();                                           // connection 1 closes; m_negotiatedCompressor stays zlib (the bug)
	conn.runCommand("admin", Bson(["ping": Bson(1)]));           // triggers reconnect -> connection 2: handshake (+ ping)

	// Let the proxy tasks finish recording the in-flight messages.
	sleep(200.msecs);

	assert(recorder.opcodesPerConnection.length >= 2,
		"the reconnect must open a second proxy connection");

	// Compression must actually be negotiated for this test to be meaningful. A server
	// that advertises no compressors (e.g. a default MongoDB 3.6 mongod) never sends
	// OP_COMPRESSED, so the reconnect-handshake-compression bug cannot manifest — skip.
	if (!recorder.opcodesPerConnection[0].canFind(OP_COMPRESSED))
	{
		logInfo("Server did not negotiate zlib compression; skipping reconnect-compression test");
		return;
	}

	assert(recorder.opcodesPerConnection[1][0] == OP_MSG,
		"the reconnect handshake must be uncompressed OP_MSG (2013), not OP_COMPRESSED (2012)");
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
			runReconnectHandshakeUncompressedTest(realPort);
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
