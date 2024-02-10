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
	if (!is(OutputStreams[0] == MulticastMode))
{
	return MulticastStream!OutputStreams(output_streams, MulticastMode.serial);
}
/// ditto
MulticastStream!OutputStreams createMulticastStream(OutputStreams...)
	(MulticastMode mode, OutputStreams output_streams)
{
	return MulticastStream!OutputStreams(output_streams, mode);
}

unittest {
	import vibe.stream.memory : createMemoryOutputStream;
	import std.traits : EnumMembers;

	createMulticastStream(nullSink, nullSink);

	ubyte[] bts = [1, 2, 3, 4];

	foreach (m; EnumMembers!MulticastMode) {
		auto s1 = createMemoryOutputStream();
		auto s2 = createMemoryOutputStream();
		auto ms = createMulticastStream(m, s1, s2);
		ms.write(bts[0 .. 3]);
		ms.write(bts[3 .. 4]);
		ms.flush();
		assert(s1.data == bts);
		assert(s2.data == bts);
	}
}


struct MulticastStream(OutputStreams...) {
	import std.algorithm : swap;

	private {
		OutputStreams m_outputs;
		Task[] m_tasks;
	}

	private this(ref OutputStreams outputs, MulticastMode mode)
	{
		foreach (i, T; OutputStreams)
			swap(outputs[i], m_outputs[i]);

		if (mode == MulticastMode.parallel)
			m_tasks.length = outputs.length - 1;
	}

	void finalize()
	@safe @blocking {
		flush();
	}

	void flush()
	@safe @blocking {
		if (m_tasks.length > 0) {
			Exception ex;
			foreach (i, T; OutputStreams[1 .. $])
				m_tasks[i] = runTask((scope MulticastStream _this) {
					try _this.m_outputs[i+1].flush();
					catch (Exception e) ex = e;
				}, () @trusted { return this; } ());
			m_outputs[0].flush();
			foreach (t; m_tasks) t.join();
			if (ex) throw ex;
		} else {
			foreach (i, T; OutputStreams)
				m_outputs[i].flush();
		}
	}

	size_t write(in ubyte[] bytes, IOMode mode)
	@safe @blocking {
		if (!m_outputs.length) return bytes.length;

		if (m_tasks.length > 0) {
			Exception ex;
			foreach (i, T; OutputStreams[1 .. $])
				m_tasks[i] = runTask((scope MulticastStream _this) {
					try _this.m_outputs[i+1].write(bytes, mode);
					catch (Exception e) ex = e;
				}, () @trusted { return this; } ());
			auto ret = m_outputs[0].write(bytes, mode);
			foreach (t; m_tasks) t.join();
			if (ex) throw ex;
			return ret;
		} else {
			auto ret = m_outputs[0].write(bytes, mode);
			foreach (i, T; OutputStreams[1 .. $])
				m_outputs[i+1].write(bytes[0 .. ret]);
			return ret;
		}
	}
	void write(in ubyte[] bytes) @blocking { auto n = write(bytes, IOMode.all); assert(n == bytes.length); }
	void write(in char[] bytes) @blocking { write(cast(const(ubyte)[])bytes); }
}

enum MulticastMode {
	/// Output streams are written in serial order
	serial,
	/// Output streams are written in parallel using multiple tasks
	parallel
}

mixin validateOutputStream!(MulticastStream!NullOutputStream);
