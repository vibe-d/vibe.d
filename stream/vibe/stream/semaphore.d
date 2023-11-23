/** I/O concurrency limiting wrapper stream

	Copyright: © 2023 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.semaphore;

import vibe.core.stream;

import core.time;


/** Creates a new semaphore stream instance.

	Params:
		stream = The stream to forward any operations to
		semaphore = Semaphore-like object that offers a `lock`/`unlock` or
			`wait`/`notify` interface to limit the amount of concurrent I/O
			operations. `vibe.core.sync` provides a suitable semaphore
			implementation.
		lock_args = Optional arguments to pass to the semaphore's `lock`/`wait`
			method.

	See_also: `SemaphoreStream`
*/
SemaphoreStream!(Stream, Semaphore, LockArgs) createSemaphoreStream
	(Stream, Semaphore, LockArgs...)(Stream stream, Semaphore semaphore, LockArgs lock_args)
	if (isInputStream!Stream || isOutputStream!Stream)
{
	static assert(
			is(typeof(semaphore.lock())) && is(typeof(semaphore.unlock()))
			|| is(typeof(semaphore.wait())) && is(typeof(semaphore.notify())),
		"Semaphore type must have lock/unlock or wait/notify methods.");

	return SemaphoreStream!(Stream, Semaphore, LockArgs)(stream, semaphore, lock_args);
}


/** Limits the number concurrent blocking operations using a semaphore.

	This stream can be used to wrap any type of stream in order to limit the
	amount of concurrent I/O operations across all streams that use the same
	semaphore. The main use for this is avoiding high concurrency overhead on
	I/O devices with bad random access performance, such as spinning hard disks.

	See_also: `createSemaphoreStream`
*/
struct SemaphoreStream(Stream, Semaphore, LockArgs...) {
	private {
		Stream m_stream;
		Semaphore m_semaphore;
		LockArgs m_lockArgs;
	}

	private this(Stream stream, Semaphore semaphore, LockArgs lock_args)
	{
		m_stream = stream;
		m_semaphore = semaphore;
		m_lockArgs = lock_args;
	}

	static if (isInputStream!Stream) {
		@property bool empty() @blocking { auto l = lock(); return m_stream.empty; }
		@property ulong leastSize() @blocking { auto l = lock(); return m_stream.leastSize; }
		@property bool dataAvailableForRead() { return m_stream.dataAvailableForRead; }
		const(ubyte)[] peek() { return m_stream.peek; }
		size_t read(scope ubyte[] dst, IOMode mode) @blocking { auto l = lock(); return m_stream.read(dst, mode); }
		void read(scope ubyte[] dst) @blocking { auto n = read(dst, IOMode.all); assert(n == dst.length); }
	}

	static if (isOutputStream!Stream) {
		enum outputStreamVersion = 2;

		size_t write(scope const(ubyte)[] bytes, IOMode mode) @blocking { auto l = lock(); return m_stream.write(bytes, mode); }
		void write(scope const(ubyte)[] bytes) @blocking { auto n = write(bytes, IOMode.all); assert(n == bytes.length); }
		void write(scope const(char)[] bytes) @blocking { write(cast(const(ubyte)[])bytes); }
		void flush() @blocking { auto l = lock(); m_stream.flush(); }
		void finalize() @blocking { auto l = lock(); m_stream.finalize(); }
	}

	static if (isConnectionStream!Stream) {
		@property bool connected() const { return m_stream.connected; }
		void close() @blocking { auto l = lock(); m_stream.close(); }
		bool waitForData(Duration timeout = Duration.max) @blocking { auto l = lock(); return m_stream.waitForData(timeout); }
	}

	static if (isRandomAccessStream!Stream) {
		@property ulong size() const nothrow { return m_stream.size; }
		@property bool readable() const nothrow { return m_stream.readable; }
		@property bool writable() const nothrow { return m_stream.writable; }
		void seek(ulong offset) @blocking { auto l = lock(); m_stream.seek(offset); }
		ulong tell() nothrow { return m_stream.tell(); }
	}

	static if (isTruncatableStream!Stream) {
		void truncate(ulong size) @blocking { auto l = lock(); return m_stream.truncate(size); }
	}

	static if (isClosableRandomAccessStream!Stream) {
		@property bool isOpen() const nothrow { return m_stream.isOpen; }
		void close() @blocking { auto l = lock(); return m_stream.close(); }
	}

	private auto lock()
	@safe nothrow {
		struct L {
			Semaphore* sem;
			@disable this(this);
			~this() {
				if (sem) {
					static if (is(typeof((*sem).unlock())))
						sem.unlock();
					else sem.notify();
				}
			}
		}

		static if (is(typeof(m_semaphore.lock(m_lockArgs))))
			m_semaphore.lock(m_lockArgs);
		else m_semaphore.wait(m_lockArgs);
		return L(() @trusted { return &m_semaphore; } ());
	}
}

mixin validateInputStream!(SemaphoreStream!(InputStream, DummySemaphore));
mixin validateOutputStream!(SemaphoreStream!(OutputStream, DummySemaphore));
mixin validateStream!(SemaphoreStream!(Stream, DummySemaphore));
mixin validateConnectionStream!(SemaphoreStream!(ConnectionStream, DummySemaphore));
mixin validateRandomAccessStream!(SemaphoreStream!(RandomAccessStream, DummySemaphore));
mixin validateTruncatableStream!(SemaphoreStream!(TruncatableStream, DummySemaphore));
mixin validateClosableRandomAccessStream!(SemaphoreStream!(ClosableRandomAccessStream, DummySemaphore));

private struct DummySemaphore {
	void lock() @safe nothrow {}
	void unlock() @safe nothrow {}
}
