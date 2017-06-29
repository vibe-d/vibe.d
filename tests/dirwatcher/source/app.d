import vibe.vibe;
import std.file, std.process;
import std.algorithm : canFind, all;
import std.typecons : No, Yes;

void runTest()
{
	auto dir = buildPath(tempDir, format("dirwatcher_test_%d", thisProcessID()));
	mkdir(dir);
	scope(exit) rmdirRecurse(dir);

	DirectoryWatcher watcher;
	try watcher = Path(dir).watchDirectory(No.recursive);
	catch (AssertError e) {
		logInfo("DirectoryWatcher not yet implemented. Skipping test.");
		return;
	}
	DirectoryChange[] changes;
	assert(!watcher.readChanges(changes, 500.msecs));

	auto foo = dir.buildPath("foo");

	alias Type = DirectoryChangeType;
	static DirectoryChange dc(Type t, string p) { return DirectoryChange(t, Path(p)); }
	void check(DirectoryChange[] expected)
	{
		sleep(100.msecs);
		assert(watcher.readChanges(changes, 100.msecs), "Could not read changes for " ~ expected.to!string);
		assert(expected.all!((a)=> changes.canFind(a))(), "Change is not what was expected, got: " ~ changes.to!string ~ " but expected: " ~ expected.to!string);
		assert(!watcher.readChanges(changes, 0.msecs), "Changes were returned when they shouldn't have, for " ~ expected.to!string);
	}

	write(foo, null);
	check([dc(Type.added, foo)]);
	sleep(1.seconds); // OSX has a second resolution on file modification times
	write(foo, [0, 1]);
	check([dc(Type.modified, foo)]);
	remove(foo);
	check([dc(Type.removed, foo)]);
	write(foo, null);
	sleep(1.seconds);
	write(foo, [0, 1]);
	sleep(100.msecs);
	remove(foo);
	check([dc(Type.added, foo), dc(Type.modified, foo), dc(Type.removed, foo)]);

	auto subdir = dir.buildPath("subdir");
	mkdir(subdir);
	check([dc(Type.added, subdir)]);
	auto bar = subdir.buildPath("bar");
	write(bar, null);
	assert(!watcher.readChanges(changes, 100.msecs));
	remove(bar);
	watcher = Path(dir).watchDirectory(Yes.recursive);
	write(foo, null);
	sleep(1.seconds);
	write(foo, [0, 1]);
	sleep(100.msecs);
	remove(foo);

	write(bar, null);
	sleep(1.seconds);
	write(bar, [0, 1]);
	sleep(100.msecs);
	remove(bar);
	check([dc(Type.added, foo), dc(Type.modified, foo), dc(Type.removed, foo),
		 dc(Type.added, bar), dc(Type.modified, bar), dc(Type.removed, bar)]);

	write(foo, null);
	sleep(100.msecs);
	rename(foo, bar);
	sleep(100.msecs);
	remove(bar);
	check([dc(Type.added, foo), dc(Type.removed, foo), dc(Type.added, bar), dc(Type.removed, bar)]);

}

int main()
{
	int ret = 0;
	runTask({
		try runTest();
		catch (Throwable th) {
			logError("Test failed: %s", th.toString());
			ret = 1;
		} finally exitEventLoop(true);
	});
	runEventLoop();
	return ret;
}
