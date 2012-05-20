/**
	Zlib input/output streams

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.zlib;

import vibe.stream.stream;

import std.algorithm;
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
		Compress m_comp;
	}

	this(OutputStream dst, HeaderFormat type)
	{
		m_out = dst;
		m_comp = new Compress(type);
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
		UnCompress m_uncomp;
		ubyte[] m_buffer;
	}

	this(InputStream src, HeaderFormat type)
	{
		m_in = src;
		m_uncomp = new UnCompress(type);
	}

	@property bool empty()
	{
		if( m_buffer.length ) return false;
		if( !m_in.empty ) return false;
		return true;
	}

	@property ulong leastSize()
	{
		if( m_buffer.length ) return m_buffer.length;
		if( m_in.empty ) return 0;
		readChunk();
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
		while( dst.length > 0 ){
			size_t sz = min(m_buffer.length, dst.length);
			dst[0 .. sz] = m_buffer[0 .. sz];
			dst = dst[sz .. $];
			m_buffer = m_buffer[sz .. $];
			if( !m_buffer.length ) readChunk();
		}
	}

	ubyte[] readLine(size_t max_bytes = 0, string linesep = "\r\n")
	{
		return readLineDefault(max_bytes, linesep);
	}

	ubyte[] readAll(size_t max_bytes = 0) { return readAllDefault(max_bytes); }


	private void readChunk()
	{
		assert(m_buffer.length == 0);
		auto chunk = new ubyte[4096];
		while(!m_in.empty && m_buffer.length == 0){
			auto sz = min(m_in.leastSize, 4096);
			m_in.read(chunk[0 .. sz]);
			m_buffer = cast(ubyte[])m_uncomp.uncompress(chunk[0 .. sz]);
		}

		if( m_buffer.length == 0 ){
			m_buffer = cast(ubyte[])m_uncomp.flush();
		}
	}
}
