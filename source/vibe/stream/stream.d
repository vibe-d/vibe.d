/**
	Generic stream interface used by several stream-like classes.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.stream;

import vibe.core.log;

import std.array;
import std.algorithm;
import std.exception;
import std.datetime;

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

	/**	Fills the preallocated array 'bytes' with data from the stream.

		Throws: An exception if the operation reads past the end of the stream
	*/
	void read(ubyte[] dst);

	/**	Reads and returns a single line from the stream.

		Throws: An exception if either the stream end was hit without hitting a newline first, or
			if more than max_bytes have been read from the stream in case of max_bytes != 0.
	*/
	ubyte[] readLine(size_t max_bytes = 0, string linesep = "\r\n");

	ubyte[] readAll(size_t max_bytes = 0);

	protected final ubyte[] readLineDefault(size_t max_bytes = 0, in string linesep = "\r\n")
	{
		auto dst = appender!(ubyte[])();
		size_t n = 0, m = 0;
		while(true){
			enforce(!max_bytes || n++ < max_bytes, "Line too long!");
			enforce(!empty, "Unterminated line!");
			ubyte[1] bt;
			read(bt);
			if( bt[0] == linesep[m] ) m++;
			else {
				dst.put(cast(ubyte[])linesep[0 .. m]);
				dst.put(bt[]);
				m = 0;
			}
			if( m >= linesep.length ) break;
		}
		return dst.data;
	}

	protected final ubyte[] readAllDefault(size_t max_bytes)
	{
		auto dst = appender!(ubyte[])();
		auto buffer = new ubyte[64*1024];
		size_t n = 0, m = 0;
		while( !empty ){
			enforce(!max_bytes || n++ < max_bytes, "Data too long!");
			size_t chunk = cast(size_t)min(leastSize, buffer.length);
			logTrace("read pipe chunk %d", chunk);
			read(buffer[0 .. chunk]);
			dst.put(buffer[0 .. chunk]);
		}
		return dst.data;
	}
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
		write(cast(ubyte[])bytes, do_flush);
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
	void write(InputStream stream, ulong nbytes, bool do_flush = true)
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

	void read(ubyte[] dst)
	{
		if (dst.length > m_sizeLimit) onSizeLimitReached();
		m_input.read(dst);
		m_sizeLimit -= dst.length;
	}
	
	ubyte[] readLine(size_t max_bytes = 0, string linesep = "\r\n")
	{
		if( max_bytes != 0 && max_bytes < m_sizeLimit ){
			auto ret = m_input.readLine(max_bytes, linesep);
			m_sizeLimit -= ret.length + linesep.length;
			return ret;
		}
		return readLineDefault(max_bytes, linesep);
	}

	ubyte[] readAll(size_t max_bytes = 0) { return readAllDefault(max_bytes); }

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
	void finalize() { enforce(m_out !is null, "OutputStream missing"); m_out.finalize(); }
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

	void read(ubyte[] dst)
	{
		enforce(m_in !is null, "InputStream missing");
		m_in.read(dst);
		m_bytesRead += dst.length;
	}
	
	ubyte[] readLine(size_t max_bytes = 0, string linesep = "\r\n")
	{
		enforce(m_in !is null, "InputStream missing");
		auto ln = m_in.readLine(max_bytes, linesep);
		m_bytesRead += ln.length + linesep.length;
		return ln;
	}

	ubyte[] readAll(size_t max_bytes = 0) { return readAllDefault(max_bytes); }
}
