/**
	Utility functions for array processing

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.array;

import vibe.utils.memory;

import std.algorithm;
import std.range : isInputRange, isOutputRange;
import std.traits;
static import std.utf;


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

enum AppenderResetMode {
	keepData,
	freeData,
	reuseData
}

struct AllocAppender(ArrayType : E[], E) {
	alias Unqual!E ElemType;

	static assert(!hasIndirections!E && !hasElaborateDestructor!E);

	private {
		ElemType[] m_data;
		ElemType[] m_remaining;
		Allocator m_alloc;
		bool m_allocatedBuffer = false;
	}

	this(Allocator alloc, ElemType[] initial_buffer = null)
	{
		m_alloc = alloc;
		m_data = initial_buffer;
		m_remaining = initial_buffer;
	}

	@disable this(this);

	@property ArrayType data() { return cast(ArrayType)m_data[0 .. m_data.length - m_remaining.length]; }

	void reset(AppenderResetMode reset_mode = AppenderResetMode.keepData)
	{
		if (reset_mode == AppenderResetMode.keepData) m_data = null;
		else if (reset_mode == AppenderResetMode.freeData) { if (m_allocatedBuffer) m_alloc.free(m_data); m_data = null; }
		m_remaining = m_data;
	}

	void reserve(size_t amt)
	{
		size_t nelems = m_data.length - m_remaining.length;
		if (!m_data.length) {
			m_data = cast(ElemType[])m_alloc.alloc(amt*E.sizeof);
			m_remaining = m_data;
			m_allocatedBuffer = true;
		}
		if (m_remaining.length < amt) {
			debug {
				import std.digest.crc;
				auto checksum = crc32Of(m_data[0 .. nelems]);
			}
			if (m_allocatedBuffer) m_data = cast(ElemType[])m_alloc.realloc(m_data, (nelems+amt)*E.sizeof);
			else {
				auto newdata = cast(ElemType[])m_alloc.alloc((nelems+amt)*E.sizeof);
				newdata[0 .. nelems] = m_data[0 .. nelems];
				m_data = newdata;
				m_allocatedBuffer = true;
			}
			debug assert(crc32Of(m_data[0 .. nelems]) == checksum);
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
		if (m_remaining.length < arr.length) grow(arr.length);
		m_remaining[0 .. arr.length] = arr[];
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

		auto min_size = m_data.length + min_free - m_remaining.length;
		auto new_size = max(m_data.length, 16);
		while( new_size < min_size )
			new_size = (new_size * 3) / 2;
		reserve(new_size - m_data.length + m_remaining.length);
	}
}

unittest {
	auto a = AllocAppender!string(defaultAllocator());
	a.put("Hello");
	a.put(' ');
	a.put("World");
	assert(a.data == "Hello World");
	a.reset();
	assert(a.data == "");
}

unittest {
	char[4] buf;
	auto a = AllocAppender!string(defaultAllocator(), buf);
	a.put("He");
	assert(a.data == "He");
	assert(a.data.ptr == buf.ptr);
	a.put("ll");
	assert(a.data == "Hell");
	assert(a.data.ptr == buf.ptr);
	a.put('o');
	assert(a.data == "Hello");
	assert(a.data.ptr != buf.ptr);
}

unittest {
	char[4] buf;
	auto a = AllocAppender!string(defaultAllocator(), buf);
	a.put("Hello");
	assert(a.data == "Hello");
	assert(a.data.ptr != buf.ptr);
}

struct FixedAppender(ArrayType : E[], size_t NELEM, E) {
	alias Unqual!E ElemType;
	private {
		ElemType[NELEM] m_data;
		size_t m_fill;
	}

	void clear()
	{
		m_fill = 0;
	}

	void put(E el)
	{
		m_data[m_fill++] = el;
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
		m_data[m_fill .. m_fill+arr.length] = (cast(ElemType[])arr)[];
		m_fill += arr.length;
	}

	@property ArrayType data() { return cast(ArrayType)m_data[0 .. m_fill]; }

	static if (!is(E == immutable)) {
		void reset() { m_fill = 0; }
	}
}


/**
	TODO: clear ring buffer fields upon removal (to run struct destructors, if T is a struct)
*/
struct FixedRingBuffer(T, size_t N = 0) {
	private {
		static if( N > 0 ) T[N] m_buffer;
		else T[] m_buffer;
		size_t m_start = 0;
		size_t m_fill = 0;
	}

	static if( N == 0 ){
		this(size_t capacity) { m_buffer = new T[capacity]; }
	}

	@property bool empty() const { return m_fill == 0; }

	@property bool full() const { return m_fill == m_buffer.length; }

	@property size_t length() const { return m_fill; }

	@property size_t freeSpace() const { return m_buffer.length - m_fill; }

	@property size_t capacity() const { return m_buffer.length; }

	static if( N == 0 ){
		@property void capacity(size_t new_size)
		{
			if( m_buffer.length ){
				auto newbuffer = new T[new_size];
				auto dst = newbuffer;
				auto newfill = min(m_fill, new_size);
				read(dst[0 .. newfill]);
				m_buffer = newbuffer;
				m_start = 0;
				m_fill = newfill;
			} else m_buffer = new T[new_size];
		}
	}
	
	@property ref inout(T) front() inout { assert(!empty); return m_buffer[m_start]; }

	@property ref inout(T) back() inout { assert(!empty); return m_buffer[mod(m_start+m_fill-1)]; }

	void clear()
	{
		popFrontN(length);
		assert(m_fill == 0);
		m_start = 0;
	}

	void put()(T itm) { assert(m_fill < m_buffer.length); m_buffer[mod(m_start + m_fill++)] = itm; }
	void put(TC : T)(TC[] itms)
	{
		if( !itms.length ) return;
		assert(m_fill+itms.length <= m_buffer.length);
		if( mod(m_start+m_fill) >= mod(m_start+m_fill+itms.length) ){
			size_t chunk1 = m_buffer.length - (m_start+m_fill);
			size_t chunk2 = itms.length - chunk1;
			m_buffer[m_start+m_fill .. m_buffer.length] = itms[0 .. chunk1];
			m_buffer[0 .. chunk2] = itms[chunk1 .. $];
		} else {
			m_buffer[mod(m_start+m_fill) .. mod(m_start+m_fill)+itms.length] = itms[];
		}
		m_fill += itms.length;
	}
	void putN(size_t n) { assert(m_fill+n <= m_buffer.length); m_fill += n; }

	void popFront() { assert(!empty); m_start = mod(m_start+1); m_fill--; }
	void popFrontN(size_t n) { assert(length >= n); m_start = mod(m_start + n); m_fill -= n; }

	void popBack() { assert(!empty); m_fill--; }
	void popBackN(size_t n) { assert(length >= n); m_fill -= n; }

	void removeAt(Range r)
	{
		assert(r.m_buffer is m_buffer);
		if( m_start + m_fill > m_buffer.length ){
			assert(r.m_start >= m_start && r.m_start < m_buffer.length || r.m_start < mod(m_start+m_fill));
			if( r.m_start > m_start ){
				foreach(i; r.m_start .. m_buffer.length-1)
					m_buffer[i] = m_buffer[i+1];
				m_buffer[$-1] = m_buffer[0];
				foreach(i; 0 .. mod(m_start + m_fill - 1))
					m_buffer[i] = m_buffer[i+1];
			} else {
				foreach(i; r.m_start .. mod(m_start + m_fill - 1))
					m_buffer[i] = m_buffer[i+1];
			}
		} else {
			assert(r.m_start >= m_start && r.m_start < m_start+m_fill);
			foreach(i; r.m_start .. m_start+m_fill-1)
				m_buffer[i] = m_buffer[i+1];
		}
		m_fill--;
		destroy(m_buffer[mod(m_start+m_fill)]); // TODO: only call destroy for non-POD T
	}

	inout(T)[] peek() inout { return m_buffer[m_start .. min(m_start+m_fill, m_buffer.length)]; }
	T[] peekDst() {
		if( m_start + m_fill < m_buffer.length ) return m_buffer[m_start+m_fill .. $];
		else return m_buffer[mod(m_start+m_fill) .. m_start];
	}

	void read(T[] dst)
	{
		assert(dst.length <= length);
		if( !dst.length ) return;
		if( mod(m_start) >= mod(m_start+dst.length) ){
			size_t chunk1 = m_buffer.length - m_start;
			size_t chunk2 = dst.length - chunk1;
			dst[0 .. chunk1] = m_buffer[m_start .. $];
			dst[chunk1 .. $] = m_buffer[0 .. chunk2];
		} else {
			dst[] = m_buffer[m_start .. m_start+dst.length];
		}
		popFrontN(dst.length);
	}

	int opApply(scope int delegate(ref T itm) del)
	{
		if( m_start+m_fill > m_buffer.length ){
			foreach(i; m_start .. m_buffer.length)
				if( auto ret = del(m_buffer[i]) )
					return ret;
			foreach(i; 0 .. mod(m_start+m_fill))
				if( auto ret = del(m_buffer[i]) )
					return ret;
		} else {
			foreach(i; m_start .. m_start+m_fill)
				if( auto ret = del(m_buffer[i]) )
					return ret;
		}
		return 0;
	}

	ref inout(T) opIndex(size_t idx) inout { assert(idx < length); return m_buffer[mod(m_start+idx)]; }

	Range opSlice() { return Range(m_buffer, m_start, m_fill); }

	Range opSlice(size_t from, size_t to)
	{
		assert(from <= to);
		assert(to <= m_fill);
		return Range(m_buffer, mod(m_start+from), to-from);
	}

	size_t opDollar(size_t dim)() const if(dim == 0) { return length; }

	private size_t mod(size_t n)
	const {
		static if( N == 0 ){
			/*static if(PotOnly){
				return x & (m_buffer.length-1);
			} else {*/
				return n % m_buffer.length;
			//}
		} else static if( ((N - 1) & N) == 0 ){
			return n & (N - 1);
		} else return n % N;
	}

	static struct Range {
		private {
			T[] m_buffer;
			size_t m_start;
			size_t m_length;
		}

		private this(T[] buffer, size_t start, size_t length)
		{
			m_buffer = buffer;
			m_start = start;
			m_length = length;
		}

		@property bool empty() const { return m_length == 0; }

		@property inout(T) front() inout { assert(!empty); return m_buffer[m_start]; }

		void popFront()
		{
			assert(!empty);
			m_start++;
			m_length--;
			if( m_start >= m_buffer.length )
				m_start = 0;
		}
	}
}

unittest {
	static assert(isInputRange!(FixedRingBuffer!int) && isOutputRange!(FixedRingBuffer!int, int));

	FixedRingBuffer!(int, 5) buf;
	assert(buf.length == 0 && buf.freeSpace == 5); buf.put(1); // |1 . . . .
	assert(buf.length == 1 && buf.freeSpace == 4); buf.put(2); // |1 2 . . .
	assert(buf.length == 2 && buf.freeSpace == 3); buf.put(3); // |1 2 3 . .
	assert(buf.length == 3 && buf.freeSpace == 2); buf.put(4); // |1 2 3 4 .
	assert(buf.length == 4 && buf.freeSpace == 1); buf.put(5); // |1 2 3 4 5
	assert(buf.length == 5 && buf.freeSpace == 0);
	assert(buf.front == 1);
	buf.popFront(); // .|2 3 4 5
	assert(buf.front == 2);
	buf.popFrontN(2); // . . .|4 5
	assert(buf.front == 4);
	assert(buf.length == 2 && buf.freeSpace == 3);
	buf.put([6, 7, 8]); // 6 7 8|4 5
	assert(buf.length == 5 && buf.freeSpace == 0);
	int[5] dst;
	buf.read(dst); // . . .|. .
	assert(dst == [4, 5, 6, 7, 8]);
	assert(buf.length == 0 && buf.freeSpace == 5);
	buf.put([1, 2]); // . . .|1 2
	assert(buf.length == 2 && buf.freeSpace == 3);
	buf.read(dst[0 .. 2]); //|. . . . .
	assert(dst[0 .. 2] == [1, 2]);
}


struct ArraySet(Key)
{
	private {
		Key[4] m_staticEntries;
		Key[] m_entries;
	}

	@property ArraySet dup()
	{
		return ArraySet(m_staticEntries, m_entries.dup);
	}

	bool opBinaryRight(string op)(Key key) if (op == "in") { return contains(key); }

	int opApply(int delegate(ref Key) del)
	{
		foreach (ref k; m_staticEntries)
			if (k != Key.init)
				if (auto ret = del(k))
					return ret;
		foreach (ref k; m_entries)
			if (k != Key.init)
				if (auto ret = del(k))
					return ret;
		return 0;
	}

	bool contains(Key key)
	const {
		foreach (ref k; m_staticEntries) if (k == key) return true;
		foreach (ref k; m_entries) if (k == key) return true;
		return false;
	}

	void insert(Key key)
	{
		if (contains(key)) return;
		foreach (ref k; m_staticEntries)
			if (k == Key.init) {
				k = key;
				return;
			}
		foreach (ref k; m_entries)
			if (k == Key.init) {
				k = key;
				return;
			}
		m_entries ~= key;
	}

	void remove(Key key)
	{
		foreach (ref k; m_staticEntries) if (k == key) { k = Key.init; return; }
		foreach (ref k; m_entries) if (k == key) { k = Key.init; return; }
	}
}
