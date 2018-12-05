/**
	Utility functions for array processing

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.array;

import vibe.internal.utilallocator;

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
	alias ElemType = Unqual!E;

	static assert(!hasIndirections!E && !hasElaborateDestructor!E);

	private {
		ElemType[] m_data;
		ElemType[] m_remaining;
		IAllocator m_alloc;
		bool m_allocatedBuffer = false;
	}

	this(IAllocator alloc, ElemType[] initial_buffer = null)
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
		else if (reset_mode == AppenderResetMode.freeData) { if (m_allocatedBuffer) m_alloc.deallocate(m_data); m_data = null; }
		m_remaining = m_data;
	}

	/** Grows the capacity of the internal buffer so that it can hold a minumum amount of elements.

		Params:
			amount = The minimum amount of elements that shall be appendable without
				triggering a re-allocation.

	*/
	void reserve(size_t amount)
	@trusted {
		size_t nelems = m_data.length - m_remaining.length;
		if (!m_data.length) {
			m_data = cast(ElemType[])m_alloc.allocate(amount*E.sizeof);
			m_remaining = m_data;
			m_allocatedBuffer = true;
		}
		if (m_remaining.length < amount) {
			debug {
				import std.digest.crc;
				auto checksum = crc32Of(m_data[0 .. nelems]);
			}
			if (m_allocatedBuffer) {
				void[] vdata = m_data;
				m_alloc.reallocate(vdata, (nelems+amount)*E.sizeof);
				m_data = () @trusted { return cast(ElemType[])vdata; } ();
			} else {
				auto newdata = cast(ElemType[])m_alloc.allocate((nelems+amount)*E.sizeof);
				newdata[0 .. nelems] = m_data[0 .. nelems];
				m_data = newdata;
				m_allocatedBuffer = true;
			}
			debug assert(crc32Of(m_data[0 .. nelems]) == checksum);
		}
		m_remaining = m_data[nelems .. m_data.length];
	}

	void put(E el)
	@safe {
		if( m_remaining.length == 0 ) grow(1);
		m_remaining[0] = el;
		m_remaining = m_remaining[1 .. $];
	}

	void put(ArrayType arr)
	@safe {
		if (m_remaining.length < arr.length) grow(arr.length);
		m_remaining[0 .. arr.length] = arr[];
		m_remaining = m_remaining[arr.length .. $];
	}

	static if( !hasAliasing!E ){
		void put(in ElemType[] arr)
			@trusted
		{
			put(cast(ArrayType)arr);
		}
	}

	static if( is(ElemType == char) ){
		void put(dchar el)
			@safe
		{
			if( el < 128 ) put(cast(char)el);
			else {
				char[4] buf;
				auto len = std.utf.encode(buf, el);
				put(() @trusted { return cast(ArrayType)buf[0 .. len]; }());
			}
		}
	}

	static if( is(ElemType == wchar) ){
		void put(dchar el)
			@safe
		{
			if( el < 128 ) put(cast(wchar)el);
			else {
				wchar[3] buf;
				auto len = std.utf.encode(buf, el);
				put(() @trusted { return cast(ArrayType)buf[0 .. len]; } ());
			}
		}
	}

	static if (!is(E == immutable) || !hasAliasing!E) {
		/** Appends a number of bytes in-place.

			The delegate will get the memory slice of the memory that follows
			the already written data. Use `reserve` to ensure that this slice
			has enough room. The delegate should overwrite as much of the
			slice as desired and then has to return the number of elements
			that should be appended (counting from the start of the slice).
		*/
		void append(scope size_t delegate(scope ElemType[] dst) @safe del)
		{
			auto n = del(m_remaining);
			assert(n <= m_remaining.length);
			m_remaining = m_remaining[n .. $];
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
	auto a = AllocAppender!string(theAllocator());
	a.put("Hello");
	a.put(' ');
	a.put("World");
	assert(a.data == "Hello World");
	a.reset();
	assert(a.data == "");
}

unittest {
	char[4] buf;
	auto a = AllocAppender!string(theAllocator(), buf);
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
	auto a = AllocAppender!string(theAllocator(), buf);
	a.put("Hello");
	assert(a.data == "Hello");
	assert(a.data.ptr != buf.ptr);
}

unittest {
	auto app = AllocAppender!(int[])(theAllocator);
	app.reserve(2);
	app.append((scope mem) {
		assert(mem.length >= 2);
		mem[0] = 1;
		mem[1] = 2;
		return size_t(2);
	});
	assert(app.data == [1, 2]);
}

unittest {
	auto app = AllocAppender!string(theAllocator);
	app.reserve(3);
	app.append((scope mem) {
		assert(mem.length >= 3);
		mem[0] = 'f';
		mem[1] = 'o';
		mem[2] = 'o';
		return size_t(3);
	});
	assert(app.data == "foo");
}


struct FixedAppender(ArrayType : E[], size_t NELEM, E) {
	alias ElemType = Unqual!E;
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
		m_data[m_fill .. m_fill+arr.length] = arr[];
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
struct FixedRingBuffer(T, size_t N = 0, bool INITIALIZE = true) {
	private {
		static if( N > 0 ) {
			static if (INITIALIZE) T[N] m_buffer;
			else T[N] m_buffer = void;
		} else T[] m_buffer;
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
		/// Resets the capacity to zero and explicitly frees the memory for the buffer.
		void dispose()
		{
			static if (__VERSION__ >= 2079) {
				import core.memory : __delete;
				__delete(m_buffer);
			} else mixin("delete m_buffer;");
			m_buffer = null;
			m_start = m_fill = 0;
		}

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
			} else {
				m_buffer = new T[new_size];
			}
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

	void putBack()(T itm) { assert(m_fill < m_buffer.length); m_buffer[mod(m_start + m_fill++)] = itm; }
	void putBack(TC : T)(TC[] itms)
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
	void putBackN(size_t n) { assert(m_fill+n <= m_buffer.length); m_fill += n; }

	alias put = putBack;
	alias putN = putBackN;

	void putFront(T itm)
	{
		assert(m_fill < m_buffer.length);
		m_start = mod(m_start + m_buffer.length - 1);
		m_fill++;
		m_buffer[m_start] = itm;
	}

	void popFront() { assert(!empty); m_start = mod(m_start+1); m_fill--; }
	void popFrontN(size_t n) { assert(length >= n); m_start = mod(m_start + n); m_fill -= n; }

	void popBack() { assert(!empty); m_fill--; }
	void popBackN(size_t n) { assert(length >= n); m_fill -= n; }

	void removeAt(Range r)
	{
		assert(r.m_buffer is m_buffer);
		if (r.m_start == m_start) { popFront(); return; }
		if( m_start + m_fill > m_buffer.length ){
			assert(r.m_start > m_start && r.m_start < m_buffer.length || r.m_start < mod(m_start+m_fill));
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

	int opApply(scope int delegate(ref T itm)  @safe del)
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

	/// iterate through elements with index
	int opApply(scope int delegate(size_t i, ref T itm) @safe del)
	{
		if( m_start+m_fill > m_buffer.length ){
			foreach(i; m_start .. m_buffer.length)
				if( auto ret = del(i - m_start, m_buffer[i]) )
					return ret;
			foreach(i; 0 .. mod(m_start+m_fill))
				if( auto ret = del(i + m_buffer.length - m_start, m_buffer[i]) )
					return ret;
		} else {
			foreach(i; m_start .. m_start+m_fill)
				if( auto ret = del(i - m_start, m_buffer[i]) )
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

		@property ref inout(T) front() inout { assert(!empty); return m_buffer[m_start]; }

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
	import std.range : only;

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

	buf.put([0, 0, 0, 1, 2]); //|0 0 0 1 2
	buf.popFrontN(2); //. .|0 1 2
	buf.put([3, 4]); // 3 4|0 1 2
	foreach(i, item; buf)
	{
		assert(i == item);
	}

	assert(buf.front == 0);
	assert(buf.full);
	buf.removeAt(buf[0..1]); //4 .|1 2 3
	foreach(i, item; buf)
	{
		assert(i == item - 1);
	}

	buf.put(5); // 4 5|1 2 3
	buf.removeAt(buf[3..4]); // 5 .|1 2 3
	assert(buf.front == 1); buf.popFront();
	assert(buf.front == 2); buf.popFront();
	assert(buf.front == 3); buf.popFront();
	assert(buf.front == 5); buf.popFront();
	assert(buf.empty);

	buf.put(1);
	assert(buf.front == 1);
	buf.front = 2;
	assert(buf.front == 2);
	buf[].front = 3;
	assert(buf.front == 3);

	buf.putFront(4);
	assert(buf.length == 2);
	assert(buf[].equal(only(4, 3)));
}


struct ArraySet(Key)
{
	import stdx.allocator : makeArray, expandArray, dispose;
	import stdx.allocator.building_blocks.affix_allocator : AffixAllocator;

	private {
		IAllocator AW(IAllocator a) { return a; }
		alias AllocatorType = AffixAllocator!(IAllocator, int);
		Key[4] m_staticEntries;
		Key[] m_entries;
		AllocatorType m_allocator;
	}

	~this()
	@trusted {
		if (m_entries.ptr) {
			if (--allocator.prefix(m_entries) <= 0) {
				try allocator.dispose(m_entries);
				catch (Exception e) assert(false, e.msg); // should never happen
			}
		}
	}

	this(this)
	@trusted {
		if (m_entries.ptr) {
			allocator.prefix(m_entries)++;
		}
	}

	@property ArraySet dup()
	{
		ArraySet ret;
		ret.m_staticEntries = m_staticEntries;
		ret.m_allocator = m_allocator;

		if (m_entries.length) {
			Key[] duped;
			() @trusted {
				try duped = allocator.makeArray!(Key)(m_entries.length);
				catch (Exception e) assert(false, e.msg);
				if (!duped.length)
					assert(false, "Failed to allocate memory for duplicated "~ArraySet.stringof);
				allocator.prefix(duped) = 1;
			} ();
			duped[] = m_entries[];
			ret.m_entries = duped;
		}

		return ret;
	}

	void setAllocator(IAllocator allocator)
	in { assert(m_entries.ptr is null, "Cannot set allocator after elements have been inserted."); }
	body {
		m_allocator = AllocatorType(AW(allocator));
	}

	bool opBinaryRight(string op)(Key key) if (op == "in") { return contains(key); }

	int opApply(int delegate(ref Key) @safe del)
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

		size_t oldlen = m_entries.length;

		() @trusted {
			try {
				if (!oldlen) {
					m_entries = allocator.makeArray!Key(64);
					assert(m_entries.length, "Failed to allocate memory for "~ArraySet.stringof);
					allocator.prefix(m_entries) = 1;
				} else {
					int oldrc = allocator.prefix(m_entries);
					if (!allocator.expandArray(m_entries, max(64, oldlen * 3 / 4)))
						assert(false, "Failed to allocate memory for "~ArraySet.stringof);
					allocator.prefix(m_entries) = oldrc;
				}
			} catch (Exception e) assert(false, e.msg);
		} ();

		m_entries[oldlen] = key;
	}

	void remove(Key key)
	{
		foreach (ref k; m_staticEntries) if (k == key) { k = Key.init; return; }
		foreach (ref k; m_entries) if (k == key) { k = Key.init; return; }
	}

	ref allocator()
	nothrow @trusted {
		try {
			auto palloc = m_allocator._parent;
			if (!palloc) {
				assert(vibeThreadAllocator !is null, "No theAllocator set!?");
				m_allocator = AllocatorType(AW(vibeThreadAllocator));
			}
		} catch (Exception e) assert(false, e.msg); // should never throw
		return m_allocator;
	}
}

@safe nothrow unittest {
	import stdx.allocator : allocatorObject;
	import stdx.allocator.mallocator : Mallocator;

	ArraySet!int s;
	s.setAllocator(() @trusted { return Mallocator.instance.allocatorObject; } ());

	ArraySet!int t;
	t = s;

	s.insert(1);
	s.insert(2);
	s.insert(3);
	s.insert(4);
	assert(s.contains(1));
	assert(s.contains(2));
	assert(s.contains(3));
	assert(s.contains(4));
	assert(!t.contains(1));

	s.insert(5);
	assert(s.contains(5));

	t = s;
	assert(t.contains(5));
	assert(t.contains(1));

	s.insert(6);
	assert(s.contains(6));
	assert(t.contains(6));

	s = ArraySet!int.init;
	assert(!s.contains(1));
	assert(t.contains(1));
	assert(t.contains(6));

	s = t.dup;
	assert(s.contains(1));
	assert(s.contains(6));

	t.remove(1);
	assert(!t.contains(1));
	assert(s.contains(1));
	assert(t.contains(2));
	assert(t.contains(6));

	t.remove(6);
	assert(!t.contains(6));
	assert(s.contains(6));
	assert(t.contains(5));
}
