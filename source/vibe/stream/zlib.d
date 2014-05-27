/**
	Zlib input/output streams

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.zlib;

import vibe.core.stream;
import vibe.utils.array;
import vibe.utils.memory;

import std.algorithm;
import std.exception;
import etc.c.zlib;

import vibe.core.log;



/**
	Writes any data compressed in deflate format to the specified output stream.
*/
final class DeflateOutputStream : ZlibOutputStream {
	this(OutputStream dst)
	{
		super(dst, HeaderFormat.deflate);
	}
}


/**
	Writes any data compressed in gzip format to the specified output stream.
*/
final class GzipOutputStream : ZlibOutputStream {
	this(OutputStream dst)
	{
		super(dst, HeaderFormat.gzip);
	}
}

/**
	Generic zlib output stream.
*/
class ZlibOutputStream : OutputStream {
	private {
		OutputStream m_out;
		z_stream m_zstream;
		ubyte[1024] m_outbuffer;
		//ubyte[4096] m_inbuffer;
		bool m_finalized = false;
	}

	enum HeaderFormat {
		gzip,
		deflate
	}

	this(OutputStream dst, HeaderFormat type, int level = Z_DEFAULT_COMPRESSION)
	{
		m_out = dst;
		zlibEnforce(deflateInit2(&m_zstream, level, Z_DEFLATED, 15 + (type == HeaderFormat.gzip ? 16 : 0), 8, Z_DEFAULT_STRATEGY));
	}

	final void write(in ubyte[] data)
	{
		if (!data.length) return;
		assert(!m_finalized);
		assert(m_zstream.avail_in == 0);
		m_zstream.next_in = cast(ubyte*)data.ptr;
		assert(data.length < uint.max);
		m_zstream.avail_in = cast(uint)data.length;
		doFlush(Z_NO_FLUSH);
		assert(m_zstream.avail_in == 0);
		m_zstream.next_in = null;
	}

	final void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}

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
		zlibEnforce(deflateEnd(&m_zstream));
	}

	private final void doFlush(int how)
	{
		while (true) {
			m_zstream.next_out = m_outbuffer.ptr;
			m_zstream.avail_out = cast(uint)m_outbuffer.length;
			//logInfo("deflate %s -> %s (%s)", m_zstream.avail_in, m_zstream.avail_out, how);
			auto ret = deflate(&m_zstream, how);
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
class DeflateInputStream : ZlibInputStream {
	this(InputStream dst)
	{
		super(dst, HeaderFormat.deflate);
	}
}


/**
	Takes an input stream that contains data in gzip compressed format and outputs the
	uncompressed data.
*/
class GzipInputStream : ZlibInputStream {
	this(InputStream dst)
	{
		super(dst, HeaderFormat.gzip);
	}
}


/**
	Generic zlib input stream.
*/
class ZlibInputStream : InputStream {
	import std.zlib;
	private {
		InputStream m_in;
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

	this(InputStream src, HeaderFormat type)
	{
		m_in = src;
		if (m_in.empty) {
			m_finished = true;
		} else {
			int wndbits = 15;
			if(type == HeaderFormat.gzip) wndbits += 16;
			else if(type == HeaderFormat.automatic) wndbits += 32;
			zlibEnforce(inflateInit2(&m_zstream, wndbits));
			readChunk();
		}
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

	void read(ubyte[] dst)
	{
		enforce(dst.length == 0 || !empty, "Reading empty stream");

		while (dst.length > 0) {
			auto len = min(m_outbuffer.length, dst.length);
			m_outbuffer.read(dst[0 .. len]);
			dst = dst[len .. $];

			if (!m_outbuffer.length && !m_finished) readChunk();
			enforce(dst.length == 0 || !m_finished, "Reading past end of zlib stream.");
		}
	}

	void readChunk()
	{
		assert(m_outbuffer.length == 0, "Buffer must be empty to read the next chunk.");
		assert(m_outbuffer.peekDst().length > 0);
		enforce (!m_finished, "Reading past end of zlib stream.");

		m_zstream.next_out = m_outbuffer.peekDst().ptr;
		m_zstream.avail_out = cast(uint)m_outbuffer.peekDst().length;

		while (!m_outbuffer.length) {
			if (m_zstream.avail_in == 0) {
				auto clen = min(m_inbuffer.length, m_in.leastSize);
				m_in.read(m_inbuffer[0 .. clen]);
				m_zstream.next_in = m_inbuffer.ptr;
				m_zstream.avail_in = cast(uint)clen;
			}
			auto avins = m_zstream.avail_in;
			//logInfo("inflate %s -> %s (@%s in @%s)", m_zstream.avail_in, m_zstream.avail_out, m_ninflated, n_read);
			auto ret = zlibEnforce(inflate(&m_zstream, Z_SYNC_FLUSH));
			//logInfo("    ... %s -> %s", m_zstream.avail_in, m_zstream.avail_out);
			assert(m_zstream.avail_out != m_outbuffer.peekDst.length || m_zstream.avail_in != avins);
			m_ninflated += m_outbuffer.peekDst().length - m_zstream.avail_out;
			n_read += avins - m_zstream.avail_in;
			m_outbuffer.putN(m_outbuffer.peekDst().length - m_zstream.avail_out);
			assert(m_zstream.avail_out == 0 || m_zstream.avail_out == m_outbuffer.peekDst().length);

			if (ret == Z_STREAM_END) {
				m_finished = true;
				assert(m_in.empty, "Input expected to be empty at this point.");
				return;
			}
		}
	}
}

private int zlibEnforce(int result)
{
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