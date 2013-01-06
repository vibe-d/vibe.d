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


/** The base class for a task aka Fiber.

	This class represents a single task that is executed concurrencly
	with other tasks. Each task is owned by a single thread.
*/
class Task : Fiber {
	private {
		Thread m_thread;
		Variant[string] m_taskLocalStorage;
	}

	protected this(void delegate() fun, size_t stack_size)
	{
		super(fun, stack_size);
		m_thread = Thread.getThis();
	}

	/** Returns the Task instance belonging to the calling task.
	*/
	static Task getThis(){ return cast(Task)Fiber.getThis(); }

	/** Returns the thread that owns this task.
	*/
	@property inout(Thread) thread() inout { return m_thread; }

	/** Determines if the task is still running.

		Bugs: Note that Task objects are reused for later tasks so the returned
		value may not be accurate. This may be improved in a later version.
	*/
	abstract @property bool running() const;

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
