/**
	Internal hash map implementation.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.hashmap;

import vibe.utils.memory;

import std.conv : emplace;


struct HashMap(Key, Value, alias ClearValue = () => Key.init, alias Equals = (a, b) => a == b)
{
	struct TableEntry {
		Key key;
		Value value;
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
			m_table[i].key = ClearValue();
			m_table[i].value = Value.init;

			size_t j = i, r;
			do {
				if (++i >= m_table.length) i -= m_table.length;
				if (m_table[i].key == ClearValue()) {
					m_length--;
					return;
				}
				r = m_hasher(m_table[i].key) & (m_table.length-1);
			} while ((j<r && r<=i) || (i<j && j<r) || (r<=i && i<j));
			m_table[j] = m_table[i];
		}
	}

	inout(Value) get(Key key, lazy Value default_value = Value.init)
	inout {
		auto idx = findIndex(key);
		if (idx == size_t.max) return cast(inout)default_value;
		return m_table[idx].value;
	}

	void opIndexAssign(Value value, Key key)
	{
		assert(key != ClearValue(), "Inserting clear value into hash map.");
		grow(1);

		auto hash = m_hasher(key);
		size_t target = hash & (m_table.length-1);
		auto i = target;
		while (m_table[i].key != ClearValue() && m_table[i].key != key) {
			if (++i >= m_table.length) i -= m_table.length;
			assert (i != target, "No free bucket found, HashMap full!?");
		}
		if (m_table[i].key != key) m_length++;
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
			if (!Equals(m_table[i].key, ClearValue()))
				if (auto ret = del(m_table[i].value))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref Value) del)
	const {
		foreach (i; 0 .. m_table.length)
			if (!Equals(m_table[i].key, ClearValue()))
				if (auto ret = del(m_table[i].value))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref Key, ref Value) del)
	{
		foreach (i; 0 .. m_table.length)
			if (!Equals(m_table[i].key, ClearValue()))
				if (auto ret = del(m_table[i].key, m_table[i].value))
					return ret;
		return 0;
	}

	int opApply(int delegate(in ref Key, in ref Value) del)
	const {
		foreach (i; 0 .. m_table.length)
			if (!Equals(m_table[i].key, ClearValue()))
				if (auto ret = del(m_table[i].key, m_table[i].value))
					return ret;
		return 0;
	}

	private size_t findIndex(Key key)
	const {
		if (m_length == 0) return size_t.max;
		size_t start = m_hasher(key) & (m_table.length-1);
		auto i = start;
		while (m_table[i].key != key) {
			if (Equals(m_table[i].key, ClearValue())) return size_t.max;
			if (++i >= m_table.length) i -= m_table.length;
			if (i == start) return size_t.max;
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
				m_hasher = k => k.toHash();
			} else static if (__traits(compiles, (){ Key t; size_t hash = t.toHashShared(); }())) {
				m_hasher = k => k.toHashShared();
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
			emplace!Key(&el.key, ClearValue());
			emplace!Value(&el.value);
		}
		m_length = 0;
		foreach (ref el; oldtable) {
			if (!Equals(el.key, ClearValue()))
				this[el.key] = el.value;
			destroy(el);
		}
		if (oldtable) m_allocator.free(cast(void[])oldtable);
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
