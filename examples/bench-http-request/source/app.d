import vibe.core.args;
import vibe.core.core;
import vibe.http.client;

import core.atomic;

static if (__VERSION__ >= 2076)
	import std.datetime.stopwatch;
else
	import std.datetime;

import std.functional;
import std.stdio;


shared long nreq = 0;
shared long nerr = 0;
shared long nreqc = 1000;
shared long ndisconns = 0;
shared long nconn = 0;

shared long g_concurrency = 100;
shared long g_requestDelay = 0;
shared long g_maxKeepAliveRequests = 1000;

void request(bool disconnect)
{
	atomicOp!"+="(nconn, 1);
	try {
		requestHTTP("http://127.0.0.1:8080/empty",
			(scope req){
				req.headers.remove("Accept-Encoding");
				if (disconnect) {
					atomicOp!"+="(ndisconns, 1);
					req.headers["Connection"] = "close";
				}
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
	int id = atomicOp!"+="(s_threadCount, 1) - 1;

	while (true) {
		while (atomicLoad(s_token) != id && g_concurrency > 0) {}
		if (g_concurrency == 0) break;
		runTask({
			long keep_alives = 0;
			while (true) {
				bool disconnect = ++keep_alives >= g_maxKeepAliveRequests;
				request(disconnect);
				if (disconnect) keep_alives = 0;
			}
		});
		atomicOp!"+="(g_concurrency, -1);
		atomicStore(s_token, cast(int)((id + 1) % workerThreadCount));
	}
}

void benchmark()
{
	atomicOp!"+="(g_concurrency, -1);
	if (g_concurrency > 0) {
		runWorkerTaskDist(&distTask);
		while (atomicLoad(nreq) == 0) { sleep(1.msecs); }
	}

	StopWatch sw;
	sw.start();
	ulong next_ts = 100;

	long keep_alives = 0;
	while (true) {
		static if (__VERSION__ >= 2076)
			auto tm = sw.peek().total!"msecs";
		else
			auto tm = sw.peek().msecs;

		if (nreq >= nreqc && tm >= next_ts) {
			writefln("%s iterations: %s req/s, %s err/s (%s active conn, %s disconnects/s)", nreq, (nreq*1_000)/tm, (nerr*1_000)/tm, nconn, (ndisconns*1_000)/tm);
			nreqc.atomicOp!"+="(1000);
			next_ts += 100;
		}
		bool disconnect = ++keep_alives >= g_maxKeepAliveRequests;
		request(disconnect);
		if (disconnect) keep_alives = 0;
//                if (nreq >= 5000) exitEventLoop(true);
	}
}

void main()
{
	import vibe.core.args;
	readOption("c", cast(long*) &g_concurrency, "The maximum number of concurrent requests");
	readOption("d", cast(long*) &g_requestDelay, "Artificial request delay in milliseconds");
	readOption("k", cast(long*) &g_maxKeepAliveRequests, "Maximum number of keep-alive requests for each connection");
	if (!finalizeCommandLineOptions()) return;
	runTask(toDelegate(&benchmark));
	runEventLoop();
}
