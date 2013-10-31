/**
	Stream proxy and wrapper facilities.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.wrapper;

public import vibe.core.stream;

import std.algorithm : min;
import std.exception;


/**
	Provides a way to access varying streams using a constant stream reference.
*/
class ProxyStream : Stream {
	private {
		Stream m_underlying;
	}

	/// The stream that is wrapped by this one
	@property inout(Stream) underlying() inout { return m_underlying; }
	/// ditto
	@property void underlying(Stream value) { m_underlying = value; }

	@property bool empty() { return m_underlying ? m_underlying.empty : true; }

	@property ulong leastSize() { return m_underlying ? m_underlying.leastSize : 0; }

	@property bool dataAvailableForRead() { return m_underlying ? m_underlying.dataAvailableForRead : false; }

	const(ubyte)[] peek() { return m_underlying.peek(); }

	void read(ubyte[] dst) { m_underlying.read(dst); }

	alias Stream.write write;
	void write(in ubyte[] bytes) { import vibe.core.log; logDebug("WRITE: %s", cast(string)bytes); m_underlying.write(bytes); }

	void flush() { m_underlying.flush(); }

	void finalize() { m_underlying.finalize(); }

	void write(InputStream stream, ulong nbytes = 0) { m_underlying.write(stream, nbytes); }
}


/**
	Implements an input range interface on top of an InputStream using an
	internal buffer.

	The buffer is GC allocated and is filled chunk wise. Thus an InputStream
	that has been wrapped in a StreamInputRange cannot be used reliably on its
	own anymore.

	Reading occurs in a fully lazy fashion. The first call to either front,
	popFront or empty will potentially trigger waiting for the next chunk of
	data to arrive - but especially popFront will not wait if it was called
	after a call to front. This property allows the range to be used in
	request-response scenarios.
*/
struct StreamInputRange {
	private {
		struct Buffer {
			ubyte[256] data = void;
			size_t fill = 0;
		}
		InputStream m_stream;
		Buffer* m_buffer;
	}

	this (InputStream stream)
	{
		m_stream = stream;
		m_buffer = new Buffer;
	}

	@property bool empty() { return !m_buffer.fill && m_stream.empty; }

	ubyte front()
	{
		if (m_buffer.fill < 1) readChunk();
		return m_buffer.data[$ - m_buffer.fill];
	}
	void popFront()
	{
		assert(!empty);
		if (m_buffer.fill < 1) readChunk();
		m_buffer.fill--;
	}

	private void readChunk()
	{
		auto sz = min(m_stream.leastSize, m_buffer.data.length);
		assert(sz > 0);
		m_stream.read(m_buffer.data[$-sz .. $]);
		m_buffer.fill = sz;
	}
}
