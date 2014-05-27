/**
	Stream interface for passing data between different tasks.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.taskpipe;

public import vibe.core.stream;

import core.sync.mutex;
import core.time;
import std.algorithm : min;
import std.exception;
import vibe.core.core;
import vibe.core.sync;
import vibe.utils.array;


/**
	Implements a unidirectional data pipe between two tasks.
*/
final class TaskPipe : ConnectionStream {
	private {
		TaskPipeImpl m_pipe;
	}

	/** Constructs a new pipe ready for use.
	*/
	this(bool grow_when_full = false)
	{
		m_pipe = new TaskPipeImpl(grow_when_full);
	}

	/// Deprecated. Read end of the pipe.
	deprecated("Use TaskPipe directly as an input stream instead.")
	@property InputStream reader() { return this; }

	/// Deprecated. Write end of the pipe.
	deprecated("Use TaskPipe directly as an output stream instead.")
	@property OutputStream writer() { return this; }

	/// Size of the (fixed) FIFO buffer used to transfer data between tasks
	@property size_t bufferSize() const { return m_pipe.bufferSize; }
	/// ditto
	@property void bufferSize(size_t nbytes) { m_pipe.bufferSize = nbytes; }

	@property bool empty() { return leastSize() == 0; }
	@property ulong leastSize() { m_pipe.waitForData(); return m_pipe.fill; }
	@property bool dataAvailableForRead() { return m_pipe.fill > 0; }
	@property bool connected() const { return m_pipe.open; }

	void close() { m_pipe.close(); }
	bool waitForData(Duration timeout)
	{
		if (dataAvailableForRead) return true;
		m_pipe.waitForData(timeout);
		return dataAvailableForRead;
	}
	const(ubyte)[] peek() { return m_pipe.peek; }
	void read(ubyte[] dst) { return m_pipe.read(dst); }
	void write(in ubyte[] bytes) { m_pipe.write(bytes); }
	void flush() {}
	void finalize() { m_pipe.close(); }
	void write(InputStream stream, ulong nbytes = 0) { writeDefault(stream, nbytes); }
}


/**
	Underyling pipe implementation for TaskPipe with no Stream interface.
*/
private final class TaskPipeImpl {
	private {
		Mutex m_mutex;
		TaskCondition m_condition;
		FixedRingBuffer!ubyte m_buffer;
		bool m_closed = false;
		bool m_growWhenFull;
	}

	/** Constructs a new pipe ready for use.
	*/
	this(bool grow_when_full = false)
	{
		m_mutex = new Mutex;
		m_condition = new TaskCondition(m_mutex);
		m_buffer.capacity = 2048;
		m_growWhenFull = grow_when_full;
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

	@property bool open() const { return !m_closed; }

	/** Closes the pipe.
	*/
	void close()
	{
		synchronized (m_mutex) m_closed = true;
		m_condition.notifyAll();
	}

	/** Blocks until at least one byte of data has been written to the pipe.
	*/
	void waitForData(Duration timeout = 0.seconds)
	{
		synchronized (m_mutex) {
			while (m_buffer.empty && !m_closed) {
				if (timeout > 0.seconds)
					m_condition.wait(timeout);
				else m_condition.wait();
			}
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
				else if (m_growWhenFull && m_buffer.full) {
					size_t new_sz = m_buffer.capacity;
					while (new_sz - m_buffer.capacity < data.length) new_sz += 2;
					m_buffer.capacity = new_sz;
				} else while (m_buffer.full) m_condition.wait();
				auto len = min(m_buffer.freeSpace, data.length);
				m_buffer.put(data[0 .. len]);
				data = data[len .. $];
			}
			if (need_signal) m_condition.notifyAll();
		}
		if (!m_growWhenFull) vibe.core.core.yield();
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
		vibe.core.core.yield();
	}
}
