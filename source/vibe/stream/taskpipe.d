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


/**
	Implements a unidirectional data pipe between two tasks.
*/
class TaskPipe {
	/// Proxy around TaskPipeImpl implementing an InputStream 
	static class Reader : InputStream {
		private TaskPipeImpl m_pipe;
		this(TaskPipeImpl pipe) { m_pipe = pipe; }
		@property bool empty() { return leastSize() == 0; }
		@property ulong leastSize() { m_pipe.waitForData(); return m_pipe.fill; }
		@property bool dataAvailableForRead() { return m_pipe.fill > 0; }
		const(ubyte)[] peek() { return m_pipe.peek; }
		void read(ubyte[] dst) { return m_pipe.read(dst); }
	}

	/// Proxy around TaskPipeImpl implementing an OutputStream 
	static class Writer : OutputStream {
		private TaskPipeImpl m_pipe;
		this(TaskPipeImpl pipe) { m_pipe = pipe; }
		void write(in ubyte[] bytes) { m_pipe.write(bytes); }
		void flush() {}
		void finalize() { m_pipe.close(); }
		void write(InputStream stream, ulong nbytes = 0) { writeDefault(stream, nbytes); }
	}

	private {
		Reader m_reader;
		Writer m_writer;
		TaskPipeImpl m_pipe;
	}

	/** Constructs a new pipe ready for use.
	*/
	this()
	{
		m_pipe = new TaskPipeImpl;
		m_reader = new Reader(m_pipe);
		m_writer = new Writer(m_pipe);
	}

	/// Read end of the pipe
	@property Reader reader() { return m_reader; }

	/// Write end of the pipe
	@property Writer writer() { return m_writer; }

	/// Size of the (fixed) FIFO buffer used to transfer data between tasks
	@property size_t bufferSize() const { return m_pipe.bufferSize; }
	/// ditto
	@property void bufferSize(size_t nbytes) { m_pipe.bufferSize = nbytes; }
}


/**
	Underyling pipe implementation for TaskPipe with no Stream interface.
*/
class TaskPipeImpl {
	private {
		Mutex m_mutex;
		TaskCondition m_condition;
		FixedRingBuffer!ubyte m_buffer;
		bool m_closed = false;
	}

	/** Constructs a new pipe ready for use.
	*/
	this()
	{
		m_mutex = new Mutex;
		m_condition = new TaskCondition(m_mutex);
		m_buffer.capacity = 2048;
	}

	/// Size of the (fixed) buffer used to transfer data between tasks
	@property size_t bufferSize() const { return m_buffer.capacity; }
	/// ditto
	@property void bufferSize(size_t nbytes) { m_buffer.capacity = nbytes; }

	/// Number of bytes currently in the transfer buffer
	@property size_t fill()
	const {
		synchronized (m_mutex) {
			return m_buffer.length;
		}
	}

	/** Closes the pipe.
	*/
	void close()
	{
		synchronized (m_mutex) m_closed = true;
		m_condition.notifyAll();
	}

	/** Blocks until at least one byte of data has been written to the pipe.
	*/
	void waitForData()
	{
		synchronized (m_mutex) {
			while (m_buffer.empty && !m_closed) m_condition.wait();
		}
	}

	/** Writes the given byte array to the pipe.
	*/
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

	/** Returns a temporary view of the beginning of the transfer buffer.

		Note that a call to read invalidates this array slice. Blocks in case
		of a filled up transfer buffer.
	*/
	const(ubyte[]) peek()
	{
		synchronized (m_mutex) {
			return m_buffer.peek();
		}
	}

	/** Reads data into the supplied buffer.

		Blocks until a sufficient amount of data has been written to the pipe.
	*/
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
