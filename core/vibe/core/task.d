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
		import std.concurrency : ThreadInfo, Tid;
		static ThreadInfo s_tidInfo;
	}

	private this(TaskFiber fiber, size_t task_counter)
	@safe nothrow {
		() @trusted { m_fiber = cast(shared)fiber; } ();
		m_taskCounter = task_counter;
	}

	this(in Task other) nothrow { m_fiber = cast(shared(TaskFiber))other.m_fiber; m_taskCounter = other.m_taskCounter; }

	/** Returns the Task instance belonging to the calling task.
	*/
	static Task getThis() nothrow @safe
	{
		auto fiber = () @trusted { return Fiber.getThis(); } ();
		if (!fiber) return Task.init;
		auto tfiber = cast(TaskFiber)fiber;
		if (!tfiber) return Task.init;
		if (!tfiber.m_running) return Task.init;
		return () @trusted { return Task(tfiber, tfiber.m_taskCounter); } ();
	}

	nothrow {
		@property inout(TaskFiber) fiber() inout @trusted { return cast(inout(TaskFiber))m_fiber; }
		@property size_t taskCounter() const @safe { return m_taskCounter; }
		@property inout(Thread) thread() inout @safe { if (m_fiber) return this.fiber.thread; return null; }

		/** Determines if the task is still running.
		*/
		@property bool running()
		const @trusted {
			assert(m_fiber !is null, "Invalid task handle");
			try if (this.fiber.state == Fiber.State.TERM) return false; catch (Throwable) {}
			return this.fiber.m_running && this.fiber.m_taskCounter == m_taskCounter;
		}

		// FIXME: this is not thread safe!
		@property ref ThreadInfo tidInfo() { return m_fiber ? fiber.tidInfo : s_tidInfo; }
		@property ref const(ThreadInfo) tidInfo() const { return m_fiber ? fiber.tidInfo : s_tidInfo; }
		@property Tid tid() { return tidInfo.ident; }
		@property const(Tid) tid() const { return tidInfo.ident; }
	}

	/// Reserved for internal use!
	@property inout(MessageQueue) messageQueue() inout { assert(running, "Task is not running"); return fiber.messageQueue; }

	T opCast(T)() const nothrow if (is(T == bool)) { return m_fiber !is null; }

	void join() @safe { if (running) fiber.join(); }
	void interrupt() { if (running) fiber.interrupt(); }
	void terminate() { if (running) fiber.terminate(); }

	string toString() const @safe { import std.string; return format("%s:%s", () @trusted { return cast(void*)m_fiber; } (), m_taskCounter); }

	bool opEquals(in ref Task other) const nothrow @safe { return m_fiber is other.m_fiber && m_taskCounter == other.m_taskCounter; }
	bool opEquals(in Task other) const nothrow @safe { return m_fiber is other.m_fiber && m_taskCounter == other.m_taskCounter; }
}



/** The base class for a task aka Fiber.

	This class represents a single task that is executed concurrently
	with other tasks. Each task is owned by a single thread.
*/
class TaskFiber : Fiber {
	private {
		import std.concurrency : ThreadInfo;
		Thread m_thread;
		ThreadInfo m_tidInfo;
		MessageQueue m_messageQueue;
	}

	protected {
		shared size_t m_taskCounter;
		shared bool m_running;
	}

	protected this(void delegate() fun, size_t stack_size)
	nothrow {
		super(fun, stack_size);
		m_thread = Thread.getThis();
		scope (failure) assert(false);
		m_messageQueue = new MessageQueue;
	}

	/** Returns the thread that owns this task.
	*/
	@property inout(Thread) thread() inout @safe nothrow { return m_thread; }

	/** Returns the handle of the current Task running on this fiber.
	*/
	@property Task task() @safe nothrow { return Task(this, m_taskCounter); }

	/// Reserved for internal use!
	@property inout(MessageQueue) messageQueue() inout { return m_messageQueue; }

	@property ref inout(ThreadInfo) tidInfo() inout nothrow { return m_tidInfo; }

	/** Blocks until the task has ended.
	*/
	abstract void join() @safe;

	/** Throws an InterruptExeption within the task as soon as it calls a blocking function.
	*/
	abstract void interrupt();

	/** Terminates the task without notice as soon as it calls a blocking function.
	*/
	abstract void terminate();

	void bumpTaskCounter()
	@safe nothrow {
		import core.atomic : atomicOp;
		() @trusted { atomicOp!"+="(this.m_taskCounter, 1); } ();
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
		InterruptibleTaskMutex m_mutex;
		InterruptibleTaskCondition m_condition;
		FixedRingBuffer!Variant m_queue;
		FixedRingBuffer!Variant m_priorityQueue;
		size_t m_maxMailboxSize = 0;
		bool function(Task) m_onCrowding;
	}

	this()
	{
		m_mutex = new InterruptibleTaskMutex;
		m_condition = new InterruptibleTaskCondition(m_mutex);
		m_queue.capacity = 32;
		m_priorityQueue.capacity = 8;
	}

	@property bool full() const { return m_maxMailboxSize > 0 && m_queue.length + m_priorityQueue.length >= m_maxMailboxSize; }

	void clear()
	{
		m_mutex.performLocked!({
			m_queue.clear();
			m_priorityQueue.clear();
		});
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
		m_mutex.performLocked!({
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
		});
		m_condition.notify();
	}

	void prioritySend(Variant msg)
	{
		m_mutex.performLocked!({
			if (m_priorityQueue.full)
				m_priorityQueue.capacity = (m_priorityQueue.capacity * 3) / 2;
			m_priorityQueue.put(msg);
		});
		m_condition.notify();
	}

	void receive(scope bool delegate(Variant) filter, scope void delegate(Variant) handler)
	{
		bool notify;
		scope (exit) if (notify) m_condition.notify();

		Variant args;
		m_mutex.performLocked!({
			notify = this.full;
			while (true) {
				import vibe.core.log;
				logTrace("looking for messages");
				if (receiveQueue(m_priorityQueue, args, filter)) break;
				if (receiveQueue(m_queue, args, filter)) break;
				logTrace("received no message, waiting..");
				m_condition.wait();
				notify = this.full;
			}
		});

		handler(args);
	}

	bool receiveTimeout(OPS...)(Duration timeout, scope bool delegate(Variant) filter, scope void delegate(Variant) handler)
	{
		import std.datetime;

		bool notify;
		scope (exit) if (notify) m_condition.notify();
		auto limit_time = Clock.currTime(UTC()) + timeout;
		Variant args;
		if (!m_mutex.performLocked!({
			notify = this.full;
			while (true) {
				if (receiveQueue(m_priorityQueue, args, filter)) break;
				if (receiveQueue(m_queue, args, filter)) break;
				auto now = Clock.currTime(UTC());
				if (now >= limit_time) return false;
				m_condition.wait(limit_time - now);
				notify = this.full;
			}
			return true;
		})) return false;

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
