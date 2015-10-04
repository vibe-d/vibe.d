/**
	Multicasts an input stream to multiple output streams.

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Eric Cornelius
*/
module vibe.stream.multicast;

import vibe.core.core;
import vibe.core.stream;
import vibe.utils.memory;

import std.exception;


class MulticastStream : OutputStream {
	private {
		OutputStream[] m_outputs;
	}

	this(OutputStream[] outputs ...)
	{
		// NOTE: investigate .dup dmd workaround
		m_outputs = outputs.dup;
	}

	void finalize()
	{
		flush();
	}

	void flush()
	{
		foreach (output; m_outputs)
			output.flush();
	}

	void write(in ubyte[] bytes)
	{
		foreach (output; m_outputs)
			output.write(bytes);
	}

	void write(InputStream source, ulong nbytes = 0)
	{
		writeDefault(source, nbytes);
	}
}
