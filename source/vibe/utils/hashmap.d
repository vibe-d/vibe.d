/**
	Internal hash map implementation.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.hashmap;

import vibe.utils.memory;

import std.typecons;


struct HashMap(Key, Value, alias ClearValue = { return Key.init; })
{
	alias TableEntry = Tuple!(Key, Value);
	private {
		TableEntry[] m_table; // NOTE: capacity is always POT
		size_t m_length;
		Allocator m_allocator;
		hash_t delegate(Key) m_hasher;
		bool m_resizing;
	}

	this(Allocator allocator)
	{
		assert (allocator is defaultAllocator(), "Allocators not yet supported.");
		m_allocator = allocator;
	}

	@property size_t length() const { return m_length; }

	void remove(Key key)
	{
		auto idx = findIndex(key);
		auto i = idx;
		while (true) {
			m_table[i][0] = ClearValue();
			m_table[i][1] = Value.init;

			size_t j = i, r;
			do {
				if (++i >= m_table.length) i -= m_table.length;
				if (m_table[i][0] == ClearValue()) {
					m_length--;
					return;
				}
				r = m_hasher(m_table[i][0]) & (m_table.length-1);
			} while ((j<r && r<=i) || (i<j && j<r) || (r<=i && i<j));
			m_table[j] = m_table[i];
		}
	}

	inout(Value) get(Key key, lazy Value default_value = Value.init)
	inout {
		auto idx = findIndex(key);
		if (idx == size_t.max) return cast(inout)default_value;
		return m_table[idx][1];
	}

	void opIndexAssign(Value value, Key key)
	{
		assert(key != ClearValue(), "Inserting clear value into hash map.");
		grow(1);

		auto hash = m_hasher(key);
		size_t target = hash & (m_table.length-1);
		auto i = target;
		while (m_table[i][0] != ClearValue() && m_table[i][0] != key) {
			if (++i >= m_table.length) i -= m_table.length;
			assert (i != target, "No free bucket found, HashMap full!?");
		}
		if (m_table[i][0] != key) m_length++;
		m_table[i] = TableEntry(key, value);
	}

	ref inout(Value) opIndex(Key key)
	inout {
		auto idx = findIndex(key);
		assert (idx != size_t.max, "Accessing non-existent key.");
		return m_table[idx][1];
	}

	inout(Value)* opBinaryRight(string op)(Key key)
	inout if (op == "in") {
		auto idx = findIndex(key);
		if (idx == size_t.max) return null;
		return &m_table[idx][1];
	}

	private size_t findIndex(Key key)
	const {
		if (m_length == 0) return size_t.max;
		size_t start = m_hasher(key) & (m_table.length-1);
		auto i = start;
		while (m_table[i][0] != key) {
			if (m_table[i][0] == ClearValue()) return size_t.max;
			if (++i >= m_table.length) i -= m_table.length;
			if (i == start) return size_t.max;
		}
		return i;
	}

	private void grow(size_t amount)
	{
		if( !m_allocator ){
			m_allocator = defaultAllocator();
			auto typeinfo = typeid(Key.init);
			m_hasher = k => typeinfo.getHash(&k);
		}

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

		uint pot = 0;
		while (new_size > 1) pot++, new_size /= 2;
		new_size = 1 << pot;

		auto oldtable = m_table;
		m_table = new TableEntry[new_size];
		static if (ClearValue() != Key.init)
			foreach (ref el; m_table)
				el[0] = ClearValue();
		m_length = 0;
		foreach (ref el; oldtable)
			if (el[0] != ClearValue())
				this[el[0]] = el[1];
		destroy(oldtable);
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
