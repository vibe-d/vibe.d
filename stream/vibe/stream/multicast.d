/**
	Multicasts an input stream to multiple output streams.

	Copyright: © 2014-2020 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Eric Cornelius
*/
module vibe.stream.multicast;

import vibe.core.core;
import vibe.core.stream;

import std.exception;


/** Creates a new multicast stream based on the given set of output streams.
*/
MulticastStream!OutputStreams createMulticastStream(OutputStreams...)(OutputStreams output_streams)
{
	return MulticastStream!OutputStreams(output_streams);
}

unittest {
	createMulticastStream(nullSink, nullSink);
}


struct MulticastStream(OutputStreams...) {
	import std.algorithm : swap;

	private {
		OutputStreams m_outputs;
	}

	private this(ref OutputStreams outputs)
	{
		foreach (i, T; OutputStreams)
			swap(outputs[i], m_outputs[i]);
	}

	void finalize()
	@safe @blocking {
		flush();
	}

	void flush()
	@safe @blocking {
		foreach (i, T; OutputStreams)
			m_outputs[i].flush();
	}

	size_t write(in ubyte[] bytes, IOMode mode)
	@safe @blocking {
		if (!m_outputs.length) return bytes.length;

		auto ret = m_outputs[0].write(bytes, mode);

		foreach (i, T; OutputStreams[1 .. $])
			m_outputs[i+1].write(bytes[0 .. ret]);

		return ret;
	}
	void write(in ubyte[] bytes) @blocking { auto n = write(bytes, IOMode.all); assert(n == bytes.length); }
	void write(in char[] bytes) @blocking { write(cast(const(ubyte)[])bytes); }
}

mixin validateOutputStream!(MulticastStream!NullOutputStream);
