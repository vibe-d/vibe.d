/**
	Utiltiy functions for memory management

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.memory;

import core.stdc.stdlib;
import core.memory;
import std.conv;

T* heap_new(T, ARGS...)(ARGS args)
	if( is(T == struct) )
{
	auto ret = cast(T*)malloc(T.sizeof);
	GC.addRange(ret, T.sizeof);
	emplace(ret, args);
	return ret;
}

void heap_delete(T)(T* ptr)
	if( is(T == struct) )
{
	GC.removeRange(ptr);
	typeid(T).destroy(ptr);
	free(ptr);
}
