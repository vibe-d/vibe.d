/**
	Mutex locking functionality.

	Copyright: © 2012 Sönke Ludwig
	Authors: Leonid Kramer
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.mutex;

import std.exception;
import vibe.core.signal;

enum LockMode{
	Lock,
	Try,
	Defer
}


/** RAII lock for the Mutex class.
*/
struct ScopedLock {
	private {
		Mutex m_mutex;
		bool m_locked;
		LockMode m_mode;
	}

	@disable this(this);

	this(Mutex mutex, LockMode mode=LockMode.Lock)
	{
		switch(mode){
			default:
				assert(false, "unsupported enum value");
				break;
			case LockMode.Lock: 
				lock();
				break;
			case LockMode.Try: 
				tryLock();
				break;
			case LockMode.Defer: 
				break;
		}
	}

	~this()
	{
		m_mutex.unlock();
	}

	@property bool locked() const { return m_locked; }

	bool tryLock()
	{
		enforce(!m_locked);
		return m_mutex.tryLock();
	}

	void lock()
	{
		enforce(!m_locked);
		m_mutex.lock();
	}

	void unlock(){
		enforce(m_locked);
		m_mutex.unlock();
	}
}

/** Mutex implementation for fibers.

	Note that this mutex is suitable only for synchronizing different fibers. If you need inter
	thread synchronization, go for core.sync.mutex instead.
*/
class Mutex {
	private {
		bool m_locked = false;
		Signal m_signal;
	}

	private	@property bool locked() const { return m_locked; }

	private bool tryLock()
	{
		if(m_locked) return false;
		m_locked = true;
		return true;
	}

	private void lock()
	{
		if(m_locked){
			m_signal.acquire();
			do{ m_signal.wait(); } while(m_locked);
		}
		m_locked = true;
	}

	private void unlock()
	{
		enforce(m_locked);
		m_locked = false;
	}
}

unittest {
	Mutex mutex;

	{
		auto lock = ScopedLock(mutex);
		assert(lock.locked);
		assert(mutex.locked);

		auto lock2 = ScopedLock(mutex, LockMode.Try);
		assert(!lock2.locked);
	}
	assert(!mutex.locked);

	auto lock = ScopedLock(mutex, LockMode.Try);
	assert(lock.locked);
	lock.unlock();
	assert(!lock.locked);
}