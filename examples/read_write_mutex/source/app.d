
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
	    if (i == 1) //In a rare case, lock for writing
	    {
	        synchronized(m_mutex.writer)
	        {
	        	version(PrintRequests)
	        		writeln("Blocked for writing!");
	        	//Simulate a slow operation
	            vibe.core.core.sleep(50.msecs);
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

shared static this()
{
	auto routes = new URLRouter;
	registerRestInterface(routes, new RestInterfaceImplementation());

	auto settings = new HTTPServerSettings();
	settings.port = 8080;
	settings.options = HTTPServerOption.parseURL | HTTPServerOption.distribute;
	settings.bindAddresses = ["::1", "127.0.0.1"];

	listenHTTP(settings, routes);

	//Wait for a couple of seconds for the server to be initialized properly and then start
	//multiple concurrent threads that simultaneously start queries on the rest interface defined above.
	setTimer(5.seconds, {
        import core.atomic;

		scope(exit)
			exitEventLoop(true);

        auto runningTasks = new shared(int)(0);
        runWorkerTaskDist(function(typeof(runningTasks) runningTasks) {
                atomicOp!"+="(*runningTasks,1);
                scope(exit)
                    atomicOp!"-="(*runningTasks,1);

                auto api = new RestInterfaceClient!MyBlockingRestInterface("http://127.0.0.1:8080");
                for (int i = 0; i < 1000; ++i)
                    api.getIndex();

            }, runningTasks);
         
        //Join all worker tasks. Currently, it's not possible to join tasks from non-vibe threads.
        do 
            sleep(3.seconds);
        while(atomicLoad(*runningTasks) > 0);        
	});
}
