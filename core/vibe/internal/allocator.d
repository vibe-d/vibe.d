module vibe.internal.allocator;

public import std.experimental.allocator : allocatorObject, CAllocatorImpl, dispose,
	   expandArray, IAllocator, make, makeArray, shrinkArray, theAllocator;

public import std.experimental.allocator.building_blocks.allocator_list;
public import std.experimental.allocator.building_blocks.null_allocator;
public import std.experimental.allocator.building_blocks.region;
public import std.experimental.allocator.building_blocks.stats_collector;
public import std.experimental.allocator.gc_allocator;
public import std.experimental.allocator.mallocator;

__gshared IAllocator _processAllocator;

shared static this()
{
    import std.experimental.allocator.gc_allocator : GCAllocator;
    _processAllocator = allocatorObject(GCAllocator.instance);
}

@property IAllocator processAllocator()
{
    return _processAllocator;
}
