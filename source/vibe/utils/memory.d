/**
	Utiltiy functions for memory management

	Note that this module currently is a big sand box for testing allocation related stuff.
	Nothing here, including the interfaces, is final but rather a lot of experimentation.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.memory;

import vibe.core.log;

import core.stdc.stdlib;
import core.memory;
import std.conv;
import std.traits;
import std.algorithm;

Allocator defaultAllocator()
{
	version(VibeManualMemoryManagement){
		return manualAllocator();
	} else {
		static Allocator alloc;
		if( !alloc ){
			alloc = new GCAllocator;
			alloc = new AutoFreeListAllocator(alloc);
			//alloc = new DebugAllocator(alloc);
		}
		return alloc;
	}
}

Allocator manualAllocator()
{
	static Allocator alloc;
	if( !alloc ){
		alloc = new MallocAllocator;
		alloc = new AutoFreeListAllocator(alloc);
		//alloc = new DebugAllocator(alloc);
	}
	return alloc;
}

auto allocObject(T, bool MANAGED = true, ARGS...)(Allocator allocator, ARGS args)
{
	auto mem = allocator.alloc(AllocSize!T);
	static if( MANAGED ){
		static if( hasIndirections!T ) 
			GC.addRange(mem.ptr, mem.length);
		auto ret = emplace!T(mem, args);
		Destructor des;
		des.next = m_destructors;
		des.destructor = &destroy!T;
		des.object = mem.ptr;
		m_destructors = des;
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
		foreach( ref el; ret ){
			emplace(cast(void*)&el);
			Destructor des;
			des.next = m_destructors;
			des.destructor = &destroy!T;
			des.object = &el;
			m_destructors = des;
		}
	}
	return ret;
}


interface Allocator {
	void[] alloc(size_t sz);
	void[] realloc(void[] mem, size_t new_sz);
	void free(void[] mem);
}

class DebugAllocator : Allocator {
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

class MallocAllocator : Allocator {
	void[] alloc(size_t sz) { return .malloc(sz)[0 .. sz]; }
	void[] realloc(void[] mem, size_t new_size) { return .realloc(mem.ptr, new_size)[0 .. new_size]; }
	void free(void[] mem) { .free(mem.ptr); }
}

class GCAllocator : Allocator {
	void[] alloc(size_t sz) { return GC.malloc(sz)[0 .. sz]; }
	void[] realloc(void[] mem, size_t new_size) { return GC.realloc(mem.ptr, new_size)[0 .. new_size]; }
	void free(void[] mem) { GC.free(mem.ptr); }
}

class AutoFreeListAllocator : Allocator {
	private {
		FreeListAlloc[] m_freeLists;
		Allocator m_baseAlloc;
	}

	this(Allocator base_allocator)
	{
		m_baseAlloc = base_allocator;
		foreach( i; 3 .. 12 )
			m_freeLists ~= new FreeListAlloc(1<<i, m_baseAlloc);
		m_freeLists ~= new FreeListAlloc(65540, m_baseAlloc);
	}

	void[] alloc(size_t sz)
	{
		void[] ret;
		foreach( fl; m_freeLists )
			if( sz <= fl.elementSize ){
				ret = fl.alloc(fl.elementSize)[0 .. sz];
				break;
			}
		if( !ret ) ret = m_baseAlloc.alloc(sz);
		//logTrace("AFL alloc %08X(%d)", ret.ptr, sz);
		return ret;
	}

	void[] realloc(void[] data, size_t sz)
	{
		// TODO: optimize!
		//logTrace("AFL realloc");
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
		foreach( fl; m_freeLists )
			if( data.length <= fl.elementSize ){
				fl.free(data.ptr[0 .. fl.elementSize]);
				return;
			}
		return m_baseAlloc.free(data);
	}
}

class PoolAllocator : Allocator {
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

	void[] alloc(size_t sz)
	{
		Pool* pprev = null;
		Pool* p = m_freePools;
		while( p && p.remaining.length < sz ){
			pprev = p;
			p = p.next;
		}

		if( !p ){
			auto pmem = m_baseAllocator.alloc(AllocSize!Pool);

			p = emplace!Pool(pmem);
			p.data = m_baseAllocator.alloc(sz <= m_poolSize ? m_poolSize : sz);
			p.remaining = p.data;
			p.next = m_freePools;
			m_freePools = p;
			pprev = null;
		}

		auto ret = p.remaining[0 .. sz];
		p.remaining = p.remaining[sz .. $];
		if( !p.remaining.length ){
			if( pprev ){
				pprev.next = p.next;
			} else {
				m_freePools = p.next;
			}
			p.next = m_fullPools;
			m_fullPools = p;
		}

		return ret;
	}

	void[] realloc(void[] arr, size_t newsize)
	{
		bool last_in_pool = m_freePools && arr.ptr+arr.length == m_freePools.remaining.ptr;
		if( last_in_pool && m_freePools.remaining.length+arr.length >= newsize ){
			m_freePools.remaining = arr.ptr[newsize .. m_freePools.remaining.length+arr.length-newsize];
			arr = arr.ptr[0 .. newsize];
			return arr;
		} else {
			auto ret = alloc(newsize);
			assert(ret.ptr >= arr.ptr+arr.length, "New block overlaps old one!?");
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
			for( auto d = m_destructors; d; d = d.next )
				d.destructor(d.object);
			m_destructors = null;

			// put all full Pools into the free pools list
			for( Pool* p = m_fullPools, pnext; p; p = pnext ){
				pnext = p.next;
				p.next = m_freePools;
				m_freePools = p;
			}

			// free up all pools
			for( Pool* p = m_freePools; p; p = p.next )
				p.remaining = p.data;
		}
	}

	void reset()
	{
		version(VibeManualMemoryManagement){
			freeAll();
			Pool* pnext;
			for( auto p = m_freePools; p; p = pnext ){
				pnext = p.next;
				m_baseAllocator.free(p.data);
				m_baseAllocator.free((cast(void*)p)[0 .. AllocSize!Pool]);
			}
			m_freePools = null;
		}
	}

	private static destroy(T)(void* ptr)
	{
		static if( is(T == class) ) .clear(cast(T)ptr);
		else .clear(*cast(T*)ptr);
	}
}

class FreeListAlloc : Allocator
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
			.clear(objc);//typeid(T).destroy(cast(void*)obj);
		}
		static if( hasIndirections!T ) GC.removeRange(cast(void*)obj);
		manualAllocator().free((cast(void*)obj)[0 .. ElemSize]);
	}
}

template AllocSize(T)
{
	static if( is(T == class) ) enum AllocSize = __traits(classInstanceSize, T);
	else enum AllocSize = T.sizeof;
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
		static if( INIT ) ret.m_object = emplace!T(mem, args);	
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
		if( m_magic == 0x1EE75817 ){
			if( m_object ){
				//if( m_object ) logInfo("this!%s(this): %d", T.stringof, this.refCount);
				this.refCount++;
			}
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
		if( m_magic == 0x1EE75817 ){
			if( m_object ){
				assert(this.refCount > 0);
				if( --this.refCount == 0 ){
					static if( INIT ){
						//logInfo("ref %s destroy", T.stringof);
						//typeid(T).destroy(cast(void*)m_object);
						auto objc = m_object;
						.clear(objc);
						//logInfo("ref %s destroyed", T.stringof);
					}
					static if( hasIndirections!T ) GC.removeRange(cast(void*)m_object);
					manualAllocator().free((cast(void*)m_object)[0 .. ElemSize+int.sizeof]);
				}
			}
		}

		m_object = null;
		m_magic = 0x1EE75817;
	}

	@property const(TR) get() const { return m_object; }
	@property TR get() { return m_object; }
	alias get this;

	private @property ref int refCount()
	{
		auto ptr = cast(ubyte*)cast(void*)m_object;
		ptr += ElemSize;
		return *cast(int*)ptr;
	}
}

