import vibe.d;

import std.functional : toDelegate;
import vibe.core.unix;
import std.stdio;

static immutable socket_path = "\0unix-socket-test1";
private UnixSocket listener;

debug=Verbose;
import std.stdio;

shared static this()
{
	listener = UnixSocket.listen(socket_path, toDelegate(&handleConnection));
	// This isn't required by UnixSocket, but it gives some time for the
	// server to start (else the connect might be performed before the server
	// starts to listen).
    setTimer(1.seconds,
			 () { client(UnixSocket.connect(socket_path)); });
}

/// Server part: Handle every incoming connection
private void handleConnection (UnixStream stream)
{
	writefln("[SERVER] New connection received !");
	ubyte[8] buff;
	size_t curr_value;
	assert (stream !is null, "Stream is null");
	while (curr_value < 32)
	{
		/*debug(Verbose)*/ writefln("[SERVER] Reading from stream");
		stream.read(buff);
		/*debug(Verbose)*/ writefln("[SERVER] Data read: %s", cast(char[])buff);
		auto val = to!uint(cast(char[])buff);
		assert(val == (curr_value + 1),
			   "Expected " ~ to!string(curr_value + 1)
			   ~ " not: " ~ cast(char[])buff);
		curr_value = val;
		/*debug(Verbose)*/ writefln("[SERVER] Writing to stream: %d", curr_value);
		stream.write(toBuff8(curr_value,buff));
	}
	writefln("[SERVER] Disconnecting");
	stream.close();
	listener.close();
	exitEvLoop();
}

/// Client part: Send the server numbers from 000_000_01 to 000_000_32 and
/// expect the same answer.
private void client (UnixStream stream)
{
	ubyte[8] buff;
	writefln("[CLIENT] Client connected !");
	foreach (val; 1 .. 33)
	{
		debug(Verbose) writefln("[CLIENT] Writing to stream: %d", val);
		stream.write(toBuff8(val, buff));
		debug(Verbose) writefln("[CLIENT] Reading from stream...");
		buff[] = 0;
		stream.read(buff);
		debug(Verbose) writefln("[CLIENT] Read: %s", cast(char[])buff);
		auto ret = to!uint(cast(char[])buff);
		assert(ret == val,
			   "Expected " ~ to!string(val) ~ " not: " ~ cast(char[])buff);
	}
	writefln("[CLIENT] Disconnecting...");
	stream.close();
	exitEvLoop();
}

/// Since the server and client expect to read 8 bytes...
ubyte[] toBuff8 (ulong val, ref ubyte[8] buffer)
{
	buffer[] = '0';
	foreach_reverse (ref ubyte c; buffer)
	{
		c = (val % 10) + '0';
		val /= 10;
	}
	return buffer;
}

/// Since the order of disconnection is not deterministic, and we want
/// both client to disconnect, we resort on this 'hack'
void exitEvLoop ()
{
	static short call = 0;
	call++;
	if (call == 2)
		exitEventLoop();
}
