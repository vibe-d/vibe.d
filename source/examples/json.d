import vibe.d;

import std.stdio;

static this()
{
	JSON a = 1;
	JSON b = 2;
	writefln("%s %s", a.type, b.type);
	auto c = a + b;
	c = c * 2;
	writefln("%d", cast(long)c);
}
