/**
	Internal hash map implementation.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.hashmap;

import vibe.utils.memory;

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
	{
		static if (is(Key == class) && &Key.toHash == &Object.toHash)
			return cast(size_t)cast(void*)k;
		else static if (__traits(compiles, Key.init.toHash()))
			return k.toHash();
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
			return (cast(typeof(&properlyTypedWrapper))&hashWrapper)(k);
		}
	}
}

struct HashMap(TKey, TValue, Traits = DefaultHashMapTraits!TKey)
{
	import vibe.internal.meta.traits : isOpApplyDg;

	alias Key = TKey;
	alias Value = TValue;

	struct TableEntry {
		UnConst!Key key = Traits.clearValue;
		Value value;

		this(Key key, Value value) { this.key = cast(UnConst!Key)key; this.value = value; }
	}
	private {
		TableEntry[] m_table; // NOTE: capacity is always POT
		size_t m_length;
		Allocator m_allocator;
		bool m_resizing;
	}

	this(Allocator allocator)
	{
		m_allocator = allocator;
	}

	~this()
	{
		clear();
		if (m_table.ptr !is null) freeArray(m_allocator, m_table);
	}

	@disable this(this);

	@property size_t length() const { return m_length; }

	void remove(Key key)
	{
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
			m_table[j] = m_table[i];
		}
	}

	Value get(Key key, lazy Value default_value = Value.init)
	{
		auto idx = findIndex(key);
		if (idx == size_t.max) return default_value;
		return m_table[idx].value;
	}

	/// Workaround #12647
	package Value getNothrow(Key key, Value default_value = Value.init)
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

	void opIndexAssign(Value value, Key key)
	{
		assert(!Traits.equals(key, Traits.clearValue), "Inserting clear value into hash map.");
		grow(1);
		auto i = findInsertIndex(key);
		if (!Traits.equals(m_table[i].key, key)) m_length++;
		m_table[i] = TableEntry(key, value);
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
	{
		auto newsize = m_length + amount;
		if (newsize < (m_table.length*2)/3) return;
		auto newcap = m_table.length ? m_table.length : 16;
		while (newsize >= (newcap*2)/3) newcap *= 2;
		resize(newcap);
	}

	private void resize(size_t new_size)
	@trusted {
		assert(!m_resizing);
		m_resizing = true;
		scope(exit) m_resizing = false;

		if (!m_allocator) m_allocator = defaultAllocator();

		uint pot = 0;
		while (new_size > 1) pot++, new_size /= 2;
		new_size = 1 << pot;

		auto oldtable = m_table;

		// allocate the new array, automatically initializes with empty entries (Traits.clearValue)
		m_table = allocArray!TableEntry(m_allocator, new_size);

		// perform a move operation of all non-empty elements from the old array to the new one
		foreach (ref el; oldtable)
			if (!Traits.equals(el.key, Traits.clearValue)) {
				auto idx = findInsertIndex(el.key);
				(cast(ubyte[])(&m_table[idx])[0 .. 1])[] = (cast(ubyte[])(&el)[0 .. 1])[];
			}

		// all elements have been moved to the new array, so free the old one without calling destructors
		if (oldtable !is null) freeArray(m_allocator, oldtable, false);
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
static if (__VERSION__ >= 2066)
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
		this(this) { if (constructed) constructedCounter++; }
		~this() { if (constructed) constructedCounter--; }
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

static if (__VERSION__ < 2066) private static bool nogc() { return false; }
