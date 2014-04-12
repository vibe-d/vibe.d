/**
	Contains interfaces and enums for evented I/O drivers.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.task;

import vibe.core.sync;
import vibe.utils.array;

import core.thread;
import std.exception;
import std.traits;
import std.typecons;
import std.variant;


/** Represents a single task as started using vibe.core.runTask.

	Note that the Task type is considered weakly isolated and thus can be
	passed between threads using vibe.core.concurrency.send or by passing
	it as a parameter to vibe.core.core.runWorkerTask.
*/
struct Task {
	private {
		shared(TaskFiber) m_fiber;
		size_t m_taskCounter;
	}

	private this(TaskFiber fiber, size_t task_counter)
	{
		m_fiber = cast(shared)fiber;
		m_taskCounter = task_counter;
	}

	this(in Task other) { m_fiber = cast(shared(TaskFiber))other.m_fiber; m_taskCounter = other.m_taskCounter; }

	/** Returns the Task instance belonging to the calling task.
	*/
	static Task getThis()
	{
		auto fiber = Fiber.getThis();
		if (!fiber) return Task.init;
		auto tfiber = cast(TaskFiber)fiber;
		assert(tfiber !is null, "Invalid or null fiber used to construct Task handle.");
		if (!tfiber.m_running) return Task.init;
		return Task(tfiber, tfiber.m_taskCounter);
	}

	nothrow {
		@property inout(TaskFiber) fiber() inout { return cast(inout(TaskFiber))m_fiber; }
		@property size_t taskCounter() const { return m_taskCounter; }
		@property inout(Thread) thread() inout { if (m_fiber) return this.fiber.thread; return null; }

		/** Determines if the task is still running.
		*/
		@property bool running()
		const {
			assert(m_fiber, "Invalid task handle");
			try if (this.fiber.state == Fiber.State.TERM) return false; catch {}
			return this.fiber.m_running && this.fiber.m_taskCounter == m_taskCounter;
		}
	}

	@property inout(MessageQueue) messageQueue() inout { assert(running); return fiber.messageQueue; }

	T opCast(T)() const nothrow if (is(T == bool)) { return m_fiber !is null; }

	void join() { if (running) fiber.join(); }
	void interrupt() { if (running) fiber.interrupt(); }
	void terminate() { if (running) fiber.terminate(); }


	bool opEquals(in ref Task other) const nothrow { return m_fiber is other.m_fiber && m_taskCounter == other.m_taskCounter; }
	bool opEquals(in Task other) const nothrow { return m_fiber is other.m_fiber && m_taskCounter == other.m_taskCounter; }
}



/** The base class for a task aka Fiber.

	This class represents a single task that is executed concurrently
	with other tasks. Each task is owned by a single thread.
*/
class TaskFiber : Fiber {
	private {
		Thread m_thread;
		Variant[string] m_taskLocalStorage;
		MessageQueue m_messageQueue;
	}

	protected {
		shared size_t m_taskCounter;
		shared bool m_running;
	}

	protected this(void delegate() fun, size_t stack_size)
	{
		super(fun, stack_size);
		m_thread = Thread.getThis();
		m_messageQueue = new MessageQueue;
	}

	/** Returns the thread that owns this task.
	*/
	@property inout(Thread) thread() inout nothrow { return m_thread; }

	/** Returns the handle of the current Task running on this fiber.
	*/
	@property Task task() { return Task(this, m_taskCounter); }

	@property inout(MessageQueue) messageQueue() inout { return m_messageQueue; }

	/** Blocks until the task has ended.
	*/
	abstract void join();

	/** Throws an InterruptExeption within the task as soon as it calls a blocking function.
	*/
	abstract void interrupt();

	/** Terminates the task without notice as soon as it calls a blocking function.
	*/
	abstract void terminate();

	/** Deprecated. Sets a task local variable.

		Please use vibe.core.core.TaskLocal instead.
	*/
	deprecated("Please use vibe.core.core.TaskLocal instead.")
	void set(T)(string name, T value)
	{
		m_taskLocalStorage[name] = Variant(value);
	}

	/** Deprecated. Returns a task local variable.

		Please use vibe.core.core.TaskLocal instead.
	*/
	deprecated("Please use vibe.core.core.TaskLocal instead.")
	T get(T)(string name)
	{
		Variant* pvar;
		pvar = name in m_taskLocalStorage;
		enforce(pvar !is null, "Accessing unset TLS variable '"~name~"'.");
		return pvar.get!T();
	}

	/** Deprecated. Determines if a certain task local variable is set.

		Please use vibe.core.core.TaskLocal instead.
	*/
	deprecated("Please use vibe.core.core.TaskLocal instead.")
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


class MessageQueue {
	private {
		TaskMutex m_mutex;
		TaskCondition m_condition;
		FixedRingBuffer!Variant m_queue;
		FixedRingBuffer!Variant m_priorityQueue;
		size_t m_maxMailboxSize = 0;
		bool function(Task) m_onCrowding;
	}

	this()
	{
		m_mutex = new TaskMutex;
		m_condition = new TaskCondition(m_mutex);
		m_queue.capacity = 32;
		m_priorityQueue.capacity = 8;
	}

	@property bool full() const { return m_maxMailboxSize > 0 && m_queue.length + m_priorityQueue.length >= m_maxMailboxSize; }

	void clear()
	{
		synchronized(m_mutex){
			m_queue.clear();
			m_priorityQueue.clear();
		}
		m_condition.notifyAll();
	}

	void setMaxSize(size_t count, bool function(Task tid) action)
	{
		m_maxMailboxSize = count;
		m_onCrowding = action;
	}

	void send(Variant msg)
	{
		import vibe.core.log;
		synchronized(m_mutex){
			if( this.full ){
				if( !m_onCrowding ){
					while(this.full)
						m_condition.wait();
				} else if( !m_onCrowding(Task.getThis()) ){
					return;
				}
			}
			assert(!this.full);

			if( m_queue.full )
				m_queue.capacity = (m_queue.capacity * 3) / 2;

			m_queue.put(msg);
		}
		m_condition.notify();
	}

	void prioritySend(Variant msg)
	{
		synchronized (m_mutex) {
			if (m_priorityQueue.full)
				m_priorityQueue.capacity = (m_priorityQueue.capacity * 3) / 2;
			m_priorityQueue.put(msg);
		}
		m_condition.notify();
	}

	void receive(scope bool delegate(Variant) filter, scope void delegate(Variant) handler)
	{
		bool notify;
		scope (exit) if (notify) m_condition.notify();

		Variant args;
		synchronized (m_mutex) {
			notify = this.full;
			while (true) {
				import vibe.core.log;
				logTrace("looking for messages");
				if (receiveQueue(m_priorityQueue, args, filter)) break;
				if (receiveQueue(m_queue, args, filter)) break;
				logTrace("received no message, waiting..");
				m_condition.wait();
			}
		}

		handler(args);
	}

	bool receiveTimeout(OPS...)(Duration timeout, scope bool delegate(Variant) filter, scope void delegate(Variant) handler)
	{
		import std.datetime;

		bool notify;
		scope (exit) if (notify) m_condition.notify();
		auto limit_time = Clock.currTime(UTC()) + timeout;
		Variant args;
		synchronized (m_mutex) {
			notify = this.full;
			while (true) {
				if (receiveQueue(m_priorityQueue, args, filter)) break;
				if (receiveQueue(m_queue, args, filter)) break;
				auto now = Clock.currTime(UTC());
				if (now >= limit_time) return false;
				m_condition.wait(limit_time - now);
			}
		}

		handler(args);
		return true;
	}

	private static bool receiveQueue(OPS...)(ref FixedRingBuffer!Variant queue, ref Variant dst, scope bool delegate(Variant) filter)
	{
		auto r = queue[];
		while (!r.empty) {
			scope (failure) queue.removeAt(r);
			auto msg = r.front;
			if (filter(msg)) {
				dst = msg;
				queue.removeAt(r);
				return true;
			}
			r.popFront();
		}
		return false;
	}
}
