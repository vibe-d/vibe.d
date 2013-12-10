/**
	Task synchronization facilities

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Leonid Kramer
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.sync;

import std.exception;

import vibe.core.driver;

import core.atomic;
import core.sync.mutex;
import core.sync.condition;

enum LockMode{
	lock,
	tryLock,
	defer
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

/**
	Mutex implementation for fibers.

	This mutex type can be used in exchange for a core.sync.mutex.Mutex, but
	does not block the event loop when contention happens. Note that this
	mutex does not allow recursive locking.

	See_Also: RecursiveTaskMutex, core.sync.mutex.Mutex
*/
class TaskMutex : core.sync.mutex.Mutex {
	import std.stdio;
	private {
		shared(bool) m_locked = false;
		shared(uint) m_waiters = 0;
		ManualEvent m_signal;
		debug Task m_owner;
	}

	this()
	{
		m_signal = createManualEvent();
	}

	this(Object o)
	{
		super(o);
		m_signal = createManualEvent();
	}

	override @trusted bool tryLock()
	{
		if (cas(&m_locked, false, true)) {
			debug m_owner = Task.getThis();
			version(MutexPrint) writefln("mutex %s lock %s", cast(void*)this, atomicLoad(m_waiters));
			return true;
		}
		return false;
	}

	override @trusted void lock()
	{
		if (tryLock()) return;
		debug assert(m_owner == Task() || m_owner != Task.getThis(), "Recursive mutex lock.");
		atomicOp!"+="(m_waiters, 1);
		version(MutexPrint) writefln("mutex %s wait %s", cast(void*)this, atomicLoad(m_waiters));
		scope(exit) atomicOp!"-="(m_waiters, 1);
		auto ecnt = m_signal.emitCount();
		while (!tryLock()) ecnt = m_signal.wait(ecnt);
	}

	override @trusted void unlock()
	{
		assert(m_locked);
		debug {
			assert(m_owner == Task.getThis());
			m_owner = Task();
		}
		atomicStore!(MemoryOrder.rel)(m_locked, false);
		version(MutexPrint) writefln("mutex %s unlock %s", cast(void*)this, atomicLoad(m_waiters));
		if (atomicLoad(m_waiters) > 0)
			m_signal.emit();
	}
}

unittest {
	auto mutex = new TaskMutex;

	{
		auto lock = ScopedMutexLock(mutex);
		assert(lock.locked);
		assert(mutex.m_locked);

		auto lock2 = ScopedMutexLock(mutex, LockMode.tryLock);
		assert(!lock2.locked);
	}
	assert(!mutex.m_locked);

	auto lock = ScopedMutexLock(mutex, LockMode.tryLock);
	assert(lock.locked);
	lock.unlock();
	assert(!lock.locked);

	synchronized(mutex){
		assert(mutex.m_locked);
	}
}


/**
	Recursive mutex implementation for tasks.

	This mutex type can be used in exchange for a core.sync.mutex.Mutex, but
	does not block the event loop when contention happens.

	See_Also: TaskMutex, core.sync.mutex.Mutex
*/
class RecursiveTaskMutex : core.sync.mutex.Mutex {
	import std.stdio;
	private {
		Mutex m_mutex;
		Task m_owner;
		size_t m_recCount = 0;
		shared(uint) m_waiters = 0;
		ManualEvent m_signal;
	}

	this()
	{
		m_signal = createManualEvent();
		m_mutex = new Mutex;
	}

	this(Object o)
	{
		super(o);
		m_signal = createManualEvent();
		m_mutex = new Mutex;
	}

	override @trusted bool tryLock()
	{
		auto self = Task.getThis();
		synchronized (m_mutex) {
			if (!m_owner) {
				assert(m_recCount == 0);
				m_recCount = 1;
				m_owner = self;
				return true;
			} else if (m_owner == self) {
				m_recCount++;
				return true;
			}
		}
		return false;
	}

	override @trusted void lock()
	{
		if (tryLock()) return;
		atomicOp!"+="(m_waiters, 1);
		version(MutexPrint) writefln("mutex %s wait %s", cast(void*)this, atomicLoad(m_waiters));
		scope(exit) atomicOp!"-="(m_waiters, 1);
		auto ecnt = m_signal.emitCount();
		while (!tryLock()) ecnt = m_signal.wait(ecnt);
	}

	override @trusted void unlock()
	{
		auto self = Task.getThis();
		synchronized (m_mutex) {
			assert(m_owner == self);
			assert(m_recCount > 0);
			m_recCount--;
			if (m_recCount == 0) {
				m_owner = Task.init;
			}

		}
		version(MutexPrint) writefln("mutex %s unlock %s", cast(void*)this, atomicLoad(m_waiters));
		if (atomicLoad(m_waiters) > 0)
			m_signal.emit();
	}
}


class TaskCondition : core.sync.condition.Condition {
	private {
		Mutex m_mutex;
		ManualEvent m_signal;
	}

	this(Mutex mutex)
	{
		super(mutex);
		m_mutex = mutex;
		m_signal = createManualEvent();
	}

	override @trusted @property Mutex mutex() { return m_mutex; }

	override @trusted void wait()
	{
		if (auto tm = cast(TaskMutex)m_mutex) {
			assert(tm.m_locked);
			debug assert(tm.m_owner == Task.getThis());
		}

		auto refcount = m_signal.emitCount;
		m_mutex.unlock();
		scope(failure) m_mutex.lock();
		m_signal.wait(refcount);
		m_mutex.lock();
	}

	override @trusted bool wait(Duration timeout)
	{
		assert(!timeout.isNegative());
		if (auto tm = cast(TaskMutex)m_mutex) {
			assert(tm.m_locked);
			debug assert(tm.m_owner == Task.getThis());
		}

		auto refcount = m_signal.emitCount;
		m_mutex.unlock();
		scope(failure) m_mutex.lock();

		auto succ = m_signal.wait(timeout, refcount) != refcount;

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
ManualEvent createManualEvent()
{
	return getEventDriver().createManualEvent();
}

/** A manually triggered cross-task event.

	Note: the ownership can be shared between multiple fibers and threads.
*/
interface ManualEvent {
	/// A counter that is increased with every emit() call
	@property int emitCount() const;

	/// Emits the signal, waking up all owners of the signal.
	void emit();

	/// Acquires ownership and waits until the signal is emitted.
	void wait();

	/// Acquires ownership and waits until the signal is emitted if no emit has happened since the given reference emit count.
	int wait(int reference_emit_count);

	/// 
	int wait(Duration timeout, int reference_emit_count);
}
