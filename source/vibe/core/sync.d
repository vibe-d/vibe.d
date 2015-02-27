/**
	Interruptible Task synchronization facilities

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
import std.stdio;
enum LockMode {
	lock,
	tryLock,
	defer
}

interface Lockable {
	@trusted bool tryLock();
	@trusted void lock();
	@trusted void unlock();
}

class LockableMutex : Lockable
{
	core.sync.mutex.Mutex m_mutex;

	@property core.sync.mutex.Mutex get() {
		return m_mutex;
	}

	this(core.sync.mutex.Mutex mtx) {
		m_mutex = mtx;
	}

	~this() { }

	@trusted bool tryLock() { return m_mutex.tryLock(); }
	@trusted void lock() { m_mutex.lock(); }
	@trusted void unlock() { m_mutex.unlock(); }
}

ScopedMutexLock scopedLock(core.sync.mutex.Mutex mutex, LockMode mode = LockMode.lock) {
	return ScopedMutexLock(mutex, mode);
}

ScopedMutexLock scopedLock(T : Lockable)(LockMode mode = LockMode.lock) {
	return ScopedMutexLock(new T, mode);
}

ScopedMutexLock scopedLock(T : Lockable)(T mutex, LockMode mode = LockMode.lock) {
	return ScopedMutexLock(mutex, mode);
}

/** RAII lock for the Mutex class.
*/
struct ScopedMutexLock
{
	@disable this(this);
	private {
		Lockable m_mutex;
		bool m_locked;
		LockMode m_mode;
	}
	
	this(core.sync.mutex.Mutex mutex, LockMode mode=LockMode.lock) {
		Lockable mtx = new LockableMutex(mutex);
		this(mtx, mode);
	}
	
	this(Lockable mutex, LockMode mode=LockMode.lock)
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
	
	void unlock()
	{
		enforce(m_locked);
		m_mutex.unlock();
		m_locked = false;
	}
	
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


}

/**
	Mutex implementation for fibers.

	This mutex type can be used in exchange for a core.sync.mutex.Mutex, but
	does not block the event loop when contention happens. Note that this
	mutex does not allow recursive locking.

	See_Also: RecursiveTaskMutex, core.sync.mutex.Mutex
*/

static if (__VERSION__ <= 2066) {
	deprecated("Synchronized and Object.Monitor/inheritance is now unavailable. Use TaskMutexInt instead.")
	class TaskMutex : core.sync.mutex.Mutex {

		this(Object o) {
			super(o);
			m_signal = createManualEvent();
		}

		
		this()
		{
			m_signal = createManualEvent();
		}

		mixin TaskMutexImpl!();
	}
} else {
	deprecated("Synchronized and Object.Monitor/inheritance is now unavailable. Use TaskMutexInt instead.")
	alias TaskMutex = TaskMutexInt;

}


class TaskMutexInt : Lockable {
	
	
	this()
	{
		m_signal = createManualEvent();
	}
	
	mixin TaskMutexImpl!();
}

mixin template TaskMutexImpl() {
	import std.stdio;
	private {
		shared(bool) m_locked = false;
		shared(uint) m_waiters = 0;
		ManualEvent m_signal;
		debug Task m_owner;
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

static if (__VERSION__ <= 2066) {
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
}

unittest {
	auto mutex = new TaskMutexInt;
	{
		auto lock = mutex.scopedLock;
		assert(lock.locked);
		assert(mutex.m_locked);
	}
	{
		auto lock = scopedLock(mutex);
		assert(lock.locked);
		assert(mutex.m_locked);

		auto lock2 = scopedLock(mutex, LockMode.tryLock);
		assert(!lock2.locked);
	}
	assert(!mutex.m_locked);

	auto lock = scopedLock(mutex, LockMode.tryLock);
	assert(lock.locked);
	lock.unlock();
	assert(!lock.locked);

	static if (__VERSION__ >= 2067) {
		with(mutex.scopedLock) {
			assert(mutex.m_locked);
		}
	}
}

/**
	Recursive mutex implementation for tasks.

	This mutex type can be used in exchange for a core.sync.mutex.Mutex, but
	does not block the event loop when contention happens.

	See_Also: TaskMutex, core.sync.mutex.Mutex
*/
static if (__VERSION__ <= 2066) {
	deprecated("Synchronized and Object.Monitor/inheritance is now unavailable. Use RecursiveTaskMutexInt instead.")
	class RecursiveTaskMutex : core.sync.mutex.Mutex {
		this()
		{
			m_signal = createManualEvent();
			m_mutex = new core.sync.mutex.Mutex;
		}

		this(Object o) {
			super(o);
			m_signal = createManualEvent();
			m_mutex = new core.sync.mutex.Mutex;
		}

		mixin RecursiveTaskMutexImpl!();
	}
}
else {
	deprecated("Synchronized and Object.Monitor/inheritance is now unavailable. Use RecursiveTaskMutexInt instead.")
	alias RecursiveTaskMutex = RecursiveTaskMutexInt;
}

class RecursiveTaskMutexInt : Lockable {
	this()
	{
		m_signal = createManualEvent();
		m_mutex = new core.sync.mutex.Mutex;
	}
	
	mixin RecursiveTaskMutexImpl!();
	
}

mixin template RecursiveTaskMutexImpl() {
	import std.stdio;
	private {
		core.sync.mutex.Mutex m_mutex;
		Task m_owner;
		size_t m_recCount = 0;
		shared(uint) m_waiters = 0;
		ManualEvent m_signal;
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

static if (__VERSION__ <= 2066) {
	deprecated("You cannot inherit from TaskCondition anymore. Use TaskConditionInt instead")
	class TaskCondition : core.sync.condition.Condition {
		private {
			Lockable m_mutex;
			ManualEvent m_signal;
		}
		
		this(LockableMutex mtx)
		{
			super(mtx.get);
			m_mutex = mtx;
			m_signal = createManualEvent();
		}
		
		this(core.sync.mutex.Mutex mtx) {
			super(mtx);
			m_mutex = new LockableMutex(mtx);
			m_signal = createManualEvent();
		}
		
		~this() { }
		
		override @trusted @property Mutex mutex() { if (auto mtx = cast(LockableMutex)m_mutex) return mtx.m_mutex; return null; }
		
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
}
else {
	deprecated("You cannot inherit from TaskCondition anymore. Use TaskConditionInt instead")
	alias TaskCondition = TaskConditionInt;
}

class TaskConditionInt {
	private {
		Lockable m_mutex;
		ManualEvent m_signal;
	}
	
	this(Lockable mutex)
	{
		m_mutex = mutex;
		m_signal = createManualEvent();
	}
	
	this(core.sync.mutex.Mutex mutex) {
		m_mutex = new LockableMutex(mutex);
		m_signal = createManualEvent();
	}
	
	~this() { }
	
	@property Lockable mutex() { return m_mutex; }
	
	void wait()
	{
		if (auto tm = cast(TaskMutexInt)m_mutex) {
			assert(tm.m_locked);
			debug assert(tm.m_owner == Task.getThis());
		}
		
		auto refcount = m_signal.emitCount;
		m_mutex.unlock();
		scope(failure) m_mutex.lock();
		m_signal.wait(refcount);
		m_mutex.lock();
	}
	
	bool wait(Duration timeout)
	{
		assert(!timeout.isNegative());
		if (auto tm = cast(TaskMutexInt)m_mutex) {
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
	
	void notify()
	{
		m_signal.emit(); 
	}
	
	void notifyAll()
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
