
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
	//by a TaskReadWriteMutex. Read operations are performed recently (95%) 
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

	//Wait for a second for the server to be initialized properly and then start
	//multiple concurrent threads that simultaneously start queries on the rest
	//interface defined above.
	setTimer(1.seconds, {
		import std.parallelism : totalCPUs;

		for (int cpu = 0; cpu < totalCPUs; ++cpu)
		{
			auto val = async({
					auto api = new RestInterfaceClient!MyBlockingRestInterface("http://127.0.0.1:8080");

					for (int i = 0; i < 100000; ++i)
						api.getIndex();

					//Since we can't join threads in a setTimer call,
					//exit the event loop after the first thread has complete all
					//of it's requests. In any other code, this is propably a bad idea.
					scope(exit)
						exitEventLoop(true);

					return 0;
				});
		}
	});
}
