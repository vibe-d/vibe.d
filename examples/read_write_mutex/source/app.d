
import vibe.d;

interface MyBlockingRestInterface {
	@path("/")
	int getIndex();
}

class RestInterfaceImplementation : MyBlockingRestInterface {
	private {
		TaskReadWriteMutex m_mutex;
	}

	this()
	{
		m_mutex = new TaskReadWriteMutex(TaskReadWriteMutex.Policy.PREFER_WRITERS);
	}

	//This method naively simulates access to a shared resource protected
	//by a TaskReadWriteMutex. Read operations are performed frequently (95%)
	//and finish quickly (1ms wait time), while write operations occur rarely
	//(5%) and take much longer to process (50ms wait time).
	int getIndex()
	{
		import std.random;
		import std.stdio;
		auto i = uniform(0,20);

		if (i == 0) //In a rare case, lock for writing
		{
			synchronized(m_mutex.writer)
			{
				version(PrintRequests)
					writeln("Blocked for writing!");
				//Simulate a slow operation
				vibe.core.core.sleep(100.msecs);
			}
		}
		else //More regularly, lock for reading
		{
			synchronized(m_mutex.reader)
			{
				version(PrintRequests)
					writeln("Blocked for reading!");
				//Simulate a faster operation
				vibe.core.core.sleep(1.msecs);
			}
		}
		return 0;
	}
}


__gshared {
	TaskMutex s_taskMutex;
	TaskCondition s_taskCondition;
	ulong s_runningTasks;
}

shared static this()
{
	s_taskMutex = new TaskMutex();
	s_taskCondition = new TaskCondition(s_taskMutex);

	runWorkerTaskDist({
		import core.thread : Thread; logInfo("Listen on thread %s", Thread.getThis().name);
		auto routes = new URLRouter;
		registerRestInterface(routes, new RestInterfaceImplementation());

		auto settings = new HTTPServerSettings();
		settings.port = 8080;
		settings.options = HTTPServerOption.parseURL|HTTPServerOption.reusePort;
		settings.bindAddresses = ["::1", "127.0.0.1"];

		listenHTTP(settings, routes);
	});

	//Wait for a couple of seconds for the server to be initialized properly and then start
	//multiple concurrent threads that simultaneously start queries on the rest interface defined above.
	setTimer(500.msecs, () @trusted  {
		scope (failure) assert(false);

		scope(exit)
			exitEventLoop(true);

		//Start multiple tasks performing requests on "http://localhost:8080/" concurrently
		synchronized(s_taskMutex) s_runningTasks = workerThreadCount();
		runWorkerTaskDist({
				try {
					//Keep track of the number of currently running tasks
					scope (exit) {
						synchronized(s_taskMutex) s_runningTasks -= 1;
						s_taskCondition.notifyAll();
					}

					//Perform a couple of request to the rest interface
					auto api = new RestInterfaceClient!MyBlockingRestInterface("http://127.0.0.1:8080");
					for (int i = 0; i < 1000; ++i)
						api.getIndex();
				} catch (Exception e) {
					logError("Performing client request failed: %s", e.msg);
				}
			});

		//Wait for all tasks to complete
		synchronized(s_taskMutex) {
			do s_taskCondition.wait();
			while(s_runningTasks > 0);
		}
	});
}
