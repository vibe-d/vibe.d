module vibe.internal.allocator;

public import stdx.allocator : allocatorObject, CAllocatorImpl, dispose,
	   expandArray, IAllocator, make, makeArray, shrinkArray, theAllocator;

public import stdx.allocator.building_blocks.allocator_list;
public import stdx.allocator.building_blocks.null_allocator;
public import stdx.allocator.building_blocks.region;
public import stdx.allocator.building_blocks.stats_collector;
public import stdx.allocator.gc_allocator;
public import stdx.allocator.mallocator;

// NOTE: this needs to be used instead of theAllocator due to Phobos issue 17564
@property IAllocator vibeThreadAllocator()
@safe nothrow @nogc {
	static IAllocator s_threadAllocator;
	if (!s_threadAllocator)
		s_threadAllocator = () @trusted { return allocatorObject(GCAllocator.instance); } ();
	return s_threadAllocator;
}

auto makeGCSafe(T, Allocator, A...)(Allocator allocator, auto ref A args)
{
	import core.memory : GC;
	import std.traits : hasIndirections;

	auto ret = allocator.make!T(args);
	static if (is (T == class)) enum tsize = __traits(classInstanceSize, T);
	else enum tsize = T.sizeof;
	static if (hasIndirections!T)
		() @trusted { GC.addRange(cast(void*)ret, tsize, typeid(T)); } ();
	return ret;
}

void disposeGCSafe(T, Allocator)(Allocator allocator, T obj)
{
	import core.memory : GC;
	import std.traits : hasIndirections;

	static if (hasIndirections!T)
		GC.removeRange(cast(void*)obj);
	allocator.dispose(obj);
}
