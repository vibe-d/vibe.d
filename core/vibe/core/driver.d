/**
	Contains interfaces and enums for asynchronous drivers.

	At the lowest level of Vibe.d sits a library which handle all the
	asynchronous I/O operations.
	There are currently 3 supported I/O backend: libasync, libevent and libev.
	This module define the interface such a library must conform with
	to work with Vibe.d

	Copyright: © 2012-2015 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.driver;

public import vibe.core.file;
public import vibe.core.net;
public import vibe.core.path;
public import vibe.core.sync;
public import vibe.core.stream;
public import vibe.core.task;

import core.time;
import std.exception;


version (VibeUseNativeDriverType) {
	import vibe.core.drivers.native;
	alias StoredEventDriver = NativeEventDriver;
} else alias StoredEventDriver = EventDriver;


/**
	Returns the active event driver
*/
StoredEventDriver getEventDriver(bool ignore_unloaded = false)
@safe nothrow {
	assert(ignore_unloaded || s_driver !is null, "No event driver loaded. Did the vibe.core.core module constructor run?");
	return s_driver;
}

/// private
package void setupEventDriver(DriverCore core_)
{
	version (VibeUseNativeDriverType) {}
	else import vibe.core.drivers.native;

	s_driver = new NativeEventDriver(core_);
}

package void deleteEventDriver()
{
	if (s_driver) {
		s_driver.dispose();
		destroy(s_driver);
		s_driver = null;
	}
}


private {
	StoredEventDriver s_driver;
}


/**
	Interface for all evented I/O implementations.

	This is the low level interface for all event based functionality. It is
	not intended to be used directly by users of the library.
*/
interface EventDriver {
@safe:

	/** Frees all resources of the driver and prepares it for consumption by the GC.

		Note that the driver will not be usable after calling this method. Any
		further calls are illegal and result in undefined behavior.
	*/
	void dispose() /*nothrow*/;

	/** Starts the event loop.

		The loop will continue to run until either no more event listeners are active or until
		exitEventLoop() is called.
	*/
	int runEventLoop() /*nothrow*/;

	/* Processes all outstanding events, potentially blocking to wait for the first event.
	*/
	int runEventLoopOnce() /*nothrow*/;

	/** Processes all outstanding events if any, does not block.
	*/
	bool processEvents() /*nothrow*/;

	/** Exits any running event loop.
	*/
	void exitEventLoop() /*nothrow*/;

	/** Opens a file on disk with the speficied file mode.
	*/
	FileStream openFile(Path path, FileMode mode);

	/** Starts watching a directory for changes.
	*/
	DirectoryWatcher watchDirectory(Path path, bool recursive);

	/** Resolves the given host name or IP address string.

		'host' can be a DNS name (if use_dns is set) or an IPv4 or IPv6
		address string.
	*/
	NetworkAddress resolveHost(string host, ushort family, bool use_dns);

	/** Establiches a tcp connection on the specified host/port.
	*/
	TCPConnection connectTCP(NetworkAddress address, NetworkAddress bind_address);

	/** Listens on the specified port and interface for TCP connections.

		'bind_address' must be an IPv4 or IPv6 address string corresponding to a local network
		interface. conn_callback is called for every incoming connection, each time from a
		new task.
	*/
	TCPListener listenTCP(ushort port, void delegate(TCPConnection conn) @safe conn_callback, string bind_address, TCPListenOptions options);

	/** Creates a new UDP socket and sets the specified address/port as the destination for packets.

		If a bind port is specified, the socket will be able to receive UDP packets on that port.
		Otherwise, a random bind port is chosen.
	*/
	UDPConnection listenUDP(ushort port, string bind_address = "0.0.0.0");

	/** Creates a new manually triggered event.
	*/
	ManualEvent createManualEvent() nothrow;

	/** Creates an event for waiting on a non-bocking file handle.
	*/
	FileDescriptorEvent createFileDescriptorEvent(int file_descriptor, FileDescriptorEvent.Trigger triggers, FileDescriptorEvent.Mode mode);

	/** Creates a new timer.

		The timer can be started by calling rearmTimer() with a timeout.
		The initial reference count is 1, use releaseTimer to free all resources
		associated with the timer.
	*/
	size_t createTimer(void delegate() @safe callback);

	/// Increases the reference count by one.
	void acquireTimer(size_t timer_id);

	/// Decreases the reference count by one.
	void releaseTimer(size_t timer_id);

	/// Queries if the timer is currently active.
	bool isTimerPending(size_t timer_id);

	/// Resets the timeout of the timer.
	void rearmTimer(size_t timer_id, Duration dur, bool periodic);

	/// Stops the timer.
	void stopTimer(size_t timer_id) nothrow;

	/// Waits for the pending timer to expire.
	void waitTimer(size_t timer_id);
}


/**
	Provides an event driver with core functions for task/fiber control.
*/
interface DriverCore {
@safe:

	/** Sets an exception to be thrown on the next call to $(D yieldForEvent).

		Note that this only has an effect if $(D yieldForEvent) is called
		outside of a task. To throw an exception in a task, use the
		$(D event_exception) parameter to $(D resumeTask).
	*/
	@property void eventException(Exception e);

	/** Yields execution until the event loop receives an event.

		Throws:
			May throw an $(D InterruptException) if the task got interrupted
			using $(D vibe.core.task.Task.interrupt()). Rethrows any
			exception that is passed to the $(D resumeTask) call that wakes
			up the task.
	*/
	void yieldForEvent() @safe;

	/** Yields execution until the event loop receives an event.

		Throws:
			This method doesn't throw. Any exceptions, such as
			$(D InterruptException) or an exception passed to $(D resumeTask),
			are stored and thrown on the next call to $(D yieldForEvent).

	*/
	void yieldForEventDeferThrow() nothrow @safe;

	/** Resumes the given task.

		This function may only be called outside of a task to resume a
		yielded task. The optional $(D event_exception) will be thrown in the
		context of the resumed task.

		See_also: $(D yieldAndResumeTask)
	*/
	void resumeTask(Task task, Exception event_exception = null) @safe nothrow;

	/** Yields the current task and resumes another one.

		This is the same as $(D resumeTask), but also works from within a task.
		If called from a task, that task will be yielded first before resuming
		the other one.

		Throws:
			May throw an `InterruptException` if the calling task gets
			interrupted using `Task.interrupt()`.

		See_also: $(D resumeTask)
	*/
	void yieldAndResumeTask(Task task, Exception event_exception = null) @safe;

	/** Notifies the core that all events have been processed.

		This should be called by the driver whenever the event queue has been
		fully processed.
	*/
	void notifyIdle();

	bool isScheduledForResume(Task t);
}


/**
	Generic file descriptor event.

	This kind of event can be used to wait for events on a non-blocking
	file descriptor. Note that this can usually only be used on socket
	based file descriptors.
*/
interface FileDescriptorEvent {
@safe:

	/** Event mask selecting the kind of events to listen for.
	*/
	enum Trigger {
		none = 0,         /// Match no event (invalid value)
		read = 1<<0,      /// React on read-ready events
		write = 1<<1,     /// React on write-ready events
		any = read|write  /// Match any kind of event
	}

	/** Event waiting mode.
	*/
	enum Mode {
		nonPersistent, /// Indicates that the event is non-persistent
		persistent,    /// Indicates that the event is persistent
		edgeTriggered  /// Indicates that the event should be edge-triggered
	}

	/** Waits for the selected event to occur.

		Params:
			which = Optional event mask to react only on certain events
			timeout = Maximum time to wait for an event

		Returns:
			If events occurs, returns a mask of these events.
			If the timeout expired, returns the `Trigger.none`
	*/
	Trigger wait(Trigger which = Trigger.any);
	/// ditto
	Trigger wait(Duration timeout, Trigger which = Trigger.any);
}
