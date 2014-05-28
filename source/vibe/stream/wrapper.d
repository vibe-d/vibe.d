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
import core.time;


/**
	Provides a way to access varying streams using a constant stream reference.
*/
class ProxyStream : Stream {
	private {
		InputStream m_input;
		OutputStream m_output;
		Stream m_underlying;
	}

	this(Stream stream = null)
	{
		m_underlying = stream;
		m_input = stream;
		m_output = stream;
	}

	this(InputStream input, OutputStream output)
	{
		m_input = input;
		m_output = output;
	}

	/// The stream that is wrapped by this one
	@property inout(Stream) underlying() inout { return m_underlying; }
	/// ditto
	@property void underlying(Stream value) { m_underlying = value; m_input = value; m_output = value; }

	@property bool empty() { return m_input ? m_input.empty : true; }

	@property ulong leastSize() { return m_input ? m_input.leastSize : 0; }

	@property bool dataAvailableForRead() { return m_input ? m_input.dataAvailableForRead : false; }

	const(ubyte)[] peek() { return m_input.peek(); }

	void read(ubyte[] dst) { m_input.read(dst); }

	void write(in ubyte[] bytes) { m_output.write(bytes); }

	void flush() { m_output.flush(); }

	void finalize() { m_output.finalize(); }

	void write(InputStream stream, ulong nbytes = 0) { m_output.write(stream, nbytes); }
}


/**
	Special kind of proxy stream for streams nested in a ConnectionStream.

	This stream will forward all stream operations to the selected stream,
	but will forward all connection related operations to the given
	ConnectionStream. This allows wrapping embedded streams, such as
	SSL streams in a ConnectionStream.
*/
class ConnectionProxyStream : ProxyStream, ConnectionStream {
	private {
		ConnectionStream m_connection;
	}

	this(Stream stream, ConnectionStream connection_stream)
	{
		super(stream);
		m_connection = connection_stream;
	}

	@property bool connected() const { return m_connection.connected; }

	void close()
	{
		if (m_connection.connected) finalize();
		m_connection.close();
	}

	bool waitForData(Duration timeout = 0.seconds)
	{
		if (this.dataAvailableForRead) return true;
		return m_connection.waitForData(timeout);
	}

	// for some reason DMD will complain if we don't wrap these here
	override void write(in ubyte[] bytes) { super.write(bytes); }
	override void flush() { super.flush(); }
	override void finalize() { super.finalize(); }
	override void write(InputStream stream, ulong nbytes = 0) { super.write(stream, nbytes); }
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


/**
	Implements a buffered output range interface on top of an OutputStream.
*/
struct StreamOutputRange {
	private {
		OutputStream m_stream;
		size_t m_fill = 0;
		ubyte[256] m_data = void;
	}

	@disable this(this);

	this(OutputStream stream)
	{
		m_stream = stream;
	}

	~this()
	{
		flush();
	}

	void flush()
	{
		if (m_fill == 0) return;
		m_stream.write(m_data[0 .. m_fill]);
		m_fill = 0;
	}

	void put(ubyte bt)
	{
		m_data[m_fill++] = bt;
		if (m_fill >= m_data.length) flush();
	}

	void put(const(ubyte)[] bts)
	{
		while (bts.length) {
			auto len = min(m_data.length - m_fill, bts.length);
			m_data[m_fill .. m_fill + len] = bts[0 .. len];
			m_fill += len;
			bts = bts[len .. $];
			if (m_fill >= m_data.length) flush();
		}
	}

	void put(char elem) { put(cast(ubyte)elem); }
	void put(const(char)[] elems) { put(cast(const(ubyte)[])elems); }

	void put(dchar elem) { import std.utf; char[4] chars; encode(chars, elem); put(chars); }
	void put(const(dchar)[] elems) { foreach( ch; elems ) put(ch); }
}