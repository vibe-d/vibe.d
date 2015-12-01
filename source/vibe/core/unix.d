/**
 * Unix socket implementation compatible with the event driver
 *
 * Copyright:
 * © 2015 RejectedSoftware e.K.
 *
 * Authors:
 * Mathias 'Geod24' Lang
 *
 * License:
 * Subject to the terms of the MIT license, as written in
 * the included LICENSE.txt file.
 */
module vibe.core.unix;

import core.time;
import core.sys.posix.fcntl;
import core.sys.posix.unistd : close, write;
import core.sys.posix.sys.socket;

import std.exception : enforce;

import vibe.core.core;
import vibe.core.driver;
import vibe.core.log;
import vibe.core.stream;


/*******************************************************************************

	Class to instantiate connections to/via unix sockets.

	This class only support streaming (SOCK_STREAM) sockets.

	Server example:
	---
	// Note: Path starting with '\0' are in the abstract linux namespace
	auto server = UnixSocket.listen("\0test", &handleSingleConnection);
	// After a while...
	server.close(); // Stop listening on the socket for new connections
	---

	Client example:
	---
	auto client = UnixSocket.connect("\0test");
	// The connection is a `vibe.core.stream.ConnectionStream`, see the
	// documentation for available methods.
	client.close(); // Close client connection
	---

*******************************************************************************/

public final class UnixSocket
{
	import core.sys.posix.sys.un;


	/***************************************************************************

		Convenience alias to the type of delegate to provide to handle
		a connection.

	***************************************************************************/

	public alias ConnectionHandler = void delegate(UnixStream);


	/***************************************************************************

		Starts listening for connection on the given `path`, and call `handler`
		for each incoming request.

		See `UnixSocket` documentation for a short example.

		Throws:
			`UnixSocketException` on error

	***************************************************************************/

	public static UnixSocket listen (string path, ConnectionHandler handler)
	{
		// Does not need the null termination as it's fixed-length
		enforce!(UnixSocketException)
			(path.length <= sockaddr_un.sun_path.length,
			 "The given path is larger than sockaddr_un.sun_path !");

		// Create socket. We should be able to pass SOCK_STREAM | SOCK_NONBLOCK
		// as the type but it somehow cause EINVAL to be returned.
		auto fd = socket(AF_UNIX, SOCK_STREAM, 0);
		cenforce(fd != -1, "Call to socket failed");

		// Bind to the address
		sockaddr_un addr;
		addr.sun_family = AF_UNIX;
		addr.sun_path[0 .. path.length] = cast(byte[])path;
		auto ret = bind(fd, cast(sockaddr*) &addr, addr.sizeof);
		cenforce(ret == 0, "Call to bind failed");

		// Set the non-blocking flag, POSIX way.
		auto flags = fcntl(fd, F_GETFL, 0);
		cenforce(flags > -1, "Call to fcntl(F_GETFL) failed");
		cenforce(0 == fcntl(fd, F_SETFL, flags | O_NONBLOCK),
				 "Call to fcntl(F_SETFL) failed");

		// Create the file descriptor event
		auto event = getEventDriver().createFileDescriptorEvent
			(fd, FileDescriptorEvent.Trigger.read);

		// We're done
		return new UnixSocket(fd, event).startListener(handler);
	}


	/***************************************************************************

		Start a streaming connection to the given path, as a client.

		See `UnixSocket` documentation for a short example.

		Throws:
			`UnixSocketException` on error

	***************************************************************************/

	public static UnixStream connect (string path)
	{
		// Does not need the null termination as it's fixed-length
		enforce!(UnixSocketException)
			(path.length <= sockaddr_un.sun_path.length,
			 "The given path is larger than sockaddr_un.sun_path !");

		// Create socket. We should be able to pass SOCK_STREAM | SOCK_NONBLOCK
		// as the type but it somehow cause EINVAL to be returned.
		auto fd = socket(AF_UNIX, SOCK_STREAM, 0);
		cenforce(fd != -1, "Call to socket failed");

		// Bind to the address
		sockaddr_un addr;
		addr.sun_family = AF_UNIX;
		addr.sun_path[0 .. path.length] = cast(byte[])path;
		cenforce(0 == .connect(fd, cast(sockaddr*) &addr, addr.sizeof),
				 "Call to bind failed");

		// Set the non-blocking flag, POSIX way.
		auto flags = fcntl(fd, F_GETFL, 0);
		cenforce(flags > -1, "Call to fcntl failed");
		cenforce(0 == fcntl(fd, F_SETFL, flags | O_NONBLOCK),
				 "Call to fcntl failed");

		return new UnixStream(fd);
	}


	/***************************************************************************

		Close a server connection

		Close the listening socket, but does not do any synchronization with
		any running client task.

	***************************************************************************/

	public void close ()
	{
		this.event = null;
		if (this.file_descriptor != -1)
		{
			.close(this.file_descriptor);
			this.file_descriptor = -1;
		}
	}


	/***************************************************************************

		Private constructor

		Instance should only ever be created via call to the static functions:
		`listen` or `connect`.

	***************************************************************************/

	private this (int fd, FileDescriptorEvent ev)
	{
		this.file_descriptor = fd;
		this.event = ev;
	}


	/***************************************************************************

		Start to listen on the binded socket, within a task.

		This starts a new taks which will on the socket in a non-blocking way.

		Returns:
			`this` for chaining (it's only called from the public `listen`)

	***************************************************************************/

	private UnixSocket startListener (ConnectionHandler handler)
	{
		this.listener = runTask(
			()
			{
				cenforce(0 == .listen(this.file_descriptor, 128),
						 "Call to listen failed");

				do
				{
					this.event.wait(FileDescriptorEvent.Trigger.read);
					auto fd = accept(this.file_descriptor, null, null);
					cenforce(fd >= 0, "Call to accept failed");

					runTask(
						()
						{
							handler(new UnixStream(fd));
						});
				} while (true);
			});
		return this;
	}


	private Task listener;
	private int file_descriptor;
	private FileDescriptorEvent event;
}


/*******************************************************************************

	Class to represent an unix socket stream connection, either client or
	server side.

*******************************************************************************/

public final class UnixStream : ConnectionStream
{
	/***************************************************************************

		Number of bytes which can be returned by `.peek`, at most.

	***************************************************************************/

	private enum size_t max_peek_size = 4096;


	/***************************************************************************

		Private constructor

		Instance should only ever be created by `UnixSocket`'s methods.

	***************************************************************************/

	private this (int fd)
	{
		this.file_descriptor = fd;
		this.event = getEventDriver().createFileDescriptorEvent
			(fd, FileDescriptorEvent.Trigger.read);
	}


	/***************************************************************************

		Determines the current connection status.

		If connected is false, writing to the connection will trigger an
		exception. Reading may still succeed as long as there is data left in
		the input buffer.
		Use InputStream.empty to determine when to stop reading.

		Returns:
			Whether or not the connection is active.

	***************************************************************************/

	public override @property bool connected () const
	{
		return this.event !is null && this.file_descriptor != -1;
	}


	/***************************************************************************

		Actively closes the connection and frees associated resources.

		Note that close must always be called, even if the remote has already
		closed the connection. Failure to do so will result in resource and
		memory leakage.

		Closing a connection implies a call to finalize, so that it doesn't
		need to be called explicitly (it will be a no-op in that case).

	***************************************************************************/

	public override void close ()
	{
		this.event = null;
		if (this.file_descriptor != -1)
		{
			.close(this.file_descriptor);
			this.file_descriptor = -1;
		}
	}


	/***************************************************************************

		Sets a timeout until data has to be availabe for read.

		Returns:
			false on timeout.

	***************************************************************************/

	public override bool waitForData (Duration timeout = Duration.max)
	{
		assert(this.connected,
			   "UnixStream.waitForData called on a closed connection !");

		return this.event.wait(int.max.seconds, FileDescriptorEvent.Trigger.read);
	}


	public override bool empty () @property
	{
		assert(this.connected,
			   "UnixStream.empty called on a closed connection !");

		return this.leastSize == 0;
	}


	public override ulong leastSize () @property
	{
		assert(this.connected,
			   "UnixStream.leastSize called on a closed connection !");

		if (this.available)
		{
			return this.available;
		}
		if (this.waitForData())
		{
			this.available = this.peek().length;
			return this.available;
		}
		return 0;
	}


	public override bool dataAvailableForRead () @property
	{
		return this.event.wait(0.seconds, FileDescriptorEvent.Trigger.read);
	}

	public override const(ubyte)[] peek ()
	{
		assert(this.connected,
			   "UnixStream.peek called on a closed connection !");

		import core.stdc.errno;
		errno = 0;
		auto size = recv(this.file_descriptor, this.buffer.ptr,
						 this.buffer.length, MSG_PEEK);
		if (errno == EWOULDBLOCK || errno == EAGAIN)
			return null;
		cenforce(-1 != size, "Call to recv failed");
		this.available = size;
		return this.buffer[0 .. size];
	}


	public override void read (ubyte[] dst)
	{
		assert(this.connected,
			   "UnixStream.read called on a closed connection !");

		while (dst.length && this.waitForData(Duration.max))
		{
			auto size = recv(this.file_descriptor, dst.ptr, dst.length, 0);
			cenforce(-1 != size, "Call to recv failed");
			this.available = 0;
			dst = dst[size .. $];
		}
	}


	public override void write (const(ubyte[]) bytes)
	{
		assert(this.connected,
			   "UnixStream.write called on a closed connection !");

		cenforce(bytes.length ==
				 .write(this.file_descriptor, bytes.ptr, bytes.length),
			"Call to write failed");
	}


	public override void write (InputStream stream, ulong nbytes = 0LU)
	{
		assert(this.connected,
			   "UnixStream.write called on a closed connection !");

		this.writeDefault(stream, nbytes);
	}


	public override void flush ()
	{
		assert(this.connected,
			   "UnixStream.flush called on a closed connection !");

		assert (0, "FLUSH CALLED");
	}

	/***************************************************************************

		Flushes and finalizes the stream.

		Finalize has to be called on certain types of streams.
		No writes are possible after a call to finalize().

	***************************************************************************/

	public override void finalize ()
	{
		// No memory to finalize
	}

	private size_t available;
	private ubyte[max_peek_size] buffer;
	private int file_descriptor;
	private FileDescriptorEvent event;
}


/*******************************************************************************

	Type of Exception thrown by this module

*******************************************************************************/

public class UnixSocketException : Exception
{
	@nogc @safe pure nothrow:

    /**
     * Creates a new instance of Exception. The next parameter is used
     * internally and should always be $(D null) when passed by user code.
     * This constructor does not automatically throw the newly-created
     * Exception; the $(D throw) statement should be used for that purpose.
     */
	public this (string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(msg, file, line, next);
	}

	/// Ditto
	public this (string msg, Throwable next, string file = __FILE__, size_t line = __LINE__)
	{
		super(msg, file, line, next);
	}
}


/*******************************************************************************

	Helper function which mimic enforce but append the `strerror` of `errno`
	to the error message

	Params:

	Returns:

	Throws:
		`UnixSocketException` by default

*******************************************************************************/

private T cenforce (T, E : Exception = UnixSocketException)
	(T ok, lazy const(char)[] message, string file = __FILE__,
	 ulong line = __LINE__)
{
	import core.stdc.errno;
	import core.stdc.string;
	import std.format;

	if (!ok)
	{
		char* cerror_ptr = strerror(errno);
		char[] cerror = cerror_ptr[0 .. strlen(cerror_ptr)];
		throw new E(format("{}: {}", message, cerror), file, line);
	}
	return ok;
}
