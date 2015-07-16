/// Small helper module to determine if the new std.concurrency interop features are present
module vibe.internal.newconcurrency;

static if (__VERSION__ >= 2066 && false) {
	import std.concurrency;
	static if (is(std.concurrency.Scheduler)) enum bool newStdConcurrency = true;
	else enum bool newStdConcurrency = false;
} else enum bool newStdConcurrency = false;
