import vibe.vibe;
import std.file, std.process;

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
		assert(watcher.readChanges(changes, 0.seconds));
		assert(changes == expected);
		assert(!watcher.readChanges(changes, 100.msecs));
	}

	write(foo, null);
	check([dc(Type.added, foo)]);
	write(foo, [0, 1]);
	check([dc(Type.modified, foo)]);
	remove(foo);
	check([dc(Type.removed, foo)]);
	write(foo, null);
	write(foo, [0, 1]);
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
	write(foo, [0, 1]);
	remove(foo);
	write(bar, null);
	write(bar, [0, 1]);
	remove(bar);
	check([dc(Type.added, foo), dc(Type.modified, foo), dc(Type.removed, foo),
		 dc(Type.added, bar), dc(Type.modified, bar), dc(Type.removed, bar)]);

	write(foo, null);
	rename(foo, bar);
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
