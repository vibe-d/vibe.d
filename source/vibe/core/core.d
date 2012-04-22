/**
	This module contains the core functionality of the vibe framework.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.core;

import vibe.core.log;
import intf.event2.dns;
import intf.event2.event;
import std.conv;
import std.exception;
import std.variant;
import core.thread;

version(Posix){
	import core.sys.posix.signal;
}


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Starts the vibe event loop.

	Note that this function is usually called automatically by the vibe framework. However, if
	you provide your own main() function, you need to call it manually.

	The event loop will continue running during the whole life time of the application.
	Tasks will be started and handled from within the event loop.
	
	The 'num_worker_threads' parameter allows to specify the number of threads
	that are used to handle incoming connections. Increasing the number of threads
	can be useful for server applications that perform a considerable amount of
	CPU work. In this case it is recommended to set the number of worker threads
	equal to the number of CPU cores in the system for optimum performance.
	
	In some cases it may be desirable to specify a number that is higher
	than the actual CPU core count to decrease the maximum wait time for lengthy
	CPU operations. However, if at all possible, such operations should instead
	be broken up into small chunks with calls to vibeYield() inbetween.
*/
int start(int num_worker_threads = 1)
{
	assert(num_worker_threads == 1);
	s_eventLoopRunning = true;
	scope(exit) s_eventLoopRunning = false;
	if( auto err = event_base_loop(s_eventLoop, 0) != 0){
		if( err == 1 ){
			logDebug("No events active, exiting message loop.");
			return 0;
		}
		logError("Error running event loop: %d", err);
		return 1;
	}
	return 0;
}

/**
	Runs a new asynchronous task.

	task will be called synchronously from within the vibeRunTask call. It will
	continue to run until vibeYield() or any of the I/O or wait functions is
	called.
*/
void runTask(void delegate() task)
{
	auto f = new Fiber({
			logTrace("entering task.");
			task();
			logTrace("exiting task.");
			clearTaskLocals();
		});
	s_tasks ~= f;
	logDebug("initial task call");
	vibeResumeTask(f);
	logDebug("run task out");
}

/**
	Suspends the execution of the calling task to let other tasks and events be
	handled.
	
	Calling this function in short intervals is recommended if long CPU
	computations are carried out by a task. It can also be used in conjunction
	with Signals to implement cross-fiber events with no polling.
*/
void yield()
{
	vibeYieldForEvent();
}

/**
	Suspends the execution of the calling task for the specified amount of time.
*/
void sleep(double seconds)
{
	assert(false);
}

/**
	Sets a variable specific to the calling task/fiber.
*/
void setTaskLocal(T)(string name, T value)
{
	auto self = Fiber.getThis();
	auto ptls = self in s_taskLocalStorage;
	if( !ptls ){
		s_taskLocalStorage[self] = null;
		ptls = self in s_taskLocalStorage;
	}
	(*ptls)[name] = Variant(value);
}

/**
	Returns a task/fiber specific variable.
*/
T getTaskLocal(T)(string name)
{
	auto self = Fiber.getThis();
	auto ptls = self in s_taskLocalStorage;
	auto pvar = ptls ? name in *ptls : null;
	enforce(pvar !is null, "Accessing unset TLS variable '"~name~"'.");
	return pvar.get!T();
}

/**
	Returns a task/fiber specific variable.
*/
bool isTaskLocalSet(string name)
{
	auto self = Fiber.getThis();
	auto ptls = self in s_taskLocalStorage;
	auto pvar = ptls ? name in *ptls : null;
	return pvar !is null;
}

/// A version string representing the current vibe version
enum VibeVersionString = "0.8";


/**************************************************************************************************/
/* vibe internal functions                                                                        */
/**************************************************************************************************/
private {
	Variant[string][Fiber] s_taskLocalStorage;
	//Variant[string] s_currentTaskStorage;
}


private extern(C) void extrap()
{
	logTrace("exception trap");
}

package void vibeResumeTask(Fiber f, Exception event_exception = null)
{
	assert(f.state == Fiber.State.HOLD, "Resuming task that is " ~ (f.state == Fiber.state.TERM ? "terminated" : "running"));

	if( event_exception ){
		extrap();
		s_exceptions[f] = event_exception;
	}
	
	auto uncaught_exception = f.call(false);
	if( uncaught_exception ){
		extrap();
		assert(f.state == Fiber.State.TERM);
		logError("Task terminated with unhandled exception: %s", uncaught_exception.toString());
	}
	
	if( f.state == Fiber.State.TERM ){
		s_tasks.removeFromArray(f);
	}
}

package void vibeYieldForEvent()
{
	auto fiber = Fiber.getThis();
	if( fiber ){
		logTrace("yield");
		Fiber.yield();
		logTrace("resume");
		auto pe = fiber in s_exceptions;
		if( pe ){
			auto e = *pe;
			s_exceptions.remove(fiber);
			throw e;
		}
	} else {
		assert(!s_eventLoopRunning, "Event processing outside of a fiber should only happen before the event loop is running!?");
		if( auto err = event_base_loop(s_eventLoop, EVLOOP_ONCE) != 0){
			if( err == 1 ){
				logDebug("No events registered, exiting event loop.");
				throw new Exception("No events registered in vibeYieldForEvent.");
			}
			logError("Error running event loop: %d", err);
			throw new Exception("Error waiting for events.");
		}
	}
}

package event_base* vibeGetEventLoop()
{
	return s_eventLoop;
}

package evdns_base* vibeGetDnsBase()
{
	return s_dnsBase;
}

private void clearTaskLocals()
{
	auto self = Fiber.getThis();
	auto ptls = self in s_taskLocalStorage;
	if( ptls ) s_taskLocalStorage.remove(self);
}

/// private
package void removeFromArray(T)(ref T[] array, T item)
{
	foreach( i; 0 .. array.length )
		if( array[i] is item ){
			array = array[0 .. i] ~ array[i+1 .. $];
			return;
		}
}


/**************************************************************************************************/
/* private functions                                                                              */
/**************************************************************************************************/

private {
	event_base* s_eventLoop;
	evdns_base* s_dnsBase;
	Fiber[] s_tasks;
	Exception[Fiber] s_exceptions;
	bool s_eventLoopRunning = false;
}

shared static this()
{
	version(Windows){
		logTrace("init winsock");
		// initialize WinSock2
		import std.c.windows.winsock;
		WSADATA data;
		WSAStartup(0x0202, &data);
	}
	
	logTrace("event_set_mem_functions");
	// set the malloc/free versions of our runtime so we don't run into trouble
	// because the libevent DLL uses a different one.
	import core.stdc.stdlib;
	event_set_mem_functions(&malloc, &realloc, &free);

	// initialize libevent
	logInfo("libevent version: %s", to!string(event_get_version()));
	s_eventLoop = event_base_new();
	logInfo("libevent is using %s for events.", to!string(event_base_get_method(s_eventLoop)));
	
	s_dnsBase = evdns_base_new(s_eventLoop, 1);
	if( !s_dnsBase ) logError("Failed to initialize DNS lookup.");
	
	version(Posix){
		// support proper shutdown using signals
		sigset_t sigset;
		sigemptyset(&sigset);
		sigaction_t siginfo;
		siginfo.sa_handler = &onSignal;
		siginfo.sa_mask = sigset;
		siginfo.sa_flags = SA_RESTART;
		sigaction(SIGINT, &siginfo, null);
		sigaction(SIGTERM, &siginfo, null);
	}
}

version(Posix){
	private extern(C) void onSignal(int signal)
	{
		logInfo("Received signal %d. Shutting down.", signal);

		if( event_base_loopexit(s_eventLoop, null) ){
			logError("Error shutting down server");
		}
	}
}
