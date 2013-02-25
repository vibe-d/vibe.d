/**
	Task synchronization facilities

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Leonid Kramer
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.sync;

import std.exception;
import vibe.core.core;
public import vibe.core.driver;

import core.sync.mutex;
import core.sync.condition;

enum LockMode{
	lock,
	tryLock,
	defer,

	/// deprecated
	Lock = lock,
	/// deprecated
	Try = tryLock,
	/// deprecated
	Defer = defer
}


/** RAII lock for the Mutex class.
*/
struct ScopedMutexLock {
	private {
		core.sync.mutex.Mutex m_mutex;
		bool m_locked;
		LockMode m_mode;
	}

	@disable this(this);

	this(core.sync.mutex.Mutex mutex, LockMode mode=LockMode.lock)
	{
		assert(mutex !is null);
		m_mutex = mutex;

		switch(mode){
			default:
				assert(false, "unsupported enum value");
			case LockMode.lock: 
				lock();
				break;
			case LockMode.tryLock: 
				tryLock();
				break;
			case LockMode.defer: 
				break;
		}
	}

	~this()
	{
		if( m_locked )
			m_mutex.unlock();
	}

	@property bool locked() const { return m_locked; }

	bool tryLock()
	{
		enforce(!m_locked);
		return m_locked = m_mutex.tryLock();
	}

	void lock()
	{
		enforce(!m_locked);
		m_locked = true;
		m_mutex.lock();
	}

	void unlock()
	{
		enforce(m_locked);
		m_mutex.unlock();
		m_locked = false;
	}
}

/** Mutex implementation for fibers.

	Note: 
		This mutex is currently suitable only for synchronizing different
		fibers. If you need inter-thread synchronization, go for
		core.sync.mutex instead.
*/
class TaskMutex : core.sync.mutex.Mutex {
	private {
		bool m_locked = false;
		Signal m_signal;
		debug Task m_owner;
	}

	this()
	{
		m_signal = createSignal();
	}

	private	@property bool locked() const { return m_locked; }

	override @trusted bool tryLock()
	{
		if(m_locked) return false;
		m_locked = true;
		debug m_owner = Task.getThis();
		return true;
	}

	override @trusted void lock()
	{
		if(m_locked){
			m_signal.acquire();
			do{ m_signal.wait(); } while(m_locked);
		}
		m_locked = true;
		debug m_owner = Task.getThis();
	}

	override @trusted void unlock()
	{
		enforce(m_locked);
		m_locked = false;
		debug m_owner = Task();
	}
}

deprecated("please use TaskMutex instead.")
alias Mutex = TaskMutex;

unittest {
	auto mutex = new TaskMutex;

	{
		auto lock = ScopedMutexLock(mutex);
		assert(lock.locked);
		assert(mutex.locked);

		auto lock2 = ScopedMutexLock(mutex, LockMode.tryLock);
		assert(!lock2.locked);
	}
	assert(!mutex.locked);

	auto lock = ScopedMutexLock(mutex, LockMode.tryLock);
	assert(lock.locked);
	lock.unlock();
	assert(!lock.locked);

	synchronized(mutex){
		assert(mutex.m_locked);
	}
}


class TaskCondition : core.sync.condition.Condition {
	private {
		TaskMutex m_mutex;
		Signal m_signal;
		Timer m_timer;
	}

	this(TaskMutex mutex)
	{
		super(mutex);
		m_mutex = mutex;
		m_signal = createSignal();
		m_timer = getEventDriver().createTimer(null);
	}

	override @trusted @property TaskMutex mutex() { return m_mutex; }

	override @trusted void wait()
	{
		assert(m_mutex.m_locked);
		debug assert(m_mutex.m_owner == Task.getThis());

		auto refcount = m_signal.emitCount;
		m_mutex.unlock();
		scope(failure) m_mutex.lock();

		while(refcount == m_signal.emitCount)
			rawYield();
		m_mutex.lock();
	}

	override @trusted bool wait(Duration timeout)
	{
		assert(m_mutex.m_locked);
		debug assert(m_mutex.m_owner == Task.getThis());

		auto refcount = m_signal.emitCount;
		m_mutex.unlock();
		scope(failure) m_mutex.lock();

		m_timer.rearm(timeout);
		while(refcount == m_signal.emitCount && m_timer.pending)
			rawYield();
		auto succ = refcount != m_signal.emitCount;
		m_mutex.lock();
		return succ;
	}

	override @trusted void notify()
	{
		m_signal.emit();
	}

	override @trusted void notifyAll()
	{
		m_signal.emit();
	}
}

/** Creates a new signal that can be shared between fibers.
*/
Signal createSignal()
{
	return getEventDriver().createSignal();
}

/** A cross-fiber signal

	Note: the ownership can be shared between multiple fibers.
*/
interface Signal : EventedObject {
	/// A counter that is increased with every emit() call
	@property int emitCount() const;

	/// Emits the signal, waking up all owners of the signal.
	void emit();

	/// Acquires ownership and waits until the signal is emitted.
	void wait();

	/// Acquires ownership and waits until the signal is emitted if no emit has happened since the given reference emit count.
	int wait(int reference_emit_count);
}

class SignalException : Exception {
	this() { super("Signal emitted."); }
}

