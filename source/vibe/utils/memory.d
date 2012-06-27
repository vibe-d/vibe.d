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

struct FreeListRef(T, bool INIT = true)
{
	static if( is(T == class) ){
		alias T TR;
		enum InstSize = __traits(classInstanceSize, T);
	} else {
		alias T* TR;
		enum InstSize = T.sizeof;
	}

	private {
		static struct Slot { Slot* next; }
		static Slot* s_firstFree;
		static size_t s_count = 0;
		static size_t s_freeCount = 0;
	}

	private TR m_object;
	private size_t m_magic = 0x1EE75817; // workaround for compiler bug

	static FreeListRef opCall(ARGS...)(ARGS args)
	{
		size_t size;
		static if( is(T == class) ){
			assert(InstSize >= Slot.sizeof, "Class type "~T.stringof~" must be at least as big as a pointer!");
			size = InstSize;
		} else size = T.sizeof;

		void* ptr;
		if( s_firstFree ){
			auto obj = s_firstFree;
			s_firstFree = obj.next;
			ptr = cast(void*)obj;
			s_freeCount--;
		} else {
			ptr = GC.malloc(size + int.sizeof);
			s_count++;
			//logInfo("Count of %s: %d/%d", T.stringof, s_count - s_freeCount, s_count);
		}

		FreeListRef ret;
		static if( INIT ) ret.m_object = emplace!T(ptr[0 .. size], args);	
		else ret.m_object = cast(TR)ptr;
		ret.refCount = 1;
		return ret;
	}

	~this()
	{
		//if( m_object ) logInfo("~this!%s(): %d", T.stringof, this.refCount);
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
					static if( INIT )
						typeid(T).destroy(cast(void*)m_object);
					auto slot = cast(Slot*)cast(void*)m_object;
					slot.next = s_firstFree;
					s_firstFree = slot;
					s_freeCount++;
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
		ptr += InstSize;
		return *cast(int*)ptr;
	}
}

