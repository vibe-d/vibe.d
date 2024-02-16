import vibe.core.core;
import vibe.core.file;
import std.stdio;
import std.datetime.stopwatch;

void main() {
	FileStream fs = openFile("./hello.txt", FileMode.createTrunc);
	StopWatch sw;
	sw.start();
	bool finished;
	auto task = runTask({
		try {
			writeln("Task 1: Starting write operations to hello.txt");
			while (sw.peek.total!"msecs" < 150) {
				fs.write("Some string is being written here ..");
			}
			writeln("Task 1: Final offset: ", fs.tell(), "B, file size: ",
				fs.size(), "B", ", total time: ", sw.peek.total!"msecs", " ms");
			fs.close();
		} catch (Exception e) assert(false, e.msg);
		finished = true;
	});

	runTask({
		try {
			while (!finished) {
				writeln("Task 2: Task 1 has written ", fs.size(), "B so far in ", sw.peek.total!"msecs", " ms");
				sleep(10.msecs);
			}
			removeFile("./hello.txt");
			writeln("Task 2: Done.");
			sw.stop();
		} catch (Exception e) assert(false, e.msg);
		exitEventLoop();
	});
	writeln("Main Thread: Writing small chunks in a yielding task (Task 1) for 150 ms");

	runApplication();
}
