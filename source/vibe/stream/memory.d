/**
	In-memory streams

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.memory;

import vibe.core.stream;
import vibe.utils.array;
import vibe.utils.memory;

import std.algorithm;
import std.array;
import std.exception;
import std.typecons;


/** OutputStream that collects the written data in memory and allows to query it
	as a byte array.
*/
final class MemoryOutputStream : OutputStream {
	private {
		AllocAppender!(ubyte[]) m_destination;
	}

	this(Allocator alloc = defaultAllocator())
	{
		m_destination = AllocAppender!(ubyte[])(alloc);
	}

	/// An array with all data written to the stream so far.
	@property ubyte[] data() { return m_destination.data(); }

	/// Resets the stream to its initial state containing no data.
	void reset()
	{
		m_destination.reset();
	}

	/// Reserves space for data - useful for optimization.
	void reserve(size_t nbytes)
	{
		m_destination.reserve(nbytes);
	}

	void write(in ubyte[] bytes)
	{
		m_destination.put(bytes);
	}

	void flush()
	{
	}

	void finalize()
	{
	}

	void write(InputStream stream, ulong nbytes = 0)
	{
		writeDefault(stream, nbytes);
	}
}


/**
	Provides a random access stream interface for accessing an array of bytes.
*/
final class MemoryStream : RandomAccessStream {
	private {
		ubyte[] m_data;
		size_t m_size;
		bool m_writable;
		size_t m_ptr = 0;
		size_t m_peekWindow;
	}

	/** Creates a new stream with the given data array as its contents.

		Params:
			data = The data array
			writable = Flag that controls whether the data array may be changed
			initial_size = The initial value that size returns - the file can grow up to data.length in size
	*/
	this(ubyte[] data, bool writable = true, size_t initial_size = size_t.max)
	{
		m_data = data;
		m_size = min(initial_size, data.length);
		m_writable = writable;
		m_peekWindow = m_data.length;
	}

	/** Controls the maximum size of the array returned by peek().

		This property is mainly useful for debugging purposes.
	*/
	@property void peekWindow(size_t size) { m_peekWindow = size; }

	@property bool empty() { return leastSize() == 0; }
	@property ulong leastSize() { return m_size - m_ptr; }
	@property bool dataAvailableForRead() { return leastSize() > 0; }
	@property ulong size() const nothrow { return m_size; }
	@property size_t capacity() const nothrow { return m_data.length; }
	@property bool readable() const nothrow { return true; }
	@property bool writable() const nothrow { return m_writable; }

	void seek(ulong offset) { assert(offset <= m_size); m_ptr = cast(size_t)offset; }
	ulong tell() nothrow { return m_ptr; }
	const(ubyte)[] peek() { return m_data[m_ptr .. min(m_size, m_ptr+m_peekWindow)]; }

	void read(ubyte[] dst)
	{
		assert(dst.length <= leastSize);
		dst[] = m_data[m_ptr .. m_ptr+dst.length];
		m_ptr += dst.length;
	}

	void write(in ubyte[] bytes)
	{
		assert(writable);
		enforce(bytes.length <= m_data.length - m_ptr, "Size limit of memory stream reached.");
		m_data[m_ptr .. m_ptr+bytes.length] = bytes[];
		m_ptr += bytes.length;
		m_size = max(m_size, m_ptr);
	}

	void flush() {}
	void finalize() {}
	void write(InputStream stream, ulong nbytes = 0) { writeDefault(stream, nbytes); }
}
