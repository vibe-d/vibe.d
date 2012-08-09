/**
	Contains interfaces and enums for evented I/O drivers.

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.driver;

public import vibe.stream.stream;

import vibe.inet.url;

import core.thread;


/**
	Interface for all evented I/O implementations
*/
interface EventDriver {
	/** Starts the event loop.

		The loop will continue to run until either no more event listeners are active or until
		exitEventLoop() is called.
	*/
	int runEventLoop();

	/* Processes all outstanding events, potentially blocking to wait for the first event.
	*/
	int runEventLoopOnce();

	/** Processes all outstanding events if any, does not block.
	*/
	int processEvents();

	/** Exits any running event loop.
	*/
	void exitEventLoop();

	/** Opens a file on disk with the speficied file mode.
	*/
	FileStream openFile(string path, FileMode mode);

	/** Establiches a tcp connection on the specified host/port.

		'host' can be a DNS name or an IPv4 or IPv6 address string.
	*/
	TcpConnection connectTcp(string host, ushort port);

	/** Listens on the specified port and interface for TCP connections.

		'bind_address' must be an IPv4 or IPv6 address string corresponding to a local network
		interface.
	*/
	void listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string bind_address);

	/** Creates a new signal (a single-threaded condition variable).
	*/
	Signal createSignal();

	/** Creates a new timer.

		The timer can be started by calling rearm() with a timeout.
	*/
	Timer createTimer(void delegate() callback);
}

/**
	Provides an event driver with core functions for task/fiber control.
*/
interface DriverCore {
	void yieldForEvent();
	void resumeTask(Task f, Exception event_exception = null);
	void notifyIdle();
}

class Task : Fiber {
	protected this(void delegate() fun, size_t stack_size)
	{
		super(fun);
	}

	static Task getThis(){ return cast(Task)Fiber.getThis(); }
}


/**
	Base interface for all evented objects.

	Evented objects are owned by the fiber/task that created them and may only be used inside this
	specific fiber. By using release(), a fiber can drop the ownership of an object so that 
	another fiber can gain ownership using acquire(). This way it becomes possible to share
	connections and files across fibers.
*/
interface EventedObject {
	/// Releases the ownership of the object.
	void release();

	/// Acquires the ownership of an unowned object.
	void acquire();

	/// Returns true if the calling fiber owns this object
	bool isOwner();
}

/**
	Represents a single TCP connection.
*/
interface TcpConnection : Stream, EventedObject {
	/// Used to disable Nagle's algorithm
	@property void tcpNoDelay(bool enabled);
	/// ditto
	@property bool tcpNoDelay() const;

	/// Controls the read time out after which the connection is closed automatically
	@property void readTimeout(Duration duration)
		in { assert(duration >= dur!"seconds"(0)); }
	/// ditto
	@property Duration readTimeout() const;

	/// Actively closes the connection.
	void close();

	/// The current connection status
	@property bool connected() const;

	/// Returns the IP address of the connected peer.
	@property string peerAddress() const;

	/// Sets a timeout until data has to be availabe for read. Returns false on timeout.
	bool waitForData(Duration timeout);
}

/**
	Specifies how a file is manipulated on disk.
*/
enum FileMode {
	Read,
	ReadWrite,
	CreateTrunc,
	Append
}

/**
	Accesses the contents of a file as a stream.
*/
interface FileStream : Stream, EventedObject {
	/// The path of the file.
	@property Path path() const;

	/// Returns the total size of the file.
	@property ulong size() const;

	/// Determines if this stream is readable.
	@property bool readable() const;

	/// Determines if this stream is writable.
	@property bool writable() const;

	/// Closes the file handle.
	void close();

	/// Seeks to a specific position in the file if supported by the stream.
	void seek(ulong offset);

	/// Returns the current offset of the file pointer
	ulong tell();
}

/** A cross-fiber signal

	Note: the ownership can be shared between multiple fibers.
*/
interface Signal : EventedObject {
	@property int emitCount() const;
	void emit();
	void wait();
	void wait(int reference_emit_count);
}

/**
*/
interface Timer : EventedObject {
	@property bool pending();

	void rearm(Duration dur, bool periodic = false);
	void stop();
	void wait();
}
