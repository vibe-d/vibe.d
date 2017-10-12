/**
	Base64 encoding routines

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger, Sönke Ludwig
*/
module vibe.stream.base64;

import vibe.core.stream;

import std.base64;

/** Creates a Base64 encoding stream.max_bytes_per_line

	By default, the stream generates a MIME compatible Base64 encoding.

	Params:
		output = The output sink to which the encoded result is written.
		max_bytes_per_line = The maximum number of input bytes after which a
			line break is inserted into the output. Defaults to 57,
			according to the MIME standard.
*/
Base64OutputStreamImpl!(C62, C63, CPAD, OutputStream) createBase64OutputStream(char C62 = '+', char C63 = '/', char CPAD = '=', OutputStream)(OutputStream output, ulong max_bytes_per_line = 57)
	if (isOutputStream!OutputStream)
{
	return new Base64OutputStreamImpl!(C62, C63, CPAD, OutputStream)(output, max_bytes_per_line, true);
}

/** Creates a URL safe Base64 encoding stream (using '-' and '_' for non-alphabetic values).

	Params:
		output = The output sink to which the encoded result is written.
		max_bytes_per_line = The maximum number of input bytes after which a
			line break is inserted into the output. Defaults to 57,
			according to the MIME standard.
*/
Base64OutputStreamImpl!('-', '_', '=', OutputStream) createBase64URLOutputStream(OutputStream)(OutputStream output, ulong max_bytes_per_line = 57)
	if (isOutputStream!OutputStream)
{
	return craeteBase64OutputStream!('-', '_')(output, max_bytes_per_line);
}


/**
	MIME compatible Base64 encoding stream.
*/
alias Base64OutputStream = Base64OutputStreamImpl!('+', '/');

/**
	URL safe Base64 encoding stream (using '-' and '_' for non-alphabetic values).
*/
alias Base64URLOutputStream = Base64OutputStreamImpl!('-', '_');

/**
	Generic Base64 encoding output stream.

	The template arguments C62 and C63 determine which non-alphabetic characters
	are used to represent the 62nd and 63rd code units. CPAD is the character
	used for padding the end of the result if necessary.
*/
final class Base64OutputStreamImpl(char C62, char C63, char CPAD = '=', OutputStream = .OutputStream) : .OutputStream
	if (isOutputStream!OutputStream)
{
	private {
		OutputStream m_out;
		ulong m_maxBytesPerLine;
		ulong m_bytesInCurrentLine = 0;
	}

	private alias B64 = Base64Impl!(C62, C63, CPAD);

	deprecated("Use `createBase64OutputStream` or `createBase64URLOutputStream` instead.")
	this(OutputStream output, ulong max_bytes_per_line = 57)
	{
		this(output, max_bytes_per_line, true);
	}

	/// private
	this(OutputStream output, ulong max_bytes_per_line, bool dummy)
	{
		m_out = output;
		m_maxBytesPerLine = max_bytes_per_line;
	}


	size_t write(in ubyte[] bytes_, IOMode)
	@trusted { // StreamOutputRange is not @safe
		import vibe.stream.wrapper;

		const(ubyte)[] bytes = bytes_;

		auto rng = StreamOutputRange(m_out);

		size_t nwritten = 0;

		while (bytes.length > 0) {
			if (m_bytesInCurrentLine + bytes.length >= m_maxBytesPerLine) {
				size_t bts = cast(size_t)(m_maxBytesPerLine - m_bytesInCurrentLine);
				B64.encode(bytes[0 .. bts], &rng);
				rng.put("\r\n");
				bytes = bytes[bts .. $];
				m_bytesInCurrentLine = 0;
				nwritten += bts;
			} else {
				B64.encode(bytes, &rng);
				m_bytesInCurrentLine += bytes.length;
				nwritten += bytes.length;
				break;
			}
		}

		return nwritten;
	}

	alias write = .OutputStream.write;

	void flush()
	{
		m_out.flush();
	}

	void finalize()
	{
		flush();
	}
}

/+
/**
	MIME compatible Base64 decoding stream.
*/
alias Base64InputStream = Base64InputStreamImpl!('+', '/');

/**
	URL safe Base64 decoding stream (using '-' and '_' for non-alphabetic values).
*/
alias Base64URLInputStream = Base64InputStreamImpl!('-', '_');
class Base64InputStream(char C62, char C63, char CPAD = '=') : InputStream {
	private {
		InputStream m_in;
		FixedRingBuffer!(ubyte, 1024) m_buffer;
	}

	private alias B64 = Base64Impl!(C62, C63, CPAD);

	this(InputStream input)
	{
		m_in = input;
		fillBuffer();
	}

	bool empty() const { return m_buffer.empty; }
	ulong leastSize() const { return m_buffer.length; }
	const(ubyte)[] peek() const { return m_buffer.peek; }

	void read(ubyte[] dst)
	{
		ubyte[74] inbuf;
		while (!dst.empty) {
			enforce(!empty, "Reading past end of base-64 stream.");
			auto sz = min(dst.length, m_buffer.length);
			m_buffer.read(dst[0 .. sz]);
			dst = dst[sz .. $];
			fillBuffer();
		}
	}

	private void fillBuffer()
	{
		ubyte[74] buf;
		size_t buf_fill = 0;
		while (!m_buffer.full || !m_in.empty) {
			auto insz = m_in.leastSize;
			auto sz = min(insz, (m_buffer.freeSpace/3)*4);
			if (sz == 0) {
				m_in.read(buf[buf_fill .. buf_fill+insz]);
				buf_fill += insz;
			}
			auto csz = min(sz, buf.length);
			m_in.read(buf[0 .. csz])
			B64.decode();

			m_in.read(m_buffer.peekDst[0 .. min(sz, $)]);
		}
	}
}
+/

unittest {
	void test(in ubyte[] data, string encoded, ulong bytes_per_line = 57)
	{
		import vibe.stream.memory;
		auto encstr = createMemoryOutputStream();
		auto bostr = createBase64OutputStream(encstr, bytes_per_line);
		bostr.write(data);
		assert(encstr.data == encoded);
		/*encstr.seek(0);
		auto bistr = new Base64InputStream(encstr);
		assert(bistr.readAll() == data);*/
	}

	test([0x14, 0xfb, 0x9c, 0x03, 0xd9, 0x7e], "FPucA9l+");

	ubyte[200] data;
	foreach (i, ref b; data) b = (i * 1337) % 256;
	string encoded =
		"ADlyq+QdVo/IATpzrOUeV5DJAjt0reYfWJHKAzx1rucgWZLLBD12r+ghWpPMBT53sOkiW5TNBj94\r\n" ~
		"seojXJXOB0B5suskXZbPCEF6s+wlXpfQCUJ7tO0mX5jRCkN8te4nYJnSC0R9tu8oYZrTDEV+t/Ap\r\n" ~
		"YpvUDUZ/uPEqY5zVDkeAufIrZJ3WD0iBuvMsZZ7XEEmCu/QtZp/YEUqDvPUuZ6DZEkuEvfYvaKHa\r\n" ~
		"E0yFvvcwaaLbFE2Gv/gxaqPcFU6HwPkya6TdFk8=";
	test(data, encoded);
}
