module vibe.internal.conv;

import std.traits : OriginalType;

string enumToString(E)(E value)
{
	import std.conv : to;

	switch (value) {
		default: return "cast("~E.stringof~")"~(cast(OriginalType!E)value).to!string;
		static foreach (m; __traits(allMembers, E)) {
			static if (!isDeprecated!(E, m)) {
				case __traits(getMember, E, m): return m;
			}
		}
	}
}

private enum isDeprecated(alias parent, string symbol)
	= __traits(isDeprecated, __traits(getMember, parent, symbol));
