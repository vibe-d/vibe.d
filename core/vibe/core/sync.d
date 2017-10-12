/**
	Interruptible Task synchronization facilities

	Copyright: © 2012-2015 RejectedSoftware e.K.
	Authors: Leonid Kramer, Sönke Ludwig, Manuel Frischknecht
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.sync;

import std.exception;

import vibe.core.driver;

import core.atomic;
import core.sync.mutex;
import core.sync.condition;
import std.stdio;
import std.traits : ReturnType;


enum LockMode {
	lock,
	tryLock,
	defer
}

interface Lockable {
	@safe:
	void lock();
	void unlock();
	bool tryLock();
}

/** RAII lock for the Mutex class.
*/
struct ScopedMutexLock
{
@safe:
	@disable this(this);
	private {
		Mutex m_mutex;
		bool m_locked;
		LockMode m_mode;
	}

	this(core.sync.mutex.Mutex mutex, LockMode mode = LockMode.lock) {
		assert(mutex !is null);
		m_mutex = mutex;

		final switch (mode) {
			case LockMode.lock: lock(); break;
			case LockMode.tryLock: tryLock(); break;
			case LockMode.defer: break;
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
		return m_locked = () @trusted { return m_mutex.tryLock(); } ();
	}

	void lock()
	{
		enforce(!m_locked);
		m_locked = true;
		() @trusted { m_mutex.lock(); } ();
	}
}


/*
	Only for internal use:
	Ensures that a mutex is locked while executing the given procedure.

	This function works for all kinds of mutexes, in particular for
	$(D core.sync.mutex.Mutex), $(D TaskMutex) and $(D InterruptibleTaskMutex).

	Returns:
		Returns the value returned from $(D PROC), if any.
*/
/// private
package(vibe) ReturnType!PROC performLocked(alias PROC, MUTEX)(MUTEX mutex)
{
	mutex.lock();
	scope (exit) mutex.unlock();
	return PROC();
}

///
unittest {
	int protected_var = 0;
	auto mtx = new TaskMutex;
	mtx.performLocked!({
		protected_var++;
	});
}


/**
	Thread-local semaphore implementation for tasks.

	When the semaphore runs out of concurrent locks, it will suspend. This class
	is used in `vibe.core.connectionpool` to limit the number of concurrent
	connections.
*/
class LocalTaskSemaphore
{
@safe:

	// requires a queue
	import std.container.binaryheap;
	import std.container.array;

	private {
		struct Waiter {
			ManualEvent signal;
			ubyte priority;
			uint seq;
		}

		BinaryHeap!(Array!Waiter, asc) m_waiters;
		uint m_maxLocks;
		uint m_locks;
		uint m_seq;
	}

	this(uint max_locks)
	{
		m_maxLocks = max_locks;
	}

	/// Maximum number of concurrent locks
	@property void maxLocks(uint max_locks) { m_maxLocks = max_locks; }
	/// ditto
	@property uint maxLocks() const { return m_maxLocks; }

	/// Number of concurrent locks still available
	@property uint available() const { return m_maxLocks - m_locks; }

	/** Try to acquire a lock.

		If a lock cannot be acquired immediately, returns `false` and leaves the
		semaphore in its previous state.

		Returns:
			`true` is returned $(I iff) the number of available locks is greater
			than one.
	*/
	bool tryLock()
	{
		if (available > 0)
		{
			m_locks++;
			return true;
		}
		return false;
	}

	/** Acquires a lock.

		Once the limit of concurrent locks is reached, this method will block
		until the number of locks drops below the limit.
	*/
	void lock(ubyte priority = 0)
	{
		import std.algorithm : min;

		if (tryLock())
			return;

		Waiter w;
		w.signal = getEventDriver().createManualEvent();
		scope(exit)
			() @trusted { return destroy(w.signal); } ();
		w.priority = priority;
		w.seq = min(0, m_seq - w.priority);
		if (++m_seq == uint.max)
			rewindSeq();

		() @trusted { m_waiters.insert(w); } ();
		w.signal.waitUninterruptible(w.signal.emitCount);
	}

	/** Gives up an existing lock.
	*/
	void unlock()
	{
		if (m_waiters.length > 0) {
			ManualEvent s = m_waiters.front().signal;
			() @trusted { m_waiters.removeFront(); } ();
			s.emit(); // resume one
		} else m_locks--;
	}

	// if true, a goes after b. ie. b comes out front()
	/// private
	static bool asc(ref Waiter a, ref Waiter b)
	{
		if (a.seq == b.seq) {
			if (a.priority == b.priority) {
				// resolve using the pointer address
				return (cast(size_t)&a.signal) > (cast(size_t) &b.signal);
			}
			// resolve using priority
			return a.priority < b.priority;
		}
		// resolve using seq number
		return a.seq > b.seq;
	}

	private void rewindSeq()
	@trusted {
		Array!Waiter waiters = m_waiters.release();
		ushort min_seq;
		import std.algorithm : min;
		foreach (ref waiter; waiters[])
			min_seq = min(waiter.seq, min_seq);
		foreach (ref waiter; waiters[])
			waiter.seq -= min_seq;
		m_waiters.assume(waiters);
	}
}


/**
	Mutex implementation for fibers.

	This mutex type can be used in exchange for a core.sync.mutex.Mutex, but
	does not block the event loop when contention happens. Note that this
	mutex does not allow recursive locking.

	Notice:
		Because this class is annotated nothrow, it cannot be interrupted
		using $(D vibe.core.task.Task.interrupt()). The corresponding
		$(D InterruptException) will be deferred until the next blocking
		operation yields the event loop.

		Use $(D InterruptibleTaskMutex) as an alternative that can be
		interrupted.

	See_Also: InterruptibleTaskMutex, RecursiveTaskMutex, core.sync.mutex.Mutex
*/
class TaskMutex : core.sync.mutex.Mutex, Lockable {
@safe:

	private TaskMutexImpl!false m_impl;

	this(Object o) @trusted { m_impl.setup(); super(o); }
	this() @trusted { m_impl.setup(); }

	override bool tryLock() nothrow { return m_impl.tryLock(); }
	override void lock() nothrow { m_impl.lock(); }
	override void unlock() nothrow { m_impl.unlock(); }
}

unittest {
	auto mutex = new TaskMutex;

	{
		auto lock = ScopedMutexLock(mutex);
		assert(lock.locked);
		assert(mutex.m_impl.m_locked);

		auto lock2 = ScopedMutexLock(mutex, LockMode.tryLock);
		assert(!lock2.locked);
	}
	assert(!mutex.m_impl.m_locked);

	auto lock = ScopedMutexLock(mutex, LockMode.tryLock);
	assert(lock.locked);
	lock.unlock();
	assert(!lock.locked);

	synchronized(mutex){
		assert(mutex.m_impl.m_locked);
	}
	assert(!mutex.m_impl.m_locked);

	mutex.performLocked!({
		assert(mutex.m_impl.m_locked);
	});
	assert(!mutex.m_impl.m_locked);

	with(mutex.ScopedMutexLock) {
		assert(mutex.m_impl.m_locked);
	}
}

unittest { // test deferred throwing
	import vibe.core.core;

	auto mutex = new TaskMutex;
	auto t1 = runTask({
		try {
			mutex.lock();
			scope (exit) mutex.unlock();
			sleep(20.msecs);
		} catch (Exception e) {
			assert(false, "No exception expected in first task: "~e.msg);
		}
	});

	auto t2 = runTask({
		try mutex.lock();
		catch (Exception e) {
			assert(false, "No exception supposed to be thrown: "~e.msg);
		}
		scope (exit) mutex.unlock();
		try {
			yield();
			assert(false, "Yield is supposed to have thrown an InterruptException.");
		} catch (InterruptException) {
			// as expected!
		} catch (Exception e) {
			assert(false, "Only InterruptException supposed to be thrown: "~e.msg);
		}
	});

	runTask({
		// mutex is now locked in first task for 20 ms
		// the second tasks is waiting in lock()
		t2.interrupt();
		t1.join();
		t2.join();
		assert(!mutex.m_impl.m_locked); // ensure that the scope(exit) has been executed
		exitEventLoop();
	});

	runEventLoop();
}

unittest {
	runMutexUnitTests!TaskMutex();
}


/**
	Alternative to $(D TaskMutex) that supports interruption.

	This class supports the use of $(D vibe.core.task.Task.interrupt()) while
	waiting in the $(D lock()) method. However, because the interface is not
	$(D nothrow), it cannot be used as an object monitor.

	See_Also: $(D TaskMutex), $(D InterruptibleRecursiveTaskMutex)
*/
final class InterruptibleTaskMutex : Lockable {
@safe:

	private TaskMutexImpl!true m_impl;

	this() { m_impl.setup(); }

	bool tryLock() nothrow { return m_impl.tryLock(); }
	void lock() { m_impl.lock(); }
	void unlock() nothrow { m_impl.unlock(); }
}

unittest {
	runMutexUnitTests!InterruptibleTaskMutex();
}



/**
	Recursive mutex implementation for tasks.

	This mutex type can be used in exchange for a core.sync.mutex.Mutex, but
	does not block the event loop when contention happens.

	Notice:
		Because this class is annotated nothrow, it cannot be interrupted
		using $(D vibe.core.task.Task.interrupt()). The corresponding
		$(D InterruptException) will be deferred until the next blocking
		operation yields the event loop.

		Use $(D InterruptibleRecursiveTaskMutex) as an alternative that can be
		interrupted.

	See_Also: TaskMutex, core.sync.mutex.Mutex
*/
class RecursiveTaskMutex : core.sync.mutex.Mutex, Lockable {
@safe:

	private RecursiveTaskMutexImpl!false m_impl;

	this(Object o) { m_impl.setup(); super(o); }
	this() { m_impl.setup(); }

	override bool tryLock() { return m_impl.tryLock(); }
	override void lock() { m_impl.lock(); }
	override void unlock() { m_impl.unlock(); }
}

unittest {
	runMutexUnitTests!RecursiveTaskMutex();
}


/**
	Alternative to $(D RecursiveTaskMutex) that supports interruption.

	This class supports the use of $(D vibe.core.task.Task.interrupt()) while
	waiting in the $(D lock()) method. However, because the interface is not
	$(D nothrow), it cannot be used as an object monitor.

	See_Also: $(D RecursiveTaskMutex), $(D InterruptibleTaskMutex)
*/
final class InterruptibleRecursiveTaskMutex : Lockable {
@safe:

	private RecursiveTaskMutexImpl!true m_impl;

	this() { m_impl.setup(); }

	bool tryLock() { return m_impl.tryLock(); }
	void lock() { m_impl.lock(); }
	void unlock() { m_impl.unlock(); }
}

unittest {
	runMutexUnitTests!InterruptibleRecursiveTaskMutex();
}


private void runMutexUnitTests(M)()
{
	import vibe.core.core;

	auto m = new M;
	Task t1, t2;
	void runContendedTasks(bool interrupt_t1, bool interrupt_t2) {
		assert(!m.m_impl.m_locked);

		// t1 starts first and acquires the mutex for 20 ms
		// t2 starts second and has to wait in m.lock()
		t1 = runTask({
			assert(!m.m_impl.m_locked);
			m.lock();
			assert(m.m_impl.m_locked);
			if (interrupt_t1) assertThrown!InterruptException(sleep(100.msecs));
			else assertNotThrown(sleep(20.msecs));
			m.unlock();
		});
		t2 = runTask({
			assert(!m.tryLock());
			if (interrupt_t2) {
				try m.lock();
				catch (InterruptException) return;
				try yield(); // rethrows any deferred exceptions
				catch (InterruptException) {
					m.unlock();
					return;
				}
				assert(false, "Supposed to have thrown an InterruptException.");
			} else assertNotThrown(m.lock());
			assert(m.m_impl.m_locked);
			sleep(20.msecs);
			m.unlock();
			assert(!m.m_impl.m_locked);
		});
	}

	// basic lock test
	m.performLocked!({
		assert(m.m_impl.m_locked);
	});
	assert(!m.m_impl.m_locked);

	// basic contention test
	runContendedTasks(false, false);
	runTask({
		assert(t1.running && t2.running);
		assert(m.m_impl.m_locked);
		t1.join();
		assert(!t1.running && t2.running);
		yield(); // give t2 a chance to take the lock
		assert(m.m_impl.m_locked);
		t2.join();
		assert(!t2.running);
		assert(!m.m_impl.m_locked);
		exitEventLoop();
	});
	runEventLoop();
	assert(!m.m_impl.m_locked);

	// interruption test #1
	runContendedTasks(true, false);
	runTask({
		assert(t1.running && t2.running);
		assert(m.m_impl.m_locked);
		t1.interrupt();
		t1.join();
		assert(!t1.running && t2.running);
		yield(); // give t2 a chance to take the lock
		assert(m.m_impl.m_locked);
		t2.join();
		assert(!t2.running);
		assert(!m.m_impl.m_locked);
		exitEventLoop();
	});
	runEventLoop();
	assert(!m.m_impl.m_locked);

	// interruption test #2
	runContendedTasks(false, true);
	runTask({
		assert(t1.running && t2.running);
		assert(m.m_impl.m_locked);
		t2.interrupt();
		t2.join();
		assert(!t2.running);
		static if (is(M == InterruptibleTaskMutex) || is (M == InterruptibleRecursiveTaskMutex))
			assert(t1.running && m.m_impl.m_locked);
		t1.join();
		assert(!t1.running);
		assert(!m.m_impl.m_locked);
		exitEventLoop();
	});
	runEventLoop();
	assert(!m.m_impl.m_locked);
}


/**
	Event loop based condition variable or "event" implementation.

	This class can be used in exchange for a $(D core.sync.condition.Condition)
	to avoid blocking the event loop when waiting.

	Notice:
		Because this class is annotated nothrow, it cannot be interrupted
		using $(D vibe.core.task.Task.interrupt()). The corresponding
		$(D InterruptException) will be deferred until the next blocking
		operation yields to the event loop.

		Use $(D InterruptibleTaskCondition) as an alternative that can be
		interrupted.

		Note that it is generally not safe to use a `TaskCondition` together with an
		interruptible mutex type.

	See_Also: InterruptibleTaskCondition
*/
class TaskCondition : core.sync.condition.Condition {
@safe:

	private TaskConditionImpl!(false, Mutex) m_impl;

	this(core.sync.mutex.Mutex mtx) nothrow { m_impl.setup(mtx); super(mtx); }

	override @property Mutex mutex() nothrow { return m_impl.mutex; }
	override void wait() { m_impl.wait(); }
	override bool wait(Duration timeout) { return m_impl.wait(timeout); }
	override void notify() { m_impl.notify(); }
	override void notifyAll() { m_impl.notifyAll(); }
}

/** This example shows the typical usage pattern using a `while` loop to make
	sure that the final condition is reached.
*/
unittest {
	import vibe.core.core;

	__gshared Mutex mutex;
	__gshared TaskCondition condition;
	__gshared int workers_still_running = 0;

	// setup the task condition
	mutex = new Mutex;
	condition = new TaskCondition(mutex);

	// start up the workers and count how many are running
	foreach (i; 0 .. 4) {
		workers_still_running++;
		runWorkerTask({
			// simulate some work
			sleep(100.msecs);

			// notify the waiter that we're finished
			synchronized (mutex)
				workers_still_running--;
			condition.notify();
		});
	}

	// wait until all tasks have decremented the counter back to zero
	synchronized (mutex) {
		while (workers_still_running > 0)
			condition.wait();
	}
}


/**
	Alternative to `TaskCondition` that supports interruption.

	This class supports the use of `vibe.core.task.Task.interrupt()` while
	waiting in the `wait()` method.

	See `TaskCondition` for an example.

	Notice:
		Note that it is generally not safe to use an
		`InterruptibleTaskCondition` together with an interruptible mutex type.

	See_Also: `TaskCondition`
*/
final class InterruptibleTaskCondition {
@safe:

	private TaskConditionImpl!(true, Lockable) m_impl;

	this(core.sync.mutex.Mutex mtx) nothrow { m_impl.setup(mtx); }
	this(Lockable mtx) nothrow { m_impl.setup(mtx); }

	@property Lockable mutex() { return m_impl.mutex; }
	void wait() { m_impl.wait(); }
	bool wait(Duration timeout) { return m_impl.wait(timeout); }
	void notify() { m_impl.notify(); }
	void notifyAll() { m_impl.notifyAll(); }
}


/** Creates a new signal that can be shared between fibers.
*/
ManualEvent createManualEvent()
@safe nothrow {
	return getEventDriver().createManualEvent();
}

/** Creates a new signal that can be shared between fibers.
*/
LocalManualEvent createLocalManualEvent()
@safe nothrow {
	return getEventDriver().createManualEvent();
}

alias LocalManualEvent = ManualEvent;

/** A manually triggered cross-task event.

	Note: the ownership can be shared between multiple fibers and threads.
*/
interface ManualEvent {
@safe:

	/// A counter that is increased with every emit() call
	@property int emitCount() const nothrow;

	/// Emits the signal, waking up all owners of the signal.
	void emit() nothrow;

	/** Acquires ownership and waits until the signal is emitted.

		Throws:
			May throw an $(D InterruptException) if the task gets interrupted
			using $(D Task.interrupt()).
	*/
	void wait();

	/** Acquires ownership and waits until the emit count differs from the given one.

		Throws:
			May throw an $(D InterruptException) if the task gets interrupted
			using $(D Task.interrupt()).
	*/
	int wait(int reference_emit_count);

	/** Acquires ownership and waits until the emit count differs from the given one or until a timeout is reached.

		Throws:
			May throw an $(D InterruptException) if the task gets interrupted
			using $(D Task.interrupt()).
	*/
	int wait(Duration timeout, int reference_emit_count);

	/** Same as $(D wait), but defers throwing any $(D InterruptException).

		This method is annotated $(D nothrow) at the expense that it cannot be
		interrupted.
	*/
	int waitUninterruptible(int reference_emit_count) nothrow;

	/// ditto
	int waitUninterruptible(Duration timeout, int reference_emit_count) nothrow;
}


private struct TaskMutexImpl(bool INTERRUPTIBLE) {
	import std.stdio;
	private {
		shared(bool) m_locked = false;
		shared(uint) m_waiters = 0;
		ManualEvent m_signal;
		debug Task m_owner;
	}

	void setup()
	nothrow {
		m_signal = createManualEvent();
	}


	@trusted bool tryLock()
	{
		if (cas(&m_locked, false, true)) {
			debug m_owner = Task.getThis();
			version(MutexPrint) writefln("mutex %s lock %s", cast(void*)this, atomicLoad(m_waiters));
			return true;
		}
		return false;
	}

	@trusted void lock()
	{
		if (tryLock()) return;
		debug assert(m_owner == Task() || m_owner != Task.getThis(), "Recursive mutex lock.");
		atomicOp!"+="(m_waiters, 1);
		version(MutexPrint) writefln("mutex %s wait %s", cast(void*)this, atomicLoad(m_waiters));
		scope(exit) atomicOp!"-="(m_waiters, 1);
		auto ecnt = m_signal.emitCount();
		while (!tryLock()) {
			static if (INTERRUPTIBLE) ecnt = m_signal.wait(ecnt);
			else ecnt = m_signal.waitUninterruptible(ecnt);
		}
	}

	@trusted void unlock()
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

private struct RecursiveTaskMutexImpl(bool INTERRUPTIBLE) {
	import std.stdio;
	private {
		core.sync.mutex.Mutex m_mutex;
		Task m_owner;
		size_t m_recCount = 0;
		shared(uint) m_waiters = 0;
		ManualEvent m_signal;
		@property bool m_locked() const { return m_recCount > 0; }
	}

	void setup()
	{
		m_signal = createManualEvent();
		m_mutex = new core.sync.mutex.Mutex;
	}

	@trusted bool tryLock()
	{
		auto self = Task.getThis();
		return m_mutex.performLocked!({
			if (!m_owner) {
				assert(m_recCount == 0);
				m_recCount = 1;
				m_owner = self;
				return true;
			} else if (m_owner == self) {
				m_recCount++;
				return true;
			}
			return false;
		});
	}

	@trusted void lock()
	{
		if (tryLock()) return;
		atomicOp!"+="(m_waiters, 1);
		version(MutexPrint) writefln("mutex %s wait %s", cast(void*)this, atomicLoad(m_waiters));
		scope(exit) atomicOp!"-="(m_waiters, 1);
		auto ecnt = m_signal.emitCount();
		while (!tryLock()) {
			static if (INTERRUPTIBLE) ecnt = m_signal.wait(ecnt);
			else ecnt = m_signal.waitUninterruptible(ecnt);
		}
	}

	@trusted void unlock()
	{
		auto self = Task.getThis();
		m_mutex.performLocked!({
			assert(m_owner == self);
			assert(m_recCount > 0);
			m_recCount--;
			if (m_recCount == 0) {
				m_owner = Task.init;
			}
		});
		version(MutexPrint) writefln("mutex %s unlock %s", cast(void*)this, atomicLoad(m_waiters));
		if (atomicLoad(m_waiters) > 0)
			m_signal.emit();
	}
}

private struct TaskConditionImpl(bool INTERRUPTIBLE, LOCKABLE) {
	private {
		LOCKABLE m_mutex;

		ManualEvent m_signal;
	}

	static if (is(LOCKABLE == Lockable)) {
		final class MutexWrapper : Lockable {
			private core.sync.mutex.Mutex m_mutex;
			this(core.sync.mutex.Mutex mtx) { m_mutex = mtx; }
			@trusted void lock() { m_mutex.lock(); }
			@trusted void unlock() { m_mutex.unlock(); }
			@trusted bool tryLock() { return m_mutex.tryLock(); }
		}

		void setup(core.sync.mutex.Mutex mtx)
		{
			setup(new MutexWrapper(mtx));
		}
	}

	void setup(LOCKABLE mtx)
	{
		m_mutex = mtx;
		m_signal = createManualEvent();
	}

	@property LOCKABLE mutex() { return m_mutex; }

	@trusted void wait()
	{
		if (auto tm = cast(TaskMutex)m_mutex) {
			assert(tm.m_impl.m_locked);
			debug assert(tm.m_impl.m_owner == Task.getThis());
		}

		auto refcount = m_signal.emitCount;
		m_mutex.unlock();
		scope(exit) m_mutex.lock();
		static if (INTERRUPTIBLE) m_signal.wait(refcount);
		else m_signal.waitUninterruptible(refcount);
	}

	@trusted bool wait(Duration timeout)
	{
		assert(!timeout.isNegative());
		if (auto tm = cast(TaskMutex)m_mutex) {
			assert(tm.m_impl.m_locked);
			debug assert(tm.m_impl.m_owner == Task.getThis());
		}

		auto refcount = m_signal.emitCount;
		m_mutex.unlock();
		scope(exit) m_mutex.lock();

		static if (INTERRUPTIBLE) return m_signal.wait(timeout, refcount) != refcount;
		else return m_signal.waitUninterruptible(timeout, refcount) != refcount;
	}

	@trusted void notify()
	{
		m_signal.emit();
	}

	@trusted void notifyAll()
	{
		m_signal.emit();
	}
}

/** Contains the shared state of a $(D TaskReadWriteMutex).
 *
 *  Since a $(D TaskReadWriteMutex) consists of two actual Mutex
 *  objects that rely on common memory, this class implements
 *  the actual functionality of their method calls.
 *
 *  The method implementations are based on two static parameters
 *  ($(D INTERRUPTIBLE) and $(D INTENT)), which are configured through
 *  template arguments:
 *
 *  - $(D INTERRUPTIBLE) determines whether the mutex implementation
 *    are interruptible by vibe.d's $(D vibe.core.task.Task.interrupt())
 *    method or not.
 *
 *  - $(D INTENT) describes the intent, with which a locking operation is
 *    performed (i.e. $(D READ_ONLY) or $(D READ_WRITE)). RO locking allows for
 *    multiple Tasks holding the mutex, whereas RW locking will cause
 *    a "bottleneck" so that only one Task can write to the protected
 *    data at once.
 */
private struct ReadWriteMutexState(bool INTERRUPTIBLE)
{
@safe:
    /** The policy with which the mutex should operate.
     *
     *  The policy determines how the acquisition of the locks is
     *  performed and can be used to tune the mutex according to the
     *  underlying algorithm in which it is used.
     *
     *  According to the provided policy, the mutex will either favor
     *  reading or writing tasks and could potentially starve the
     *  respective opposite.
     *
     *  cf. $(D core.sync.rwmutex.ReadWriteMutex.Policy)
     */
    enum Policy : int
    {
        /** Readers are prioritized, writers may be starved as a result. */
        PREFER_READERS = 0,
        /** Writers are prioritized, readers may be starved as a result. */
        PREFER_WRITERS
    }

    /** The intent with which a locking operation is performed.
     *
     *  Since both locks share the same underlying algorithms, the actual
     *  intent with which a lock operation is performed (i.e read/write)
     *  are passed as a template parameter to each method.
     */
    enum LockingIntent : bool
    {
        /** Perform a read lock/unlock operation. Multiple reading locks can be
         *  active at a time. */
        READ_ONLY = 0,
        /** Perform a write lock/unlock operation. Only a single writer can
         *  hold a lock at any given time. */
        READ_WRITE = 1
    }

    private {
        //Queue counters
        /** The number of reading tasks waiting for the lock to become available. */
        shared(uint)  m_waitingForReadLock = 0;
        /** The number of writing tasks waiting for the lock to become available. */
        shared(uint)  m_waitingForWriteLock = 0;

        //Lock counters
        /** The number of reading tasks that currently hold the lock. */
        uint  m_activeReadLocks = 0;
        /** The number of writing tasks that currently hold the lock (binary). */
        ubyte m_activeWriteLocks = 0;

        /** The policy determining the lock's behavior. */
        Policy m_policy;

        //Queue Events
        /** The event used to wake reading tasks waiting for the lock while it is blocked. */
        ManualEvent m_readyForReadLock;
        /** The event used to wake writing tasks waiting for the lock while it is blocked. */
        ManualEvent m_readyForWriteLock;

        /** The underlying mutex that gates the access to the shared state. */
        Mutex m_counterMutex;
    }

    this(Policy policy)
    {
        m_policy = policy;
        m_counterMutex = new Mutex();
        m_readyForReadLock  = createManualEvent();
        m_readyForWriteLock = createManualEvent();
    }

    @disable this(this);

    /** The policy with which the lock has been created. */
    @property policy() const { return m_policy; }

    version(RWMutexPrint)
    {
        /** Print out debug information during lock operations. */
        void printInfo(string OP, LockingIntent INTENT)() nothrow
        {
        	import std.string;
            try
            {
                import std.stdio;
                writefln("RWMutex: %s (%s), active: RO: %d, RW: %d; waiting: RO: %d, RW: %d",
                    OP.leftJustify(10,' '),
                    INTENT == LockingIntent.READ_ONLY ? "RO" : "RW",
                    m_activeReadLocks,    m_activeWriteLocks,
                    m_waitingForReadLock, m_waitingForWriteLock
                    );
            }
            catch (Exception t){}
        }
    }

    /** An internal shortcut method to determine the queue event for a given intent. */
    @property ref auto queueEvent(LockingIntent INTENT)()
    {
        static if (INTENT == LockingIntent.READ_ONLY)
            return m_readyForReadLock;
        else
            return m_readyForWriteLock;
    }

    /** An internal shortcut method to determine the queue counter for a given intent. */
    @property ref auto queueCounter(LockingIntent INTENT)()
    {
        static if (INTENT == LockingIntent.READ_ONLY)
            return m_waitingForReadLock;
        else
            return m_waitingForWriteLock;
    }

    /** An internal shortcut method to determine the current emitCount of the queue counter for a given intent. */
    int emitCount(LockingIntent INTENT)()
    {
        return queueEvent!INTENT.emitCount();
    }

    /** An internal shortcut method to determine the active counter for a given intent. */
    @property ref auto activeCounter(LockingIntent INTENT)()
    {
        static if (INTENT == LockingIntent.READ_ONLY)
            return m_activeReadLocks;
        else
            return m_activeWriteLocks;
    }

    /** An internal shortcut method to wait for the queue event for a given intent.
     *
     *  This method is used during the `lock()` operation, after a
     *  `tryLock()` operation has been unsuccessfully finished.
     *  The active fiber will yield and be suspended until the queue event
     *  for the given intent will be fired.
     */
    int wait(LockingIntent INTENT)(int count)
    {
        static if (INTERRUPTIBLE)
            return queueEvent!INTENT.wait(count);
        else
            return queueEvent!INTENT.waitUninterruptible(count);
    }

    /** An internal shortcut method to notify tasks waiting for the lock to become available again.
     *
     *  This method is called whenever the number of owners of the mutex hits
     *  zero; this is basically the counterpart to `wait()`.
     *  It wakes any Task currently waiting for the mutex to be released.
     */
    @trusted void notify(LockingIntent INTENT)()
    {
        static if (INTENT == LockingIntent.READ_ONLY)
        { //If the last reader unlocks the mutex, notify all waiting writers
            if (atomicLoad(m_waitingForWriteLock) > 0)
                m_readyForWriteLock.emit();
        }
        else
        { //If a writer unlocks the mutex, notify both readers and writers
            if (atomicLoad(m_waitingForReadLock) > 0)
                m_readyForReadLock.emit();

            if (atomicLoad(m_waitingForWriteLock) > 0)
                m_readyForWriteLock.emit();
        }
    }

    /** An internal method that performs the acquisition attempt in different variations.
     *
     *  Since both locks rely on a common TaskMutex object which gates the access
     *  to their common data acquisition attempts for this lock are more complex
     *  than for simple mutex variants. This method will thus be performing the
     *  `tryLock()` operation in two variations, depending on the callee:
     *
     *  If called from the outside ($(D WAIT_FOR_BLOCKING_MUTEX) = false), the method
     *  will instantly fail if the underlying mutex is locked (i.e. during another
     *  `tryLock()` or `unlock()` operation), in order to guarantee the fastest
     *  possible locking attempt.
     *
     *  If used internally by the `lock()` method ($(D WAIT_FOR_BLOCKING_MUTEX) = true),
     *  the operation will wait for the mutex to be available before deciding if
     *  the lock can be acquired, since the attempt would anyway be repeated until
     *  it succeeds. This will prevent frequent retries under heavy loads and thus
     *  should ensure better performance.
     */
    @trusted bool tryLock(LockingIntent INTENT, bool WAIT_FOR_BLOCKING_MUTEX)()
    {
        //Log a debug statement for the attempt
        version(RWMutexPrint)
            printInfo!("tryLock",INTENT)();

        //Try to acquire the lock
        static if (!WAIT_FOR_BLOCKING_MUTEX)
        {
            if (!m_counterMutex.tryLock())
                return false;
        }
        else
            m_counterMutex.lock();

        scope(exit)
            m_counterMutex.unlock();

        //Log a debug statement for the attempt
        version(RWMutexPrint)
            printInfo!("checkCtrs",INTENT)();

        //Check if there's already an active writer
        if (m_activeWriteLocks > 0)
            return false;

        //If writers are preferred over readers, check whether there
        //currently is a writer in the waiting queue and abort if
        //that's the case.
        static if (INTENT == LockingIntent.READ_ONLY)
            if (m_policy.PREFER_WRITERS && m_waitingForWriteLock > 0)
                return false;

        //If we are locking the mutex for writing, make sure that
        //there's no reader active.
        static if (INTENT == LockingIntent.READ_WRITE)
            if (m_activeReadLocks > 0)
                return false;

        //We can successfully acquire the lock!
        //Log a debug statement for the success.
        version(RWMutexPrint)
            printInfo!("lock",INTENT)();

        //Increase the according counter
        //(number of active readers/writers)
        //and return a success code.
        activeCounter!INTENT += 1;
        return true;
    }

    /** Attempt to acquire the lock for a given intent.
     *
     *  Returns:
     *      `true`, if the lock was successfully acquired;
     *      `false` otherwise.
     */
    @trusted bool tryLock(LockingIntent INTENT)()
    {
        //Try to lock this mutex without waiting for the underlying
        //TaskMutex - fail if it is already blocked.
        return tryLock!(INTENT,false)();
    }

    /** Acquire the lock for the given intent; yield and suspend until the lock has been acquired. */
    @trusted void lock(LockingIntent INTENT)()
    {
        //Prepare a waiting action before the first
        //`tryLock()` call in order to avoid a race
        //condition that could lead to the queue notification
        //not being fired.
        auto count = emitCount!INTENT;
        atomicOp!"+="(queueCounter!INTENT,1);
        scope(exit)
            atomicOp!"-="(queueCounter!INTENT,1);

        //Try to lock the mutex
        auto locked = tryLock!(INTENT,true)();
        if (locked)
            return;

        //Retry until we successfully acquired the lock
        while(!locked)
        {
            version(RWMutexPrint)
                printInfo!("wait",INTENT)();

            count  = wait!INTENT(count);
            locked = tryLock!(INTENT,true)();
        }
    }

    /** Unlock the mutex after a successful acquisition. */
    @trusted void unlock(LockingIntent INTENT)()
    {
        version(RWMutexPrint)
            printInfo!("unlock",INTENT)();

        debug assert(activeCounter!INTENT > 0);

        synchronized(m_counterMutex)
        {
            //Decrement the counter of active lock holders.
            //If the counter hits zero, notify waiting Tasks
            activeCounter!INTENT -= 1;
            if (activeCounter!INTENT == 0)
            {
                version(RWMutexPrint)
                    printInfo!("notify",INTENT)();

                notify!INTENT();
            }
        }
    }
}

/** A ReadWriteMutex implementation for fibers.
 *
 *  This mutex can be used in exchange for a $(D core.sync.mutex.ReadWriteMutex),
 *  but does not block the event loop in contention situations. The `reader` and `writer`
 *  members are used for locking. Locking the `reader` mutex allows access to multiple
 *  readers at once, while the `writer` mutex only allows a single writer to lock it at
 *  any given time. Locks on `reader` and `writer` are mutually exclusive (i.e. whenever a
 *  writer is active, no readers can be active at the same time, and vice versa).
 *
 *  Notice:
 *      Mutexes implemented by this class cannot be interrupted
 *      using $(D vibe.core.task.Task.interrupt()). The corresponding
 *      InterruptException will be deferred until the next blocking
 *      operation yields the event loop.
 *
 *      Use $(D InterruptibleTaskReadWriteMutex) as an alternative that can be
 *      interrupted.
 *
 *  cf. $(D core.sync.mutex.ReadWriteMutex)
 */
class TaskReadWriteMutex
{
@safe:

    private {
        alias State = ReadWriteMutexState!false;
        alias LockingIntent = State.LockingIntent;
        alias READ_ONLY  = LockingIntent.READ_ONLY;
        alias READ_WRITE = LockingIntent.READ_WRITE;

        /** The shared state used by the reader and writer mutexes. */
        State m_state;
    }

    /** The policy with which the mutex should operate.
     *
     *  The policy determines how the acquisition of the locks is
     *  performed and can be used to tune the mutex according to the
     *  underlying algorithm in which it is used.
     *
     *  According to the provided policy, the mutex will either favor
     *  reading or writing tasks and could potentially starve the
     *  respective opposite.
     *
     *  cf. $(D core.sync.rwmutex.ReadWriteMutex.Policy)
     */
    alias Policy = State.Policy;

    /** A common baseclass for both of the provided mutexes.
     *
     *  The intent for the according mutex is specified through the
     *  $(D INTENT) template argument, which determines if a mutex is
     *  used for read or write locking.
     */
    final class Mutex(LockingIntent INTENT): core.sync.mutex.Mutex, Lockable
    {
        /** Try to lock the mutex. cf. $(D core.sync.mutex.Mutex) */
        override bool tryLock() { return m_state.tryLock!INTENT(); }
        /** Lock the mutex. cf. $(D core.sync.mutex.Mutex) */
        override void lock()    { m_state.lock!INTENT(); }
        /** Unlock the mutex. cf. $(D core.sync.mutex.Mutex) */
        override void unlock()  { m_state.unlock!INTENT(); }
    }
    alias Reader = Mutex!READ_ONLY;
    alias Writer = Mutex!READ_WRITE;

    Reader reader;
    Writer writer;

    this(Policy policy = Policy.PREFER_WRITERS)
    {
        m_state = State(policy);
        reader = new Reader();
        writer = new Writer();
    }

    /** The policy with which the lock has been created. */
    @property Policy policy() const { return m_state.policy; }
}

/** Alternative to $(D TaskReadWriteMutex) that supports interruption.
 *
 *  This class supports the use of $(D vibe.core.task.Task.interrupt()) while
 *  waiting in the `lock()` method.
 *
 *  cf. $(D core.sync.mutex.ReadWriteMutex)
 */
class InterruptibleTaskReadWriteMutex
{
@safe:

    private {
        alias State = ReadWriteMutexState!true;
        alias LockingIntent = State.LockingIntent;
        alias READ_ONLY  = LockingIntent.READ_ONLY;
        alias READ_WRITE = LockingIntent.READ_WRITE;

        /** The shared state used by the reader and writer mutexes. */
        State m_state;
    }

    /** The policy with which the mutex should operate.
     *
     *  The policy determines how the acquisition of the locks is
     *  performed and can be used to tune the mutex according to the
     *  underlying algorithm in which it is used.
     *
     *  According to the provided policy, the mutex will either favor
     *  reading or writing tasks and could potentially starve the
     *  respective opposite.
     *
     *  cf. $(D core.sync.rwmutex.ReadWriteMutex.Policy)
     */
    alias Policy = State.Policy;

    /** A common baseclass for both of the provided mutexes.
     *
     *  The intent for the according mutex is specified through the
     *  $(D INTENT) template argument, which determines if a mutex is
     *  used for read or write locking.
     *
     */
    final class Mutex(LockingIntent INTENT): core.sync.mutex.Mutex, Lockable
    {
        /** Try to lock the mutex. cf. $(D core.sync.mutex.Mutex) */
        override bool tryLock() { return m_state.tryLock!INTENT(); }
        /** Lock the mutex. cf. $(D core.sync.mutex.Mutex) */
        override void lock()    { m_state.lock!INTENT(); }
        /** Unlock the mutex. cf. $(D core.sync.mutex.Mutex) */
        override void unlock()  { m_state.unlock!INTENT(); }
    }
    alias Reader = Mutex!READ_ONLY;
    alias Writer = Mutex!READ_WRITE;

    Reader reader;
    Writer writer;

    this(Policy policy = Policy.PREFER_WRITERS)
    {
        m_state = State(policy);
        reader = new Reader();
        writer = new Writer();
    }

    /** The policy with which the lock has been created. */
    @property Policy policy() const { return m_state.policy; }
}
