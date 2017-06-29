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
import vibe.internal.interfaceproxy;
import vibe.internal.freelistref : FreeListRef;


/** Constructs a limited stream from an existing input stream.

	Params:
		stream = the input stream to be wrapped
		byte_limit = the maximum number of bytes readable from the constructed stream
		silent_limit = if set, the stream will behave exactly like the original stream, but
			will throw an exception as soon as the limit is reached.
*/
LimitedInputStream createLimitedInputStream(InputStream)(InputStream stream, ulong byte_limit, bool silent_limit = false)
	if (isInputStream!InputStream)
{
	return new LimitedInputStream(interfaceProxy!(.InputStream)(stream), byte_limit, silent_limit, true);
}

/// private
FreeListRef!LimitedInputStream createLimitedInputStreamFL(InputStream)(InputStream stream, ulong byte_limit, bool silent_limit = false)
	if (isInputStream!InputStream)
{
	return FreeListRef!LimitedInputStream(interfaceProxy!(.InputStream)(stream), byte_limit, silent_limit, true);
}

/** Creates a proxy stream that counts the number of bytes written.

	Params:
		output = The stream to forward the written data to
		byte_limit = Optional total write size limit after which an exception is thrown
*/
CountingOutputStream createCountingOutputStream(OutputStream)(OutputStream output, ulong byte_limit = ulong.max)
	if (isOutputStream!OutputStream)
{
	return new CountingOutputStream(interfaceProxy!(.OutputStream)(output), byte_limit, true);
}

/// private
FreeListRef!CountingOutputStream createCountingOutputStreamFL(OutputStream)(OutputStream output, ulong byte_limit = ulong.max)
	if (isOutputStream!OutputStream)
{
	return FreeListRef!CountingOutputStream(interfaceProxy!(.OutputStream)(output), byte_limit, true);
}


/** Creates a stream that fires a callback once the end of the underlying input stream is reached.

	Params:
		input = Source stream to read from
		callback = The callback that is invoked one the source stream has been drained
*/
EndCallbackInputStream createEndCallbackInputStream(InputStream)(InputStream input, void delegate() @safe callback)
	if (isInputStream!InputStream)
{
	return new EndCallbackInputStream(interfaceProxy!(.InputStream)(input), callback, true);
}

/// private
FreeListRef!EndCallbackInputStream createEndCallbackInputStreamFL(InputStream)(InputStream input, void delegate() @safe callback)
	if (isInputStream!InputStream)
{
	return FreeListRef!EndCallbackInputStream(interfaceProxy!(.InputStream)(input), callback, true);
}


/**
	Wraps an existing stream, limiting the amount of data that can be read.
*/
class LimitedInputStream : InputStream {
@safe:

	private {
		InterfaceProxy!InputStream m_input;
		ulong m_sizeLimit;
		bool m_silentLimit;
	}

	deprecated("Use createLimitedInputStream instead.")
	this(InputStream stream, ulong byte_limit, bool silent_limit = false)
	{
		this(interfaceProxy!InputStream(stream), byte_limit, silent_limit, true);
	}

	/// private
	this(InterfaceProxy!InputStream stream, ulong byte_limit, bool silent_limit, bool dummy)
	{
		assert(!!stream);
		m_input = stream;
		m_sizeLimit = byte_limit;
		m_silentLimit = silent_limit;
	}

	/// The stream that is wrapped by this one
	@property inout(InterfaceProxy!InputStream) sourceStream() inout { return m_input; }

	@property bool empty() { return m_silentLimit ? m_input.empty : (m_sizeLimit == 0); }

	@property ulong leastSize() { if( m_silentLimit ) return m_input.leastSize; return m_sizeLimit; }

	@property bool dataAvailableForRead() { return m_input.dataAvailableForRead; }

	void increment(ulong bytes)
	{
		if( bytes > m_sizeLimit ) onSizeLimitReached();
		m_sizeLimit -= bytes;
	}

	const(ubyte)[] peek() { return m_input.peek(); }

	size_t read(scope ubyte[] dst, IOMode mode)
	{
		if (dst.length > m_sizeLimit) onSizeLimitReached();
		auto ret = m_input.read(dst, mode);
		m_sizeLimit -= ret;
		return ret;
	}

	alias read = InputStream.read;

	protected void onSizeLimitReached() @safe {
		throw new LimitException("Size limit reached", m_sizeLimit);
	}
}


/**
	Wraps an existing output stream, counting the bytes that are written.
*/
class CountingOutputStream : OutputStream {
@safe:

	private {
		ulong m_bytesWritten;
		ulong m_writeLimit;
		InterfaceProxy!OutputStream m_out;
	}

	deprecated("Use createCountingOutputStream instead.")
	this(OutputStream stream, ulong write_limit = ulong.max)
	{
		this(interfaceProxy!OutputStream(stream), write_limit, true);
	}

	/// private
	this(InterfaceProxy!OutputStream stream, ulong write_limit, bool dummy)
	{
		assert(!!stream);
		m_writeLimit = write_limit;
		m_out = stream;
	}

	/// Returns the total number of bytes written.
	@property ulong bytesWritten() const { return m_bytesWritten; }

	/// The maximum number of bytes to write
	@property ulong writeLimit() const { return m_writeLimit; }
	/// ditto
	@property void writeLimit(ulong value) { m_writeLimit = value; }

	/** Manually increments the write counter without actually writing data.
	*/
	void increment(ulong bytes)
	{
		enforce(m_bytesWritten + bytes <= m_writeLimit, "Incrementing past end of output stream.");
		m_bytesWritten += bytes;
	}

	size_t write(in ubyte[] bytes, IOMode mode)
	{
		enforce(m_bytesWritten + bytes.length <= m_writeLimit, "Writing past end of output stream.");

		auto ret = m_out.write(bytes, mode);
		m_bytesWritten += ret;
		return ret;
	}

	alias write = OutputStream.write;

	void flush() { m_out.flush(); }
	void finalize() { m_out.flush(); }
}


/**
	Wraps an existing input stream, counting the bytes that are written.
*/
class CountingInputStream : InputStream {
@safe:

	private {
		ulong m_bytesRead;
		InterfaceProxy!InputStream m_in;
	}

	deprecated("Use createCountingOutputStream instead.")
	this(InputStream stream)
	{
		this(interfaceProxy!InputStream(stream), true);
	}

	/// private
	this(InterfaceProxy!InputStream stream, bool dummy)
	{
		assert(!!stream);
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

	size_t read(scope ubyte[] dst, IOMode mode)
	{
		auto ret = m_in.read(dst, mode);
		m_bytesRead += ret;
		return ret;
	}

	alias read = InputStream.read;
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
@safe:

	private {
		InterfaceProxy!InputStream m_in;
		bool m_eof = false;
		void delegate() @safe m_callback;
	}

	deprecated("use createEndCallbackInputStream instead.")
	this(InputStream input, void delegate() @safe callback)
	{
		this(interfaceProxy!InputStream(input), callback, true);
	}

	/// private
	this(InterfaceProxy!InputStream input, void delegate() @safe callback, bool dummy)
	{
		m_in = input;
		m_callback = callback;
		checkEOF();
	}

	@property bool empty()
	{
		checkEOF();
		return !m_in;
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

	size_t read(scope ubyte[] dst, IOMode mode)
	{
		enforce(!!m_in, "Reading past end of stream.");
		auto ret = m_in.read(dst, mode);
		checkEOF();
		return ret;
	}

	alias read = InputStream.read;

	private void checkEOF()
	@safe {
		if( !m_in ) return;
		if( m_in.empty ){
			m_in = InterfaceProxy!InputStream.init;
			m_callback();
		}
	}
}

class LimitException : Exception {
@safe:

	private ulong m_limit;

	this(string message, ulong limit, Throwable next = null, string file = __FILE__, int line = __LINE__)
	{
		super(message, next, file, line);
	}

	/// The byte limit of the stream that emitted the exception
	@property ulong limit() const { return m_limit; }
}
