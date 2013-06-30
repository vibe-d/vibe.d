/**
	Contains interfaces and enums for evented I/O drivers.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.driver;

public import vibe.core.file;
public import vibe.core.net;
public import vibe.core.sync;
public import vibe.core.stream;
public import vibe.core.task;
public import vibe.core._eventedobject;

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
	bool processEvents();

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
	TCPConnection connectTCP(string host, ushort port);

	/// Deprecated compatibility alias
	deprecated("Please use connectTCP instead.") alias connectTcp = connectTCP;

	/** Listens on the specified port and interface for TCP connections.

		'bind_address' must be an IPv4 or IPv6 address string corresponding to a local network
		interface. conn_callback is called for every incoming connection, each time from a
		new task.
	*/
	TCPListener listenTCP(ushort port, void delegate(TCPConnection conn) conn_callback, string bind_address, TCPListenOptions options);

	/// Deprecated compatibility alias
	deprecated("Please use listenTCP instead.") alias listenTcp = listenTCP;

	/** Creates a new UDP socket and sets the specified address/port as the destination for packets.

		If a bind port is specified, the socket will be able to receive UDP packets on that port.
		Otherwise, a random bind port is chosen.
	*/
	UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0");

	/// Deprecated compatibility alias
	deprecated("Please use listenUDP instead.") alias listenUdp = listenUDP;

	/** Creates a new manually triggered event.
	*/
	ManualEvent createManualEvent();

	/// Deprecated compatibility alias
	deprecated("Please use createNanualEvent instead.") alias createSignal = createManualEvent;

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


mixin template SingleOwnerEventedObject() {
	protected {
		Task m_owner;
	}

	protected void release()
	{
		assert(amOwner(), "Releasing evented object that is not owned by the calling task.");
		m_owner = Task();
	}

	protected void acquire()
	{
		assert(m_owner == Task(), "Acquiring evented object that is already owned.");
		m_owner = Task.getThis();
	}

	protected bool amOwner()
	{
		return m_owner != Task() && m_owner == Task.getThis();
	}
}

mixin template MultiOwnerEventedObject() {
	protected {
		Task[] m_owners;
	}

	protected void release()
	{
		auto self = Task.getThis();
		auto idx = m_owners.countUntil(self);
		assert(idx >= 0, "Releasing evented object that is not owned by the calling task.");
		m_owners = m_owners[0 .. idx] ~ m_owners[idx+1 .. $];
	}

	protected void acquire()
	{
		auto self = Task.getThis();
		assert(!amOwner(), "Acquiring evented object that is already owned by the calling task.");
		m_owners ~= self;
	}

	protected bool amOwner()
	{
		return m_owners.countUntil(Task.getThis()) >= 0;
	}
}
