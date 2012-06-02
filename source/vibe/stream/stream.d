/**
	Generic stream interface used by several stream-like classes.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.stream;

import vibe.core.log;
import vibe.stream.memory;

import std.array;
import std.algorithm;
import std.exception;
import std.datetime;

/**
	Reads and returns a single line from the stream.

	Throws:
		An exception if either the stream end was hit without hitting a newline first, or
		if more than max_bytes have been read from the stream in case of max_bytes != 0.
*/
ubyte[] readLine(InputStream stream, size_t max_bytes = 0, string linesep = "\r\n") /*@ufcs*/
{
	return readUntil(stream, cast(const(ubyte)[])linesep, max_bytes);
}

/**
	Reads all data of a stream until the specified end marker is detected.

	Throws:
		An exception if either the stream end was hit without hitting a marker first, or
		if more than max_bytes have been read from the stream in case of max_bytes != 0.
*/
ubyte[] readUntil(InputStream stream, in ubyte[] end_marker, size_t max_bytes = 0) /*@ufcs*/
{
	auto output = new MemoryOutputStream();
	readUntil(stream, output, end_marker, max_bytes);
	return output.data();
}
/// ditto
void readUntil(InputStream stream, OutputStream dst, in ubyte[] end_marker, ulong max_bytes = 0) /*@ufcs*/
{
	// TODO: implement a more efficient algorithm for long end_markers such as a Boyer-Moore variant
	size_t nmatched = 0;
	ubyte[128] buf;

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

		foreach( i, ch; str ){
			if( ch == end_marker[nmatched] ){
				nmatched++;
				if( nmatched == end_marker.length ){
					skip(i+1-nread);
					return;
				}
			} else {
				enforce(max_bytes == 0 || bytes_written < max_bytes,
					"Maximum number of bytes read before reading the end marker.");
				if( nmatched > 0 ){
					dst.write(end_marker[0 .. nmatched]);
					bytes_written += nmatched;
					nmatched = 0;
				}
				dst.write((&ch)[0 .. 1]);
				bytes_written++;
			}
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
	auto buffer = new ubyte[64*1024];
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
		auto buffer = new ubyte[64*1024];
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


/**
	Wraps an existing stream, limiting the amount of data that can be read.
*/
class LimitedInputStream : InputStream {
	private {
		InputStream m_input;
		ulong m_sizeLimit;
		bool m_silentLimit;
	}

	/** Constructs a limited stream from an existing input stream.

		Params:
			stream: the input stream to be wrapped
			byte_limit: the maximum number of bytes readable from the constructed stream
			silent_limit: if set, the stream will behave exactly like the original stream, but
				will throw an exception as soon as the limit is reached.		
	*/
	this(InputStream stream, ulong byte_limit, bool silent_limit = false)
	{
		m_input = stream;
		m_sizeLimit = byte_limit;
		m_silentLimit = silent_limit;
	}

	@property inout(InputStream) sourceStream() inout { return m_input; }

	@property bool empty() { return m_silentLimit ? m_input.empty : m_sizeLimit == 0; }

	@property ulong leastSize() { return m_silentLimit ? m_input.leastSize : m_sizeLimit; }

	@property bool dataAvailableForRead() { return m_input.dataAvailableForRead; }

	const(ubyte)[] peek() { return m_input.peek(); }

	void read(ubyte[] dst)
	{
		if (dst.length > m_sizeLimit) onSizeLimitReached();
		m_input.read(dst);
		m_sizeLimit -= dst.length;
	}
	
	protected void onSizeLimitReached() {
		throw new Exception("Size limit reached");
	}
}


/**
	Wraps an existing output stream, counting the bytes that are written.
*/
class CountingOutputStream : OutputStream {
	private {
		ulong m_bytesWritten;
		OutputStream m_out;
	}
	this(OutputStream stream) {
		m_out = stream;
	}

	@property ulong bytesWritten() const { return m_bytesWritten; }

	void write(in ubyte[] bytes, bool do_flush = true) 
	{
		enforce(m_out !is null, "OutputStream missing");
		m_out.write(bytes, do_flush);
		m_bytesWritten += bytes.length;
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		enforce(m_out !is null, "OutputStream missing");
		writeDefault(stream, nbytes, do_flush);
	}

	void flush() { enforce(m_out !is null, "OutputStream missing"); m_out.flush(); }
	void finalize() { enforce(m_out !is null, "OutputStream missing"); m_out.flush(); }
}

/**
	Wraps an existing input stream, counting the bytes that are written.
*/
class CountingInputStream : InputStream {
	private {
		ulong m_bytesRead;
		InputStream m_in;
	}
	this(InputStream stream) {
		m_in = stream;
	}

	@property ulong bytesRead() const { return m_bytesRead; }

	@property bool empty() { enforce(m_in !is null, "InputStream missing"); return m_in.empty(); }
	@property ulong leastSize() { enforce(m_in !is null, "InputStream missing"); return m_in.leastSize();  }
	@property bool dataAvailableForRead() { return m_in.dataAvailableForRead; }
	const(ubyte)[] peek() { return m_in.peek(); }

	void read(ubyte[] dst)
	{
		enforce(m_in !is null, "InputStream missing");
		m_in.read(dst);
		m_bytesRead += dst.length;
	}
}