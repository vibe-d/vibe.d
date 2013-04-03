import vibe.core.args;
import vibe.core.core;
import vibe.http.client;
import std.datetime;
import std.functional;
import std.stdio;


shared long nreq = 0;
shared long nerr = 0;
shared long nreqc = 1000;
shared long nconn = 0;

shared long g_concurrency = 1;
shared long g_requestDelay = 0;

__gshared StopWatch sw;

void request()
{
	nconn++;
	try {
		requestHTTP("http://127.0.0.1:8080/empty",
			(scope req){
				req.headers.remove("Accept-Encoding");
			},
			(scope res){
				if (g_requestDelay)
					sleep(g_requestDelay.msecs());
				res.dropBody();
			}
		);
	} catch (Exception) { nerr++; }
	nconn--;
	nreq++;
	if (nreq >= nreqc && sw.peek().msecs() > 0) {
		writefln("%s iterations: %s req/s, %s err/s (%s active conn)", nreq, (nreq*1_000)/sw.peek().msecs(), (nerr*1_000)/sw.peek().msecs(), nconn);
		nreqc += 1000;
	}
}

void reqTask()
{
	while (true) request();
}

void benchmark()
{
	sw.start();
	foreach (i; 0 .. g_concurrency)
		runWorkerTask(&reqTask);
	
	while (true) request();
}

void main(string[] args)
{
	import std.getopt;
	getopt(args,
		config.passThrough,
		"c", &g_concurrency,
		"d", &g_requestDelay
		);

	enableWorkerThreads();
	processCommandLineArgs(args);
	runTask(toDelegate(&benchmark));
	runEventLoop();
}
