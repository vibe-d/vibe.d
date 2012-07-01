/**
	Utiltiy functions for memory management

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

struct PoolAllocator {
	static struct Pool { Pool* next; void[] data; void[] remaining; }
	static struct Destructor { Destructor* next; void function(void*) destructor; void* object; }
	private {
		Pool* m_freePools;
		Pool* m_fullPools;
		Destructor* m_destructors;
		size_t m_poolSize;
	}

	this(size_t pool_size)
	{
		m_poolSize = pool_size;
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
			p = new Pool;
			p.data = new void[sz <= m_poolSize ? m_poolSize : sz];
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

	auto allocObject(T, bool INIT = true, ARGS...)(ARGS args)
	{
		auto mem = alloc(AllocSize!T);
		static if( INIT ){
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

	T[] allocArray(T, bool INIT = true)(size_t n)
	{
		auto ret = cast(T[])alloc(T.sizeof * n);
		static if( INIT ){
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

	void freeAll()
	{
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

	private static destroy(T)(void* ptr)
	{
		static if( is(T == class) ) .clear(cast(T)ptr);
		else .clear(*cast(T*)ptr);
	}
}

class FixedAppender(ArrayType : E[], size_t NELEM, E) {
	alias Unqual!E ElemType;
	private {
		ElemType[NELEM] m_data;
		ElemType[] m_remaining;
	}

	this()
	{
		m_remaining = m_data;
	}

	void put(ElemType el)
	{
		m_remaining[0] = el;
		m_remaining = m_remaining[1 .. $];
	}

	static if( is(ElemType == char) ){
		void put(dchar el)
		{
			if( el < 128 ) put(cast(char)el);
			else {
				char[4] buf;
				auto len = std.utf.encode(buf, el);
				put(cast(ArrayType)buf[0 .. len]);
			}
		}
	}

	static if( is(ElemType == wchar) ){
		void put(dchar el)
		{
			if( el < 128 ) put(cast(wchar)el);
			else {
				wchar[3] buf;
				auto len = std.utf.encode(buf, el);
				put(cast(ArrayType)buf[0 .. len]);
			}
		}
	}

	void put(ArrayType arr)
	{
		m_remaining[0 .. arr.length] = cast(ElemType[])arr;
		m_remaining = m_remaining[arr.length .. $];
	}

	@property ArrayType data() { return cast(ArrayType)m_data[0 .. $-m_remaining.length]; }
}

template FreeListAlloc(size_t SZ, bool USE_GC = true)
{
	private struct FreeListSlot { FreeListSlot* next; }
	static assert(SZ >= size_t.sizeof);
	static FreeListSlot* s_firstFree = null;
	size_t s_nalloc = 0;
	size_t s_nfree = 0;

	void* alloc()
	{
		void* ptr;
		if( s_firstFree ){
			auto slot = s_firstFree;
			s_firstFree = slot.next;
			slot.next = null;
			ptr = cast(void*)slot;
			s_nfree--;
		} else {
			static if( USE_GC ) ptr = GC.malloc(SZ);
			else ptr = malloc(SZ);
		}
		s_nalloc++;
		//logInfo("Alloc %d bytes: alloc: %d, free: %d", SZ, s_nalloc, s_nfree);
		return ptr;
	}

	void free(void* mem)
	{
		auto s = cast(FreeListSlot*)mem;
		s.next = s_firstFree;
		s_firstFree = s;
		s_nalloc--;
		s_nfree++;
	}
}

template FreeListObjectAlloc(T, bool USE_GC = true, bool INIT = true)
{
	enum ElemSize = AllocSize!T;
	alias FreeListAlloc!(ElemSize, USE_GC) Alloc;

	static if( is(T == class) ){
		alias T TR;
	} else {
		alias T* TR;
	}

	TR alloc(ARGS...)(ARGS args)
	{
		//logInfo("alloc %s/%d", T.stringof, ElemSize);
		auto ptr = Alloc.alloc();
		static if( hasIndirections!T ) GC.addRange(ptr, ElemSize);
		static if( INIT ) return emplace!T(ptr[0 .. ElemSize], args);
		else return cast(TR)ptr;
	}

	void free(TR obj)
	{
		static if( INIT ){
			auto objc = obj;
			.clear(objc);//typeid(T).destroy(cast(void*)obj);
		}
		static if( hasIndirections!T ) GC.removeRange(cast(void*)obj);
		Alloc.free(cast(void*)obj);
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
	alias FreeListAlloc!(ElemSize + int.sizeof) Alloc;

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
		void* ptr = Alloc.alloc();

		FreeListRef ret;
		static if( INIT ) ret.m_object = emplace!T(ptr[0 .. ElemSize], args);	
		else ret.m_object = cast(TR)ptr;
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
					Alloc.free(cast(void*)m_object);
				}
			}
		}

		m_object = null;
		m_magic = 0x1EE75817;
	}

	@property inout(TR) get() inout { return m_object; }
	alias get this;

	private @property ref int refCount()
	{
		auto ptr = cast(ubyte*)cast(void*)m_object;
		ptr += ElemSize;
		return *cast(int*)ptr;
	}
}

