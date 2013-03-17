import vibe.vibe;
import vibe.core.args;
import std.datetime;
import std.stdio;


ulong nreq = 0;
ulong nerr = 0;
ulong nreqc = 1000;


void request()
{
	try requestHttp("http://127.0.0.1:8080/empty", null, (scope res){ res.dropBody(); });
	catch (Exception) { nerr++; }
	nreq++;
}

void reqTask()
{
	while (true) request();
}

void main(string[] args)
{
	processCommandLineArgs(args);

	StopWatch sw;
	sw.start();
	//foreach (i; 0 .. 2) runTask(toDelegate(&reqTask));
	while (true) {
		request();
		if (nreq > nreqc) {
			writefln("%s iterations: %s req/s, %s err/s", nreq, (nreq*1_000)/sw.peek().msecs(), (nerr*1_000)/sw.peek().msecs());
			nreqc += 1000;
		}
	}
}
