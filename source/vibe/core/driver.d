/**
	Contains interfaces and enums for evented I/O drivers.

	Copyright: © 2012 Sönke Ludwig
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.driver;

public import vibe.crypto.ssl;
public import vibe.stream.stream;

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

	/** Processes all outstanding events, potentially blocking until the first event comes
		available.
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

	/** 
	*/
	Timer createTimer(void delegate() callback);
}

/**
	Provides an event driver with core functions for task/fiber control.
*/
interface DriverCore {
	void yieldForEvent();
	void resumeTask(Fiber f, Exception event_exception = null);
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
	CreateTrunc,
	Append
}

/**
	Accesses the contents of a file as a stream.
*/
interface FileStream : Stream, EventedObject {
	/// Closes the file handle.
	void close();

	/// Returns the total size of the file.
	@property ulong size() const;

	/// Determines if this stream is readable.
	@property bool readable() const;

	/// Determines if this stream is writable.
	@property bool writable() const;

	/// Seeks to a specific position in the file if supported by the stream.
	void seek(ulong offset);
}

/** A cross-fiber signal

	Note: the ownership can be shared between multiple fibers.
*/
interface Signal : EventedObject {
	@property int emitCount() const;
	void emit();
	void wait();
}

/**
*/
interface Timer : EventedObject {
	@property bool pending();

	void rearm(Duration dur, bool periodic = false);
	void stop();
	void wait();
}
