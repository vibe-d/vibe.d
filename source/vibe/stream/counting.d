/**
	Wrapper streams which count the number of bytes or limit the stream based on the number of
	transferred bytes.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.counting;

public import vibe.core.stream;

import std.exception;


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
		assert(stream !is null);
		m_input = stream;
		m_sizeLimit = byte_limit;
		m_silentLimit = silent_limit;
	}

	/// The stream that is wrapped by this one
	@property inout(InputStream) sourceStream() inout { return m_input; }

	@property bool empty() { return m_silentLimit ? m_input.empty : (m_sizeLimit == 0); }

	@property ulong leastSize() { if( m_silentLimit ) return m_input.leastSize; return m_sizeLimit; }

	@property bool dataAvailableForRead() { return m_input.dataAvailableForRead; }

	void increment(ulong bytes)
	{
		if( bytes > m_sizeLimit ) onSizeLimitReached();
		m_sizeLimit -= bytes;
	}

	const(ubyte)[] peek() { return m_input.peek(); }

	void read(ubyte[] dst)
	{
		if (dst.length > m_sizeLimit) onSizeLimitReached();
		m_input.read(dst);
		m_sizeLimit -= dst.length;
	}

	protected void onSizeLimitReached() {
		throw new LimitException("Size limit reached", m_sizeLimit);
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
	this(OutputStream stream)
	{
		assert(stream !is null);
		m_out = stream;
	}

	@property ulong bytesWritten() const { return m_bytesWritten; }

	void increment(ulong bytes)
	{
		m_bytesWritten += bytes;
	}

	void write(in ubyte[] bytes)
	{
		m_out.write(bytes);
		m_bytesWritten += bytes.length;
	}

	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}

	void flush() { m_out.flush(); }
	void finalize() { m_out.flush(); }
}

/**
	Wraps an existing input stream, counting the bytes that are written.
*/
class CountingInputStream : InputStream {
	private {
		ulong m_bytesRead;
		InputStream m_in;
	}
	this(InputStream stream)
	{
		assert(stream !is null);
		m_in = stream;
	}

	@property ulong bytesRead() const { return m_bytesRead; }

	@property bool empty() { return m_in.empty(); }
	@property ulong leastSize() { return m_in.leastSize();  }
	@property bool dataAvailableForRead() { return m_in.dataAvailableForRead; }

	void increment(ulong bytes)
	{
		m_bytesRead += bytes;
	}

	const(ubyte)[] peek() { return m_in.peek(); }

	void read(ubyte[] dst)
	{
		m_in.read(dst);
		m_bytesRead += dst.length;
	}
}

/**
	Wraps an input stream and calls the given delegate once the stream is empty.

	Note that this function will potentially block after each read operation to
	see if the end has already been reached - this may take as long until either
	new data has arrived or until the connection was closed.

	The stream will also guarantee that the inner stream is not used after it
	has been determined to be empty. It can thus be safely deleted once the
	callback is invoked.
*/
class EndCallbackInputStream : InputStream {
	private {
		InputStream m_in;
		bool m_eof = false;
		void delegate() m_callback;
	}

	this(InputStream input, void delegate() callback)
	{
		m_in = input;
		m_callback = callback;
		checkEOF();
	}

	@property bool empty()
	{
		checkEOF();
		return m_in is null;
	}

	@property ulong leastSize()
	{
		checkEOF();
		if( m_in ) return m_in.leastSize();
		return 0;
	}

	@property bool dataAvailableForRead()
	{
		if( !m_in ) return false;
		return m_in.dataAvailableForRead;
	}

	const(ubyte)[] peek()
	{
		if( !m_in ) return null;
		return m_in.peek();
	}

	void read(ubyte[] dst)
	{
		enforce(m_in !is null, "Reading past end of stream.");
		m_in.read(dst);
		checkEOF();
	}

	private void checkEOF()
	{
		if( !m_in ) return;
		if( m_in.empty ){
			m_in = null;
			m_callback();
		}
	}
}

class LimitException : Exception {
	private ulong m_limit;

	this(string message, ulong limit, Throwable next = null, string file = __FILE__, int line = __LINE__)
	{
		super(message, next, file, line);
	}

	/// The byte limit of the stream that emitted the exception
	@property ulong limit() const { return m_limit; }
}
