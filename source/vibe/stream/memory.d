/**
	In-memory streams

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.memory;

import vibe.stream.stream;
import vibe.utils.memory;

import std.array;
import std.typecons;


class MemoryOutputStream : OutputStream {
	private {
		AllocAppender!(ubyte[]) m_destination;
	}

	this(Allocator alloc = defaultAllocator())
	{
		m_destination = AllocAppender!(ubyte[])(alloc);
	}

	void reserve(size_t nbytes)
	{
		m_destination.reserve(nbytes);
	}

	@property ubyte[] data() { return m_destination.data(); }

	void write(in ubyte[] bytes, bool do_flush = true)
	{
		m_destination.put(bytes);
	}

	void flush()
	{
	}

	void finalize()
	{
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}
}
