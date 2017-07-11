/**
	Stream proxy and wrapper facilities.

	Copyright: © 2013-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.wrapper;

public import vibe.core.stream;

import std.algorithm : min;
import std.exception;
import core.time;
import vibe.internal.interfaceproxy;
import vibe.internal.freelistref : FreeListRef;


ProxyStream createProxyStream(Stream)(Stream stream)
	if (isStream!Stream)
{
	return new ProxyStream(interfaceProxy!(.Stream)(stream), true);
}

ProxyStream createProxyStream(InputStream, OutputStream)(InputStream input, OutputStream output)
	if (isInputStream!InputStream && isOutputStream!OutputStream)
{
	return new ProxyStream(interfaceProxy!(.InputStream)(input), interfaceProxy!(.OutputStream)(output), true);
}

ConnectionProxyStream createConnectionProxyStream(Stream, ConnectionStream)(Stream stream, ConnectionStream connection_stream)
	if (isStream!Stream && isConnectionStream!ConnectionStream)
{
	mixin validateStream!Stream;
	mixin validateConnectionStream!ConnectionStream;
	return new ConnectionProxyStream(interfaceProxy!(.Stream)(stream), interfaceProxy!(.ConnectionStream)(connection_stream), true);
}

/// private
FreeListRef!ConnectionProxyStream createConnectionProxyStreamFL(Stream, ConnectionStream)(Stream stream, ConnectionStream connection_stream)
	if (isStream!Stream && isConnectionStream!ConnectionStream)
{
	mixin validateStream!Stream;
	mixin validateConnectionStream!ConnectionStream;
	return FreeListRef!ConnectionProxyStream(interfaceProxy!(.Stream)(stream), interfaceProxy!(.ConnectionStream)(connection_stream), true);
}

ConnectionProxyStream createConnectionProxyStream(InputStream, OutputStream, ConnectionStream)(InputStream input, OutputStream output, ConnectionStream connection_stream)
	if (isInputStream!InputStream && isOutputStream!OutputStream && isConnectionStream!ConnectionStream)
{
	return new ConnectionProxyStream(interfaceProxy!(.InputStream)(input), interfaceProxy!(.OutputStream)(output), interfaceProxy!(.ConnectionStream)(connection_stream), true);
}


/**
	Provides a way to access varying streams using a constant stream reference.
*/
class ProxyStream : Stream {
@safe:
	private {
		InterfaceProxy!(.InputStream) m_input;
		InterfaceProxy!(.OutputStream) m_output;
		InterfaceProxy!(.Stream) m_underlying;
	}

	deprecated("Use createProxyStream instead.")
	this(Stream stream = null)
	{
		m_underlying = interfaceProxy!Stream(stream);
		m_input = interfaceProxy!InputStream(stream);
		m_output = interfaceProxy!OutputStream(stream);
	}

	deprecated("Use createProxyStream instead.")
	this(InputStream input, OutputStream output)
	{
		m_input = interfaceProxy!InputStream(input);
		m_output = interfaceProxy!OutputStream(output);
	}

	/// private
	this(InterfaceProxy!Stream stream, bool dummy)
	{
		m_underlying = stream;
		m_input = stream;
		m_output = stream;
	}

	/// private
	this(InterfaceProxy!InputStream input, InterfaceProxy!OutputStream output, bool dummy)
	{
		m_input = input;
		m_output = output;
	}

	/// The stream that is wrapped by this one
	@property inout(InterfaceProxy!Stream) underlying() inout { return m_underlying; }
	/// ditto
	@property void underlying(InterfaceProxy!Stream value) { m_underlying = value; m_input = value; m_output = value; }
	/// ditto
	static if (!is(Stream == InterfaceProxy!Stream))
		@property void underlying(Stream value) { this.underlying = interfaceProxy!Stream(value); }

	@property bool empty() { return m_input ? m_input.empty : true; }

	@property ulong leastSize() { return m_input ? m_input.leastSize : 0; }

	@property bool dataAvailableForRead() { return m_input ? m_input.dataAvailableForRead : false; }

	const(ubyte)[] peek() { return m_input.peek(); }

	size_t read(scope ubyte[] dst, IOMode mode) { return m_input.read(dst, mode); }

	alias read = Stream.read;

	size_t write(in ubyte[] bytes, IOMode mode) { return m_output.write(bytes, mode); }

	alias write = Stream.write;

	void flush() { m_output.flush(); }

	void finalize() { m_output.finalize(); }
}


/**
	Special kind of proxy stream for streams nested in a ConnectionStream.

	This stream will forward all stream operations to the selected stream,
	but will forward all connection related operations to the given
	ConnectionStream. This allows wrapping embedded streams, such as
	SSL streams in a ConnectionStream.
*/
class ConnectionProxyStream : ConnectionStream {
@safe:

	private {
		InterfaceProxy!ConnectionStream m_connection;
		InterfaceProxy!Stream m_underlying;
		InterfaceProxy!InputStream m_input;
		InterfaceProxy!OutputStream m_output;
	}

	deprecated("Use createConnectionProxyStream instead.")
	this(Stream stream, ConnectionStream connection_stream)
	{
		this(interfaceProxy!Stream(stream), interfaceProxy!ConnectionStream(connection_stream), true);
	}

	deprecated("Use createConnectionProxyStream instead.")
	this(InputStream input, OutputStream output, ConnectionStream connection_stream)
	{
		this(interfaceProxy!InputStream(input), interfaceProxy!OutputStream(output), interfaceProxy!ConnectionStream(connection_stream), true);
	}

	/// private
	this(InterfaceProxy!Stream stream, InterfaceProxy!ConnectionStream connection_stream, bool dummy)
	{
		assert(!!stream);
		m_underlying = stream;
		m_input = stream;
		m_output = stream;
		m_connection = connection_stream;
	}

	/// private
	this(InterfaceProxy!InputStream input, InterfaceProxy!OutputStream output, InterfaceProxy!ConnectionStream connection_stream, bool dummy)
	{
		m_input = input;
		m_output = output;
		m_connection = connection_stream;
	}

	@property bool connected()
	const {
		if (!m_connection)
			return true;

		return m_connection.connected;
	}

	void close()
	{
		if (!m_connection)
			return;

		if (m_connection.connected) finalize();
		m_connection.close();
	}

	bool waitForData(Duration timeout = 0.seconds)
	{
		if (this.dataAvailableForRead) return true;

		if (!m_connection)
			return timeout == 0.seconds ? !this.empty : false;

		return m_connection.waitForData(timeout);
	}

	/// The stream that is wrapped by this one
	@property inout(InterfaceProxy!Stream) underlying() inout { return m_underlying; }
	/// ditto
	@property void underlying(InterfaceProxy!Stream value) { m_underlying = value; m_input = value; m_output = value; }
	/// ditto
	static if (!is(Stream == InterfaceProxy!Stream))
		@property void underlying(Stream value) { this.underlying = InterfaceProxy!Stream(value); }

	@property bool empty() { return m_input ? m_input.empty : true; }

	@property ulong leastSize() { return m_input ? m_input.leastSize : 0; }

	@property bool dataAvailableForRead() { return m_input ? m_input.dataAvailableForRead : false; }

	const(ubyte)[] peek() { return m_input.peek(); }

	size_t read(scope ubyte[] dst, IOMode mode) { return m_input.read(dst, mode); }

	alias read = ConnectionStream.read;

	size_t write(in ubyte[] bytes, IOMode mode) { return m_output.write(bytes, mode); }

	alias write = ConnectionStream.write;

	void flush() { m_output.flush(); }

	void finalize() { m_output.finalize(); }
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
@safe:

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
StreamOutputRange!OutputStream StreamOutputRange()(OutputStream stream) { return StreamOutputRange!OutputStream(stream); }
/// ditto
struct StreamOutputRange(OutputStream, size_t buffer_size = 256)
	if (isOutputStream!OutputStream)
{
@safe:

	private {
		OutputStream m_stream;
		size_t m_fill = 0;
		ubyte[buffer_size] m_data = void;
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

	void drop()
	{
		m_fill = 0;
	}

	void put(ubyte bt)
	{
		m_data[m_fill++] = bt;
		if (m_fill >= m_data.length) flush();
	}

	void put(const(ubyte)[] bts)
	{
		// avoid writing more chunks than necessary
		if (bts.length + m_fill >= m_data.length * 2) {
			flush();
			m_stream.write(bts);
			return;
		}

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

	void put(dchar elem)
	{
		import std.utf;
		char[4] chars;
		auto len = encode(chars, elem);
		put(chars[0 .. len]);
	}

	void put(const(dchar)[] elems) { foreach( ch; elems ) put(ch); }
}
/// ditto
auto streamOutputRange(size_t buffer_size = 256, OutputStream)(OutputStream stream)
	if (isOutputStream!OutputStream)
{
	return StreamOutputRange!(OutputStream, buffer_size)(stream);
}

unittest {
	static long writeLength(ARGS...)(ARGS args) {
		import vibe.stream.memory;
		auto dst = createMemoryOutputStream;
		{
			auto rng = StreamOutputRange(dst);
			foreach (a; args) rng.put(a);
		}
		return dst.data.length;
	}
	assert(writeLength("hello", ' ', "world") == "hello world".length);
	assert(writeLength("h\u00E4llo", ' ', "world") == "h\u00E4llo world".length);
	assert(writeLength("hello", '\u00E4', "world") == "hello\u00E4world".length);
	assert(writeLength("h\u1000llo", '\u1000', "world") == "h\u1000llo\u1000world".length);
	auto test = "häl";
	assert(test.length == 4);
	assert(writeLength(test[0], test[1], test[2], test[3]) == test.length);
}
