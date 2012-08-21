import vibe.vibe;

import std.stdio;

void main()
{
	Json a = 1;
	Json b = 2;
	writefln("%s %s", a.type, b.type);
	auto c = a + b;
	c = c * 2;
	writefln("%d", cast(long)c);
}
