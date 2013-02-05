/**
	This module contains the core functionality of the vibe framework.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.core;

public import vibe.core.driver;

import vibe.core.log;
import vibe.utils.array;
import std.algorithm;
import std.conv;
import std.exception;
import std.functional;
import std.range;
import std.variant;
import core.sync.mutex;
import core.stdc.stdlib;
import core.thread;

import vibe.core.drivers.libev;
import vibe.core.drivers.libevent2;
import vibe.core.drivers.win32;
import vibe.core.drivers.winrt;

version(Posix){
	import core.sys.posix.signal;
}
version(Windows){
	import core.stdc.signal;
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
int runEventLoop()
{
	s_eventLoopRunning = true;
	scope(exit) s_eventLoopRunning = false;

	// runs any yield()ed tasks first
	s_core.notifyIdle();

	if( auto err = getEventDriver().runEventLoop() != 0){
		if( err == 1 ){
			logDebug("No events active, exiting message loop.");
			return 0;
		}
		logError("Error running event loop: %d", err);
		return 1;
	}
	return 0;
}

deprecated int start() { return runEventLoop(); }

/**
	Stops the currently running event loop.

	Calling this function will cause the event loop to stop event processing and
	the corresponding call to runEventLoop() will return to its caller.
*/
void exitEventLoop()
{
	assert(s_eventLoopRunning);
	getEventDriver().exitEventLoop();
}

/**
	Process all pending events without blocking.

	Checks if events are ready to trigger immediately, and run their callbacks if so.
*/
int processEvents()
{
	return getEventDriver().processEvents();
}

/**
	Sets a callback that is called whenever no events are left in the event queue.
*/
void setIdleHandler(void delegate() del)
{
	s_idleHandler = del;
}

/**
	Runs a new asynchronous task.

	task will be called synchronously from within the vibeRunTask call. It will
	continue to run until vibeYield() or any of the I/O or wait functions is
	called.
*/
Task runTask(void delegate() task)
{
	// if there is no fiber available, create one.
	if( s_availableFibersCount == 0 ){
		if( s_availableFibers.length == 0 ) s_availableFibers.length = 1024;
		logDebug("Creating new fiber...");
		s_fiberCount++;
		s_availableFibers[s_availableFibersCount++] = new CoreTask;
	}
	
	// pick the first available fiber
	auto f = s_availableFibers[--s_availableFibersCount];
	f.m_taskFunc = task;
	f.m_taskCounter++;
	auto handle = f.task();
	logDebug("initial task call");
	s_core.resumeTask(handle, null, true);
	logDebug("run task out");
	return handle;
}

/**
	Runs a new asynchronous task in a worker thread.

	NOTE: the interface of this function will change in the future to ensure that no unprotected
	data is passed between threads!

	NOTE: You should not use this function yet and it currently behaves just like runTask.
*/
void runWorkerTask(void delegate() task)
{
	if( st_workerTaskMutex ){
		synchronized(st_workerTaskMutex){
			st_workerTasks ~= task;
		}
		st_workerTaskSignal.emit();
	} else {
		runTask(task);
	}
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
	s_yieldedTasks ~= Task.getThis();
	rawYield();
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
void sleep(Duration timeout)
{
	auto tm = getEventDriver().createTimer(null);
	tm.rearm(timeout);
	tm.wait();
}


/**
	Returns a new armed timer.

	Params:
		timeout = Determines the minimum amount of time that elapses before the timer fires.
		callback = This delegate will be called when the timer fires
		periodic = Speficies if the timer fires repeatedly or only once

	Returns:
		Returns a Timer object that can be used to identify and modify the timer.
*/
Timer setTimer(Duration timeout, void delegate() callback, bool periodic = false)
{
	auto tm = getEventDriver().createTimer(callback);
	tm.rearm(timeout, periodic);
	return tm;
}

/**
	Sets a variable specific to the calling task/fiber.

	Remarks:
		This function also works if called from outside if a fiber. In this case, it will work
		on a thread local storage.
*/
void setTaskLocal(T)(string name, T value)
{
	auto self = cast(CoreTask)Fiber.getThis();
	if( self ) self.set(name, value);
	s_taskLocalStorageGlobal[name] = Variant(value);
}

/**
	Returns a task/fiber specific variable.

	Remarks:
		This function also works if called from outside if a fiber. In this case, it will work
		on a thread local storage.
*/
T getTaskLocal(T)(string name)
{
	auto self = cast(CoreTask)Fiber.getThis();
	if( self ) return self.get!T(name);
	auto pvar = name in s_taskLocalStorageGlobal;
	enforce(pvar !is null, "Accessing unset TLS variable '"~name~"'.");
	return pvar.get!T();
}

/**
	Returns a task/fiber specific variable.

	Remarks:
		This function also works if called from outside if a fiber. In this case, it will work
		on a thread local storage.
*/
bool isTaskLocalSet(string name)
{
	auto self = cast(CoreTask)Fiber.getThis();
	if( self ) return self.isSet(name);
	return (name in s_taskLocalStorageGlobal) !is null;
}

/**
	Sets the stack size for tasks.

	The default stack size is set to 16 KiB, which is sufficient for most tasks. Tuning this value
	can be used to reduce memory usage for great numbers of concurrent tasks or to allow applications
	with heavy stack use.

	Note that this function must be called before any task is started to have an effect.
*/
void setTaskStackSize(size_t sz)
{
	s_taskStackSize = sz;
}

/**
	Enables multithreaded worker task processing.

	This function will start up a number of worker threads that will process tasks started using
	runWorkerTask(). runTask() will still execute tasks on the calling thread.

	Note that this functionality is experimental right now and is not recommended for general use.
*/
void enableWorkerThreads()
{
	assert(st_workerTaskMutex is null);

	st_workerTaskMutex = new Mutex;	

	foreach( i; 0 .. 4 ){
		auto thr = new Thread(&workerThreadFunc);
		thr.name = "Vibe Task Worker";
		thr.start();
	}
}

/**
	A version string representing the current vibe version
*/
enum VibeVersionString = "0.7.11";


/**************************************************************************************************/
/* private types                                                                                  */
/**************************************************************************************************/

private class CoreTask : TaskFiber {
	private {
		void delegate() m_taskFunc;
		Exception m_exception;
		Task[] m_yielders;
	}

	this()
	{
		super(&run, s_taskStackSize);
	}

	private void run()
	{
		scope(failure) logError("CoreTaskFiber was terminated unexpectedly.");

		while(true){
			while( !m_taskFunc ){
				try {
					s_core.yieldForEvent();
				} catch( Exception e ){
					logWarn("CorTaskFiber was resumed with exception but without active task!");
					logDebug("Full error: %s", e.toString().sanitize());
				}
			}

			auto task = m_taskFunc;
			m_taskFunc = null;
			try {
				m_running = true;
				scope(exit) m_running = false;
				logTrace("entering task.");
				task();
				logTrace("exiting task.");
			} catch( Exception e ){
				logError("Task terminated with exception: %s", e.toString());
			}
			resetLocalStorage();

			foreach( t; m_yielders ) s_core.resumeTask(t);
			
			// make the fiber available for the next task
			if( s_availableFibers.length <= s_availableFibersCount )
				s_availableFibers.length = 2*s_availableFibers.length;
			s_availableFibers[s_availableFibersCount++] = this;
		}
	}

	override void join()
	{
		auto caller = Task.getThis();
		assert(caller !is this, "A task cannot join itself.");
		m_yielders ~= caller;
		auto run_count = m_taskCounter;
		if( m_running && run_count == m_taskCounter ){
			s_core.resumeTask(this.task);
			while( m_running && run_count == m_taskCounter ) rawYield();
		}
	}

	override void interrupt()
	{
		auto caller = Task.getThis();
		assert(caller != this.task, "A task cannot interrupt itself.");
		assert(caller.thread is this.thread, "Interrupting tasks in different threads is not yet supported.");
		s_core.resumeTask(this.task, new InterruptException);
	}

	override void terminate()
	{
		assert(false, "Not implemented");
	}
}


private class VibeDriverCore : DriverCore {
	private {
		Duration m_gcCollectTimeout;
		Timer m_gcTimer;
		bool m_ignoreIdleForGC = false;
	}

	private void setupGcTimer()
	{
		m_gcTimer = getEventDriver().createTimer(&collectGarbage);
		m_gcCollectTimeout = dur!"seconds"(2);
	}

	void yieldForEvent()
	{
		auto fiber = cast(CoreTask)Fiber.getThis();
		if( fiber ){
			logTrace("yield");
			Fiber.yield();
			logTrace("resume");
			auto e = fiber.m_exception;
			if( e ){
				fiber.m_exception = null;
				throw e;
			}
		} else {
			assert(!s_eventLoopRunning, "Event processing outside of a fiber should only happen before the event loop is running!?");
			if( auto err = getEventDriver().runEventLoopOnce() ){
				if( err == 1 ){
					logDebug("No events registered, exiting event loop.");
					throw new Exception("No events registered in vibeYieldForEvent.");
				}
				logError("Error running event loop: %d", err);
				throw new Exception("Error waiting for events.");
			}
		}
	}

	void resumeTask(Task task, Exception event_exception = null)
	{
		resumeTask(task, event_exception, false);
	}

	void resumeTask(Task task, Exception event_exception, bool initial_resume)
	{
		CoreTask ctask = cast(CoreTask)task.fiber;
		assert(ctask.state == Fiber.State.HOLD, "Resuming fiber that is " ~ (ctask.state == Fiber.State.TERM ? "terminated" : "running"));

		assert(initial_resume || task.running, "Resuming terminated task.");

		if( event_exception ){
			extrap();
			ctask.m_exception = event_exception;
		}
		
		auto uncaught_exception = task.call(false);
		if( uncaught_exception ){
			extrap();
			assert(task.state == Fiber.State.TERM);
			logError("Task terminated with unhandled exception: %s", uncaught_exception.toString());
		}
	}

	void notifyIdle()
	{
		while(true){
			Task[] tmp;
			swap(s_yieldedTasks, tmp);
			foreach(t; tmp) resumeTask(t);
			if( s_yieldedTasks.length == 0 ) break;
			processEvents();
		}

		if( s_idleHandler ) s_idleHandler();

		if( !m_ignoreIdleForGC && m_gcTimer ){
			m_gcTimer.rearm(m_gcCollectTimeout);
		} else m_ignoreIdleForGC = false;
	}

	private void collectGarbage()
	{
		import core.memory;
		logTrace("gc idle collect");
		GC.collect();
		GC.minimize();
		m_ignoreIdleForGC = true;
	}
}


/**************************************************************************************************/
/* private functions                                                                              */
/**************************************************************************************************/

private {
	__gshared size_t s_taskStackSize = 16*4096;
	Task[] s_yieldedTasks;
	bool s_eventLoopRunning = false;
	__gshared VibeDriverCore s_core;
	Variant[string] s_taskLocalStorageGlobal; // for use outside of a task
	CoreTask[] s_availableFibers;
	size_t s_availableFibersCount;
	size_t s_fiberCount;
	void delegate() s_idleHandler;

	__gshared Mutex st_workerTaskMutex;
	__gshared void delegate()[] st_workerTasks;
	__gshared Signal st_workerTaskSignal;
}

// per process setup
shared static this()
{
	version(Windows){
		logTrace("init winsock");
		// initialize WinSock2
		import std.c.windows.winsock;
		WSADATA data;
		WSAStartup(0x0202, &data);

	}
	
	logTrace("create driver core");
	
	s_core = new VibeDriverCore;

	version(Posix){
		logTrace("setup signal handler");
		// support proper shutdown using signals
		sigset_t sigset;
		sigemptyset(&sigset);
		sigaction_t siginfo;
		siginfo.sa_handler = &onSignal;
		siginfo.sa_mask = sigset;
		siginfo.sa_flags = SA_RESTART;
		sigaction(SIGINT, &siginfo, null);
		sigaction(SIGTERM, &siginfo, null);

		siginfo.sa_handler = &onBrokenPipe;
		sigaction(SIGPIPE, &siginfo, null);
	}

	version(Windows){
		signal(SIGABRT, &onSignal);
		signal(SIGTERM, &onSignal);
		signal(SIGINT, &onSignal);
	}

	setupDriver();

	version(VibeIdleCollect){
		logTrace("setup gc");
		s_core.setupGcTimer();
	}
}

shared static ~this()
{
	bool tasks_left = false;

	if(st_workerTaskMutex !is null) { //This mutex is experimentally in enableWorkerThreads
		synchronized(st_workerTaskMutex){ 
			if( !st_workerTasks.empty ) tasks_left = true;
		}	
	} else {
		if( !st_workerTasks.empty ) tasks_left = true;
	}

	
	if( !s_yieldedTasks.empty ) tasks_left = true;
	if( tasks_left ) logWarn("There are still tasks running at exit.");

	delete s_core;
}

// per thread setup
static this()
{
	assert(s_core !is null);

	setupDriver();

	if( st_workerTaskMutex ){
		synchronized(st_workerTaskMutex)
		{
			if( !st_workerTaskSignal ){
				st_workerTaskSignal = getEventDriver().createSignal();
				st_workerTaskSignal.release();
				assert(!st_workerTaskSignal.isOwner());
			}
		}
	}
}

static ~this()
{
	deleteEventDriver();
}

private void setupDriver()
{
	if( getEventDriver() !is null ) return;

	logTrace("create driver");
	version(VibeWin32Driver) setEventDriver(new Win32EventDriver(s_core));
	else version(VibeWinrtDriver) setEventDriver(new WinRtEventDriver(s_core));
	else version(VibeLibevDriver) setEventDriver(new LibevDriver(s_core));
	else setEventDriver(new Libevent2Driver(s_core));
}

private void workerThreadFunc()
{
	logDebug("entering worker thread");
	runTask(toDelegate(&handleWorkerTasks));
	logDebug("running event loop");
	runEventLoop();
}

private void handleWorkerTasks()
{
	logDebug("worker task enter");
	yield();

	logDebug("worker task loop enter");
	assert(!st_workerTaskSignal.isOwner());
	while(true){
		void delegate() t;
		auto emit_count = st_workerTaskSignal.emitCount;
		synchronized(st_workerTaskMutex){
			logDebug("worker task check");
			if( st_workerTasks.length ){
				logDebug("worker task got");
				t = st_workerTasks.front;
				st_workerTasks.popFront();
			}
		}
		assert(!st_workerTaskSignal.isOwner());
		if( t ) runTask(t);
		else st_workerTaskSignal.wait(emit_count);
		assert(!st_workerTaskSignal.isOwner());
	}
}

private extern(C) nothrow
{
	void extrap()
	{
		logTrace("exception trap");
	}

	nothrow void onSignal(int signal)
	{
		logInfo("Received signal %d. Shutting down.", signal);

		if( s_eventLoopRunning ) try exitEventLoop(); catch(Exception e) {}
		else exit(1);
	}

	void onBrokenPipe(int signal)
	{
	}
}
