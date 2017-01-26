/**
	Zlib input/output streams

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.zlib;

import vibe.core.stream;
import vibe.utils.array;
import vibe.internal.freelistref;
import vibe.internal.interfaceproxy : InterfaceProxy, interfaceProxy;

import std.algorithm;
import std.exception;
import etc.c.zlib;

import vibe.core.log;


/** Creates a new deflate uncompression stream.
*/
ZlibInputStream createDeflateInputStream(InputStream)(InputStream source) @safe
	if (isInputStream!InputStream)
{
	return new ZlibInputStream(interfaceProxy!(.InputStream)(source), ZlibInputStream.HeaderFormat.deflate, true);
}

/// private
FreeListRef!ZlibInputStream createDeflateInputStreamFL(InputStream)(InputStream source) @safe
	if (isInputStream!InputStream)
{
	return FreeListRef!ZlibInputStream(interfaceProxy!(.InputStream)(source), ZlibInputStream.HeaderFormat.deflate, true);
}

/** Creates a new deflate compression stream.
*/
ZlibOutputStream createDeflateOutputStream(OutputStream)(OutputStream destination) @safe
	if (isOutputStream!OutputStream)
{
	return new ZlibOutputStream(interfaceProxy!(.OutputStream)(destination), ZlibOutputStream.HeaderFormat.deflate, Z_DEFAULT_COMPRESSION, true);
}

/// private
FreeListRef!ZlibOutputStream createDeflateOutputStreamFL(OutputStream)(OutputStream destination) @safe
	if (isOutputStream!OutputStream)
{
	return FreeListRef!ZlibOutputStream(interfaceProxy!(.OutputStream)(destination), ZlibOutputStream.HeaderFormat.deflate, Z_DEFAULT_COMPRESSION, true);
}

/** Creates a new deflate uncompression stream.
*/
ZlibInputStream createGzipInputStream(InputStream)(InputStream source) @safe
	if (isInputStream!InputStream)
{
	return new ZlibInputStream(interfaceProxy!(.InputStream)(source), ZlibInputStream.HeaderFormat.gzip, true);
}

/// private
FreeListRef!ZlibInputStream createGzipInputStreamFL(InputStream)(InputStream source) @safe
	if (isInputStream!InputStream)
{
	return FreeListRef!ZlibInputStream(interfaceProxy!(.InputStream)(source), ZlibInputStream.HeaderFormat.gzip, true);
}

/** Creates a new deflate uncompression stream.
*/
ZlibOutputStream createGzipOutputStream(OutputStream)(OutputStream destination) @safe
	if (isOutputStream!OutputStream)
{
	return new ZlibOutputStream(interfaceProxy!(.OutputStream)(destination), ZlibOutputStream.HeaderFormat.gzip, Z_DEFAULT_COMPRESSION, true);
}

/// private
FreeListRef!ZlibOutputStream createGzipOutputStreamFL(OutputStream)(OutputStream destination) @safe
	if (isOutputStream!OutputStream)
{
	return FreeListRef!ZlibOutputStream(interfaceProxy!(.OutputStream)(destination), ZlibOutputStream.HeaderFormat.gzip, Z_DEFAULT_COMPRESSION, true);
}


/**
	Writes any data compressed in deflate format to the specified output stream.
*/
deprecated("Use createDeflateOutputStream instead.")
final class DeflateOutputStream : ZlibOutputStream {
	@safe this(OutputStream dst)
	{
		super(dst, HeaderFormat.deflate);
	}
}


/**
	Writes any data compressed in gzip format to the specified output stream.
*/
deprecated("Use createGzipOutputStream instead.")
final class GzipOutputStream : ZlibOutputStream {
	@safe this(OutputStream dst)
	{
		super(dst, HeaderFormat.gzip);
	}
}

/**
	Generic zlib output stream.
*/
class ZlibOutputStream : OutputStream {
@safe:

	private {
		InterfaceProxy!OutputStream m_out;
		z_stream m_zstream;
		ubyte[1024] m_outbuffer;
		//ubyte[4096] m_inbuffer;
		bool m_finalized = false;
	}

	enum HeaderFormat {
		gzip,
		deflate
	}

	deprecated("Use createGzipOutputStream/createDeflateOutputStream instead.")
	this(OutputStream dst, HeaderFormat type, int level = Z_DEFAULT_COMPRESSION)
	{
		this(interfaceProxy!OutputStream(dst), type, level, true);
	}

	/// private
	this(InterfaceProxy!OutputStream dst, HeaderFormat type, int level, bool dummy)
	{
		m_out = dst;
		zlibEnforce(() @trusted { return deflateInit2(&m_zstream, level, Z_DEFLATED, 15 + (type == HeaderFormat.gzip ? 16 : 0), 8, Z_DEFAULT_STRATEGY); } ());
	}

	~this() {
		if (!m_finalized)
			() @trusted { deflateEnd(&m_zstream); } ();
	}

	final size_t write(in ubyte[] data, IOMode mode)
	{
		// TODO: support IOMode!
		if (!data.length) return 0;
		assert(!m_finalized);
		assert(m_zstream.avail_in == 0);
		m_zstream.next_in = () @trusted { return cast(ubyte*)data.ptr; } ();
		assert(data.length < uint.max);
		m_zstream.avail_in = cast(uint)data.length;
		doFlush(Z_NO_FLUSH);
		assert(m_zstream.avail_in == 0);
		m_zstream.next_in = null;
		return data.length;
	}

	alias write = OutputStream.write;

	final void flush()
	{
		assert(!m_finalized);
		//doFlush(Z_SYNC_FLUSH);
		m_out.flush();
	}

	final void finalize()
	{
		if (m_finalized) return;
		m_finalized = true;
		doFlush(Z_FINISH);
		m_out.flush();
		zlibEnforce(() @trusted { return deflateEnd(&m_zstream); }());
	}

	private final void doFlush(int how)
	@safe {
		while (true) {
			m_zstream.next_out = &m_outbuffer[0];
			m_zstream.avail_out = cast(uint)m_outbuffer.length;
			//logInfo("deflate %s -> %s (%s)", m_zstream.avail_in, m_zstream.avail_out, how);
			auto ret = () @trusted { return deflate(&m_zstream, how); } ();
			//logInfo("    ... %s -> %s", m_zstream.avail_in, m_zstream.avail_out);
			switch (ret) {
				default:
					zlibEnforce(ret);
					assert(false, "Unknown return value for zlib deflate.");
				case Z_OK:
					assert(m_zstream.avail_out < m_outbuffer.length || m_zstream.avail_in == 0);
					m_out.write(m_outbuffer[0 .. m_outbuffer.length - m_zstream.avail_out]);
					break;
				case Z_BUF_ERROR:
					assert(m_zstream.avail_in == 0);
					return;
				case Z_STREAM_END:
					assert(how == Z_FINISH);
					m_out.write(m_outbuffer[0 .. m_outbuffer.length - m_zstream.avail_out]);
					return;
			}
		}
	}
}


/**
	Takes an input stream that contains data in deflate compressed format and outputs the
	uncompressed data.
*/
deprecated("Use createDeflateInputStream instead.")
class DeflateInputStream : ZlibInputStream {
	@safe this(InputStream dst)
	{
		super(dst, HeaderFormat.deflate);
	}
}


/**
	Takes an input stream that contains data in gzip compressed format and outputs the
	uncompressed data.
*/
deprecated("Use createGzipInputStream instead.")
class GzipInputStream : ZlibInputStream {
	this(InputStream dst)
	@safe {
		super(dst, HeaderFormat.gzip);
	}
}

unittest {
	import vibe.stream.memory;
	import vibe.stream.operations;

	auto raw = cast(ubyte[])"Hello, World!\n".dup;
	ubyte[] gzip = [
		0x1F, 0x8B, 0x08, 0x08, 0xAF, 0x12, 0x42, 0x56, 0x00, 0x03, 0x74, 0x65, 0x73, 0x74, 0x2E, 0x74,
		0x78, 0x74, 0x00, 0xF3, 0x48, 0xCD, 0xC9, 0xC9, 0xD7, 0x51, 0x08, 0xCF, 0x2F, 0xCA, 0x49, 0x51,
		0xE4, 0x02, 0x00, 0x84, 0x9E, 0xE8, 0xB4, 0x0E, 0x00, 0x00, 0x00];

	auto gzipin = createGzipInputStream(createMemoryStream(gzip));
	assert(gzipin.readAll() == raw);
}

unittest {
	import vibe.stream.memory;
	import vibe.stream.operations;

	ubyte[] gzip_partial = [
		0x1F, 0x8B, 0x08, 0x08, 0xAF, 0x12, 0x42, 0x56, 0x00, 0x03, 0x74, 0x65, 0x73, 0x74, 0x2E, 0x74,
		0x78, 0x74, 0x00, 0xF3, 0x48, 0xCD, 0xC9, 0xC9, 0xD7, 0x51, 0x08, 0xCF, 0x2F, 0xCA, 0x49, 0x51,
	];

	auto gzipin = createGzipInputStream(createMemoryStream(gzip_partial));
	try {
		gzipin.readAll();
		assert(false, "Expected exception.");
	} catch (Exception e) {}
	assert(gzipin.empty);
}

/**
	Generic zlib input stream.
*/
class ZlibInputStream : InputStream {
@safe:

	import std.zlib;
	private {
		InterfaceProxy!InputStream m_in;
		z_stream m_zstream;
		FixedRingBuffer!(ubyte, 4096) m_outbuffer;
		ubyte[1024] m_inbuffer;
		bool m_finished = false;
		ulong m_ninflated, n_read;
	}

	enum HeaderFormat {
		gzip,
		deflate,
		automatic
	}

	deprecated("Use createGzipInputStream/createDeflateInputStream instead.")
	this(InputStream src, HeaderFormat type)
	{
		this(interfaceProxy!InputStream(src), type, true);
	}

	/// private
	this(InterfaceProxy!InputStream src, HeaderFormat type, bool dummy)
	{
		m_in = src;
		if (m_in.empty) {
			m_finished = true;
		} else {
			int wndbits = 15;
			if(type == HeaderFormat.gzip) wndbits += 16;
			else if(type == HeaderFormat.automatic) wndbits += 32;
			zlibEnforce(() @trusted { return inflateInit2(&m_zstream, wndbits); } ());
			readChunk();
		}
	}

	~this() {
		if (!m_finished)
			() @trusted { inflateEnd(&m_zstream); } ();
	}

	@property bool empty() { return this.leastSize == 0; }

	@property ulong leastSize()
	{
		assert(!m_finished || m_in.empty, "Input contains more data than expected.");
		if (m_outbuffer.length > 0) return m_outbuffer.length;
		if (m_finished) return 0;
		readChunk();
		assert(m_outbuffer.length || m_finished);

		return m_outbuffer.length;
	}

	@property bool dataAvailableForRead()
	{
		return m_outbuffer.length > 0;
	}

	const(ubyte)[] peek() { return m_outbuffer.peek(); }

	size_t read(scope ubyte[] dst, IOMode mode)
	{
		enforce(dst.length == 0 || !empty, "Reading empty stream");

		size_t nread = 0;

		while (dst.length > 0) {
			auto len = min(m_outbuffer.length, dst.length);
			m_outbuffer.read(dst[0 .. len]);
			dst = dst[len .. $];

			nread += len;

			if (!m_outbuffer.length && !m_finished) {
				if (mode == IOMode.immediate || mode == IOMode.once && !nread)
					break;
				readChunk();
			}
			enforce(dst.length == 0 || m_outbuffer.length || !m_finished, "Reading past end of zlib stream.");
		}

		return nread;
	}

	alias read = InputStream.read;

	private void readChunk()
	@safe {
		assert(m_outbuffer.length == 0, "Buffer must be empty to read the next chunk.");
		assert(m_outbuffer.peekDst().length > 0);
		enforce (!m_finished, "Reading past end of zlib stream.");

		m_zstream.next_out = &m_outbuffer.peekDst()[0];
		m_zstream.avail_out = cast(uint)m_outbuffer.peekDst().length;

		while (!m_outbuffer.length) {
			if (m_zstream.avail_in == 0) {
				auto clen = min(m_inbuffer.length, m_in.leastSize);
				if (clen == 0) {
					m_finished = true;
					throw new Exception("Premature end of compressed input.");
				}
				m_in.read(m_inbuffer[0 .. clen]);
				m_zstream.next_in = &m_inbuffer[0];
				m_zstream.avail_in = cast(uint)clen;
			}
			auto avins = m_zstream.avail_in;
			//logInfo("inflate %s -> %s (@%s in @%s)", m_zstream.avail_in, m_zstream.avail_out, m_ninflated, n_read);
			auto ret = zlibEnforce(() @trusted { return inflate(&m_zstream, Z_SYNC_FLUSH); } ());
			//logInfo("    ... %s -> %s", m_zstream.avail_in, m_zstream.avail_out);
			assert(m_zstream.avail_out != m_outbuffer.peekDst.length || m_zstream.avail_in != avins);
			m_ninflated += m_outbuffer.peekDst().length - m_zstream.avail_out;
			n_read += avins - m_zstream.avail_in;
			m_outbuffer.putN(m_outbuffer.peekDst().length - m_zstream.avail_out);
			assert(m_zstream.avail_out == 0 || m_zstream.avail_out == m_outbuffer.peekDst().length);

			if (ret == Z_STREAM_END) {
				m_finished = true;
				zlibEnforce(() @trusted { return inflateEnd(&m_zstream); }());
				assert(m_in.empty, "Input expected to be empty at this point.");
				return;
			}
		}
	}
}

unittest {
	import vibe.stream.memory;

	auto data = new ubyte[5000];

	auto mos = createMemoryOutputStream();
	auto gos = createGzipOutputStream(mos);
	gos.write(data);
	gos.finalize();

	auto ms = createMemoryStream(mos.data, false);
	auto gis = createGzipInputStream(ms);

	auto result = new ubyte[data.length];
	gis.read(result);
	assert(data == result);
}

private int zlibEnforce(int result)
@safe {
	switch (result) {
		default:
			if (result < 0) throw new Exception("unknown zlib error");
			else return result;
		case Z_ERRNO: throw new Exception("zlib errno error");
		case Z_STREAM_ERROR: throw new Exception("zlib stream error");
		case Z_DATA_ERROR: throw new Exception("zlib data error");
		case Z_MEM_ERROR: throw new Exception("zlib memory error");
		case Z_BUF_ERROR: throw new Exception("zlib buffer error");
		case Z_VERSION_ERROR: throw new Exception("zlib version error");
	}
}
