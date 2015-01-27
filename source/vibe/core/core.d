/**
	This module contains the core functionality of the vibe.d framework.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.core;

public import vibe.core.driver;

import vibe.core.args;
import vibe.core.concurrency;
import vibe.core.log;
import vibe.internal.newconcurrency;
import vibe.utils.array;
import std.algorithm;
import std.conv;
import std.encoding;
import std.exception;
import std.functional;
import std.range : empty, front, popFront;
import std.string;
import std.variant;
import std.typecons : Typedef, Tuple, tuple;
import core.atomic;
import core.sync.condition;
import core.sync.mutex;
import core.stdc.stdlib;
import core.thread;


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
	scope (exit) {
		s_eventLoopRunning = false;
		s_exitEventLoop = false;
		st_threadShutdownCondition.notifyAll();
	}

	// runs any yield()ed tasks first
	assert(!s_exitEventLoop);
	s_exitEventLoop = false;
	s_core.notifyIdle();
	if (getExitFlag()) return 0;

	// handle worker tasks and st_term
	runTask(toDelegate(&handleWorkerTasks));
	if (getExitFlag()) return 0;

	if (auto err = getEventDriver().runEventLoop() != 0) {
		if (err == 1) {
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

	Params:
		shutdown_all_threads = If true, exits event loops of all threads -
			false by default. Note that the event loops of all threads are
			automatically stopped when the main thread exits, so usually
			there is no need to set shutdown_all_threads to true.
*/
void exitEventLoop(bool shutdown_all_threads = false)
{
	assert(s_eventLoopRunning || shutdown_all_threads);
	if (shutdown_all_threads) {
		atomicStore(st_term, true);
		st_threadsSignal.emit();
	}

	// shutdown the calling thread
	s_exitEventLoop = true;
	if (s_eventLoopRunning) getEventDriver().exitEventLoop();
}

/**
	Process all pending events without blocking.

	Checks if events are ready to trigger immediately, and run their callbacks if so.

	Returns: Returns false iff exitEventLoop was called in the process.
*/
bool processEvents()
{
	if (!getEventDriver().processEvents()) return false;
	s_core.notifyIdle();
	return true;
}

/**
	Sets a callback that is called whenever no events are left in the event queue.

	The callback delegate is called whenever all events in the event queue have been
	processed. Returning true from the callback will cause another idle event to
	be triggered immediately after processing any events that have arrived in the
	meantime. Returning false will instead wait until another event has arrived first.
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

	Note that the maximum size of all args must not exceed MaxTaskParameterSize.
*/
Task runTask(ARGS...)(void delegate(ARGS) task, ARGS args)
{
	auto tfi = makeTaskFuncInfo(task, args);
	return runTask_internal(tfi);
}

private Task runTask_internal(ref TaskFuncInfo tfi)
{
	import std.typecons : Tuple, tuple;

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

	f.m_taskFunc = tfi;

	atomicOp!"+="(f.m_taskCounter, 1);
	auto handle = f.task();

	debug Task self = Task.getThis();
	debug if (s_taskEventCallback) {
		if (self != Task.init) s_taskEventCallback(TaskEvent.yield, self);
		s_taskEventCallback(TaskEvent.preStart, handle);
	}
	s_core.resumeTask(handle, null, true);
	debug if (s_taskEventCallback) {
		s_taskEventCallback(TaskEvent.postStart, handle);
		if (self != Task.init) s_taskEventCallback(TaskEvent.resume, self);
	}

	return handle;
}

/**
	Runs a new asynchronous task in a worker thread.

	Only function pointers with weakly isolated arguments are allowed to be
	able to guarantee thread-safety.
*/
void runWorkerTask(FT, ARGS...)(FT func, auto ref ARGS args)
	if (is(typeof(*func) == function))
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");
	runWorkerTask_unsafe(func, args);
}

/// ditto
void runWorkerTask(alias method, T, ARGS...)(shared(T) object, auto ref ARGS args)
	if (is(typeof(__traits(getMember, object, __traits(identifier, method)))))
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");
	auto func = &__traits(getMember, object, __traits(identifier, method));
	runWorkerTask_unsafe(func, args);
}

/**
	Runs a new asynchronous task in a worker thread, returning the task handle.

	This function will yield and wait for the new task to be created and started
	in the worker thread, then resume and return it.

	Only function pointers with weakly isolated arguments are allowed to be
	able to guarantee thread-safety.
*/
Task runWorkerTaskH(FT, ARGS...)(FT func, auto ref ARGS args)
	if (is(typeof(*func) == function))
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");

	alias PrivateTask = Typedef!(Task, Task.init, __PRETTY_FUNCTION__);
	Task caller = Task.getThis();
	static void taskFun(Task caller, FT func, ARGS args) {
		PrivateTask callee = Task.getThis();
		caller.prioritySend(callee);
		mixin(callWithMove!ARGS("func", "args"));
	}
	runWorkerTask_unsafe(&taskFun, caller, func, args);
	return cast(Task)receiveOnly!PrivateTask();
}
/// ditto
Task runWorkerTaskH(alias method, T, ARGS...)(shared(T) object, auto ref ARGS args)
	if (is(typeof(__traits(getMember, object, __traits(identifier, method)))))
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");

	auto func = &__traits(getMember, object, __traits(identifier, method));
	alias FT = typeof(func);

	alias PrivateTask = Typedef!(Task, Task.init, __PRETTY_FUNCTION__);
	Task caller = Task.getThis();
	static void taskFun(Task caller, FT func, ARGS args) {
		PrivateTask callee = Task.getThis();
		caller.prioritySend(callee);
		mixin(callWithMove!ARGS("func", "args"));
	}
	runWorkerTask_unsafe(&taskFun, caller, func, args);
	return cast(Task)receiveOnly!PrivateTask();
}

/// Running a worker task using a function
unittest {
	static void workerFunc(int param)
	{
		logInfo("Param: %s", param);
	}

	static void test()
	{
		runWorkerTask(&workerFunc, 42);
		runWorkerTask(&workerFunc, cast(ubyte)42); // implicit conversion #719
		runWorkerTaskDist(&workerFunc, 42);
		runWorkerTaskDist(&workerFunc, cast(ubyte)42); // implicit conversion #719
	}
}

/// Running a worker task using a class method
unittest {
	static class Test {
		void workerMethod(int param)
		shared {
			logInfo("Param: %s", param);
		}
	}

	static void test()
	{
		auto cls = new shared Test;
		runWorkerTask!(Test.workerMethod)(cls, 42);
		runWorkerTask!(Test.workerMethod)(cls, cast(ubyte)42); // #719
		runWorkerTaskDist!(Test.workerMethod)(cls, 42);
		runWorkerTaskDist!(Test.workerMethod)(cls, cast(ubyte)42); // #719
	}
}

/// Running a worker task using a function and communicating with it
unittest {
	static void workerFunc(Task caller)
	{
		int counter = 10;
		while (receiveOnly!string() == "ping" && --counter) {
			logInfo("pong");
			caller.send("pong");
		}
		caller.send("goodbye");

	}

	static void test()
	{
		Task callee = runWorkerTaskH(&workerFunc, Task.getThis);
		do {
			logInfo("ping");
			callee.send("ping");
		} while (receiveOnly!string() == "pong");
	}

	static void work719(int) {}
	static void test719() { runWorkerTaskH(&work719, cast(ubyte)42); }
}

/// Running a worker task using a class method and communicating with it
unittest {
	static class Test {
		void workerMethod(Task caller) shared {
			int counter = 10;
			while (receiveOnly!string() == "ping" && --counter) {
				logInfo("pong");
				caller.send("pong");
			}
			caller.send("goodbye");
		}
	}

	static void test()
	{
		auto cls = new shared Test;
		Task callee = runWorkerTaskH!(Test.workerMethod)(cls, Task.getThis());
		do {
			logInfo("ping");
			callee.send("ping");
		} while (receiveOnly!string() == "pong");
	}

	static class Class719 {
		void work(int) shared {}
	}
	static void test719() {
		auto cls = new shared Class719;
		runWorkerTaskH!(Class719.work)(cls, cast(ubyte)42);
	}
}

private void runWorkerTask_unsafe(CALLABLE, ARGS...)(CALLABLE callable, ref ARGS args)
{
	import std.traits : ParameterTypeTuple;
	import vibe.internal.meta.traits : areConvertibleTo;
	import vibe.internal.meta.typetuple;

	alias FARGS = ParameterTypeTuple!CALLABLE;
	static assert(areConvertibleTo!(Group!ARGS, Group!FARGS),
		"Cannot convert arguments '"~ARGS.stringof~"' to function arguments '"~FARGS.stringof~"'.");

	setupWorkerThreads();

	auto tfi = makeTaskFuncInfo(callable, args);

	synchronized (st_threadsMutex) st_workerTasks ~= tfi;
	st_threadsSignal.emit();
}


/**
	Runs a new asynchronous task in all worker threads concurrently.

	This function is mainly useful for long-living tasks that distribute their
	work across all CPU cores. Only function pointers with weakly isolated
	arguments are allowed to be able to guarantee thread-safety.
*/
void runWorkerTaskDist(FT, ARGS...)(FT func, auto ref ARGS args)
	if (is(typeof(*func) == function))
{
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");
	runWorkerTaskDist_unsafe(func, args);
}
/// ditto
void runWorkerTaskDist(alias method, T, ARGS...)(shared(T) object, ARGS args)
{
	auto func = &__traits(getMember, object, __traits(identifier, method));
	foreach (T; ARGS) static assert(isWeaklyIsolated!T, "Argument type "~T.stringof~" is not safe to pass between threads.");

	runWorkerTaskDist_unsafe(func, args);
}

private void runWorkerTaskDist_unsafe(CALLABLE, ARGS...)(ref CALLABLE callable, ref ARGS args)
{
	import std.traits : ParameterTypeTuple;
	import vibe.internal.meta.traits : areConvertibleTo;
	import vibe.internal.meta.typetuple;

	alias FARGS = ParameterTypeTuple!CALLABLE;
	static assert(areConvertibleTo!(Group!ARGS, Group!FARGS),
		"Cannot convert arguments '"~ARGS.stringof~"' to function arguments '"~FARGS.stringof~"'.");

	setupWorkerThreads();

	auto tfi = makeTaskFuncInfo(callable, args);

	synchronized (st_threadsMutex) {
		foreach (ref ctx; st_threads)
			if (ctx.isWorker)
				ctx.taskQueue ~= tfi;
	}
	st_threadsSignal.emit();
}

private TaskFuncInfo makeTaskFuncInfo(CALLABLE, ARGS...)(ref CALLABLE callable, ref ARGS args)
{
	import std.algorithm : move;
	import std.traits : hasElaborateAssign;

	struct TARGS { ARGS expand; }

	static assert(CALLABLE.sizeof <= TaskFuncInfo.callable.length);
	static assert(TARGS.sizeof <= maxTaskParameterSize,
		"The arguments passed to run(Worker)Task must not exceed "~
		MaxTaskParameterSize.to!string~" bytes in total size.");

	static void callDelegate(TaskFuncInfo* tfi) {
		assert(tfi.func is &callDelegate);

		// copy original call data to stack
		CALLABLE c;
		TARGS args;
		move(*(cast(CALLABLE*)tfi.callable.ptr), c);
		move(*(cast(TARGS*)tfi.args.ptr), args);

		// reset the info
		tfi.func = null;

		// make the call
		mixin(callWithMove!ARGS("c", "args.expand"));
	}

	TaskFuncInfo tfi;
	tfi.func = &callDelegate;
	static if (hasElaborateAssign!CALLABLE) tfi.initCallable!CALLABLE();
	static if (hasElaborateAssign!TARGS) tfi.initArgs!TARGS();

	tfi.typedCallable!CALLABLE = callable;
	foreach (i, A; ARGS) {
		static if (needsMove!A) args[i].move(tfi.typedArgs!TARGS.expand[i]);
		else tfi.typedArgs!TARGS.expand[i] = args[i];
	}
	return tfi;
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

	Note that other tasks of the same thread will continue to run during the
	wait time, in contrast to $(D core.thread.Thread.sleep), which shouldn't be
	used in vibe.d applications.
*/
void sleep(Duration timeout)
{
	assert(timeout >= 0.seconds, "Argument to sleep must not be negative.");
	if (timeout <= 0.seconds) return;
	auto tm = setTimer(timeout, null);
	tm.wait();
}
///
unittest {
	import vibe.core.core : sleep;
	import vibe.core.log : logInfo;
	import core.time : msecs;

	void test()
	{
		logInfo("Sleeping for half a second...");
		sleep(500.msecs);
		logInfo("Done sleeping.");
	}
}


/**
	Returns a new armed timer.

	Note that timers can only work if an event loop is running.

	Params:
		timeout = Determines the minimum amount of time that elapses before the timer fires.
		callback = This delegate will be called when the timer fires
		periodic = Speficies if the timer fires repeatedly or only once

	Returns:
		Returns a Timer object that can be used to identify and modify the timer.

	See_also: createTimer
*/
Timer setTimer(Duration timeout, void delegate() callback, bool periodic = false)
{
	auto tm = createTimer(callback);
	tm.rearm(timeout, periodic);
	return tm;
}
///
unittest {
	void printTime()
	{
		import std.datetime;
		logInfo("The time is: %s", Clock.currTime());
	}

	void test()
	{
		import vibe.core.core;
		// start a periodic timer that prints the time every second
		setTimer(1.seconds, toDelegate(&printTime), true);
	}
}


/**
	Creates a new timer without arming it.

	See_also: setTimer
*/
Timer createTimer(void delegate() callback)
{
	auto drv = getEventDriver();
	return Timer(drv, drv.createTimer(callback));
}


/**
	Creates an event to wait on an existing file descriptor.

	The file descriptor usually needs to be a non-blocking socket for this to
	work.

	Params:
		file_descriptor = The Posix file descriptor to watch
		event_mask = Specifies which events will be listened for

	Returns:
		Returns a newly created FileDescriptorEvent associated with the given
		file descriptor.
*/
FileDescriptorEvent createFileDescriptorEvent(int file_descriptor, FileDescriptorEvent.Trigger event_mask)
{
	auto drv = getEventDriver();
	return drv.createFileDescriptorEvent(file_descriptor, event_mask);
}


/**
	Sets the stack size to use for tasks.

	The default stack size is set to 512 KiB on 32-bit systems and to 16 MiB
	on 64-bit systems, which is sufficient for most tasks. Tuning this value
	can be used to reduce memory usage for large numbers of concurrent tasks
	or to avoid stack overflows for applications with heavy stack use.

	Note that this function must be called at initialization time, before any
	task is started to have an effect.

	Also note that the stack will initially not consume actual physical memory -
	it just reserves virtual address space. Only once the stack gets actually
	filled up with data will physical memory then be reserved page by page. This
	means that the stack can safely be set to large sizes on 64-bit systems
	without having to worry about memory usage.
*/
void setTaskStackSize(size_t sz)
{
	s_taskStackSize = sz;
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
void lowerPrivileges(string uname, string gname)
{
	if (!isRoot()) return;
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

// ditto
void lowerPrivileges()
{
	lowerPrivileges(s_privilegeLoweringUserName, s_privilegeLoweringGroupName);
}


/**
	Sets a callback that is invoked whenever a task changes its status.

	This function is useful mostly for implementing debuggers that
	analyze the life time of tasks, including task switches. Note that
	the callback will only be called for debug builds.
*/
void setTaskEventCallback(void function(TaskEvent, Task) func)
{
	debug s_taskEventCallback = func;
}


/**
	A version string representing the current vibe version
*/
enum vibeVersionString = "0.7.22";

/// Compatibility alias
deprecated("Use vibeVersionString instead.") alias VibeVersionString = vibeVersionString;

/**
	The maximum combined size of all parameters passed to a task delegate

	See_Also: runTask
*/
enum maxTaskParameterSize = 128;

/// Compatibility alias
deprecated("Use maxTaskParameterSize instead.") alias MaxTaskParameterSize = maxTaskParameterSize;

/**
	Represents a timer.
*/
struct Timer {
	private {
		EventDriver m_driver;
		size_t m_id;
		debug uint m_magicNumber = 0x4d34f916;
	}

	private this(EventDriver driver, size_t id)
	{
		m_driver = driver;
		m_id = id;
	}

	this(this)
	{
		debug assert(m_magicNumber == 0x4d34f916);
		if (m_driver) m_driver.acquireTimer(m_id);
	}

	~this()
	{
		debug assert(m_magicNumber == 0x4d34f916);
		if (m_driver) m_driver.releaseTimer(m_id);
	}

	/// True if the timer is yet to fire.
	@property bool pending() { return m_driver.isTimerPending(m_id); }

	/// The internal ID of the timer.
	@property size_t id() const { return m_id; }

	bool opCast() const { return m_driver !is null; }

	/** Resets the timer to the specified timeout
	*/
	void rearm(Duration dur, bool periodic = false)
		in { assert(dur > 0.seconds); }
		body { m_driver.rearmTimer(m_id, dur, periodic); }

	/** Resets the timer and avoids any firing.
	*/
	void stop() { m_driver.stopTimer(m_id); }

	/** Waits until the timer fires.
	*/
	void wait() { m_driver.waitTimer(m_id); }
}


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
		bool m_hasInitValue = false;
	}

	this(T init_val) { m_initValue = init_val; m_hasInitValue = true; }

	@disable this(this);

	void opAssign(T value) { this.storage = value; }

	@property ref T storage()
	{
		auto fiber = CoreTask.getThis();

		// lazily register in FLS storage
		if (m_offset == size_t.max) {
			static assert(T.alignof <= 8, "Unsupported alignment for type "~T.stringof);
			assert(CoreTask.ms_flsFill % 8 == 0, "Misaligned fiber local storage pool.");
			m_offset = CoreTask.ms_flsFill;
			m_id = CoreTask.ms_flsCounter++;


			CoreTask.ms_flsFill += T.sizeof;
			while (CoreTask.ms_flsFill % 8 != 0)
				CoreTask.ms_flsFill++;
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
			import std.traits : hasElaborateDestructor, hasAliasing;
			static if (hasElaborateDestructor!T || hasAliasing!T) {
				void function(void[], size_t) destructor = (void[] fls, size_t offset){
					static if (hasElaborateDestructor!T) {
						auto obj = cast(T*)&fls[offset];
						// call the destructor on the object if a custom one is known declared
						obj.destroy();
					}
					else static if (hasAliasing!T) {
						// zero the memory to avoid false pointers
						foreach (size_t i; offset .. offset + T.sizeof) {
							ubyte* u = cast(ubyte*)&fls[i];
							*u = 0;
						}
					}
				};
				FLSInfo fls_info;
				fls_info.fct = destructor;
				fls_info.offset = m_offset;

				// make sure flsInfo has enough space
				if (fiber.ms_flsInfo.length <= m_id)
					fiber.ms_flsInfo.length = m_id + 64;

				fiber.ms_flsInfo[m_id] = fls_info;
			}

			if (m_hasInitValue) {
				static if (__traits(compiles, emplace!T(data, m_initValue)))
					emplace!T(data, m_initValue);
				else assert(false, "Cannot emplace initialization value for type "~T.stringof);
			} else emplace!T(data);
		}
		return (cast(T[])data)[0];
	}

	alias storage this;
}

private struct FLSInfo {
	void function(void[], size_t) fct;
	size_t offset;
	void destroy(void[] fls) {
		fct(fls, offset);
	}
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
		TaskFuncInfo m_taskFunc;
		Exception m_exception;
		Task[] m_yielders;

		// task local storage
		static FLSInfo[] ms_flsInfo;
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
		version (VibeDebugCatchAll) alias UncaughtException = Throwable;
		else alias UncaughtException = Exception;
		try {
			while(true){
				while (!m_taskFunc.func) {
					try {
						Fiber.yield();
					} catch( Exception e ){
						logWarn("CoreTaskFiber was resumed with exception but without active task!");
						logDiagnostic("Full error: %s", e.toString().sanitize());
					}
				}

				auto task = m_taskFunc;
				m_taskFunc = TaskFuncInfo.init;
				Task handle = this.task;
				try {
					m_running = true;
					scope(exit) m_running = false;
					debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.start, handle);
					if (!s_eventLoopRunning) {
						logTrace("Event loop not running at task start - yielding.");
						assert(!m_queue);
						.yield();
						logTrace("Initial resume of task.");
					}
					task.func(&task);
					debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.end, handle);
				} catch( Exception e ){
					debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.fail, handle);
					import std.encoding;
					logCritical("Task terminated with uncaught exception: %s", e.msg);
					logDebug("Full error: %s", e.toString().sanitize());
				}

				foreach (t; m_yielders) s_yieldedTasks.insertBack(cast(CoreTask)t.fiber);
				m_yielders.length = 0;

				// zero the fls initialization ByteArray for memory safety
				foreach (size_t i, ref bool b; m_flsInit) {
					if (b) {
						if (ms_flsInfo !is null && ms_flsInfo.length >= i && ms_flsInfo[i] != FLSInfo.init)
							ms_flsInfo[i].destroy(m_fls);
						b = false;
					}
				}

				// make the fiber available for the next task
				if (s_availableFibers.full)
					s_availableFibers.capacity = 2 * s_availableFibers.capacity;

				// clear the message queue for the next task
				messageQueue.clear();

				s_availableFibers.put(this);
			}
		} catch(UncaughtException th) {
			logCritical("CoreTaskFiber was terminated unexpectedly: %s", th.msg);
			logDiagnostic("Full error: %s", th.toString().sanitize());
			s_fiberCount--;
		}
	}

	override void join()
	{
		auto caller = Task.getThis();
		if (caller != Task.init) {
			assert(caller.fiber !is this, "A task cannot join itself.");
			assert(caller.thread is this.thread, "Joining tasks in foreign threads is currently not supported.");
			m_yielders ~= caller;
		} else assert(Thread.getThis() is this.thread, "Joining tasks in different threads is not yet supported.");
		auto run_count = m_taskCounter;
		if (m_running && run_count == m_taskCounter) {
			s_core.resumeTask(this.task);
			while (m_running && run_count == m_taskCounter) rawYield();
		}
	}

	override void interrupt()
	{
		auto caller = Task.getThis();
		if (caller != Task.init) {
			assert(caller != this.task, "A task cannot interrupt itself.");
			assert(caller.thread is this.thread, "Interrupting tasks in different threads is not yet supported.");
		} else assert(Thread.getThis() is this.thread, "Interrupting tasks in different threads is not yet supported.");
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
		Exception m_eventException;
	}

	private void setupGcTimer()
	{
		m_gcTimer = createTimer(&collectGarbage);
		m_gcCollectTimeout = dur!"seconds"(2);
	}

	@property void eventException(Exception e) { m_eventException = e; }

	void yieldForEvent()
	{
		auto task = Task.getThis();
		if (task != Task.init) {
			auto fiber = cast(CoreTask)task.fiber;
			debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.yield, task);
			fiber.yield();
			debug if (s_taskEventCallback) s_taskEventCallback(TaskEvent.resume, task);
			auto e = fiber.m_exception;
			if( e ){
				fiber.m_exception = null;
				throw e;
			}
		} else {
			assert(!s_eventLoopRunning, "Event processing outside of a fiber should only happen before the event loop is running!?");
			m_eventException = null;
			if (auto err = getEventDriver().runEventLoopOnce()) {
				if (err == 1) {
					logDebug("No events registered, exiting event loop.");
					throw new Exception("No events registered in vibeYieldForEvent.");
				}
				logError("Error running event loop: %d", err);
				throw new Exception("Error waiting for events.");
			}
			if (auto e = m_eventException) {
				m_eventException = null;
				throw e;
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
		if (auto th = cast(Throwable)uncaught_exception) {
			extrap();
			assert(ctask.state == Fiber.State.TERM);
			logError("Task terminated with unhandled exception: %s", th.msg);
			logDebug("Full error: %s", th.toString().sanitize);

			// always pass Errors on
			if (auto err = cast(Error)th) throw err;
		} else assert(!uncaught_exception, "Fiber returned exception object that is not a Throwable!?");
	}

	void notifyIdle()
	{
		bool again = !getExitFlag();
		while (again) {
			if (s_idleHandler)
				again = s_idleHandler();
			else again = false;

			for (auto limit = s_yieldedTasks.length; limit > 0 && !s_yieldedTasks.empty; limit--) {
				auto tf = s_yieldedTasks.front;
				s_yieldedTasks.popFront();
				resumeCoreTask(tf);
			}

			again = (again || !s_yieldedTasks.empty) && !getExitFlag();

			if (again && !getEventDriver().processEvents()) {
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
	TaskFuncInfo[] taskQueue;

	this(Thread thr, bool worker) { this.thread = thr; this.isWorker = worker; }
}

private struct TaskFuncInfo {
	void function(TaskFuncInfo*) func;
	void[2*size_t.sizeof] callable = void;
	void[maxTaskParameterSize] args = void;

	@property ref C typedCallable(C)()
	{
		static assert(C.sizeof <= callable.sizeof);
		return *cast(C*)callable.ptr;
	}

	@property ref A typedArgs(A)()
	{
		static assert(A.sizeof <= args.sizeof);
		return *cast(A*)args.ptr;
	}

	void initCallable(C)()
	{
		C cinit;
		this.callable[0 .. C.sizeof] = cast(void[])(&cinit)[0 .. 1];
	}

	void initArgs(A)()
	{
		A ainit;
		this.args[0 .. A.sizeof] = cast(void[])(&ainit)[0 .. 1];
	}
}

alias TaskArgsVariant = VariantN!maxTaskParameterSize;

/**************************************************************************************************/
/* private functions                                                                              */
/**************************************************************************************************/

private {
	static if ((void*).sizeof >= 8) enum defaultTaskStackSize = 16*1024*1024;
	else enum defaultTaskStackSize = 512*1024;

	__gshared VibeDriverCore s_core;
	__gshared size_t s_taskStackSize = defaultTaskStackSize;

	__gshared core.sync.mutex.Mutex st_threadsMutex;
	__gshared ManualEvent st_threadsSignal;
	__gshared ThreadContext[] st_threads;
	__gshared TaskFuncInfo[] st_workerTasks;
	__gshared Condition st_threadShutdownCondition;
	__gshared debug void function(TaskEvent, Task) s_taskEventCallback;
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

	// COMPILER BUG: Must be some kind of module constructor order issue:
	//    without this, the stdout/stderr handles are not initialized before
	//    the log module is set up.
	import std.stdio; write("");

	initializeLogModule();

	logTrace("create driver core");

	s_core = new VibeDriverCore;
	st_threadsMutex = new Mutex;
	st_threadShutdownCondition = new Condition(st_threadsMutex);

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
		// WORKAROUND: we don't care about viral @nogc attribute here!
		import std.traits;
		signal(SIGABRT, cast(ParameterTypeTuple!signal[1])&onSignal);
		signal(SIGTERM, cast(ParameterTypeTuple!signal[1])&onSignal);
		signal(SIGINT, cast(ParameterTypeTuple!signal[1])&onSignal);
	}

	auto thisthr = Thread.getThis();
	thisthr.name = "Main";
	st_threads ~= ThreadContext(thisthr, false);

	setupDriver();

	st_threadsSignal = getEventDriver().createManualEvent();

	version(VibeIdleCollect){
		logTrace("setup gc");
		s_core.setupGcTimer();
	}

	getOption("uid|user", &s_privilegeLoweringUserName, "Sets the user name or id used for privilege lowering.");
	getOption("gid|group", &s_privilegeLoweringGroupName, "Sets the group name or id used for privilege lowering.");

	static if (newStdConcurrency) {
		import std.concurrency;
		scheduler = new VibedScheduler;
	}
}

shared static ~this()
{
	deleteEventDriver();

	bool tasks_left = false;

	synchronized (st_threadsMutex) {
		if( !st_workerTasks.empty ) tasks_left = true;
	}

	if (!s_yieldedTasks.empty) tasks_left = true;
	if (tasks_left) logWarn("There are still tasks running at exit.");

	delete s_core;
}

// per thread setup
static this()
{
	/// workaround for:
	// object.Exception@src/rt/minfo.d(162): Aborting: Cycle detected between modules with ctors/dtors:
	// vibe.core.core -> vibe.core.drivers.native -> vibe.core.drivers.libasync -> vibe.core.core
	if (Thread.getThis().isDaemon && Thread.getThis().name == "CmdProcessor") return;
			
	assert(s_core !is null);

	auto thisthr = Thread.getThis();
	synchronized (st_threadsMutex)
		if (!st_threads.any!(c => c.thread is thisthr))
			st_threads ~= ThreadContext(thisthr, false);

	//CoreTask.ms_coreTask = new CoreTask;

	setupDriver();
}

static ~this()
{
	auto thisthr = Thread.getThis();

	bool is_main_thread = false;

	synchronized (st_threadsMutex) {
		auto idx = st_threads.countUntil!(c => c.thread is thisthr);
		assert(idx >= 0);
		if (idx >= 0) {
			st_threads[idx] = st_threads[$-1];
			st_threads.length--;
		}

		// if we are the main thread, wait for all others before terminating
		is_main_thread = idx == 0;
		if (is_main_thread) { // we are the main thread, wait for others
			atomicStore(st_term, true);
			st_threadsSignal.emit();
			// wait for all non-daemon threads to shut down
			while (st_threads.any!(th => !th.thread.isDaemon))
				st_threadShutdownCondition.wait();
		}
	}

	// delay deletion of the main event driver to "~shared static this()"
	if (!is_main_thread) deleteEventDriver();

	st_threadShutdownCondition.notifyAll();
}

private void setupDriver()
{
	if (getEventDriver(true) !is null) return;

	logTrace("create driver");
	setupEventDriver(s_core);
	logTrace("driver %s created", (cast(Object)getEventDriver()).classinfo.name);
}

private void setupWorkerThreads()
{
	import core.cpuid;

	static bool s_workerThreadsStarted = false;
	if (s_workerThreadsStarted) return;
	s_workerThreadsStarted = true;

	synchronized (st_threadsMutex) {
		if (st_threads.any!(t => t.isWorker))
			return;

		foreach (i; 0 .. threadsPerCPU) {
			auto thr = new Thread(&workerThreadFunc);
			thr.name = format("Vibe Task Worker #%s", i);
			st_threads ~= ThreadContext(thr, true);
			thr.start();
		}
	}
}

private void workerThreadFunc()
{
	assert(s_core !is null);
	if (getExitFlag()) return;
	logDebug("entering worker thread");
	runTask(toDelegate(&handleWorkerTasks));
	logDebug("running event loop");
	if (!getExitFlag()) runEventLoop();
	logDebug("Worker thread exit.");
}

private void handleWorkerTasks()
{
	logDebug("worker thread enter");

	auto thisthr = Thread.getThis();

	logDebug("worker thread loop enter");
	while(true){
		auto emit_count = st_threadsSignal.emitCount;
		TaskFuncInfo task;

		synchronized (st_threadsMutex) {
			auto idx = st_threads.countUntil!(c => c.thread is thisthr);
			assert(idx >= 0);
			logDebug("worker thread check");

			if (getExitFlag()) {
				if (st_threads[idx].taskQueue.length > 0)
					logWarn("Worker thread shuts down with specific worker tasks left in its queue.");
				if (st_threads.count!(c => c.isWorker) == 1 && st_workerTasks.length > 0)
					logWarn("Worker threads shut down with worker tasks still left in the queue.");
				break;
			}

			if (!st_workerTasks.empty) {
				logDebug("worker thread got task");
				task = st_workerTasks.front;
				st_workerTasks.popFront();
			} else if (!st_threads[idx].taskQueue.empty) {
				logDebug("worker thread got specific task");
				task = st_threads[idx].taskQueue.front;
				st_threads[idx].taskQueue.popFront();
			}
		}

		if (task.func !is null) runTask_internal(task);
		else emit_count = st_threadsSignal.wait(emit_count);
	}

	logDebug("worker thread exit");
	getEventDriver().exitEventLoop();
}


private extern(C) void extrap()
nothrow {
	logTrace("exception trap");
}

// backwards compatibility with DMD < 2.066
static if (__VERSION__ <= 2065) @property bool nogc() { return false; }

private extern(C) void onSignal(int signal)
nothrow {
	atomicStore(st_term, true);
	try st_threadsSignal.emit(); catch (Throwable) {}

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
	size_t length;

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
		length++;
	}

	void popFront()
	{
		if (first == last) last = null;
		assert(first && first.m_queue == &this);
		auto next = first.m_nextInQueue;
		first.m_nextInQueue = null;
		first.m_queue = null;
		first = next;
		length--;
	}
}

// mixin string helper to call a function with arguments that potentially have
// to be moved
private string callWithMove(ARGS...)(string func, string args)
{
	import std.string;
	string ret = func ~ "(";
	foreach (i, T; ARGS) {
		if (i > 0) ret ~= ", ";
		ret ~= format("%s[%s]", args, i);
		static if (needsMove!T) ret ~= ".move";
	}
	return ret ~ ");";
}

private template needsMove(T)
{
	// FIXME: reverse the condition and only call .move for non-copyable types!
	enum needsMove = is(typeof(T.init.move));
}
