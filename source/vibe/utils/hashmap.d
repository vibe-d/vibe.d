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
}

struct HashMap(Key, Value, Traits = DefaultHashMapTraits!Key)
{
	struct TableEntry {
		UnConst!Key key;
		Value value;

		this(Key key, Value value) { this.key = cast(UnConst!Key)key; this.value = value; }
	}
	private {
		TableEntry[] m_table; // NOTE: capacity is always POT
		size_t m_length;
		Allocator m_allocator;
		hash_t delegate(Key) m_hasher;
		bool m_resizing;
	}

	this(Allocator allocator)
	{
		m_allocator = allocator;
	}

	~this()
	{
		if (m_table) m_allocator.free(cast(void[])m_table);
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
				r = m_hasher(m_table[i].key) & (m_table.length-1);
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

	int opApply(int delegate(ref Value) del)
	{
		foreach (i; 0 .. m_table.length)
			if (!Traits.equals(m_table[i].key, Traits.clearValue))
				if (auto ret = del(m_table[i].value))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref Value) del)
	const {
		foreach (i; 0 .. m_table.length)
			if (!Traits.equals(m_table[i].key, Traits.clearValue))
				if (auto ret = del(m_table[i].value))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref Key, ref Value) del)
	{
		foreach (i; 0 .. m_table.length)
			if (!Traits.equals(m_table[i].key, Traits.clearValue))
				if (auto ret = del(m_table[i].key, m_table[i].value))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref Key, in ref Value) del)
	const {
		foreach (i; 0 .. m_table.length)
			if (!Traits.equals(m_table[i].key, Traits.clearValue))
				if (auto ret = del(m_table[i].key, m_table[i].value))
					return ret;
		return 0;
	}

	private size_t findIndex(Key key)
	const {
		if (m_length == 0) return size_t.max;
		size_t start = m_hasher(key) & (m_table.length-1);
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
		auto hash = m_hasher(key);
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
	{
		assert(!m_resizing);
		m_resizing = true;
		scope(exit) m_resizing = false;

		if (!m_allocator) m_allocator = defaultAllocator();
		if (!m_hasher) {
			static if (__traits(compiles, (){ Key t; size_t hash = t.toHash(); }())) {
				static if (isPointer!Key || is(Unqual!Key == class)) m_hasher = k => k ? k.toHash() : 0;
				else m_hasher = k => k.toHash();
			} else static if (__traits(compiles, (){ Key t; size_t hash = t.toHashShared(); }())) {
				static if (isPointer!Key || is(Unqual!Key == class)) m_hasher = k => k ? k.toHashShared() : 0;
				else m_hasher = k => k.toHashShared();
			} else {
				auto typeinfo = typeid(Key);
				m_hasher = k => typeinfo.getHash(&k);
			}
		}

		uint pot = 0;
		while (new_size > 1) pot++, new_size /= 2;
		new_size = 1 << pot;

		auto oldtable = m_table;
		m_table = allocArray!TableEntry(m_allocator, new_size);
		foreach (ref el; m_table) {
			static if (is(Key == struct)) {
				emplace(cast(UnConst!Key*)&el.key);
				static if (Traits.clearValue !is Key.init)
					el.key = cast(UnConst!Key)Traits.clearValue;
			} else el.key = cast(UnConst!Key)Traits.clearValue;
			emplace(&el.value);
		}
		foreach (ref el; oldtable)
			if (!Traits.equals(el.key, Traits.clearValue)) {
				auto idx = findInsertIndex(el.key);
				(cast(ubyte[])(&m_table[idx])[0 .. 1])[] = (cast(ubyte[])(&el)[0 .. 1])[];
			}
		if (oldtable) freeArray(m_allocator, oldtable);
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

private template UnConst(T) {
	static if (is(T U == const(U))) {
		alias UnConst = U;
	} else static if (is(T V == immutable(V))) {
		alias UnConst = V;
	} else alias UnConst = T;
}