/**
	Wrapper streams which count the number of bytes or limit the stream based on the number of
	transferred bytes.

	Copyright: © 2012-2017 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.counting;

public import vibe.core.stream;

import std.algorithm.mutation : move, swap;
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
LimitedInputStream!InputStream createLimitedInputStream(InputStream)(InputStream stream, ulong byte_limit, bool silent_limit = false)
	if (isInputStream!InputStream)
{
	return new LimitedInputStream!InputStream(stream.move, byte_limit, silent_limit, true);
}


/** Creates a proxy stream that counts the number of bytes written.

	Params:
		output = The stream to forward the written data to
		byte_limit = Optional total write size limit after which an exception is thrown
*/
CountingOutputStream!OutputStream createCountingOutputStream(OutputStream)(OutputStream output, ulong byte_limit = ulong.max)
	if (isOutputStream!OutputStream)
{
	return new CountingOutputStream!OutputStream(output.move, byte_limit);
}
/// ditto
CountingOutputStream!OutputStream createCountingOutputStream(OutputStream)(OutputStream output, ulong byte_limit, ulong* counter)
	if (isOutputStream!OutputStream)
{
	return new CountingOutputStream!OutputStream(output.move, byte_limit, counter);
}


/** Creates a proxy stream that counts the number of bytes written.

	Params:
		output = The stream to forward the written data to
		byte_limit = Optional total write size limit after which an exception is thrown
*/
CountingInputStream!InputStream createCountingInputStream(InputStream)(InputStream input, ulong byte_limit = ulong.max)
	if (isInputStream!InputStream)
{
	return new CountingInputStream!InputStream(input.move, byte_limit, true);
}


/** Creates a stream that fires a callback once the end of the underlying input stream is reached.

	Params:
		input = Source stream to read from
		callback = The callback that is invoked one the source stream has been drained
*/
EndCallbackInputStream!InputStream createEndCallbackInputStream(InputStream)(InputStream input, void delegate() @safe callback)
	if (isInputStream!InputStream)
{
	return new EndCallbackInputStream!InputStream(input.move, callback, true);
}


/**
	Wraps an existing stream, limiting the amount of data that can be read.
*/
class LimitedInputStream(IS = InputStream) : InputStream
	if (isInputStream!IS)
{
@safe:

	private {
		IS m_input;
		ulong m_sizeLimit;
		bool m_silentLimit;
	}

	void delegate() @safe onSizeLimitReached;

	/// private
	this(IS stream, ulong byte_limit, bool silent_limit, bool dummy)
	{
		static if (is(typeof(!!stream)))
			assert(!!stream);
		swap(m_input, stream);
		m_sizeLimit = byte_limit;
		m_silentLimit = silent_limit;
		() @trusted { onSizeLimitReached = &throwLimitException; } ();
	}

	/// The stream that is wrapped by this one
	@property ref inout(IS) sourceStream() inout { return m_input; }

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

	alias InputStream.read read;

	protected void throwLimitException() @safe {
		throw new LimitException("Size limit reached", m_sizeLimit);
	}
}


/**
	Wraps an existing output stream, counting the bytes that are written.
*/
final class CountingOutputStream(OS) : OutputStream
	if (isOutputStream!OS)
{
@safe:
	private {
		ulong m_bytesWritten;
		ulong* m_pbytesWritten;
		ulong m_writeLimit;
		OS m_out;
	}

	/// private
	this(OS stream, ulong write_limit)
	{
		assert(!!stream);
		m_writeLimit = write_limit;
		swap(m_out, stream);
	}

	this(OS stream, ulong write_limit, ulong* counter)
	{
		assert(!!stream);
		m_writeLimit = write_limit;
		m_pbytesWritten = counter;
		swap(m_out, stream);
	}

	/// Returns the total number of bytes written.
	@property ulong bytesWritten() const { return m_pbytesWritten ? *m_pbytesWritten : m_bytesWritten; }

	/// The maximum number of bytes to write
	@property ulong writeLimit() const { return m_writeLimit; }
	/// ditto
	@property void writeLimit(ulong value) { m_writeLimit = value; }

	/** Manually increments the write counter without actually writing data.
	*/
	void increment(ulong bytes)
	{
		enforce(m_bytesWritten + bytes <= m_writeLimit, "Incrementing past end of output stream.");
		doIncrement(bytes);
	}

	size_t write(in ubyte[] bytes, IOMode mode)
	{
		enforce(m_bytesWritten + bytes.length <= m_writeLimit, "Writing past end of output stream.");

		auto ret = m_out.write(bytes, mode);
		doIncrement(ret);
		return ret;
	}

	alias OutputStream.write write;

	void flush() { m_out.flush(); }
	void finalize() { m_out.flush(); }

	private void doIncrement(ulong amt)
	{
		if (m_pbytesWritten) *m_pbytesWritten += amt;
		else m_bytesWritten += amt;
	}
}


/**
	Wraps an existing input stream, counting the bytes that are written.
*/
final class CountingInputStream(IS) : InputStream
	if (isInputStream!IS)
{
@safe:
	private {
		ulong m_bytesRead;
		IS m_in;
	}

	/// private
	this(IS stream, bool dummy)
	{
		assert(!!stream);
		swap(m_in, stream);
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

	alias InputStream.read read;
}

mixin validateInputStream!(CountingInputStream!InputStream);


/**
	Wraps an input stream and calls the given delegate once the stream is empty.

	Note that this function will potentially block after each read operation to
	see if the end has already been reached - this may take as long until either
	new data has arrived or until the connection was closed.

	The stream will also guarantee that the inner stream is not used after it
	has been determined to be empty. It can thus be safely deleted once the
	callback is invoked.
*/
final class EndCallbackInputStream(IS) : InputStream
	if (isInputStream!IS)
{
@safe:
	import std.typecons : Nullable;

	private {
		IS m_in;
		bool m_eof = false;
		void delegate() @safe m_callback;
	}

	/// private
	this(IS input, void delegate() @safe callback, bool dummy)
	{
		swap(m_in, input);
		m_callback = callback;
		checkEOF();
	}

	@property bool empty()
	{
		checkEOF();
		return !hasStream;
	}

	@property ulong leastSize()
	{
		checkEOF();
		if (hasStream) return m_in.leastSize();
		return 0;
	}

	@property bool dataAvailableForRead()
	{
		if (!hasStream) return false;
		return m_in.dataAvailableForRead;
	}

	const(ubyte)[] peek()
	{
		if (!hasStream) return null;
		return m_in.peek();
	}

	size_t read(scope ubyte[] dst, IOMode mode)
	{
		enforce(hasStream, "Reading past end of stream.");
		auto ret = m_in.read(dst, mode);
		checkEOF();
		return ret;
	}

	alias InputStream.read read;

	private void checkEOF()
	@safe {
		if (!m_eof) return;
		if (m_in.empty) {
			static if (is(typeof(!IS.init))) m_in = IS.init;
			else destroy(m_in);
			m_eof = true;
			m_callback();
		}
	}

	private bool hasStream()
	{
		return !m_eof;
	}
}

mixin validateInputStream!(EndCallbackInputStream!InputStream);

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
