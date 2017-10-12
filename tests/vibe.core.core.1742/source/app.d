import std.stdio;
import std.socket;
import std.datetime;
import std.functional;
import core.time;
import vibe.core.core;
import vibe.core.log;
import vibe.core.concurrency;
import vibe.core.connectionpool;

class Conn {}

void main()
{
	auto g = new Generator!int({
		auto t = runTask({});
		t.join();
		yield(2);
	});
	assert(!g.empty);
	assert(g.front == 2);
	g.popFront();
	assert(g.empty);

	runTask({
		auto g2 = new Generator!int({
			auto t = runTask({});
			t.join();
			yield(1);
		});
		assert(!g2.empty);
		assert(g2.front == 1);
		g2.popFront();
		assert(g2.empty);
		exitEventLoop();
	});

	setTimer(5.seconds, {
		assert(false, "Test has hung.");
	});

	runApplication();
}

