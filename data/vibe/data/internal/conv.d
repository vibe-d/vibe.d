module vibe.data.internal.conv;

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

// wraps formattedWrite in a way that allows using a `scope` range without
// deprecation warnings
void formattedWriteFixed(size_t MAX_BYTES, R, ARGS...)(ref R sink, string format, ARGS args)
@safe {
	import std.format : formattedWrite;
	import vibe.container.internal.appender : FixedAppender;

	FixedAppender!(char[], MAX_BYTES) app;
	app.formattedWrite(format, args);
	sink.put(app.data);
}

private enum isDeprecated(alias parent, string symbol)
	= __traits(isDeprecated, __traits(getMember, parent, symbol));
