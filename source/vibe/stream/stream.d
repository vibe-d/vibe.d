/**
	Generic stream interface used by several stream-like classes.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.stream;

import vibe.core.log;
import vibe.stream.memory;
import vibe.utils.memory;

import std.algorithm;
import std.array;
import std.datetime;
import std.exception;
import std.typecons;


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Reads and returns a single line from the stream.

	Throws:
		An exception if either the stream end was hit without hitting a newline first, or
		if more than max_bytes have been read from the stream in case of max_bytes != 0.
*/
ubyte[] readLine(InputStream stream, size_t max_bytes = 0, string linesep = "\r\n", Allocator alloc = defaultAllocator()) /*@ufcs*/
{
	return readUntil(stream, cast(const(ubyte)[])linesep, max_bytes, alloc);
}

/**
	Reads all data of a stream until the specified end marker is detected.

	Throws:
		An exception if either the stream end was hit without hitting a marker first, or
		if more than max_bytes have been read from the stream in case of max_bytes != 0.
*/
ubyte[] readUntil(InputStream stream, in ubyte[] end_marker, size_t max_bytes = 0, Allocator alloc = defaultAllocator()) /*@ufcs*/
{
	auto output = scoped!MemoryOutputStream(alloc);
	output.reserve(max_bytes ? max_bytes < 128 ? max_bytes : 128 : 128);
	readUntil(stream, output, end_marker, max_bytes);
	return output.data();
}
/// ditto
void readUntil(InputStream stream, OutputStream dst, in ubyte[] end_marker, ulong max_bytes = 0) /*@ufcs*/
{
	// TODO: implement a more efficient algorithm for long end_markers such as a Boyer-Moore variant
	size_t nmatched = 0;
	auto bufferobj = FreeListRef!(Buffer, false)();
	auto buf = bufferobj.bytes[];

	void skip(size_t nbytes)
	{
		while( nbytes > 0 ){
			auto n = min(nbytes, buf.length);
			stream.read(buf[0 .. n]);
			nbytes -= n;
		}
	}

	ulong bytes_written = 0;

	while( !stream.empty ){
		size_t nread = 0;
		auto least_size = stream.leastSize(); // NOTE: blocks until data is available
		auto str = stream.peek(); // try to get some data for free
		if( str.length == 0 ){ // if not, read as much as possible without reading past the end
			nread = min(least_size, end_marker.length-nmatched, buf.length);
			stream.read(buf[0 .. nread]);
			str = buf[0 .. nread];
		}

		auto mpart = min(end_marker.length - nmatched, str.length);
		if( str[0 .. mpart] == end_marker[nmatched .. nmatched+mpart] ){
			nmatched += mpart;
			if( nmatched == end_marker.length ){
				skip(mpart-nread);
				return;
			}
		} else {
			if( nmatched > 0 ){
				dst.write(end_marker[0 .. nmatched]);
				nmatched = 0;
			}
			foreach( i, ch; str ){
				if( ch == end_marker[nmatched] ){
					if( ++nmatched == end_marker.length ){
						if( i+1 > end_marker.length )
							dst.write(str[0 .. i+1-end_marker.length]);
						skip(i+1-nread);
						return;
					}
				} else nmatched = 0;
			}

			dst.write(str[0 .. str.length-nmatched]);
		}

		skip(str.length - nread);
	}
	enforce(false, "Reached EOF before reaching end marker.");
}

/**
	Reads the complete contents of a stream, optionally limited by max_bytes.

	Throws:
		An exception is thrown if max_bytes != 0 and the stream contains more than max_bytes data.
*/
ubyte[] readAll(InputStream stream, size_t max_bytes = 0) /*@ufcs*/
{
	auto dst = appender!(ubyte[])();
	auto bufferobj = FreeListRef!(Buffer, false)();
	auto buffer = bufferobj.bytes[];
	size_t n = 0, m = 0;
	while( !stream.empty ){
		enforce(!max_bytes || n++ < max_bytes, "Data too long!");
		size_t chunk = cast(size_t)min(stream.leastSize, buffer.length);
		logTrace("read pipe chunk %d", chunk);
		stream.read(buffer[0 .. chunk]);
		dst.put(buffer[0 .. chunk]);
	}
	return dst.data;
}

private struct Buffer { ubyte[64*1024] bytes; }

/**************************************************************************************************/
/* Public types                                                                                   */
/**************************************************************************************************/

/**
	Interface for all classes implementing readable streams.
*/
interface InputStream {
	/** Returns true iff the end of the stream has been reached
	*/
	@property bool empty();

	/**	Returns the maximum number of bytes that are known to remain in this stream until the
		end is reached. After leastSize() bytes have been read, the stream will either have
		reached EOS and empty() returns true, or leastSize() returns again a number > 0.
	*/
	@property ulong leastSize();

	/**
		Queries if there is data available for immediate, non-blocking read.
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
	void write(in ubyte[] bytes, bool do_flush = true);

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
	final void write(in char[] bytes, bool do_flush = true)
	{
		write(cast(const(ubyte)[])bytes, do_flush);
	}

	/** Pipes an InputStream directly into this OutputStream.

		The number of bytes written is either the whole input stream when nbytes == 0, or exactly
		nbytes for nbytes > 0. If the input stream contains less than nbytes of data, an exception
		is thrown.
	*/
	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true);

	protected final void writeDefault(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		static struct Buffer { ubyte[64*1024] bytes; }
		auto bufferobj = FreeListRef!(Buffer, false)();
		auto buffer = bufferobj.bytes[];

		logTrace("default write %d bytes, empty=%s", nbytes, stream.empty);
		if( nbytes == 0 ){
			while( !stream.empty ){
				size_t chunk = cast(size_t)min(stream.leastSize, buffer.length);
				logTrace("read pipe chunk %d", chunk);
				stream.read(buffer[0 .. chunk]);
				write(buffer[0 .. chunk], false);
			}
		} else {
			while( nbytes > 0 ){
				size_t chunk = cast(size_t)min(nbytes, buffer.length);
				logTrace("read pipe chunk %d", chunk);
				stream.read(buffer[0 .. chunk]);
				write(buffer[0 .. chunk], false);
				nbytes -= chunk;
			}
		}
		if( do_flush ) flush();
	}
}

/**
	Interface for all classes implementing readable and writable streams.
*/
interface Stream : InputStream, OutputStream {
}


/**
	Stream implementation acting as a sink with no function.

	Any data written to the stream will be ignored and discarded. This stream type is useful if
	the output of a particular stream is not needed but the stream needs to be drained.
*/
class NullOutputStream : OutputStream {
	void write(in ubyte[] bytes, bool do_flush = true) {}
	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}
	void flush() {}
	void finalize() {}
}
