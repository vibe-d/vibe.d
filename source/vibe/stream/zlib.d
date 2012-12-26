/**
	Zlib input/output streams

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.zlib;

import vibe.core.stream;
import vibe.utils.memory;

import std.algorithm;
import std.exception;
import std.zlib;


/**
	Writes any data compressed in deflate format to the specified output stream.
*/
class DeflateOutputStream : ZlibOutputStream {
	this(OutputStream dst)
	{
		super(dst, HeaderFormat.deflate);
	}
}


/**
	Writes any data compressed in gzip format to the specified output stream.
*/
class GzipOutputStream : ZlibOutputStream {
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
		FreeListRef!Compress m_comp;
	}

	this(OutputStream dst, HeaderFormat type)
	{
		m_out = dst;
		m_comp = FreeListRef!Compress(type);
	}

	void write(in ubyte[] data, bool do_flush = true)
	{
		auto ret = m_comp.compress(data);
		if( ret.length )
			m_out.write(cast(ubyte[])ret, do_flush);
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}

	void flush()
	{
		//m_out.write(cast(ubyte[])m_comp.flush(Z_SYNC_FLUSH));
		m_out.flush();
	}

	void finalize()
	{
		auto ret = m_comp.flush(Z_FINISH);
		if( ret.length > 0 )
			m_out.write(cast(ubyte[])ret);
		m_out.flush();
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
	private {
		InputStream m_in;
		FreeListRef!UnCompress m_uncomp;
		ubyte[] m_buffer;
		bool m_finished = false;
	}

	this(InputStream src, HeaderFormat type)
	{
		m_in = src;
		m_uncomp = FreeListRef!UnCompress(type);
	}

	@property bool empty()
	{
		assert(!m_finished || m_in.empty);
		return m_finished && m_buffer.length == 0;
	}

	@property ulong leastSize()
	{
		if( m_buffer.length ) return m_buffer.length;
		if( m_finished ){
			assert(m_in.empty);
			return 0;
		}
		readChunk();
		assert(m_buffer.length || empty);
		return m_buffer.length;
	}

	@property bool dataAvailableForRead()
	{
		return m_buffer.length > 0 || m_in.dataAvailableForRead;
	}

	const(ubyte)[] peek()
	{
		return m_buffer;
	}

	void read(ubyte[] dst)
	{
		enforce(dst.length == 0 || !empty, "Reading empty stream");
		while( dst.length > 0 ){
			enforce(!empty, "Reading zlib stream past EOS");
			size_t sz = min(m_buffer.length, dst.length);
			dst[0 .. sz] = m_buffer[0 .. sz];
			dst = dst[sz .. $];
			m_buffer = m_buffer[sz .. $];
			if( !m_buffer.length ){
				assert(!dst.length || !m_finished, "Bug: UnCompress returned an empty buffer but more is still to be read.");
				if( !m_finished ) readChunk();
			}
		}
	}

	private void readChunk()
	{
		assert(m_buffer.length == 0, "readChunk called before buffer was emptied");
		assert(!m_finished, "readChunk called after zlib stream was finished.");
		auto chunk = new ubyte[4096];
		while(!m_in.empty && m_buffer.length == 0){
			auto sz = min(m_in.leastSize, 4096);
			m_in.read(chunk[0 .. sz]);
			m_buffer = cast(ubyte[])m_uncomp.uncompress(chunk[0 .. sz]);
		}

		if( m_buffer.length == 0 ){
			m_buffer = cast(ubyte[])m_uncomp.flush();
			m_finished = true;
		}
	}
}
