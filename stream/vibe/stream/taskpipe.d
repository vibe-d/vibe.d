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
	size_t read(scope ubyte[] dst, IOMode mode) { return m_pipe.read(dst, mode); }
	alias read = ConnectionStream.read;
	size_t write(in ubyte[] bytes, IOMode mode) { return m_pipe.write(bytes, mode); }
	alias write = ConnectionStream.write;
	void flush() {}
	void finalize() { m_pipe.close(); }
}


/**
	Underyling pipe implementation for TaskPipe with no Stream interface.
*/
private final class TaskPipeImpl {
	@safe:

	private {
		Mutex m_mutex;
		InterruptibleTaskCondition m_condition;
		vibe.utils.array.FixedRingBuffer!ubyte m_buffer;
		bool m_closed = false;
		bool m_growWhenFull;
	}

	/** Constructs a new pipe ready for use.
	*/
	this(bool grow_when_full = false)
	{
		m_mutex = new Mutex;
		() @trusted { m_condition = new InterruptibleTaskCondition(m_mutex); } ();
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
		() @trusted { m_condition.notifyAll(); } ();
	}

	/** Blocks until at least one byte of data has been written to the pipe.
	*/
	void waitForData(Duration timeout = Duration.max)
	{
		import std.datetime : Clock, SysTime, UTC;
		bool have_timeout = timeout > 0.seconds && timeout != Duration.max;
		SysTime now = Clock.currTime(UTC());
		SysTime timeout_target;
		if (have_timeout) timeout_target = now + timeout;

		synchronized (m_mutex) {
			while (m_buffer.empty && !m_closed && (!have_timeout || now < timeout_target)) {
				if (have_timeout)
					() @trusted { m_condition.wait(timeout_target - now); } ();
				else () @trusted { m_condition.wait(); } ();
				now = Clock.currTime(UTC());
			}
		}
	}

	/** Writes the given byte array to the pipe.
	*/
	size_t write(const(ubyte)[] data, IOMode mode)
	{
		size_t ret = 0;

		enforce(!m_closed, "Writing to closed task pipe.");

		while (data.length > 0){
			bool need_signal;
			synchronized (m_mutex) {
				if (m_growWhenFull && m_buffer.full) {
					size_t new_sz = m_buffer.capacity;
					while (new_sz - m_buffer.capacity < data.length) new_sz += 2;
					m_buffer.capacity = new_sz;
				} else while (m_buffer.full) {
					if (mode == IOMode.immediate || mode == IOMode.once && ret > 0)
						return ret;
					() @trusted { m_condition.wait(); } ();
				}

				need_signal = m_buffer.empty;
				auto len = min(m_buffer.freeSpace, data.length);
				m_buffer.put(data[0 .. len]);
				data = data[len .. $];
				ret += len;
			}
			if (need_signal) () @trusted { m_condition.notifyAll(); } ();
		}
		if (!m_growWhenFull) vibe.core.core.yield();

		return ret;
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
	size_t read(scope ubyte[] dst, IOMode mode)
	{
		size_t ret = 0;

		while (dst.length > 0) {
			bool need_signal;
			size_t len;
			synchronized (m_mutex) {
				while (m_buffer.empty && !m_closed) {
					if (mode == IOMode.immediate || mode == IOMode.once && ret > 0)
						return ret;
					() @trusted { m_condition.wait(); } ();
				}

				need_signal = m_buffer.full;
				enforce(!m_buffer.empty, "Reading past end of closed pipe.");
				len = min(dst.length, m_buffer.length);
				m_buffer.read(dst[0 .. len]);
				ret += len;
			}
			if (need_signal) () @trusted { m_condition.notifyAll(); } ();
			dst = dst[len .. $];
		}
		vibe.core.core.yield();

		return ret;
	}
}

unittest { // issue #1501 - deadlock in TaskPipe
	import std.datetime : Clock, UTC;
	import core.time : msecs;

	// test read after write and write after read
	foreach (i; 0 .. 2) {
		auto p = new TaskPipe;
		p.bufferSize = 2048;

		Task a, b;
		a = runTask({ ubyte[2100] buf; if (i == 0) p.read(buf, IOMode.all); else p.write(buf, IOMode.all); });
		b = runTask({ ubyte[2100] buf; if (i == 0) p.write(buf, IOMode.all); else p.read(buf, IOMode.all); });

		auto joiner = runTask({
			auto starttime = Clock.currTime(UTC());
			while (a.running || b.running) {
				if (Clock.currTime(UTC()) - starttime > 500.msecs)
					assert(false, "TaskPipe is dead locked.");
				yield();
			}
		});

		joiner.join();
	}
}

unittest { // issue #
	auto t = runTask({
		auto tp = new TaskPipeImpl;
		tp.waitForData(10.msecs);
		exitEventLoop();
	});
	runTask({
		sleep(500.msecs);
		assert(!t.running, "TaskPipeImpl.waitForData didn't timeout.");
	});
	runEventLoop();
}
