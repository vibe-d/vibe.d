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

	@property ArrayType data() { return cast(ArrayType)m_data[0 .. m_data.length - m_remaining.length]; }

	void reset()
	{
		m_remaining = m_data;
	}

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

struct FixedRingBuffer(T, size_t N) {
	private {
		T[N] m_buffer;
		size_t m_start = 0;
		size_t m_fill = 0;
	}

	@property bool empty() const { return m_fill == 0; }

	@property size_t length() const { return m_fill; }

	@property size_t freeSpace() const { return N - m_fill; }
	
	void put(T itm) { assert(m_fill < N); m_buffer[(m_start + m_fill++) % N] = itm; }
	void put(T[] itms)
	{
		if( !itms.length ) return;
		assert(m_fill+itms.length <= N);
		if( (m_start+m_fill)%N >= (m_start+m_fill+itms.length)%N ){
			size_t chunk1 = N - (m_start+m_fill);
			size_t chunk2 = itms.length - chunk1;
			m_buffer[m_start+m_fill .. N] = itms[0 .. chunk1];
			m_buffer[0 .. chunk2] = itms[chunk1 .. $];
		} else {
			m_buffer[m_start+m_fill .. m_start+m_fill+itms.length] = itms;
		}
		m_fill += itms.length;
	}
	void putN(size_t n) { assert(m_fill+n <= N); m_fill += n; }

	@property ref inout(T) front() inout { assert(!empty); return m_buffer[m_start]; }

	void popFront() { assert(!empty); m_start = (m_start+1) % N; m_fill--; }
	void popFrontN(size_t n) { assert(length >= n); m_start = (m_start + n) % N; m_fill -= n; }

	inout(T)[] peek() inout { return m_buffer[m_start .. min(m_start+m_fill, N)]; }
	T[] peekDst() {
		if( m_start + m_fill < N ) return m_buffer[m_start+m_fill .. $];
		else return m_buffer[(m_start+m_fill)%N .. m_start];
	}

	void read(T[] dst)
	{
		assert(dst.length <= length);
		if( m_start%N >= (m_start+dst.length)%N ){
			size_t chunk1 = N - m_start;
			size_t chunk2 = dst.length - chunk1;
			dst[0 .. chunk1] = m_buffer[m_start .. $];
			dst[chunk1 .. $] = m_buffer[0 .. chunk2];
		} else {
			dst[] = m_buffer[m_start .. m_start+dst.length];
		}
		popFrontN(dst.length);
	}
}
