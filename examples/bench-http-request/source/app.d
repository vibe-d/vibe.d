import vibe.vibe;
import vibe.core.args;
import std.datetime;
import std.stdio;


long nreq = 0;
long nerr = 0;
long nreqc = 1000;
long nconn = 0;

long g_concurrency = 1;
long g_requestDelay = 0;

StopWatch sw;

void request()
{
	nconn++;
	try requestHttp("http://127.0.0.1:8080/empty",
			(scope req){
				req.headers.remove("Accept-Encoding");
			},
			(scope res){
				if (g_requestDelay)
					sleep(g_requestDelay.msecs());
				res.dropBody();
			}
		);
	catch (Exception) { nerr++; }
	nconn--;
	nreq++;
	if (nreq >= nreqc) {
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
	foreach (i; 0 .. g_concurrency){
		runTask(toDelegate(&reqTask));
		sleep(2.msecs());
	}
	
	while (true) {
		request();
	}
}

void main(string[] args)
{
	import std.getopt;
	getopt(args,
		config.passThrough,
		"c", &g_concurrency,
		"d", &g_requestDelay
		);

	processCommandLineArgs(args);
	runTask(toDelegate(&benchmark));
	runEventLoop();
}
