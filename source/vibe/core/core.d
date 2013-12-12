/**
	This module contains the core functionality of the vibe framework.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.core;

public import vibe.core.driver;

import vibe.core.args;
import vibe.core.concurrency;
import vibe.core.log;
import vibe.utils.array;
import std.algorithm;
import std.conv;
import std.encoding;
import std.exception;
import std.functional;
import std.range;
import std.string;
import std.variant;
import core.atomic;
import core.sync.condition;
import core.sync.mutex;
import core.stdc.stdlib;
import core.thread;

version(VibeLibevDriver) import vibe.core.drivers.libev;
version(VibeLibeventDriver) import vibe.core.drivers.libevent2;
version(VibeWin32Driver) import vibe.core.drivers.win32;
version(VibeWinrtDriver) import vibe.core.drivers.winrt;

version(Posix)
{
	import core.sys.posix.signal;
	import core.sys.posix.unistd;
	import core.sys.posix.pwd;

	static if (__traits(compiles, {import core.sys.posix.grp; getgrgid(0);})) {
		import core.sys.posix.grp;
	} else {
		extern (C) {
			struct group {
				char*   gr_name;
				char*   gr_passwd;
				gid_t   gr_gid;
				char**  gr_mem;
			}
			group* getgrgid(gid_t);
			group* getgrnam(in char*);
		}
	}
}

version (Windows)
{
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
	scope(exit) {
		s_eventLoopRunning = false;
		s_exitEventLoop = false;
		st_threadShutdownCondition.notifyAll();
	}

	// runs any yield()ed tasks first
	assert(!s_exitEventLoop);
	s_exitEventLoop = false;
	s_core.notifyIdle();
	if (s_exitEventLoop) return 0;

	// handle worker tasks and st_term
	runTask(toDelegate(&handleWorkerTasks));

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

/**
	Stops the currently running event loop.

	Calling this function will cause the event loop to stop event processing and
	the corresponding call to runEventLoop() will return to its caller.
*/
void exitEventLoop(bool shutdown_all_threads = true)
{
	assert(s_eventLoopRunning || shutdown_all_threads);
	if (shutdown_all_threads) {
		auto thisthr = Thread.getThis();
		atomicStore(st_term, true);
		st_workerTaskSignal.emit();

		synchronized (st_workerTaskMutex) {
			while (true) {
				if (!st_threads.canFind!(c => c.thread !is thisthr))
					break;

				st_threadShutdownCondition.wait();
			}
		}
	}

	// shutdown the calling thread
	if (s_eventLoopRunning) getEventDriver().exitEventLoop();
}

/**
	Process all pending events without blocking.

	Checks if events are ready to trigger immediately, and run their callbacks if so.

	Returns: Returns false iff exitEventLoop was called in the process.
*/
bool processEvents()
{
	return getEventDriver().processEvents();
}

/**
	Sets a callback that is called whenever no events are left in the event queue.

	The callback delegate is called whenever all events in the event queue have been
	processed. Returning true from the callback will cause another idle event to
	be triggered immediately after processing any events that have arrived in the
	meantime. Returning fals will instead wait until another event has arrived first.
*/
void setIdleHandler(void delegate() del)
{
	s_idleHandler = { del(); return false; };
}
/// ditto
void setIdleHandler(bool delegate() del)
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
	CoreTask f;
	while (!f && !s_availableFibers.empty) {
		f = s_availableFibers.back;
		s_availableFibers.popBack();
		if (f.state != Fiber.State.HOLD) f = null;
	}

	if (f is null) {
		// if there is no fiber available, create one.
		if (s_availableFibers.capacity == 0) s_availableFibers.capacity = 1024;
		logDebug("Creating new fiber...");
		s_fiberCount++;
		f = new CoreTask;
	}
	
	f.m_taskFunc = task;
	f.m_taskCounter++;
	auto handle = f.task();
	debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.preStart, f);
	s_core.resumeTask(handle, null, true);
	debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.postStart, f);
	return handle;
}

/**
	Runs a new asynchronous task in a worker thread.

	Only function pointers with weakly isolated arguments are allowed to be
	able to guarantee thread-safety.
*/
void runWorkerTask(R, ARGS...)(R function(ARGS) func, ARGS args)
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");
	runWorkerTask_unsafe({ func(args); });
}
/// ditto
void runWorkerTask(alias method, T, ARGS...)(shared(T) object, ARGS args)
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");
	runWorkerTask_unsafe({ object.method(args); });
}

private void runWorkerTask_unsafe(void delegate() del)
{
	synchronized (st_workerTaskMutex) st_workerTasks ~= del;
	st_workerTaskSignal.emit();
}

/**
	Runs a new asynchronous task in all worker threads concurrently.

	This function is mainly useful for long-living tasks that distribute their
	work across all CPU cores. Only function pointers with weakly isolated
	arguments are allowed to be able to guarantee thread-safety.
*/
void runWorkerTaskDist(R, ARGS...)(R function(ARGS) func, ARGS args)
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");
	runWorkerTaskDist_unsafe({ func(args); });
}
/// ditto
void runWorkerTaskDist(alias method, T, ARGS...)(shared(T) object, ARGS args)
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");
	runWorkerTaskDist_unsafe({ object.method(args); });
}

private void runWorkerTaskDist_unsafe(void delegate() del)
{
	bool got_worker_threads = false;
	synchronized (st_workerTaskMutex) {
		foreach (ref ctx; st_threads)
			if (ctx.isWorker)
				ctx.taskQueue ~= del;
	}
	st_workerTaskSignal.emit();
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
	auto t = CoreTask.getThis();
	if (t && t !is CoreTask.ms_coreTask) {
		// it can happen that a task with the same fiber was
		// terminated while it was yielded.
		assert(!t.m_queue || t.m_queue is &s_yieldedTasks);
		if (!t.m_queue)
			s_yieldedTasks.insertBack(CoreTask.getThis());
		rawYield();
	}
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
	destroy(tm);
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
	Creates a new timer without arming it.
*/
Timer createTimer(void delegate() callback)
{
	return getEventDriver().createTimer(callback);
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
	Compatibility stub - will be deprecated soon.

	This function was used to start the worker threads necessary for
	runWorkerTask and runWorkerTaskDist. These threads are now started
	automatically, so there is no need to call this function anymore
*/
void enableWorkerThreads()
{
	logDiagnostic("enableWorkerThreads() does nothing and will be deprecated soon.");
}


/**
	The number of worker threads.
*/
@property size_t workerThreadCount()
{
	return st_threads.count!(c => c.isWorker);
}


/**
	Sets the effective user and group ID to the ones configured for privilege lowering.

	This function is useful for services run as root to give up on the privileges that
	they only need for initialization (such as listening on ports <= 1024 or opening
	system log files).
*/
void lowerPrivileges()
{
	if (!isRoot()) return;
	auto uname = s_privilegeLoweringUserName;
	auto gname = s_privilegeLoweringGroupName;
	if (uname || gname) {
		static bool tryParse(T)(string s, out T n)
		{
			import std.conv, std.ascii;
			if (!isDigit(s[0])) return false;
			n = parse!T(s);
			return s.length==0;
		}
		int uid = -1, gid = -1;
		if (uname && !tryParse(uname, uid)) uid = getUID(uname);
		if (gname && !tryParse(gname, gid)) gid = getGID(gname);
		setUID(uid, gid);
	} else logWarn("Vibe was run as root, and no user/group has been specified for privilege lowering. Running with full permissions.");
}


/**
	Sets a callback that is invoked whenever a task changes its status.

	This function is useful mostly for implementing debuggers that
	analyze the life time of tasks, including task switches.
*/
void setTaskEventCallback(void function(TaskEvent, Fiber) func)
{
	debug s_taskEventCallback = func;
}


/**
	A version string representing the current vibe version
*/
enum VibeVersionString = "0.7.18";


/**
	Implements a task local storage variable.

	Task local variables, similar to thread local variables, exist separately
	in each task. Consequently, they do not need any form of synchronization
	when accessing them.

	Note, however, that each TaskLocal variable will increase the memory footprint
	of any task that uses task local storage. There is also an overhead to access
	TaskLocal variables, higher than for thread local variables, but generelly
	still O(1) (since actual storage acquisition is done lazily the first access
	can require a memory allocation with unknown computational costs).

	Notice:
		FiberLocal instances MUST be declared as static/global thread-local
		variables. Defining them as a temporary/stack variable will cause
		crashes or data corruption!

	Examples:
		---
		TaskLocal!string s_myString = "world";

		void taskFunc()
		{
			assert(s_myString == "world");
			s_myString = "hello";
			assert(s_myString == "hello");
		}

		shared static this()
		{
			// both tasks will get independent storage for s_myString
			runTask(&taskFunc);
			runTask(&taskFunc);
		}
		---
*/
struct TaskLocal(T)
{
	private {
		size_t m_offset = size_t.max;
		size_t m_id;
		T m_initValue;
	}

	this(T init_val) { m_initValue = init_val; }

	@disable this(this);

	void opAssign(T value) { this.storage = value; }

	@property ref T storage()
	{
		auto fiber = CoreTask.getThis();

		// lazily register in FLS storage
		if (m_offset == size_t.max) {
			// TODO: handle alignment properly
			m_offset = CoreTask.ms_flsFill;
			m_id = CoreTask.ms_flsCounter++;
			CoreTask.ms_flsFill += T.sizeof;
		}

		// make sure the current fiber has enough FLS storage
		if (fiber.m_fls.length < CoreTask.ms_flsFill) {
			fiber.m_fls.length = CoreTask.ms_flsFill + 128;
			fiber.m_flsInit.length = CoreTask.ms_flsCounter + 64;
		}
		
		// return (possibly default initialized) value
		auto data = fiber.m_fls.ptr[m_offset .. m_offset+T.sizeof];
		if (!fiber.m_flsInit[m_id]) {
			fiber.m_flsInit[m_id] = true;
			emplace!T(data, m_initValue);
		}
		return (cast(T[])data)[0];
	}

	alias storage this;
}


/**
	High level state change events for a Task
*/
enum TaskEvent {
	preStart,  /// Just about to invoke the fiber which starts execution
	postStart, /// After the fiber has returned for the first time (by yield or exit)
	start,     /// Just about to start execution
	yield,     /// Temporarily paused
	resume,    /// Resumed from a prior yield
	end,       /// Ended normally
	fail       /// Ended with an exception
}


/**************************************************************************************************/
/* private types                                                                                  */
/**************************************************************************************************/

private class CoreTask : TaskFiber {
	import std.bitmanip;
	private {
		static CoreTask ms_coreTask;
		CoreTask m_nextInQueue;
		CoreTaskQueue* m_queue;
		void delegate() m_taskFunc;
		Exception m_exception;
		Task[] m_yielders;

		// task local storage
		static size_t ms_flsFill = 0; // thread-local
		static size_t ms_flsCounter = 0;
		BitArray m_flsInit;
		void[] m_fls;
	}

	static CoreTask getThis()
	{
		auto f = Fiber.getThis();
		if (f) return cast(CoreTask)f;
		if (!ms_coreTask) ms_coreTask = new CoreTask;
		return ms_coreTask;
	}

	this()
	{
		super(&run, s_taskStackSize);
	}

	@property size_t taskCounter() const { return m_taskCounter; }

	private void run()
	{
		try {
			while(true){
				while (!m_taskFunc) {
					try {
						rawYield();
					} catch( Exception e ){
						logWarn("CoreTaskFiber was resumed with exception but without active task!");
						logDiagnostic("Full error: %s", e.toString().sanitize());
					}
				}

				auto task = m_taskFunc;
				m_taskFunc = null;
				try {
					m_running = true;
					scope(exit) m_running = false;
					debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.start, this);
					task();
					debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.end, this);
				} catch( Exception e ){
					debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.fail, this);
					import std.encoding;
					logCritical("Task terminated with uncaught exception: %s", e.msg);
					logDebug("Full error: %s", e.toString().sanitize());
				}
				resetLocalStorage();

				foreach (t; m_yielders) s_yieldedTasks.insertBack(cast(CoreTask)t.fiber);
				m_yielders.length = 0;
				
				// make the fiber available for the next task
				if (s_availableFibers.full)
					s_availableFibers.capacity = 2 * s_availableFibers.capacity;
				s_availableFibers.put(this);
			}
		} catch(Throwable th){
			logCritical("CoreTaskFiber was terminated unexpectedly: %s", th.msg);
			logDiagnostic("Full error: %s", th.toString().sanitize());
			s_fiberCount--;
		}
	}

	override void join()
	{
		auto caller = Task.getThis();
		assert(caller.fiber !is this, "A task cannot join itself.");
		assert(caller.thread is this.thread, "Joining tasks in foreign threads is currently not supported.");
		m_yielders ~= caller;
		auto run_count = m_taskCounter;
		if (m_running && run_count == m_taskCounter) {
			s_core.resumeTask(this.task);
			while (m_running && run_count == m_taskCounter) rawYield();
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
			debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.yield, fiber);
			Fiber.yield();
			debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.resume, fiber);
			auto e = fiber.m_exception;
			if( e ){
				fiber.m_exception = null;
				throw e;
			}
		} else {
			assert(!s_eventLoopRunning, "Event processing outside of a fiber should only happen before the event loop is running!?");
			if (auto err = getEventDriver().runEventLoopOnce()) {
				if (err == 1) {
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
		assert(initial_resume || task.running, "Resuming terminated task.");
		resumeCoreTask(cast(CoreTask)task.fiber, event_exception);
	}

	void resumeCoreTask(CoreTask ctask, Exception event_exception = null)
	{
		assert(ctask.thread is Thread.getThis(), "Resuming task in foreign thread.");
		assert(ctask.state == Fiber.State.HOLD, "Resuming fiber that is " ~ to!string(ctask.state));

		if( event_exception ){
			extrap();
			ctask.m_exception = event_exception;
		}
		
		auto uncaught_exception = ctask.call(false);
		if( uncaught_exception ){
			extrap();
			assert(ctask.state == Fiber.State.TERM);
			logError("Task terminated with unhandled exception: %s", uncaught_exception.toString());
		}
	}

	void notifyIdle()
	{
		bool again = true;
		while (again) {
			if (s_idleHandler)
				again = s_idleHandler();
			else again = false;

			while (!s_yieldedTasks.empty) {
				auto tf = s_yieldedTasks.front;
				s_yieldedTasks.popFront();
				resumeCoreTask(tf);
			}
			if (!s_yieldedTasks.empty)
				again = true;
			if (again && !processEvents()) {
				s_exitEventLoop = true;
				return;
			}
		}

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

private struct ThreadContext {
	Thread thread;
	bool isWorker;
	void delegate()[] taskQueue;

	this(Thread thr, bool worker) { this.thread = thr; this.isWorker = worker; }
}

/**************************************************************************************************/
/* private functions                                                                              */
/**************************************************************************************************/

private {
	__gshared VibeDriverCore s_core;
	__gshared size_t s_taskStackSize = 16*4096;

	__gshared core.sync.mutex.Mutex st_workerTaskMutex;
	__gshared void delegate()[] st_workerTasks;
	__gshared ThreadContext[] st_threads;
	__gshared ManualEvent st_workerTaskSignal;
	__gshared Mutex st_threadShutdownMutex;
	__gshared Condition st_threadShutdownCondition;
	__gshared debug void function(TaskEvent, Fiber) s_taskEventCallback;
	shared bool st_term = false;

	bool s_exitEventLoop = false;
	bool s_eventLoopRunning = false;
	bool delegate() s_idleHandler;
	CoreTaskQueue s_yieldedTasks;
	Variant[string] s_taskLocalStorageGlobal; // for use outside of a task
	FixedRingBuffer!CoreTask s_availableFibers;
	size_t s_fiberCount;

	string s_privilegeLoweringUserName;
	string s_privilegeLoweringGroupName;
}

private bool getExitFlag()
{
	return s_exitEventLoop || atomicLoad(st_term);
}

// per process setup
shared static this()
{
	version(Windows){
		version(VibeLibeventDriver) enum need_wsa = true;
		else version(VibeWin32Driver) enum need_wsa = true;
		else enum need_wsa = false;
		static if (need_wsa) {
			logTrace("init winsock");
			// initialize WinSock2
			import std.c.windows.winsock;
			WSADATA data;
			WSAStartup(0x0202, &data);

		}
	}

	initializeLogModule();
	
	logTrace("create driver core");
	
	s_core = new VibeDriverCore;
	st_workerTaskMutex = new Mutex;
	st_threadShutdownCondition = new Condition(st_workerTaskMutex);

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

	st_threads ~= ThreadContext(Thread.getThis(), false);

	setupDriver();

	st_workerTaskSignal = getEventDriver().createManualEvent();

	import core.cpuid;
	foreach (i; 0 .. threadsPerCPU) {
		auto thr = new Thread(&workerThreadFunc);
		thr.name = format("Vibe Task Worker #%s", i);
		st_threads ~= ThreadContext(thr, true);
		thr.start();
	}

	version(VibeIdleCollect){
		logTrace("setup gc");
		s_core.setupGcTimer();
	}

	getOption("uid|user", &s_privilegeLoweringUserName, "Sets the user name or id used for privilege lowering.");
	getOption("gid|group", &s_privilegeLoweringGroupName, "Sets the group name or id used for privilege lowering.");
}

shared static ~this()
{
	bool tasks_left = false;

	synchronized (st_workerTaskMutex) {
		if( !st_workerTasks.empty ) tasks_left = true;
	}	
	
	if (!s_yieldedTasks.empty) tasks_left = true;
	if (tasks_left) logWarn("There are still tasks running at exit.");

	delete s_core;
}

// per thread setup
static this()
{
	assert(s_core !is null);

	auto thisthr = Thread.getThis();
	synchronized (st_workerTaskMutex)
		if (!st_threads.canFind!(c => c.thread is thisthr))
			st_threads ~= ThreadContext(thisthr, false);

	//CoreTask.ms_coreTask = new CoreTask;

	setupDriver();
}

static ~this()
{
	auto thisthr = Thread.getThis();
	synchronized (st_workerTaskMutex) {
		auto idx = st_threads.countUntil!(c => c.thread is thisthr);
		assert(idx >= 0);
		if (idx >= 0) {
			st_threads[idx] = st_threads[$-1];
			st_threads.length--;
		}

		// if we are the main thread, wait for all others before terminating
		if (idx == 0) { // we are the main thread, wait for others
			atomicStore(st_term, true);
			st_workerTaskSignal.emit();
			while (st_threads.length)
				st_threadShutdownCondition.wait();
		}
	}

	deleteEventDriver();

	st_threadShutdownCondition.notifyAll();
}

private void setupDriver()
{
	if (getEventDriver(true) !is null) return;

	logTrace("create driver");
	version(VibeWin32Driver) setEventDriver(new Win32EventDriver(s_core));
	else version(VibeWinrtDriver) setEventDriver(new WinRTEventDriver(s_core));
	else version(VibeLibevDriver) setEventDriver(new LibevDriver(s_core));
	else version(VibeLibeventDriver) setEventDriver(new Libevent2Driver(s_core));
	else static assert(false, "No event driver is available. Please specify a -version=Vibe*Driver for the desired driver.");
	logTrace("driver %s created", (cast(Object)getEventDriver()).classinfo.name);
}

private void workerThreadFunc()
{
	auto thisthr = Thread.getThis();
	assert(s_core !is null);
	logDebug("entering worker thread");
	runTask(toDelegate(&handleWorkerTasks));
	logDebug("running event loop");
	runEventLoop();
	logDebug("Worker thread exit.");
}

private void handleWorkerTasks()
{
	logDebug("worker task enter");

	auto thisthr = Thread.getThis();

	logDebug("worker task loop enter");
	while(true){
		void delegate() t;
		auto emit_count = st_workerTaskSignal.emitCount;
		synchronized (st_workerTaskMutex) {
			auto idx = st_threads.countUntil!(c => c.thread is thisthr);
			assert(idx >= 0);
			logDebug("worker task check");
			if (getExitFlag()) {
				if (st_threads[idx].taskQueue.length > 0)
					logWarn("Worker thread shuts down with specific worker tasks left in its queue.");
				if (st_threads.count!(c => c.isWorker) == 1 && st_workerTasks.length > 0)
					logWarn("Worker threads shut down with worker tasks still left in the queue.");
				getEventDriver().exitEventLoop();
				break;
			}
			if (!st_workerTasks.empty) {
				logDebug("worker task got");
				t = st_workerTasks.front;
				st_workerTasks.popFront();
			} else if (!st_threads[idx].taskQueue.empty) {
				logDebug("worker task got specific");
				t = st_threads[idx].taskQueue.front;
				st_threads[idx].taskQueue.popFront();
			}
		}
		if (t) runTask(t);
		else st_workerTaskSignal.wait(emit_count);
	}
	logDebug("worker task exit");
}


private extern(C) void extrap()
nothrow {
	logTrace("exception trap");
}

private extern(C) void onSignal(int signal)
nothrow {
	atomicStore(st_term, true);
	try st_workerTaskSignal.emit(); catch {}

	logInfo("Received signal %d. Shutting down.", signal);
}

private extern(C) void onBrokenPipe(int signal)
nothrow {
	logTrace("Broken pipe.");
}

version(Posix)
{
	private bool isRoot() { return geteuid() == 0; }

	private void setUID(int uid, int gid)
	{
		logInfo("Lowering privileges to uid=%d, gid=%d...", uid, gid);
		if (gid >= 0) {
			enforce(getgrgid(gid) !is null, "Invalid group id!");
			enforce(setegid(gid) == 0, "Error setting group id!");
		}
		//if( initgroups(const char *user, gid_t group);
		if (uid >= 0) {
			enforce(getpwuid(uid) !is null, "Invalid user id!");
			enforce(seteuid(uid) == 0, "Error setting user id!");
		}
	}

	private int getUID(string name)
	{
		auto pw = getpwnam(name.toStringz());
		enforce(pw !is null, "Unknown user name: "~name);
		return pw.pw_uid;
	}

	private int getGID(string name)
	{
		auto gr = getgrnam(name.toStringz());
		enforce(gr !is null, "Unknown group name: "~name);
		return gr.gr_gid;
	}
} else version(Windows){
	private bool isRoot() { return false; }

	private void setUID(int uid, int gid)
	{
		enforce(false, "UID/GID not supported on Windows.");
	}

	private int getUID(string name)
	{
		enforce(false, "Privilege lowering not supported on Windows.");
		assert(false);
	}

	private int getGID(string name)
	{
		enforce(false, "Privilege lowering not supported on Windows.");
		assert(false);
	}
}

private struct CoreTaskQueue {
	CoreTask first, last;

	@disable this(this);

	@property bool empty() const { return first is null; }

	@property CoreTask front() { return first; }

	void insertBack(CoreTask task)
	{
		assert(task.m_queue == null);
		assert(task.m_nextInQueue is null);
		task.m_queue = &this;
		if (empty)
			first = task;
		else
			last.m_nextInQueue = task;
		last = task;
	}

	void popFront()
	{
		if (first == last) last = null;
		assert(first && first.m_queue == &this);
		auto next = first.m_nextInQueue;
		first.m_nextInQueue = null;
		first.m_queue = null;
		first = next;
	}
}

