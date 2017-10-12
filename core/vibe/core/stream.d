/**
	Generic stream interface used by several stream-like classes.

	This module defines the basic stream primitives. For concrete stream types, take a look at the
	`vibe.stream` package. The `vibe.stream.operations` module contains additional high-level
	operations on streams, such as reading streams by line or as a whole.

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.stream;

import core.time;
import std.algorithm;
import std.conv;


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/** Pipes an InputStream directly into this OutputStream.

	The number of bytes written is either the whole input stream when `nbytes == 0`, or exactly
	`nbytes` for `nbytes > 0`. If the input stream contains less than `nbytes` of data, an
	exception is thrown.
*/
void pipe(IS : InputStream, OS : OutputStream)(IS source, OS sink, ulong nbytes = 0)
@safe {
	import vibe.internal.allocator : dispose, makeArray, theAllocator;

	auto buffer = () @trusted { return theAllocator.makeArray!ubyte(64*1024); } ();
	scope (exit) () @trusted { theAllocator.dispose(buffer); } ();

	//logTrace("default write %d bytes, empty=%s", nbytes, stream.empty);
	if (nbytes == 0 || nbytes == ulong.max) {
		while (!source.empty) {
			size_t chunk = min(source.leastSize, buffer.length);
			assert(chunk > 0, "leastSize returned zero for non-empty stream.");
			//logTrace("read pipe chunk %d", chunk);
			source.read(buffer[0 .. chunk], IOMode.all);
			sink.write(buffer[0 .. chunk], IOMode.all);
		}
	} else {
		while (nbytes > 0) {
			size_t chunk = min(nbytes, buffer.length);
			//logTrace("read pipe chunk %d", chunk);
			source.read(buffer[0 .. chunk], IOMode.all);
			sink.write(buffer[0 .. chunk], IOMode.all);
			nbytes -= chunk;
		}
	}
}

/**
	Returns a `NullOutputStream` instance.

	The instance will only be created on the first request and gets reused for
	all subsequent calls from the same thread.
*/
NullOutputStream nullSink()
@safe {
	static NullOutputStream ret;
	if (!ret) ret = new NullOutputStream;
	return ret;
}

/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/** Controls the waiting behavior of read/write operations.

	Note that this is currently ignored for all device streams. Use the "vibe-core" package if you
	need this functionality.
*/
enum IOMode {
	immediate, /// not supported
	once,      /// not supported
	all        /// Writes/reads the whole buffer
}

/**
	Interface for all classes implementing readable streams.
*/
interface InputStream {
@safe:

	/** Returns true $(I iff) the end of the input stream has been reached.
	*/
	@property bool empty();

	/**	(Scheduled for deprecation) Returns the maximum number of bytes that are known to remain in this stream until the
		end is reached.

		After `leastSize()` bytes have been read, the stream will either have
		reached EOS and `empty()` returns `true`, or `leastSize()` returns again a number `> 0`.
	*/
	@property ulong leastSize();

	/** (Scheduled for deprecation) Queries if there is data available for immediate, non-blocking read.
	*/
	@property bool dataAvailableForRead();

	/** Returns a temporary reference to the data that is currently buffered.

		The returned slice typically has the size `leastSize()` or `0` if
		`dataAvailableForRead()` returns false. Streams that don't have an
		internal buffer will always return an empty slice.

		Note that any method invocation on the same stream potentially
		invalidates the contents of the returned buffer.
	*/
	const(ubyte)[] peek();

	/**	Fills the preallocated array 'bytes' with data from the stream.

		Throws: An exception if the operation reads past the end of the stream
	*/
	size_t read(scope ubyte[] dst, IOMode);
	/// ditto
	final void read(scope ubyte[] dst) { read(dst, IOMode.all); }
}

/**
	Interface for all classes implementing writeable streams.
*/
interface OutputStream {
@safe:

	/** Writes an array of bytes to the stream.
	*/
	size_t write(in ubyte[] bytes, IOMode mode);
	/// ditto
	final void write(in ubyte[] bytes) { write(bytes, IOMode.all); }
	/// ditto
	final void write(in char[] bytes) { write(cast(const(ubyte)[])bytes); }

	/** Flushes the stream and makes sure that all data is being written to the output device.
	*/
	void flush();

	/** Flushes and finalizes the stream.

		Finalize has to be called on certain types of streams. No writes are possible after a
		call to finalize().
	*/
	void finalize();

	/** Pipes an InputStream directly into this OutputStream.

		The number of bytes written is either the whole input stream when nbytes == 0, or exactly
		nbytes for nbytes > 0. If the input stream contains less than nbytes of data, an exception
		is thrown.
	*/
	deprecated("Use pipe(source, sink) instead.")
	final void write(InputStream stream, ulong nbytes = 0)
	{
		stream.pipe(this, nbytes);
	}
}

/**
	Interface for all classes implementing readable and writable streams.
*/
interface Stream : InputStream, OutputStream {
}


/**
	Interface for streams based on a connection.

	Connection streams are based on streaming socket connections, pipes and
	similar end-to-end streams.

	See_also: vibe.core.net.TCPConnection
*/
interface ConnectionStream : Stream {
@safe:

	/** Determines The current connection status.

		If connected is false, writing to the connection will trigger an
		exception. Reading may still succeed as long as there is data left in
		the input buffer. Use InputStream.empty to determine when to stop
		reading.
	*/
	@property bool connected() const;

	/** Actively closes the connection and frees associated resources.

		Note that close must always be called, even if the remote has already
		closed the connection. Failure to do so will result in resource and
		memory leakage.

		Closing a connection implies a call to finalize, so that it doesn't
		need to be called explicitly (it will be a no-op in that case).
	*/
	void close();

	/** Blocks until data becomes available for read.

		The maximum wait time can be customized with the `timeout` parameter.
		If there is already data availabe for read, or if the connection is
		closed, the function will return immediately without blocking.

		Params:
			timeout = Optional timeout, the default value of `Duration.max`
				indicates an infinite timeout

		Returns:
			The function will return `true` if data becomes available before the
			timeout is reached. If the connection gets closed, or the timeout
			gets reached, `false` is returned instead.
	*/
	bool waitForData(Duration timeout = Duration.max);
}


/**
	Interface for all streams supporting random access.
*/
interface RandomAccessStream : Stream {
@safe:

	/// Returns the total size of the file.
	@property ulong size() const nothrow;

	/// Determines if this stream is readable.
	@property bool readable() const nothrow;

	/// Determines if this stream is writable.
	@property bool writable() const nothrow;

	/// Seeks to a specific position in the file if supported by the stream.
	void seek(ulong offset);

	/// Returns the current offset of the file pointer
	ulong tell() nothrow;
}


/**
	Stream implementation acting as a sink with no function.

	Any data written to the stream will be ignored and discarded. This stream type is useful if
	the output of a particular stream is not needed but the stream needs to be drained.
*/
final class NullOutputStream : OutputStream {
	size_t write(in ubyte[] bytes, IOMode) { return bytes.length; }
	alias write = OutputStream.write;
	void flush() {}
	void finalize() {}
}


alias InputStreamProxy = InputStream;
alias OutputStreamProxy = OutputStream;
alias StreamProxy = Stream;
alias ConnectionStreamProxy = ConnectionStream;
alias RandomAccessStreamProxy = RandomAccessStream;

enum isInputStream(T) = is(T : InputStream);
enum isOutputStream(T) = is(T : OutputStream);
enum isStream(T) = is(T : Stream);
enum isConnectionStream(T) = is(T : ConnectionStream);
enum isRandomAccessStream(T) = is(T : RandomAccessStream);

mixin template validateInputStream(T) { static assert(isInputStream!T); }
mixin template validateOutputStream(T) { static assert(isOutputStream!T); }
mixin template validateStream(T) { static assert(isStream!T); }
mixin template validateConnectionStream(T) { static assert(isConnectionStream!T); }
mixin template validateRandomAccessStream(T) { static assert(isRandomAccessStream!T); }
