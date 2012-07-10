/**
	Utility functions for data serialization

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.data.utils;

public import std.traits;


template isRWPlainField(T, string M)
{
	static if( !__traits(compiles, typeof(__traits(getMember, T, M))) ){
		enum isRWPlainField = false;
	} else {
		//pragma(msg, T.stringof~"."~M~":"~typeof(__traits(getMember, T, M)).stringof);
		enum isRWPlainField = isRWField!(T, M) && __traits(compiles, *(&__traits(getMember, Tgen!T(), M)) = *(&__traits(getMember, Tgen!T(), M)));
	}
}

template isRWField(T, string M)
{
	enum isRWField = __traits(compiles, __traits(getMember, Tgen!T(), M) = __traits(getMember, Tgen!T(), M));
	//pragma(msg, T.stringof~"."~M~": "~(isRWField?"1":"0"));
}

/// private
private T Tgen(T)(){ return T.init; }
