/**
	This module contains the core functionality of the vibe framework.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.core;

public import vibe.core.driver;

import vibe.core.log;
import std.conv;
import std.exception;
import std.variant;
import core.stdc.stdlib;
import core.thread;

import vibe.core.drivers.libevent2;

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
*/
int start()
{
	s_eventLoopRunning = true;
	scope(exit) s_eventLoopRunning = false;
	if( auto err = s_driver.runEventLoop() != 0){
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
	s_core.resumeTask(f);
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
	assert(false);
}


/**
	Yields execution of this task until an event wakes it up again.

	Beware that the task will starve if no event wakes it up.
*/
void rawYield()
{
	s_core.yieldForEvent();
}

/**
	Suspends the execution of the calling task for the specified amount of time.
*/
void sleep(double seconds)
{
	s_driver.sleep(seconds);
}

/**
	Returns the active event driver
*/
EventDriver getEventDriver()
{
	return s_driver;
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

/**
	A version string representing the current vibe version
*/
enum VibeVersionString = "0.8";


/**************************************************************************************************/
/* private types                                                                                  */
/**************************************************************************************************/

private class VibeDriverCore : DriverCore {
	void yieldForEvent()
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
			if( auto err = s_driver.processEvents() != 0){
				if( err == 1 ){
					logDebug("No events registered, exiting event loop.");
					throw new Exception("No events registered in vibeYieldForEvent.");
				}
				logError("Error running event loop: %d", err);
				throw new Exception("Error waiting for events.");
			}
		}
	}

	void resumeTask(Fiber fiber, Exception event_exception = null)
	{
		assert(fiber.state == Fiber.State.HOLD, "Resuming task that is " ~ (fiber.state == Fiber.State.TERM ? "terminated" : "running"));

		if( event_exception ){
			extrap();
			s_exceptions[fiber] = event_exception;
		}
		
		auto uncaught_exception = fiber.call(false);
		if( uncaught_exception ){
			extrap();
			assert(fiber.state == Fiber.State.TERM);
			logError("Task terminated with unhandled exception: %s", uncaught_exception.toString());
		}
		
		if( fiber.state == Fiber.State.TERM ){
			s_tasks.removeFromArray(fiber);
		}
	}
}


/**************************************************************************************************/
/* private functions                                                                              */
/**************************************************************************************************/

private {
	Fiber[] s_tasks;
	Exception[Fiber] s_exceptions;
	bool s_eventLoopRunning = false;
	VibeDriverCore s_core;
	EventDriver s_driver;
	Variant[string][Fiber] s_taskLocalStorage;
	//Variant[string] s_currentTaskStorage;
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
	s_core = new VibeDriverCore;
	s_driver = new Libevent2Driver(s_core);
	
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

private extern(C) void extrap()
{
	logTrace("exception trap");
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

version(Posix){
	private extern(C) void onSignal(int signal)
	{
		logInfo("Received signal %d. Shutting down.", signal);

		if( s_eventLoopRunning ) s_driver.exitEventLoop();
		else exit(1);
	}
}
