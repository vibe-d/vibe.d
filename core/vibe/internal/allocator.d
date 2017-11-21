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
