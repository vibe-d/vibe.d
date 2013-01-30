/**
	Contains interfaces and enums for evented I/O drivers.

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.task;

import core.thread;
import std.exception;
import std.variant;


/** Represents a single task as started using vibe.core.runTask.

	All methods of TaskFiber are also available as methods of Task.
*/
struct Task {
	private {
		TaskFiber m_fiber;
		size_t m_taskCounter;
	}

	private this(TaskFiber fiber, size_t task_counter)
	{
		m_fiber = fiber;
		m_taskCounter = task_counter;
	}

	/// Makes all methods of TaskFiber available for Task.
	alias fiber this;

	/** Returns the Task instance belonging to the calling task.
	*/
	static Task getThis()
	{
		auto fiber = Fiber.getThis();
		if( !fiber ) return Task(null, 0);
		auto tfiber = cast(TaskFiber)fiber;
		assert(tfiber !is null, "Invalid or null fiber used to construct Task handle.");
		return Task(tfiber, tfiber.m_taskCounter);
	}

	nothrow:
	@property inout(TaskFiber) fiber() inout { return m_fiber; }
	@property inout(Thread) thread() inout { if( m_fiber ) return m_fiber.thread; return null; }

	/** Determines if the task is still running.
	*/
	@property bool running()
	const {
		assert(m_fiber, "Invalid task handle");
		try if( m_fiber.state == Fiber.State.TERM ) return false; catch {}
		return m_fiber.m_running && m_fiber.m_taskCounter == m_taskCounter;
	}

	bool opEquals(in ref Task other) const { return m_fiber is other.m_fiber && m_taskCounter == other.m_taskCounter; }
	bool opEquals(in Task other) const { return m_fiber is other.m_fiber && m_taskCounter == other.m_taskCounter; }
}



/** The base class for a task aka Fiber.

	This class represents a single task that is executed concurrencly
	with other tasks. Each task is owned by a single thread.
*/
class TaskFiber : Fiber {
	private {
		Thread m_thread;
		Variant[string] m_taskLocalStorage;
	}

	protected {
		size_t m_taskCounter;
		bool m_running;
	}

	protected this(void delegate() fun, size_t stack_size)
	{
		super(fun, stack_size);
		m_thread = Thread.getThis();
	}

	/** Returns the thread that owns this task.
	*/
	@property inout(Thread) thread() inout nothrow { return m_thread; }

	/** Returns the handle of the current Task running on this fiber.
	*/
	@property Task task() { return Task(this, m_taskCounter); }

	/** Blocks until the task has ended.
	*/
	abstract void join();

	/** Throws an InterruptExeption within the task as soon as it calls a blocking function.
	*/
	abstract void interrupt();

	/** Terminates the task without notice as soon as it calls a blocking function.
	*/
	abstract void terminate();

	/** Sets a task local variable.
	*/
	void set(T)(string name, T value)
	{
		m_taskLocalStorage[name] = Variant(value);
	}

	/** Returns a task local variable.
	*/
	T get(T)(string name)
	{
		Variant* pvar;
		pvar = name in m_taskLocalStorage;
		enforce(pvar !is null, "Accessing unset TLS variable '"~name~"'.");
		return pvar.get!T();
	}

	/** Determines if a certain task local variable is set.
	*/
	bool isSet(string name)
	{
		return (name in m_taskLocalStorage) !is null;
	}

	/** Clears all task local variables.
	*/
	protected void resetLocalStorage()
	{
		m_taskLocalStorage = null;
	}
}


/** Exception that is thrown by Task.interrupt.
*/
class InterruptException : Exception {
	this()
	{
		super("Task interrupted.");
	}
}
