module vibe.internal.memory_legacy;

import vibe.internal.meta.traits : synchronizedIsNothrow;

import core.exception : OutOfMemoryError;
import core.stdc.stdlib;
import core.memory;
import std.conv;
import std.exception : enforceEx;
import std.traits;
import std.algorithm;

Allocator defaultAllocator() @safe nothrow
{
	version(VibeManualMemoryManagement){
		return manualAllocator();
	} else return () @trusted {
		static __gshared Allocator alloc;
		if (!alloc) {
			alloc = new GCAllocator;
			//alloc = new AutoFreeListAllocator(alloc);
			//alloc = new DebugAllocator(alloc);
			alloc = new LockAllocator(alloc);
		}
		return alloc;
	} ();
}

Allocator manualAllocator() @trusted nothrow
{
	static __gshared Allocator alloc;
	if (!alloc) {
		alloc = new MallocAllocator;
		alloc = new AutoFreeListAllocator(alloc);
		//alloc = new DebugAllocator(alloc);
		alloc = new LockAllocator(alloc);
	}
	return alloc;
}

Allocator threadLocalAllocator() @safe nothrow
{
	static Allocator alloc;
	if (!alloc) {
		version(VibeManualMemoryManagement) alloc = new MallocAllocator;
		else alloc = new GCAllocator;
		alloc = new AutoFreeListAllocator(alloc);
		// alloc = new DebugAllocator(alloc);
	}
	return alloc;
}

Allocator threadLocalManualAllocator() @safe nothrow
{
	static Allocator alloc;
	if (!alloc) {
		alloc = new MallocAllocator;
		alloc = new AutoFreeListAllocator(alloc);
		// alloc = new DebugAllocator(alloc);
	}
	return alloc;
}

auto allocObject(T, bool MANAGED = true, ARGS...)(Allocator allocator, ARGS args)
{
	auto mem = allocator.alloc(AllocSize!T);
	static if( MANAGED ){
		static if( hasIndirections!T )
			GC.addRange(mem.ptr, mem.length);
		return internalEmplace!T(mem, args);
	}
	else static if( is(T == class) ) return cast(T)mem.ptr;
	else return cast(T*)mem.ptr;
}

T[] allocArray(T, bool MANAGED = true)(Allocator allocator, size_t n)
{
	auto mem = allocator.alloc(T.sizeof * n);
	auto ret = cast(T[])mem;
	static if( MANAGED ){
		static if( hasIndirections!T )
			GC.addRange(mem.ptr, mem.length);
		// TODO: use memset for class, pointers and scalars
		foreach (ref el; ret) {
			internalEmplace!T(cast(void[])((&el)[0 .. 1]));
		}
	}
	return ret;
}

void freeArray(T, bool MANAGED = true)(Allocator allocator, ref T[] array, bool call_destructors = true)
{
	static if (MANAGED) {
		static if (hasIndirections!T)
			GC.removeRange(array.ptr);
		static if (hasElaborateDestructor!T)
			if (call_destructors)
				foreach_reverse (ref el; array)
					destroy(el);
	}
	allocator.free(cast(void[])array);
	array = null;
}


interface Allocator {
nothrow:
	enum size_t alignment = 0x10;
	enum size_t alignmentMask = alignment-1;

	// NOTE: the contracts in this interface have two issues:
	//       - they require an assert(false); contract in the derived class to have any effect
	//       - there is s codegen issue that yield garbage values within the contracts defined here
	//       For these reasons contracts need to be placed into each class individually instead

	void[] alloc(size_t sz);
		//out { assert((cast(size_t)__result.ptr & alignmentMask) == 0, "alloc() returned misaligned data."); }

	void[] realloc(void[] mem, size_t new_sz);
		/*in {
			assert(mem.ptr !is null, "realloc() called with null array.");
			assert((cast(size_t)mem.ptr & alignmentMask) == 0, "misaligned pointer passed to realloc().");
		}
		out { assert((cast(size_t)__result.ptr & alignmentMask) == 0, "realloc() returned misaligned data."); }*/

	void free(void[] mem);
		/*in {
			assert(mem.ptr !is null, "free() called with null array.");
			assert((cast(size_t)mem.ptr & alignmentMask) == 0, "misaligned pointer passed to free().");
		}*/
}


/**
	Simple proxy allocator protecting its base allocator with a mutex.
*/
class LockAllocator : Allocator {
	private {
		Allocator m_base;
	}
	this(Allocator base) nothrow @safe { m_base = base; }
	void[] alloc(size_t sz) {
		static if (!synchronizedIsNothrow)
			scope (failure) assert(0, "Internal error: function should be nothrow");

		synchronized (this)
			return m_base.alloc(sz);
	}
	void[] realloc(void[] mem, size_t new_sz)
		in {
			assert(mem.ptr !is null, "realloc() called with null array.");
			assert((cast(size_t)mem.ptr & alignmentMask) == 0, "misaligned pointer passed to realloc().");
		}
		body {
			static if (!synchronizedIsNothrow)
				scope (failure) assert(0, "Internal error: function should be nothrow");

			synchronized(this)
				return m_base.realloc(mem, new_sz);
		}
	void free(void[] mem)
		in {
			assert(mem.ptr !is null, "free() called with null array.");
			assert((cast(size_t)mem.ptr & alignmentMask) == 0, "misaligned pointer passed to free().");
		}
		body {
			static if (!synchronizedIsNothrow)
				scope (failure) assert(0, "Internal error: function should be nothrow");
			synchronized(this)
				m_base.free(mem);
		}
}

final class DebugAllocator : Allocator {
	import vibe.utils.hashmap : HashMap;
	private {
		Allocator m_baseAlloc;
		HashMap!(void*, size_t) m_blocks;
		size_t m_bytes;
		size_t m_maxBytes;
	}

	this(Allocator base_allocator) nothrow @safe
	{
		import vibe.internal.utilallocator : Mallocator, allocatorObject;
		m_baseAlloc = base_allocator;
		m_blocks = HashMap!(void*, size_t)(() @trusted { return Mallocator.instance.allocatorObject; } ());
	}

	@property size_t allocatedBlockCount() const { return m_blocks.length; }
	@property size_t bytesAllocated() const { return m_bytes; }
	@property size_t maxBytesAllocated() const { return m_maxBytes; }

	void[] alloc(size_t sz)
	{
		auto ret = m_baseAlloc.alloc(sz);
		assert(ret.length == sz, "base.alloc() returned block with wrong size.");
		assert(m_blocks.getNothrow(ret.ptr, size_t.max) == size_t.max, "base.alloc() returned block that is already allocated.");
		m_blocks[ret.ptr] = sz;
		m_bytes += sz;
		if( m_bytes > m_maxBytes ){
			m_maxBytes = m_bytes;
			logDebug_("New allocation maximum: %d (%d blocks)", m_maxBytes, m_blocks.length);
		}
		return ret;
	}

	void[] realloc(void[] mem, size_t new_size)
	{
		auto sz = m_blocks.getNothrow(mem.ptr, size_t.max);
		assert(sz != size_t.max, "realloc() called with non-allocated pointer.");
		assert(sz == mem.length, "realloc() called with block of wrong size.");
		auto ret = m_baseAlloc.realloc(mem, new_size);
		assert(ret.length == new_size, "base.realloc() returned block with wrong size.");
		assert(ret.ptr is mem.ptr || m_blocks.getNothrow(ret.ptr, size_t.max) == size_t.max, "base.realloc() returned block that is already allocated.");
		m_bytes -= sz;
		m_blocks.remove(mem.ptr);
		m_blocks[ret.ptr] = new_size;
		m_bytes += new_size;
		return ret;
	}
	void free(void[] mem)
	{
		auto sz = m_blocks.getNothrow(mem.ptr, size_t.max);
		assert(sz != size_t.max, "free() called with non-allocated object.");
		assert(sz == mem.length, "free() called with block of wrong size.");
		m_baseAlloc.free(mem);
		m_bytes -= sz;
		m_blocks.remove(mem.ptr);
	}
}

final class MallocAllocator : Allocator {
	void[] alloc(size_t sz)
	{
		static err = new immutable OutOfMemoryError;
		auto ptr = .malloc(sz + Allocator.alignment);
		if (ptr is null) throw err;
		return adjustPointerAlignment(ptr)[0 .. sz];
	}

	void[] realloc(void[] mem, size_t new_size)
	{
		size_t csz = min(mem.length, new_size);
		auto p = extractUnalignedPointer(mem.ptr);
		size_t oldmisalign = mem.ptr - p;

		auto pn = cast(ubyte*).realloc(p, new_size+Allocator.alignment);
		if (p == pn) return pn[oldmisalign .. new_size+oldmisalign];

		auto pna = cast(ubyte*)adjustPointerAlignment(pn);
		auto newmisalign = pna - pn;

		// account for changed alignment after realloc (move memory back to aligned position)
		if (oldmisalign != newmisalign) {
			if (newmisalign > oldmisalign) {
				foreach_reverse (i; 0 .. csz)
					pn[i + newmisalign] = pn[i + oldmisalign];
			} else {
				foreach (i; 0 .. csz)
					pn[i + newmisalign] = pn[i + oldmisalign];
			}
		}

		return pna[0 .. new_size];
	}

	void free(void[] mem)
	{
		.free(extractUnalignedPointer(mem.ptr));
	}
}

final class GCAllocator : Allocator {
	void[] alloc(size_t sz)
	{
		auto mem = GC.malloc(sz+Allocator.alignment);
		auto alignedmem = adjustPointerAlignment(mem);
		assert(alignedmem - mem <= Allocator.alignment);
		auto ret = alignedmem[0 .. sz];
		ensureValidMemory(ret);
		return ret;
	}
	void[] realloc(void[] mem, size_t new_size)
	{
		size_t csz = min(mem.length, new_size);

		auto p = extractUnalignedPointer(mem.ptr);
		size_t misalign = mem.ptr - p;
		assert(misalign <= Allocator.alignment);

		void[] ret;
		auto extended = GC.extend(p, new_size - mem.length, new_size - mem.length);
		if (extended) {
			assert(extended >= new_size+Allocator.alignment);
			ret = p[misalign .. new_size+misalign];
		} else {
			ret = alloc(new_size);
			ret[0 .. csz] = mem[0 .. csz];
		}
		ensureValidMemory(ret);
		return ret;
	}
	void free(void[] mem)
	{
		// For safety reasons, the GCAllocator should never explicitly free memory.
		//GC.free(extractUnalignedPointer(mem.ptr));
	}
}

final class AutoFreeListAllocator : Allocator {
	import std.typetuple;

	private {
		enum minExponent = 5;
		enum freeListCount = 14;
		FreeListAlloc[freeListCount] m_freeLists;
		Allocator m_baseAlloc;
	}

	this(Allocator base_allocator) nothrow @safe
	{
		m_baseAlloc = base_allocator;
		foreach (i; iotaTuple!freeListCount)
			m_freeLists[i] = new FreeListAlloc(nthFreeListSize!(i), m_baseAlloc);
	}

	void[] alloc(size_t sz)
	{
		auto idx = getAllocatorIndex(sz);
		return idx < freeListCount ? m_freeLists[idx].alloc()[0 .. sz] : m_baseAlloc.alloc(sz);
	}

	void[] realloc(void[] data, size_t sz)
	{
		auto curidx = getAllocatorIndex(data.length);
		auto newidx = getAllocatorIndex(sz);

		if (curidx == newidx) {
			if (curidx == freeListCount) {
				// forward large blocks to the base allocator
				return m_baseAlloc.realloc(data, sz);
			} else {
				// just grow the slice if it still fits into the free list slot
				return data.ptr[0 .. sz];
			}
		}

		// otherwise re-allocate manually
		auto newd = alloc(sz);
		assert(newd.ptr+sz <= data.ptr || newd.ptr >= data.ptr+data.length, "New block overlaps old one!?");
		auto len = min(data.length, sz);
		newd[0 .. len] = data[0 .. len];
		free(data);
		return newd;
	}

	void free(void[] data)
	{
		//logTrace("AFL free %08X(%s)", data.ptr, data.length);
		auto idx = getAllocatorIndex(data.length);
		if (idx < freeListCount) m_freeLists[idx].free(data.ptr[0 .. 1 << (idx + minExponent)]);
		else m_baseAlloc.free(data);
	}

	// does a CT optimized binary search for the right allocater
	private int getAllocatorIndex(size_t sz)
	@safe nothrow @nogc {
		//pragma(msg, getAllocatorIndexStr!(0, freeListCount));
		return mixin(getAllocatorIndexStr!(0, freeListCount));
	}

	private template getAllocatorIndexStr(int low, int high)
	{
		import std.format : format;
		static if (low == high) enum getAllocatorIndexStr = format("%s", low);
		else {
			enum mid = (low + high) / 2;
			enum getAllocatorIndexStr =
				"sz > nthFreeListSize!%s ? %s : %s"
				.format(mid, getAllocatorIndexStr!(mid+1, high), getAllocatorIndexStr!(low, mid));
		}
	}

	unittest {
		auto a = new AutoFreeListAllocator(null);
		assert(a.getAllocatorIndex(0) == 0);
		foreach (i; iotaTuple!freeListCount) {
			assert(a.getAllocatorIndex(nthFreeListSize!i-1) == i);
			assert(a.getAllocatorIndex(nthFreeListSize!i) == i);
			assert(a.getAllocatorIndex(nthFreeListSize!i+1) == i+1);
		}
		assert(a.getAllocatorIndex(size_t.max) == freeListCount);
	}

	private static pure size_t nthFreeListSize(size_t i)() { return 1 << (i + minExponent); }
	private template iotaTuple(size_t i) {
		static if (i > 1) alias iotaTuple = TypeTuple!(iotaTuple!(i-1), i-1);
		else alias iotaTuple = TypeTuple!(0);
	}
}

final class PoolAllocator : Allocator {
	static struct Pool { Pool* next; void[] data; void[] remaining; }
	static struct Destructor { Destructor* next; void function(void*) destructor; void* object; }
	private {
		Allocator m_baseAllocator;
		Pool* m_freePools;
		Pool* m_fullPools;
		Destructor* m_destructors;
		size_t m_poolSize;
	}

	this(size_t pool_size, Allocator base) @safe nothrow
	{
		m_poolSize = pool_size;
		m_baseAllocator = base;
	}

	@property size_t totalSize()
	@safe nothrow @nogc {
		size_t amt = 0;
		for (auto p = m_fullPools; p; p = p.next)
			amt += p.data.length;
		for (auto p = m_freePools; p; p = p.next)
			amt += p.data.length;
		return amt;
	}

	@property size_t allocatedSize()
	@safe nothrow @nogc {
		size_t amt = 0;
		for (auto p = m_fullPools; p; p = p.next)
			amt += p.data.length;
		for (auto p = m_freePools; p; p = p.next)
			amt += p.data.length - p.remaining.length;
		return amt;
	}

	void[] alloc(size_t sz)
	{
		auto aligned_sz = alignedSize(sz);

		Pool* pprev = null;
		Pool* p = cast(Pool*)m_freePools;
		while( p && p.remaining.length < aligned_sz ){
			pprev = p;
			p = p.next;
		}

		if( !p ){
			auto pmem = m_baseAllocator.alloc(AllocSize!Pool);

			p = emplace!Pool(cast(Pool*)pmem.ptr);
			p.data = m_baseAllocator.alloc(max(aligned_sz, m_poolSize));
			p.remaining = p.data;
			p.next = cast(Pool*)m_freePools;
			m_freePools = p;
			pprev = null;
		}

		auto ret = p.remaining[0 .. aligned_sz];
		p.remaining = p.remaining[aligned_sz .. $];
		if( !p.remaining.length ){
			if( pprev ){
				pprev.next = p.next;
			} else {
				m_freePools = p.next;
			}
			p.next = cast(Pool*)m_fullPools;
			m_fullPools = p;
		}

		return ret[0 .. sz];
	}

	void[] realloc(void[] arr, size_t newsize)
	{
		auto aligned_sz = alignedSize(arr.length);
		auto aligned_newsz = alignedSize(newsize);

		if( aligned_newsz <= aligned_sz ) return arr[0 .. newsize]; // TODO: back up remaining

		auto pool = m_freePools;
		bool last_in_pool = pool && arr.ptr+aligned_sz == pool.remaining.ptr;
		if( last_in_pool && pool.remaining.length+aligned_sz >= aligned_newsz ){
			pool.remaining = pool.remaining[aligned_newsz-aligned_sz .. $];
			arr = arr.ptr[0 .. aligned_newsz];
			assert(arr.ptr+arr.length == pool.remaining.ptr, "Last block does not align with the remaining space!?");
			return arr[0 .. newsize];
		} else {
			auto ret = alloc(newsize);
			assert(ret.ptr >= arr.ptr+aligned_sz || ret.ptr+ret.length <= arr.ptr, "New block overlaps old one!?");
			ret[0 .. min(arr.length, newsize)] = arr[0 .. min(arr.length, newsize)];
			return ret;
		}
	}

	void free(void[] mem)
	{
	}

	void freeAll()
	{
		version(VibeManualMemoryManagement){
			// destroy all initialized objects
			for (auto d = m_destructors; d; d = d.next)
				d.destructor(cast(void*)d.object);
			m_destructors = null;

			// put all full Pools into the free pools list
			for (Pool* p = cast(Pool*)m_fullPools, pnext; p; p = pnext) {
				pnext = p.next;
				p.next = cast(Pool*)m_freePools;
				m_freePools = cast(Pool*)p;
			}

			// free up all pools
			for (Pool* p = cast(Pool*)m_freePools; p; p = p.next)
				p.remaining = p.data;
		}
	}

	void reset()
	{
		version(VibeManualMemoryManagement){
			freeAll();
			Pool* pnext;
			for (auto p = cast(Pool*)m_freePools; p; p = pnext) {
				pnext = p.next;
				m_baseAllocator.free(p.data);
				m_baseAllocator.free((cast(void*)p)[0 .. AllocSize!Pool]);
			}
			m_freePools = null;
		}
	}

	private static destroy(T)(void* ptr)
	{
		static if( is(T == class) ) .destroy(cast(T)ptr);
		else .destroy(*cast(T*)ptr);
	}
}

final class FreeListAlloc : Allocator
{
nothrow:
	private static struct FreeListSlot { FreeListSlot* next; }
	private {
		FreeListSlot* m_firstFree = null;
		size_t m_nalloc = 0;
		size_t m_nfree = 0;
		Allocator m_baseAlloc;
		immutable size_t m_elemSize;
	}

	this(size_t elem_size, Allocator base_allocator)
	@safe nothrow {
		assert(elem_size >= size_t.sizeof);
		m_elemSize = elem_size;
		m_baseAlloc = base_allocator;
		logDebug_("Create FreeListAlloc %d", m_elemSize);
	}

	@property size_t elementSize() const { return m_elemSize; }

	void[] alloc(size_t sz)
	{
		assert(sz == m_elemSize, "Invalid allocation size.");
		return alloc();
	}

	void[] alloc()
	{
		void[] mem;
		if( m_firstFree ){
			auto slot = m_firstFree;
			m_firstFree = slot.next;
			slot.next = null;
			mem = (cast(void*)slot)[0 .. m_elemSize];
			debug m_nfree--;
		} else {
			mem = m_baseAlloc.alloc(m_elemSize);
			//logInfo("Alloc %d bytes: alloc: %d, free: %d", SZ, s_nalloc, s_nfree);
		}
		debug m_nalloc++;
		//logInfo("Alloc %d bytes: alloc: %d, free: %d", SZ, s_nalloc, s_nfree);
		return mem;
	}

	void[] realloc(void[] mem, size_t sz)
	{
		assert(mem.length == m_elemSize);
		assert(sz == m_elemSize);
		return mem;
	}

	void free(void[] mem)
	{
		assert(mem.length == m_elemSize, "Memory block passed to free has wrong size.");
		auto s = cast(FreeListSlot*)mem.ptr;
		s.next = m_firstFree;
		m_firstFree = s;
		m_nalloc--;
		m_nfree++;
	}
}

struct FreeListObjectAlloc(T, bool USE_GC = true, bool INIT = true, EXTRA = void)
{
	enum ElemSize = AllocSize!T;
	enum ElemSlotSize = max(AllocSize!T + AllocSize!EXTRA, Slot.sizeof);

	static if( is(T == class) ){
		alias TR = T;
	} else {
		alias TR = T*;
	}

	struct Slot { Slot* next; }

	private static Slot* s_firstFree;

	static TR alloc(ARGS...)(ARGS args)
	{
		void[] mem;
		if (s_firstFree !is null) {
			auto ret = s_firstFree;
			s_firstFree = s_firstFree.next;
			ret.next = null;
			mem = (cast(void*)ret)[0 .. ElemSize];
		} else {
			//logInfo("alloc %s/%d", T.stringof, ElemSize);
			mem = manualAllocator().alloc(ElemSlotSize);
			static if( hasIndirections!T ) GC.addRange(mem.ptr, ElemSlotSize);
		}

		static if (INIT) return cast(TR)internalEmplace!(Unqual!T)(mem, args); // FIXME: this emplace has issues with qualified types, but Unqual!T may result in the wrong constructor getting called.
		else return cast(TR)mem.ptr;
	}

	static void free(TR obj)
	{
		static if (INIT) {
			scope (failure) assert(0, "You shouldn't throw in destructors");
			auto objc = obj;
			static if (is(TR == T*)) .destroy(*objc);//typeid(T).destroy(cast(void*)obj);
			else .destroy(objc);
		}

		auto sl = cast(Slot*)obj;
		sl.next = s_firstFree;
		s_firstFree = sl;
		//static if( hasIndirections!T ) GC.removeRange(cast(void*)obj);
		//manualAllocator().free((cast(void*)obj)[0 .. ElemSlotSize]);
	}
}


template AllocSize(T)
{
	static if (is(T == class)) {
		// workaround for a strange bug where AllocSize!SSLStream == 0: TODO: dustmite!
		enum dummy = T.stringof ~ __traits(classInstanceSize, T).stringof;
		enum AllocSize = __traits(classInstanceSize, T);
	} else {
		enum AllocSize = T.sizeof;
	}
}

struct FreeListRef(T, bool INIT = true)
{
	@safe:

	alias ObjAlloc = FreeListObjectAlloc!(T, true, INIT, int);
	enum ElemSize = AllocSize!T;

	static if( is(T == class) ){
		alias TR = T;
	} else {
		alias TR = T*;
	}

	private TR m_object;
	private size_t m_magic = 0x1EE75817; // workaround for compiler bug

	static FreeListRef opCall(ARGS...)(ARGS args)
	{
		//logInfo("refalloc %s/%d", T.stringof, ElemSize);
		FreeListRef ret;
		ret.m_object = () @trusted { return ObjAlloc.alloc(args); } ();
		ret.refCount = 1;
		return ret;
	}

	~this()
	{
		//if( m_object ) logInfo("~this!%s(): %d", T.stringof, this.refCount);
		//if( m_object ) logInfo("ref %s destructor %d", T.stringof, refCount);
		//else logInfo("ref %s destructor %d", T.stringof, 0);
		clear();
		m_magic = 0;
		m_object = null;
	}

	this(this)
	{
		checkInvariants();
		if( m_object ){
			//if( m_object ) logInfo("this!%s(this): %d", T.stringof, this.refCount);
			this.refCount++;
		}
	}

	void opAssign(FreeListRef other)
	{
		clear();
		m_object = other.m_object;
		if( m_object ){
			//logInfo("opAssign!%s(): %d", T.stringof, this.refCount);
			refCount++;
		}
	}

	void clear()
	{
		checkInvariants();
		if (m_object) {
			if (--this.refCount == 0)
				() @trusted { ObjAlloc.free(m_object); } ();
		}

		m_object = null;
		m_magic = 0x1EE75817;
	}

	@property const(TR) get() const { checkInvariants(); return m_object; }
	@property TR get() { checkInvariants(); return m_object; }
	alias get this;

	private @property ref int refCount()
	const @trusted {
		auto ptr = cast(ubyte*)cast(void*)m_object;
		ptr += ElemSize;
		return *cast(int*)ptr;
	}

	private void checkInvariants()
	const {
		assert(m_magic == 0x1EE75817);
		assert(!m_object || refCount > 0);
	}
}

private void* extractUnalignedPointer(void* base) nothrow
{
	ubyte misalign = *(cast(ubyte*)base-1);
	assert(misalign <= Allocator.alignment);
	return base - misalign;
}

private void* adjustPointerAlignment(void* base) nothrow
{
	ubyte misalign = Allocator.alignment - (cast(size_t)base & Allocator.alignmentMask);
	base += misalign;
	*(cast(ubyte*)base-1) = misalign;
	return base;
}

unittest {
	void test_align(void* p, size_t adjustment) {
		void* pa = adjustPointerAlignment(p);
		assert((cast(size_t)pa & Allocator.alignmentMask) == 0, "Non-aligned pointer.");
		assert(*(cast(ubyte*)pa-1) == adjustment, "Invalid adjustment "~to!string(p)~": "~to!string(*(cast(ubyte*)pa-1)));
		void* pr = extractUnalignedPointer(pa);
		assert(pr == p, "Recovered base != original");
	}
	void* ptr = .malloc(0x40);
	ptr += Allocator.alignment - (cast(size_t)ptr & Allocator.alignmentMask);
	test_align(ptr++, 0x10);
	test_align(ptr++, 0x0F);
	test_align(ptr++, 0x0E);
	test_align(ptr++, 0x0D);
	test_align(ptr++, 0x0C);
	test_align(ptr++, 0x0B);
	test_align(ptr++, 0x0A);
	test_align(ptr++, 0x09);
	test_align(ptr++, 0x08);
	test_align(ptr++, 0x07);
	test_align(ptr++, 0x06);
	test_align(ptr++, 0x05);
	test_align(ptr++, 0x04);
	test_align(ptr++, 0x03);
	test_align(ptr++, 0x02);
	test_align(ptr++, 0x01);
	test_align(ptr++, 0x10);
}

/// private
size_t alignedSize(size_t sz) nothrow
{
	return ((sz + Allocator.alignment - 1) / Allocator.alignment) * Allocator.alignment;
}

unittest {
	foreach( i; 0 .. 20 ){
		auto ia = alignedSize(i);
		assert(ia >= i);
		assert((ia & Allocator.alignmentMask) == 0);
		assert(ia < i+Allocator.alignment);
	}
}

private void ensureValidMemory(void[] mem) nothrow
{
	auto bytes = cast(ubyte[])mem;
	swap(bytes[0], bytes[$-1]);
	swap(bytes[0], bytes[$-1]);
}

/// See issue #14194
private T internalEmplace(T, Args...)(void[] chunk, auto ref Args args)
	if (is(T == class))
in {
	import std.string, std.format;
	assert(chunk.length >= T.sizeof,
		   format("emplace: Chunk size too small: %s < %s size = %s",
			  chunk.length, T.stringof, T.sizeof));
	assert((cast(size_t) chunk.ptr) % T.alignof == 0,
		   format("emplace: Misaligned memory block (0x%X): it must be %s-byte aligned for type %s", chunk.ptr, T.alignof, T.stringof));

} body {
	enum classSize = __traits(classInstanceSize, T);
	auto result = cast(T) chunk.ptr;

	// Initialize the object in its pre-ctor state
	chunk[0 .. classSize] = typeid(T).initializer[]; // Avoid deprecation warning

	// Call the ctor if any
	static if (is(typeof(result.__ctor(args))))
	{
		// T defines a genuine constructor accepting args
		// Go the classic route: write .init first, then call ctor
		result.__ctor(args);
	}
	else
	{
		static assert(args.length == 0 && !is(typeof(&T.__ctor)),
				"Don't know how to initialize an object of type "
				~ T.stringof ~ " with arguments " ~ Args.stringof);
	}
	return result;
}

/// Dittor
private auto internalEmplace(T, Args...)(void[] chunk, auto ref Args args)
	if (!is(T == class))
in {
	import std.string, std.format;
	assert(chunk.length >= T.sizeof,
		   format("emplace: Chunk size too small: %s < %s size = %s",
			  chunk.length, T.stringof, T.sizeof));
	assert((cast(size_t) chunk.ptr) % T.alignof == 0,
		   format("emplace: Misaligned memory block (0x%X): it must be %s-byte aligned for type %s", chunk.ptr, T.alignof, T.stringof));

} body {
	return emplace(cast(T*)chunk.ptr, args);
}

private void logDebug_(ARGS...)(string msg, ARGS args) {}
