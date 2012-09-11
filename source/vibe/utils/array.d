/**
	Utiltiy functions for array processing

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.array;

import vibe.utils.memory;

import std.algorithm;
import std.traits;


void removeFromArray(T)(ref T[] array, T item)
{
	foreach( i; 0 .. array.length )
		if( array[i] is item ){
			removeFromArrayIdx(array, i);
			return;
		}
}

void removeFromArrayIdx(T)(ref T[] array, size_t idx)
{
	foreach( j; idx+1 .. array.length)
		array[j-1] = array[j];
	array.length = array.length-1;
}

struct AllocAppender(ArrayType : E[], E) {
	alias Unqual!E ElemType;
	private {
		ElemType[] m_data;
		ElemType[] m_remaining;
		Allocator m_alloc;
	}

	this(Allocator alloc)
	{
		m_alloc = alloc;
	}

	@disable this(this);

	void reserve(size_t amt)
	{
		size_t nelems = m_data.length - m_remaining.length;
		if( !m_data.length ){
			m_data = cast(ElemType[])m_alloc.alloc(amt*E.sizeof);
		}
		if( m_remaining.length < amt ){
			size_t n = m_data.length - m_remaining.length;
			m_data = cast(ElemType[])m_alloc.realloc(m_data, (n+amt)*E.sizeof);
		}
		m_remaining = m_data[nelems .. m_data.length];
	}

	void put(E el)
	{
		if( m_remaining.length == 0 ) grow(1);
		m_remaining[0] = el;
		m_remaining = m_remaining[1 .. $];
	}

	void put(ArrayType arr)
	{
		if( m_remaining.length < arr.length ) grow(arr.length);
		m_remaining[0 .. arr.length] = arr;
		m_remaining = m_remaining[arr.length .. $];
	}

	static if( !hasAliasing!E ){
		void put(in ElemType[] arr){
			put(cast(ArrayType)arr);
		}
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

	@property ArrayType data() { return cast(ArrayType)m_data[0 .. m_data.length - m_remaining.length]; }

	void grow(size_t min_free)
	{
		if( !m_data.length && min_free < 16 ) min_free = 16;

		auto min_size = m_data.length + min_free;
		auto new_size = max(m_data.length, 16);
		while( new_size < min_size )
			new_size = (new_size * 3) / 2;
		reserve(new_size - m_data.length);
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

	void put(E el)
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

