/**
	In-memory streams

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.memory;

import vibe.stream.stream;

import std.array;

class MemoryOutputStream : OutputStream {
	private {
		Appender!(ubyte[]) m_destination;
	}

	this()
	{
		m_destination.clear();
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
