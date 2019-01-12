/**
	In-memory streams

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.memory;

import vibe.core.stream;
import vibe.utils.array;
import vibe.internal.allocator;

import std.algorithm;
import std.array;
import std.exception;
import std.typecons;

MemoryOutputStream createMemoryOutputStream(IAllocator alloc = vibeThreadAllocator())
@safe nothrow {
	return new MemoryOutputStream(alloc, true);
}

/** Creates a new stream with the given data array as its contents.

	Params:
		data = The data array
		writable = Flag that controls whether the data array may be changed
		initial_size = The initial value that size returns - the file can grow up to data.length in size
*/
MemoryStream createMemoryStream(ubyte[] data, bool writable = true, size_t initial_size = size_t.max)
@safe nothrow {
	return new MemoryStream(data, writable, initial_size, true);
}


/** OutputStream that collects the written data in memory and allows to query it
	as a byte array.
*/
final class MemoryOutputStream : OutputStream {
@safe:

	private {
		AllocAppender!(ubyte[]) m_destination;
	}

	deprecated("Use createMemoryOutputStream isntead.")
	this(IAllocator alloc = vibeThreadAllocator())
	{
		this(alloc, true);
	}

	/// private
	this(IAllocator alloc, bool dummy)
	nothrow {
		m_destination = AllocAppender!(ubyte[])(alloc);
	}

	/// An array with all data written to the stream so far.
	@property ubyte[] data() nothrow { return m_destination.data(); }

	/// Resets the stream to its initial state containing no data.
	void reset(AppenderResetMode mode = AppenderResetMode.keepData)
	@system {
		m_destination.reset(mode);
	}

	/// Reserves space for data - useful for optimization.
	void reserve(size_t nbytes)
	{
		m_destination.reserve(nbytes);
	}

	size_t write(in ubyte[] bytes, IOMode)
	{
		() @trusted { m_destination.put(bytes); } ();
		return bytes.length;
	}

	alias write = OutputStream.write;

	void flush()
	nothrow {
	}

	void finalize()
	nothrow {
	}
}

mixin validateOutputStream!MemoryOutputStream;


/**
	Provides a random access stream interface for accessing an array of bytes.
*/
final class MemoryStream : RandomAccessStream {
@safe:

	private {
		ubyte[] m_data;
		size_t m_size;
		bool m_writable;
		size_t m_ptr = 0;
		size_t m_peekWindow;
	}

	deprecated("Use createMemoryStream instead.")
	this(ubyte[] data, bool writable = true, size_t initial_size = size_t.max)
	{
		this(data, writable, initial_size, true);
	}

	/// private
	this(ubyte[] data, bool writable, size_t initial_size, bool dummy)
	nothrow {
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

	void truncate(ulong size)
	{
		enforce(size < m_data.length, "Size limit of memory stream reached.");
		m_size = cast(size_t)size;
	}

	void seek(ulong offset) { assert(offset <= m_data.length); m_ptr = cast(size_t)offset; }
	ulong tell() nothrow { return m_ptr; }
	const(ubyte)[] peek() { return m_data[m_ptr .. min(m_size, m_ptr+m_peekWindow)]; }

	size_t read(scope ubyte[] dst, IOMode mode)
	{
		enforce(mode != IOMode.all || dst.length <= leastSize, "Reading past end of memory stream.");
		auto len = min(leastSize, dst.length);
		dst[0 .. len] = m_data[m_ptr .. m_ptr+len];
		m_ptr += len;
		return len;
	}

	alias read = RandomAccessStream.read;

	size_t write(in ubyte[] bytes, IOMode)
	{
		assert(writable);
		enforce(bytes.length <= m_data.length - m_ptr, "Size limit of memory stream reached.");
		m_data[m_ptr .. m_ptr+bytes.length] = bytes[];
		m_ptr += bytes.length;
		m_size = max(m_size, m_ptr);
		return bytes.length;
	}

	alias write = RandomAccessStream.write;

	void flush() {}
	void finalize() {}
}

mixin validateRandomAccessStream!MemoryStream;
