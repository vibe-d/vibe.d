/**
	Internal hash map implementation.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.hashmap;

import vibe.internal.utilallocator;

import std.conv : emplace;
import std.traits;


struct DefaultHashMapTraits(Key) {
	enum clearValue = Key.init;
	static bool equals(in Key a, in Key b)
	{
		static if (is(Key == class)) return a is b;
		else return a == b;
	}
	static size_t hashOf(in ref Key k)
	@safe {
		static if (is(Key == class) && &Unqual!Key.init.toHash is &Object.init.toHash)
			return () @trusted { return cast(size_t)cast(void*)k; } ();
		else static if (__traits(compiles, Key.init.toHash()))
			return () @trusted { return (cast(Key)k).toHash(); } ();
		else static if (__traits(compiles, Key.init.toHashShared()))
			return k.toHashShared();
		else {
			// evil casts to be able to get the most basic operations of
			// HashMap nothrow and @nogc
			static size_t hashWrapper(in ref Key k) {
				static typeinfo = typeid(Key);
				return typeinfo.getHash(&k);
			}
			static @nogc nothrow size_t properlyTypedWrapper(in ref Key k) { return 0; }
			return () @trusted { return (cast(typeof(&properlyTypedWrapper))&hashWrapper)(k); } ();
		}
	}
}

struct HashMap(TKey, TValue, Traits = DefaultHashMapTraits!TKey, Allocator = IAllocator)
{
	import core.memory : GC;
	import vibe.internal.meta.traits : isOpApplyDg;
	import std.algorithm.iteration : filter, map;

	alias Key = TKey;
	alias Value = TValue;

	Allocator AW(Allocator a) { return a; }
	alias AllocatorType = AffixAllocator!(Allocator, int);
	static if (is(typeof(AllocatorType.instance)))
		alias AllocatorInstanceType = typeof(AllocatorType.instance);
	else alias AllocatorInstanceType = AllocatorType;

	struct TableEntry {
		UnConst!Key key = Traits.clearValue;
		Value value;

		this(ref Key key, ref Value value)
		{
			import std.algorithm.mutation : move;
			this.key = cast(UnConst!Key)key;
			this.value = value.move;
		}
	}
	private {
		TableEntry[] m_table; // NOTE: capacity is always POT
		size_t m_length;
		static if (!is(typeof(Allocator.instance)))
			AllocatorInstanceType m_allocator;
		bool m_resizing;
	}

	static if (!is(typeof(Allocator.instance))) {
		this(Allocator allocator)
		{
			m_allocator = typeof(m_allocator)(AW(allocator));
		}
	}

	~this()
	{
		int rc;
		try rc = m_table is null ? 1 : () @trusted { return --allocator.prefix(m_table); } ();
		catch (Exception e) assert(false, e.msg);

		if (rc == 0) {
			clear();
			if (m_table.ptr !is null) () @trusted {
				static if (hasIndirections!TableEntry) GC.removeRange(m_table.ptr);
				try allocator.dispose(m_table);
				catch (Exception e) assert(false, e.msg);
			} ();
		}
	}

	this(this)
	@trusted {
		if (m_table.ptr) {
			try allocator.prefix(m_table)++;
			catch (Exception e) assert(false, e.msg);
		}
	}

	@property size_t length() const { return m_length; }

	void remove(Key key)
	{
		import std.algorithm.mutation : move;

		auto idx = findIndex(key);
		assert (idx != size_t.max, "Removing non-existent element.");
		auto i = idx;
		while (true) {
			m_table[i].key = Traits.clearValue;
			m_table[i].value = Value.init;

			size_t j = i, r;
			do {
				if (++i >= m_table.length) i -= m_table.length;
				if (Traits.equals(m_table[i].key, Traits.clearValue)) {
					m_length--;
					return;
				}
				r = Traits.hashOf(m_table[i].key) & (m_table.length-1);
			} while ((j<r && r<=i) || (i<j && j<r) || (r<=i && i<j));
			m_table[j] = m_table[i].move;
		}
	}

	Value get(Key key, lazy Value default_value = Value.init)
	{
		auto idx = findIndex(key);
		if (idx == size_t.max) return default_value;
		return m_table[idx].value;
	}

	/// Workaround #12647
	package(vibe) Value getNothrow(Key key, Value default_value = Value.init)
	{
		auto idx = findIndex(key);
		if (idx == size_t.max) return default_value;
		return m_table[idx].value;
	}

	static if (!is(typeof({ Value v; const(Value) vc; v = vc; }))) {
		const(Value) get(Key key, lazy const(Value) default_value = Value.init)
		{
			auto idx = findIndex(key);
			if (idx == size_t.max) return default_value;
			return m_table[idx].value;
		}
	}

	void clear()
	{
		foreach (i; 0 .. m_table.length)
			if (!Traits.equals(m_table[i].key, Traits.clearValue)) {
				m_table[i].key = Traits.clearValue;
				m_table[i].value = Value.init;
			}
		m_length = 0;
	}

	void opIndexAssign(T)(T value, Key key)
	{
		import std.algorithm.mutation : move;

		assert(!Traits.equals(key, Traits.clearValue), "Inserting clear value into hash map.");
		grow(1);
		auto i = findInsertIndex(key);
		if (!Traits.equals(m_table[i].key, key)) m_length++;
		m_table[i].key = () @trusted { return cast(UnConst!Key)key; } ();
		m_table[i].value = value;
	}

	ref inout(Value) opIndex(Key key)
	inout {
		auto idx = findIndex(key);
		assert (idx != size_t.max, "Accessing non-existent key.");
		return m_table[idx].value;
	}

	inout(Value)* opBinaryRight(string op)(Key key)
	inout if (op == "in") {
		auto idx = findIndex(key);
		if (idx == size_t.max) return null;
		return &m_table[idx].value;
	}

	int opApply(DG)(scope DG del) if (isOpApplyDg!(DG, Key, Value))
	{
		import std.traits : arity;
		foreach (i; 0 .. m_table.length)
			if (!Traits.equals(m_table[i].key, Traits.clearValue)) {
				static assert(arity!del >= 1 && arity!del <= 2,
						  "isOpApplyDg should have prevented this");
				static if (arity!del == 1) {
					if (int ret = del(m_table[i].value))
						return ret;
				} else
					if (int ret = del(m_table[i].key, m_table[i].value))
						return ret;
			}
		return 0;
	}

	auto byKey() { return bySlot.map!(e => e.key); }
	auto byKey() const { return bySlot.map!(e => e.key); }
	auto byValue() { return bySlot.map!(e => e.value); }
	auto byValue() const { return bySlot.map!(e => e.value); }
	auto byKeyValue() { import std.typecons : Tuple; return bySlot.map!(e => Tuple!(Key, "key", Value, "value")(e.key, e.value)); }
	auto byKeyValue() const { import std.typecons : Tuple; return bySlot.map!(e => Tuple!(const(Key), "key", const(Value), "value")(e.key, e.value)); }

	private auto bySlot() { return m_table[].filter!(e => !Traits.equals(e.key, Traits.clearValue)); }
	private auto bySlot() const { return m_table[].filter!(e => !Traits.equals(e.key, Traits.clearValue)); }

	private @property AllocatorInstanceType allocator()
	{
		static if (is(typeof(Allocator.instance)))
			return AllocatorType.instance;
		else {
			if (!m_allocator._parent) {
				static if (is(Allocator == IAllocator)) {
					try m_allocator = typeof(m_allocator)(AW(vibeThreadAllocator()));
					catch (Exception e) assert(false, e.msg);
				} else assert(false, "Allocator not initialized.");
			}
			return m_allocator;
		}
	}

	private size_t findIndex(Key key)
	const {
		if (m_length == 0) return size_t.max;
		size_t start = Traits.hashOf(key) & (m_table.length-1);
		auto i = start;
		while (!Traits.equals(m_table[i].key, key)) {
			if (Traits.equals(m_table[i].key, Traits.clearValue)) return size_t.max;
			if (++i >= m_table.length) i -= m_table.length;
			if (i == start) return size_t.max;
		}
		return i;
	}

	private size_t findInsertIndex(Key key)
	const {
		auto hash = Traits.hashOf(key);
		size_t target = hash & (m_table.length-1);
		auto i = target;
		while (!Traits.equals(m_table[i].key, Traits.clearValue) && !Traits.equals(m_table[i].key, key)) {
			if (++i >= m_table.length) i -= m_table.length;
			assert (i != target, "No free bucket found, HashMap full!?");
		}
		return i;
	}

	private void grow(size_t amount)
	@trusted {
		auto newsize = m_length + amount;
		if (newsize < (m_table.length*2)/3) {
			int rc;
			try rc = allocator.prefix(m_table);
			catch (Exception e) assert(false, e.msg);
			if (rc > 1) {
				// enforce copy-on-write
				auto oldtable = m_table;
				try {
					m_table = allocator.makeArray!TableEntry(m_table.length);
					m_table[] = oldtable;
					allocator.prefix(oldtable)--;
					assert(allocator.prefix(oldtable) > 0);
					allocator.prefix(m_table) = 1;
				} catch (Exception e) {
					assert(false, e.msg);
				}
			}
			return;
		}
		auto newcap = m_table.length ? m_table.length : 16;
		while (newsize >= (newcap*2)/3) newcap *= 2;
		resize(newcap);
	}

	private void resize(size_t new_size)
	@trusted {
		assert(!m_resizing);
		m_resizing = true;
		scope(exit) m_resizing = false;

		uint pot = 0;
		while (new_size > 1) {
			pot++;
			new_size /= 2;
		}
		new_size = 1 << pot;

		auto oldtable = m_table;

		// allocate the new array, automatically initializes with empty entries (Traits.clearValue)
		try {
			m_table = allocator.makeArray!TableEntry(new_size);
			allocator.prefix(m_table) = 1;
		} catch (Exception e) assert(false, e.msg);
		static if (hasIndirections!TableEntry) GC.addRange(m_table.ptr, m_table.length * TableEntry.sizeof);
		// perform a move operation of all non-empty elements from the old array to the new one
		foreach (ref el; oldtable)
			if (!Traits.equals(el.key, Traits.clearValue)) {
				auto idx = findInsertIndex(el.key);
				(cast(ubyte[])(&m_table[idx])[0 .. 1])[] = (cast(ubyte[])(&el)[0 .. 1])[];
			}

		// all elements have been moved to the new array, so free the old one without calling destructors
		int rc;
		try rc = oldtable is null ? 1 : --allocator.prefix(oldtable);
		catch (Exception e) assert(false, e.msg);
		if (rc == 0) {
			static if (hasIndirections!TableEntry) GC.removeRange(oldtable.ptr);
			try allocator.deallocate(oldtable);
			catch (Exception e) assert(false, e.msg);
		}
	}
}

unittest {
	import std.conv;

	HashMap!(string, string) map;

	foreach (i; 0 .. 100) {
		map[to!string(i)] = to!string(i) ~ "+";
		assert(map.length == i+1);
	}

	foreach (i; 0 .. 100) {
		auto str = to!string(i);
		auto pe = str in map;
		assert(pe !is null && *pe == str ~ "+");
		assert(map[str] == str ~ "+");
	}

	foreach (i; 0 .. 50) {
		map.remove(to!string(i));
		assert(map.length == 100-i-1);
	}

	foreach (i; 50 .. 100) {
		auto str = to!string(i);
		auto pe = str in map;
		assert(pe !is null && *pe == str ~ "+");
		assert(map[str] == str ~ "+");
	}
}

// test for nothrow/@nogc compliance
nothrow unittest {
	HashMap!(int, int) map1;
	HashMap!(string, string) map2;
	map1[1] = 2;
	map2["1"] = "2";

	@nogc nothrow void performNoGCOps()
	{
		foreach (int v; map1) {}
		foreach (int k, int v; map1) {}
		assert(1 in map1);
		assert(map1.length == 1);
		assert(map1[1] == 2);
		assert(map1.getNothrow(1, -1) == 2);

		foreach (string v; map2) {}
		foreach (string k, string v; map2) {}
		assert("1" in map2);
		assert(map2.length == 1);
		assert(map2["1"] == "2");
		assert(map2.getNothrow("1", "") == "2");
	}

	performNoGCOps();
}

unittest { // test for proper use of constructor/post-blit/destructor
	static struct Test {
		static size_t constructedCounter = 0;
		bool constructed = false;
		this(int) { constructed = true; constructedCounter++; }
		this(this) nothrow { if (constructed) constructedCounter++; }
		~this() nothrow { if (constructed) constructedCounter--; }
	}

	assert(Test.constructedCounter == 0);

	{ // sanity check
		Test t;
		assert(Test.constructedCounter == 0);
		t = Test(1);
		assert(Test.constructedCounter == 1);
		auto u = t;
		assert(Test.constructedCounter == 2);
		t = Test.init;
		assert(Test.constructedCounter == 1);
	}
	assert(Test.constructedCounter == 0);

	{ // basic insertion and hash map resizing
		HashMap!(int, Test) map;
		foreach (i; 1 .. 67) {
			map[i] = Test(1);
			assert(Test.constructedCounter == i);
		}
	}

	assert(Test.constructedCounter == 0);

	{ // test clear() and overwriting existing entries
		HashMap!(int, Test) map;
		foreach (i; 1 .. 67) {
			map[i] = Test(1);
			assert(Test.constructedCounter == i);
		}
		map.clear();
		foreach (i; 1 .. 67) {
			map[i] = Test(1);
			assert(Test.constructedCounter == i);
		}
		foreach (i; 1 .. 67) {
			map[i] = Test(1);
			assert(Test.constructedCounter == 66);
		}
	}

	assert(Test.constructedCounter == 0);

	{ // test removing entries and adding entries after remove
		HashMap!(int, Test) map;
		foreach (i; 1 .. 67) {
			map[i] = Test(1);
			assert(Test.constructedCounter == i);
		}
		foreach (i; 1 .. 33) {
			map.remove(i);
			assert(Test.constructedCounter == 66 - i);
		}
		foreach (i; 67 .. 130) {
			map[i] = Test(1);
			assert(Test.constructedCounter == i - 32);
		}
	}

	assert(Test.constructedCounter == 0);
}

private template UnConst(T) {
	static if (is(T U == const(U))) {
		alias UnConst = U;
	} else static if (is(T V == immutable(V))) {
		alias UnConst = V;
	} else alias UnConst = T;
}
