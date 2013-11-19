import vibe.core.args;
import vibe.core.core;
import vibe.http.client;

import core.atomic;
import std.datetime;
import std.functional;
import std.stdio;


shared long nreq = 0;
shared long nerr = 0;
shared long nreqc = 1000;
shared long nconn = 0;

shared long g_concurrency = 1;
shared long g_requestDelay = 0;

void request()
{
	atomicOp!"+="(nconn, 1);
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
	} catch (Exception) { atomicOp!"+="(nerr, 1); }
	atomicOp!"-="(nconn, 1);
	atomicOp!"+="(nreq, 1);
}

void distTask()
{
	static shared int s_threadCount = 0;
	static shared int s_token = 0;
	auto id = atomicOp!"+="(s_threadCount, 1) - 1;
	
	while (true) {
		while (atomicLoad(s_token) != id && g_concurrency > 0) {}
		if (g_concurrency == 0) break;
		runTask({ while (true) request(); });
		g_concurrency--;
		atomicStore(s_token, (id + 1) % workerThreadCount);
	}
}

void benchmark()
{
	g_concurrency--;
	runWorkerTaskDist(&distTask);

	while (atomicLoad(nreq) == 0) { sleep(1.msecs); }

	StopWatch sw;
	sw.start();
	ulong next_ts = 100;

	while (true) {
		if (nreq >= nreqc && sw.peek().msecs() >= next_ts) {
			writefln("%s iterations: %s req/s, %s err/s (%s active conn)", nreq, (nreq*1_000)/sw.peek().msecs(), (nerr*1_000)/sw.peek().msecs(), nconn);
			nreqc += 1000;
			next_ts += 100;
		}
		request();
	}
}

void main()
{
	import vibe.core.args;
	getOption("c", &g_concurrency, "The maximum number of concurrent requests");
	getOption("d", &g_requestDelay, "Artificial request delay in milliseconds");
	if (!finalizeCommandLineOptions()) return;
	enableWorkerThreads();
	runTask(toDelegate(&benchmark));
	runEventLoop();
}
