/**
	Contains interfaces and enums for evented I/O drivers.

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.driver;

public import vibe.core.file;
public import vibe.core.net;
public import vibe.core.signal;
public import vibe.core.stream;
public import vibe.core.task;

import vibe.inet.url;

import core.time;
import std.exception;


/**
	Returns the active event driver
*/
EventDriver getEventDriver()
{
	return s_driver;
}

/// private
package void setEventDriver(EventDriver driver)
{
	s_driver = driver;
}

package void deleteEventDriver()
{
	// TODO: use destroy() instead
	delete s_driver;
}


private {
	EventDriver s_driver;
}


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
	FileStream openFile(Path path, FileMode mode);

	/** Starts watching a directory for changes.
	*/
	DirectoryWatcher watchDirectory(Path path, bool recursive);

	/** Resolves the given host name or IP address string.
	*/
	NetworkAddress resolveHost(string host, ushort family, bool no_dns);

	/** Establiches a tcp connection on the specified host/port.

		'host' can be a DNS name or an IPv4 or IPv6 address string.
	*/
	TcpConnection connectTcp(string host, ushort port);

	/** Listens on the specified port and interface for TCP connections.

		'bind_address' must be an IPv4 or IPv6 address string corresponding to a local network
		interface. conn_callback is called for every incoming connection, each time from a
		new task.
	*/
	TcpListener listenTcp(ushort port, void delegate(TcpConnection conn) conn_callback, string bind_address);

	/** Creates a new UDP socket and sets the specified address/port as the destination for packets.

		If a bind port is specified, the socket will be able to receive UDP packets on that port.
		Otherwise, a random bind port is chosen.
	*/
	UdpConnection listenUdp(ushort port, string bind_address = "0.0.0.0");

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
	Represents a timer.
*/
interface Timer : EventedObject {
	/// True if the timer is yet to fire.
	@property bool pending();

	/** Resets the timer to the specified timeout
	*/
	void rearm(Duration dur, bool periodic = false);

	/** Resets the timer and avoids any firing.
	*/
	void stop();

	/** Waits until the timer fires.
	*/
	void wait();
}
