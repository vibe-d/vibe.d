/**
	Utility functions for memory management

	Note that this module currently is a big sand box for testing allocation related stuff.
	Nothing here, including the interfaces, is final but rather a lot of experimentation.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.internal.freelistref;

import vibe.internal.allocator;
import vibe.internal.meta.traits : synchronizedIsNothrow;

import core.exception : OutOfMemoryError;
import core.stdc.stdlib;
import core.memory;
import std.conv;
import std.exception : enforceEx;
import std.traits;
import std.algorithm;


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
			mem = () @trusted { return (cast(void*)ret)[0 .. ElemSlotSize]; } ();
		} else {
			//logInfo("alloc %s/%d", T.stringof, ElemSize);
			mem = Mallocator.instance.allocate(ElemSlotSize);
			static if(hasIndirections!T) () @trusted { GC.addRange(mem.ptr, ElemSlotSize); } ();
		}

		// FIXME: this emplace has issues with qualified types, but Unqual!T may result in the wrong constructor getting called.
		static if (INIT) internalEmplace!(Unqual!T)(mem[0 .. ElemSize], args);

		return () @trusted { return cast(TR)mem.ptr; } ();
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
		//Mallocator.instance.deallocate((cast(void*)obj)[0 .. ElemSlotSize]);
	}
}

@safe unittest {
	struct S {}
	FreeListObjectAlloc!S.alloc();
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
		FreeListRef ret;
		ret.m_object = ObjAlloc.alloc!ARGS(args);
		ret.refCount = 1;
		//logInfo("refalloc %s/%d", T.stringof, ElemSize);
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

	static if (is(T == class)) {
		@property inout(T) get() inout @safe nothrow { return m_object; }
	} else {
		@property ref inout(T) get() inout @safe nothrow { return *m_object; }
		void opAssign(T t) { *m_object = t; }
	}
	alias get this;

	private @property ref int refCount()
	const @trusted {
		assert(m_object !is null);
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


/// See issue #14194
private T internalEmplace(T, Args...)(void[] chunk, auto ref Args args)
	if (is(T == class))
in {
	import std.string, std.format;
	assert(chunk.length >= T.sizeof,
		   format("emplace: Chunk size too small: %s < %s size = %s",
			  chunk.length, T.stringof, T.sizeof));
	assert((cast(size_t) chunk.ptr) % T.alignof == 0,
		   format("emplace: Misaligned memory block (0x%X): it must be %s-byte aligned for type %s", &chunk[0], T.alignof, T.stringof));

} body {
	enum classSize = __traits(classInstanceSize, T);
	auto result = () @trusted { return cast(T) chunk.ptr; } ();

	// Initialize the object in its pre-ctor state
	() @trusted {
		chunk[0 .. classSize] = typeid(T).initializer[]; // Avoid deprecation warning
	} ();

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
@safe	if (!is(T == class))
in {
	import std.string, std.format;
	assert(chunk.length >= T.sizeof,
		   format("emplace: Chunk size too small: %s < %s size = %s",
			  chunk.length, T.stringof, T.sizeof));
	assert((cast(size_t) chunk.ptr) % T.alignof == 0,
		   format("emplace: Misaligned memory block (0x%X): it must be %s-byte aligned for type %s", &chunk[0], T.alignof, T.stringof));

} body {
	return emplace(() @trusted { return cast(T*)chunk.ptr; } (), args);
}

private void logDebug_(ARGS...)(string msg, ARGS args) {}
