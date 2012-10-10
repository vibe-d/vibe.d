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
		Variant[string] m_taskLocalStorage;
	}

	protected this(void delegate() fun, size_t stack_size)
	{
		super(fun, stack_size);
	}

	/** Returns the Task instance belonging to the calling task.
	*/
	static Task getThis(){ return cast(Task)Fiber.getThis(); }

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


