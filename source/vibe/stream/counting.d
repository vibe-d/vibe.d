/**
	Wrapper streams which count the number of bytes or limit the stream based on the number of
	transferred bytes.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.counting;

public import vibe.stream.stream;

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