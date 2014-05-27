/**
	Generic stream interface used by several stream-like classes.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.stream;

import vibe.utils.memory : FreeListRef;

import core.time;
import std.algorithm;
import std.conv;


/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/**
Interface for all classes implementing readable streams.
*/
interface InputStream {
	/** Returns true iff the end of the input stream has been reached.
	*/
	@property bool empty();

	/**	Returns the maximum number of bytes that are known to remain in this stream until the
		end is reached. After leastSize() bytes have been read, the stream will either have
		reached EOS and empty() returns true, or leastSize() returns again a number > 0.
	*/
	@property ulong leastSize();

	/** Queries if there is data available for immediate, non-blocking read.
	*/
	@property bool dataAvailableForRead();

	/** Returns a temporary reference to the data that is currently buffered, typically has the size
		leastSize() or 0 if dataAvailableForRead() returns false.

		Note that any method invocation on the same stream invalidates the contents of the returned
		buffer.
	*/
	const(ubyte)[] peek();

	/**	Fills the preallocated array 'bytes' with data from the stream.

		Throws: An exception if the operation reads past the end of the stream
	*/
	void read(ubyte[] dst);
}

/**
	Interface for all classes implementing writeable streams.
*/
interface OutputStream {
	/** Writes an array of bytes to the stream.
	*/
	void write(in ubyte[] bytes);

	/** Flushes the stream and makes sure that all data is being written to the output device.
	*/
	void flush();

	/** Flushes and finalizes the stream.

		Finalize has to be called on certain types of streams. No writes are possible after a
		call to finalize().
	*/
	void finalize();

	/** Writes an array of chars to the stream.
	*/
	final void write(in char[] bytes)
	{
		write(cast(const(ubyte)[])bytes);
	}

	/** Pipes an InputStream directly into this OutputStream.

		The number of bytes written is either the whole input stream when nbytes == 0, or exactly
		nbytes for nbytes > 0. If the input stream contains less than nbytes of data, an exception
		is thrown.
	*/
	void write(InputStream stream, ulong nbytes = 0);

	/** These methods provide an output range interface.

		Note that these functions do not flush the output stream for performance reasons. flush()
		needs to be called manually afterwards.

		See_Also: $(LINK http://dlang.org/phobos/std_range.html#isOutputRange)
	*/
	final void put(ubyte elem) { write((&elem)[0 .. 1]); }
	/// ditto
	final void put(in ubyte[] elems) { write(elems); }
	/// ditto
	final void put(char elem) { write((&elem)[0 .. 1]); }
	/// ditto
	final void put(in char[] elems) { write(elems); }
	/// ditto
	final void put(dchar elem) { import std.utf; char[4] chars; encode(chars, elem); put(chars); }
	/// ditto
	final void put(in dchar[] elems) { foreach( ch; elems ) put(ch); }

	protected final void writeDefault(InputStream stream, ulong nbytes = 0)
	{
		static struct Buffer { ubyte[64*1024] bytes = void; }
		auto bufferobj = FreeListRef!(Buffer, false)();
		auto buffer = bufferobj.bytes[];

		//logTrace("default write %d bytes, empty=%s", nbytes, stream.empty);
		if( nbytes == 0 ){
			while( !stream.empty ){
				size_t chunk = min(stream.leastSize, buffer.length);
				assert(chunk > 0, "leastSize returned zero for non-empty stream.");
				//logTrace("read pipe chunk %d", chunk);
				stream.read(buffer[0 .. chunk]);
				write(buffer[0 .. chunk]);
			}
		} else {
			while( nbytes > 0 ){
				size_t chunk = min(nbytes, buffer.length);
				//logTrace("read pipe chunk %d", chunk);
				stream.read(buffer[0 .. chunk]);
				write(buffer[0 .. chunk]);
				nbytes -= chunk;
			}
		}
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

	See_also: vibe.core.new.TCPConnection
*/
interface ConnectionStream : Stream {
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

	/// Sets a timeout until data has to be availabe for read. Returns false on timeout.
	bool waitForData(Duration timeout = 0.seconds);
}


/**
	Interface for all streams supporting random access.
*/
interface RandomAccessStream : Stream {
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
	void write(in ubyte[] bytes) {}
	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}
	void flush() {}
	void finalize() {}
}
