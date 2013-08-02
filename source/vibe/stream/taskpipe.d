/**
	Stream interface for passing data between different tasks.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.taskpipe;

public import vibe.core.stream;

import core.sync.mutex;
import std.algorithm : min;
import std.exception;
import vibe.core.sync;
import vibe.utils.array;


class TaskPipe {
	static class Reader : InputStream {
		private TaskPipeImpl m_pipe;
		this(TaskPipeImpl pipe) { m_pipe = pipe; }
		@property bool empty() { return leastSize() == 0; }
		@property ulong leastSize() { m_pipe.waitForData(); return m_pipe.fill; }
		@property bool dataAvailableForRead() { return m_pipe.fill > 0; }
		const(ubyte)[] peek() { return m_pipe.peek; }
		void read(ubyte[] dst) { return m_pipe.read(dst); }
	}

	static class Writer : OutputStream {
		private TaskPipeImpl m_pipe;
		this(TaskPipeImpl pipe) { m_pipe = pipe; }
		void write(in ubyte[] bytes, bool do_flush = true) { m_pipe.write(bytes); }
		void flush() {}
		void finalize() { m_pipe.close(); }
		void write(InputStream stream, ulong nbytes = 0, bool do_flush = true) { writeDefault(stream, nbytes, do_flush); }
	}

	private {
		Reader m_reader;
		Writer m_writer;
		TaskPipeImpl m_pipe;
	}

	this()
	{
		m_pipe = new TaskPipeImpl;
		m_reader = new Reader(m_pipe);
		m_writer = new Writer(m_pipe);
	}

	@property Reader reader() { return m_reader; }
	@property Writer writer() { return m_writer; }
}

class TaskPipeImpl {
	private {
		Mutex m_mutex;
		TaskCondition m_condition;
		FixedRingBuffer!ubyte m_buffer;
		bool m_closed = false;
	}

	this(Mutex mutex = null)
	{
		m_mutex = mutex ? mutex : new Mutex;
		m_condition = new TaskCondition(m_mutex);
		m_buffer.capacity = 2048;
	}

	@property void bufferSize(size_t len)
	{
		m_buffer.capacity = len;
	}

	@property size_t fill()
	const {
		synchronized (m_mutex) {
			return m_buffer.length;
		}
	}

	void close()
	{
		synchronized (m_mutex) m_closed = true;
	}

	void waitForData()
	{
		synchronized (m_mutex) {
			while (m_buffer.empty && !m_closed) m_condition.wait();
		}
	}

	void write(const(ubyte)[] data)
	{
		while (data.length > 0){
			bool need_signal;
			synchronized (m_mutex) {
				if (m_buffer.empty) need_signal = true;
				else while (m_buffer.full) m_condition.wait();
				auto len = min(m_buffer.freeSpace, data.length);
				m_buffer.put(data[0 .. len]);
				data = data[len .. $];
			}
			if (need_signal) m_condition.notifyAll();
		}
	}

	const(ubyte[]) peek()
	{
		synchronized (m_mutex) {
			return m_buffer.peek();
		}
	}

	void read(ubyte[] dst)
	{
		while (dst.length > 0) {
			bool need_signal;
			size_t len;
			synchronized (m_mutex) {
				if (m_buffer.full) need_signal = true;
				else while (m_buffer.empty && !m_closed) m_condition.wait();
				enforce(!m_buffer.empty, "Reading past end of closed pipe.");
				len = min(dst.length, m_buffer.length);
				m_buffer.read(dst[0 .. len]);
			}
			if (need_signal) m_condition.notifyAll();
			dst = dst[len .. $];
		}
	}
}
