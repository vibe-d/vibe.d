import vibe.core.core;
import vibe.core.file;
import std.stdio;

shared static this()
{
	FileStream fs = openFile("./hello.txt", FileMode.createTrunc);
	import std.datetime;
	StopWatch sw;
	sw.start();
	bool finished;
	auto task = runTask({
		void print(ulong pos, size_t sz) {
			auto off = fs.tell();
			fs.seek(pos);
			ubyte[] dst = new ubyte[sz];
			fs.read(dst);
			writefln("%s", cast(string)dst);
			fs.seek(off);
		}
		writeln("Task 1: Starting write operations to hello.txt");
		while(sw.peek().msecs < 150) {
			fs.write("Some string is being written here ..");
		}
		writeln("Task 1: Final offset: ", fs.tell(), "B, file size: ", fs.size(), "B", ", total time: ", sw.peek().msecs, " ms");
		fs.close();
		finished = true;
	});

	runTask({
		while(!finished)
		{
			writeln("Task 2: Task 1 has written ", fs.size(), "B so far in ", sw.peek().msecs, " ms");
			sleep(10.msecs);
		}
		removeFile("./hello.txt");
		writeln("Task 2: Done. Press CTRL+C to exit.");
		sw.stop();
	});
	writeln("Main Thread: Writing small chunks in a yielding task (Task 1) for 150 ms");
}
