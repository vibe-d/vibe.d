/**
	Utility functions for memory management

	Note that this module currently is a big sand box for testing allocation related stuff.
	Nothing here, including the interfaces, is final but rather a lot of experimentation.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.memory;

import vibe.core.log;

import core.exception : OutOfMemoryError;
import core.stdc.stdlib;
import core.memory;
import std.conv;
import std.exception : enforceEx;
import std.traits;
import std.algorithm;


Allocator defaultAllocator()
{
	version(VibeManualMemoryManagement){
		return manualAllocator();
	} else {
		static __gshared Allocator alloc;
		if( !alloc ){
			alloc = new GCAllocator;
			//alloc = new AutoFreeListAllocator(alloc);
			//alloc = new DebugAllocator(alloc);
			alloc = new LockAllocator(alloc);
		}
		return alloc;
	}
}

Allocator manualAllocator()
{
	static __gshared Allocator alloc;
	if( !alloc ){
		alloc = new MallocAllocator;
		alloc = new AutoFreeListAllocator(alloc);
		//alloc = new DebugAllocator(alloc);
		alloc = new LockAllocator(alloc);
	}
	return alloc;
}

auto allocObject(T, bool MANAGED = true, ARGS...)(Allocator allocator, ARGS args)
{
	auto mem = allocator.alloc(AllocSize!T);
	static if( MANAGED ){
		static if( hasIndirections!T ) 
			GC.addRange(mem.ptr, mem.length);
		return emplace!T(mem, args);
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
			emplace!T(cast(void[])((&el)[0 .. 1]));
		}
	}
	return ret;
}

void freeArray(T, bool MANAGED = true)(Allocator allocator, ref T[] array)
{
	static if (MANAGED && hasIndirections!T)
		GC.removeRange(array.ptr);
	allocator.free(cast(void[])array);
	array = null;
}


interface Allocator {
	enum size_t alignment = 0x10;
	enum size_t alignmentMask = alignment-1;

	void[] alloc(size_t sz)
		out { assert((cast(size_t)__result.ptr & alignmentMask) == 0, "alloc() returned misaligned data."); }
	
	void[] realloc(void[] mem, size_t new_sz)
		in { assert((cast(size_t)mem.ptr & alignmentMask) == 0, "misaligned pointer passed to realloc()."); }
		out { assert((cast(size_t)__result.ptr & alignmentMask) == 0, "realloc() returned misaligned data."); }

	void free(void[] mem)
		in { assert((cast(size_t)mem.ptr & alignmentMask) == 0, "misaligned pointer passed to free()."); }
}


/**
	Simple proxy allocator protecting its base allocator with a mutex.
*/
class LockAllocator : Allocator {
	private {
		Allocator m_base;
	}
	this(Allocator base) { m_base = base; }
	void[] alloc(size_t sz) { synchronized(this) return m_base.alloc(sz); }
	void[] realloc(void[] mem, size_t new_sz) { synchronized(this) return m_base.realloc(mem, new_sz); }
	void free(void[] mem) { synchronized(this) m_base.free(mem); }
}

final class DebugAllocator : Allocator {
	private {
		Allocator m_baseAlloc;
		size_t[void*] m_blocks;
		size_t m_bytes;
		size_t m_maxBytes;
	}

	this(Allocator base_allocator)
	{
		m_baseAlloc = base_allocator;
	}

	@property size_t allocatedBlockCount() const { return m_blocks.length; }
	@property size_t bytesAllocated() const { return m_bytes; }
	@property size_t maxBytesAllocated() const { return m_maxBytes; }

	void[] alloc(size_t sz)
	{
		auto ret = m_baseAlloc.alloc(sz);
		assert(ret.length == sz, "base.alloc() returned block with wrong size.");
		assert(ret !in m_blocks, "base.alloc() returned block that is already allocated.");
		m_blocks[ret.ptr] = sz;
		m_bytes += sz;
		if( m_bytes > m_maxBytes ){
			m_maxBytes = m_bytes;
			logDebug("New allocation maximum: %d (%d blocks)", m_maxBytes, m_blocks.length);
		}
		return ret;
	}

	void[] realloc(void[] mem, size_t new_size)
	{
		auto pb = mem.ptr in m_blocks;
		assert(pb, "realloc() called with non-allocated pointer.");
		assert(*pb == mem.length, "realloc() called with block of wrong size.");
		auto ret = m_baseAlloc.realloc(mem, new_size);
		assert(ret.length == new_size, "base.realloc() returned block with wrong size.");
		assert(ret.ptr !in m_blocks, "base.realloc() returned block that is already allocated.");
		m_bytes -= *pb;
		m_blocks.remove(mem.ptr);
		m_blocks[ret.ptr] = new_size;
		m_bytes += new_size;
		return ret;
	}
	void free(void[] mem)
	{
		auto pb = mem.ptr in m_blocks;
		assert(pb, "free() called with non-allocated object.");
		assert(*pb == mem.length, "free() called with block of wrong size.");
		m_baseAlloc.free(mem);
		m_bytes -= *pb;
		m_blocks.remove(mem.ptr);
	}
}

final class MallocAllocator : Allocator {
	void[] alloc(size_t sz)
	{
		auto ptr = .malloc(sz + Allocator.alignment);
		enforceEx!OutOfMemoryError(ptr !is null);
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
	version (GNU) import std.typetuple;

	private {
		enum minExponent = 5;
		enum freeListCount = 14;
		FreeListAlloc[freeListCount] m_freeLists;
		Allocator m_baseAlloc;
	}

	this(Allocator base_allocator)
	{
		m_baseAlloc = base_allocator;
		foreach (i; iotaTuple!freeListCount)
			m_freeLists[i] = new FreeListAlloc(nthFreeListSize!(i), m_baseAlloc);
	}

	void[] alloc(size_t sz)
	{
		if (sz > nthFreeListSize!(freeListCount-1)) return m_baseAlloc.alloc(sz);
		foreach (i; iotaTuple!freeListCount)
			if (sz <= nthFreeListSize!(i))
				return m_freeLists[i].alloc().ptr[0 .. sz];
		//logTrace("AFL alloc %08X(%d)", ret.ptr, sz);
		assert(false);
	}

	void[] realloc(void[] data, size_t sz)
	{
		foreach (fl; m_freeLists)
			if (data.length <= fl.elementSize) {
				// just grow the slice if it still fits into the free list slot
				if (sz <= fl.elementSize)
					return data.ptr[0 .. sz];

				// otherwise re-allocate
				auto newd = alloc(sz);
				assert(newd.ptr+sz <= data.ptr || newd.ptr >= data.ptr+data.length, "New block overlaps old one!?");
				auto len = min(data.length, sz);
				newd[0 .. len] = data[0 .. len];
				free(data);
				return newd;
			}

		// forward large blocks to the base allocator
		return m_baseAlloc.realloc(data, sz);
	}

	void free(void[] data)
	{
		//logTrace("AFL free %08X(%s)", data.ptr, data.length);
		if (data.length > nthFreeListSize!(freeListCount-1)) {
			m_baseAlloc.free(data);
			return;
		}
		foreach(i; iotaTuple!freeListCount)
			if (data.length <= nthFreeListSize!i) {
				m_freeLists[i].free(data.ptr[0 .. nthFreeListSize!i]);
				return;
			}
		assert(false);
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

	this(size_t pool_size, Allocator base)
	{
		m_poolSize = pool_size;
		m_baseAllocator = base;
	}

	@property size_t totalSize()
	{
		size_t amt = 0;
		for (auto p = m_fullPools; p; p = p.next)
			amt += p.data.length;
		for (auto p = m_freePools; p; p = p.next)
			amt += p.data.length;
		return amt;
	}

	@property size_t allocatedSize()
	{
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

			p = emplace!Pool(pmem);
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
	private static struct FreeListSlot { FreeListSlot* next; }
	private {
		immutable size_t m_elemSize;
		Allocator m_baseAlloc;
		FreeListSlot* m_firstFree = null;
		size_t m_nalloc = 0;
		size_t m_nfree = 0;
	}

	this(size_t elem_size, Allocator base_allocator)
	{
		assert(elem_size >= size_t.sizeof);
		m_elemSize = elem_size;
		m_baseAlloc = base_allocator;
		logDebug("Create FreeListAlloc %d", m_elemSize);
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
			m_nfree--;
		} else {
			mem = m_baseAlloc.alloc(m_elemSize);
			//logInfo("Alloc %d bytes: alloc: %d, free: %d", SZ, s_nalloc, s_nfree);
		}
		m_nalloc++;
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

template FreeListObjectAlloc(T, bool USE_GC = true, bool INIT = true)
{
	enum ElemSize = AllocSize!T;

	static if( is(T == class) ){
		alias T TR;
	} else {
		alias T* TR;
	}

	TR alloc(ARGS...)(ARGS args)
	{
		//logInfo("alloc %s/%d", T.stringof, ElemSize);
		auto mem = manualAllocator().alloc(ElemSize);
		static if( hasIndirections!T ) GC.addRange(mem.ptr, ElemSize);
		static if( INIT ) return emplace!T(mem, args);
		else return cast(TR)mem.ptr;
	}

	void free(TR obj)
	{
		static if( INIT ){
			auto objc = obj;
			.destroy(objc);//typeid(T).destroy(cast(void*)obj);
		}
		static if( hasIndirections!T ) GC.removeRange(cast(void*)obj);
		manualAllocator().free((cast(void*)obj)[0 .. ElemSize]);
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
	enum ElemSize = AllocSize!T;

	static if( is(T == class) ){
		alias T TR;
	} else {
		alias T* TR;
	}

	private TR m_object;
	private size_t m_magic = 0x1EE75817; // workaround for compiler bug

	static FreeListRef opCall(ARGS...)(ARGS args)
	{
		//logInfo("refalloc %s/%d", T.stringof, ElemSize);
		FreeListRef ret;
		auto mem = manualAllocator().alloc(ElemSize + int.sizeof);
		static if( hasIndirections!T ) GC.addRange(mem.ptr, ElemSize);
		static if( INIT ) ret.m_object = cast(TR)emplace!(Unqual!T)(mem, args);	
		else ret.m_object = cast(TR)mem.ptr;
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
		if( m_object ){
			if( --this.refCount == 0 ){
				static if( INIT ){
					//logInfo("ref %s destroy", T.stringof);
					//typeid(T).destroy(cast(void*)m_object);
					auto objc = m_object;
					.destroy(objc);
					//logInfo("ref %s destroyed", T.stringof);
				}
				static if( hasIndirections!T ) GC.removeRange(cast(void*)m_object);
				manualAllocator().free((cast(void*)m_object)[0 .. ElemSize+int.sizeof]);
			}
		}

		m_object = null;
		m_magic = 0x1EE75817;
	}

	@property const(TR) get() const { checkInvariants(); return m_object; }
	@property TR get() { checkInvariants(); return m_object; }
	alias get this;

	private @property ref int refCount()
	const {
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

private void* extractUnalignedPointer(void* base)
{
	ubyte misalign = *(cast(ubyte*)base-1);
	assert(misalign <= Allocator.alignment);
	return base - misalign;
}

private void* adjustPointerAlignment(void* base)
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

private size_t alignedSize(size_t sz)
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

private void ensureValidMemory(void[] mem)
{
	auto bytes = cast(ubyte[])mem;
	swap(bytes[0], bytes[$-1]);
	swap(bytes[0], bytes[$-1]);
}
