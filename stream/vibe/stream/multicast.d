/**
	Multicasts an input stream to multiple output streams.

	Copyright: © 2014-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Eric Cornelius
*/
module vibe.stream.multicast;

import vibe.core.core;
import vibe.core.stream;

import std.exception;

MulticastStream createMulticastStream(scope OutputStream[] outputs...)
{
	return new MulticastStream(outputs, true);
}


class MulticastStream : OutputStream {
	private {
		OutputStream[] m_outputs;
	}

	deprecated("Use createMulticastStream instead.")
	this(OutputStream[] outputs ...)
	{
		this(outputs, true);
	}

	/// private
	this(scope OutputStream[] outputs, bool dummy)
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

	size_t write(in ubyte[] bytes, IOMode mode)
	{
		if (!m_outputs.length) return bytes.length;

		auto ret = m_outputs[0].write(bytes, mode);

		foreach (output; m_outputs[1 .. $])
			output.write(bytes[0 .. ret]);

		return ret;
	}

	alias write = OutputStream.write;
}
