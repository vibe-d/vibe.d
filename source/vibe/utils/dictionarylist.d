/**
	Defines a string based multi-map with conserved insertion order.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.dictionarylist;

import vibe.utils.array : removeFromArrayIdx;
import vibe.utils.string : icmp2;
import std.exception : enforce;


/**
	Behaves similar to string[string] but the insertion order is not changed
	and multiple values per key are supported.

	This kind of map is used for MIME headers (e.g. for HTTP, see
	vibe.inet.message.InetHeaderMap), or for form data
	(vibe.inet.webform.FormFields). Note that the map can contain fields with
	the same key multiple times if addField is used for insertion. Insertion
	order is preserved.

	Note that despite case not being relevant for matching keyse, iterating
	over the map will yield	the original case of the key that was put in.

	Insertion and lookup has O(n) complexity.
*/
struct DictionaryList(Value, bool case_sensitive = true) {
	private {
		static struct Field { uint keyCheckSum; string key; Value value; }
		Field[64] m_fields;
		size_t m_fieldCount = 0;
		Field[] m_extendedFields;
		static char[256] s_keyBuffer;
	}
	
	/** The number of fields present in the map.
	*/
	@property size_t length() const { return m_fieldCount + m_extendedFields.length; }

	/** Removes the first field that matches the given key.
	*/
	void remove(string key)
	{
		auto keysum = computeCheckSumI(key);
		auto idx = getIndex(m_fields[0 .. m_fieldCount], key, keysum);
		if( idx >= 0 ){
			auto slice = m_fields[0 .. m_fieldCount];
			removeFromArrayIdx(slice, idx);
			m_fieldCount--;
		} else {
			idx = getIndex(m_extendedFields, key, keysum);
			enforce(idx >= 0);
			removeFromArrayIdx(m_extendedFields, idx);
		}
	}

	/** Removes all fields that matches the given key.
	*/
	void removeAll(string key)
	{
		auto keysum = computeCheckSumI(key);
		for (size_t i = 0; i < m_fieldCount;) {
			if (m_fields[i].keyCheckSum == keysum && matches(m_fields[i].key, key)) {
				auto slice = m_fields[0 .. m_fieldCount];
				removeFromArrayIdx(slice, i);
				m_fieldCount--;
			} else i++;
		}

		for (size_t i = 0; i < m_extendedFields.length;) {
			if (m_fields[i].keyCheckSum == keysum && matches(m_fields[i].key, key))
				removeFromArrayIdx(m_extendedFields, i);
			else i++;
		}
	}

	/** Adds a new field to the map.

		The new field will be added regardless of any existing fields that
		have the same key, possibly resulting in duplicates. Use opIndexAssign
		if you want to avoid duplicates.
	*/
	void addField(string key, Value value)
	{
		auto keysum = computeCheckSumI(key);
		if (m_fieldCount < m_fields.length)
			m_fields[m_fieldCount++] = Field(keysum, key, value);
		else m_extendedFields ~= Field(keysum, key, value);
	}

	/** Returns the first field that matches the given key.

		If no field is found, def_val is returned.
	*/
	inout(Value) get(string key, lazy inout(Value) def_val = Value.init)
	inout {
		if (auto pv = key in this) return *pv;
		return def_val;
	}

	/** Returns all values matching the given key.

		Note that the version returning an array will allocate for each call.
	*/
	const(Value)[] getAll(string key)
	const {
		import std.array;
		auto ret = appender!(const(Value)[])();
		getAll(key, (v) { ret.put(v); });
		return ret.data;
	}
	/// ditto
	void getAll(string key, scope void delegate(const(Value)) del)
	const {
		uint keysum = computeCheckSumI(key);
		foreach (ref f; m_fields[0 .. m_fieldCount]) {
			if (f.keyCheckSum != keysum) continue;
			if (matches(f.key, key)) del(f.value);
		}
		foreach (ref f; m_extendedFields) {
			if (f.keyCheckSum != keysum) continue;
			if (matches(f.key, key)) del(f.value);
		}
	}

	/** Returns the first value matching the given key.
	*/
	inout(Value) opIndex(string key)
	inout {
		auto pitm = key in this;
		enforce(pitm !is null, "Accessing non-existent key '"~key~"'.");
		return *pitm;
	}
	
	/** Adds or replaces the given field with a new value.
	*/
	Value opIndexAssign(Value val, string key)
	{
		auto pitm = key in this;
		if( pitm ) *pitm = val;
		else if( m_fieldCount < m_fields.length ) m_fields[m_fieldCount++] = Field(computeCheckSumI(key), key, val);
		else m_extendedFields ~= Field(computeCheckSumI(key), key, val);
		return val;
	}

	/** Returns a pointer to the first field that matches the given key.
	*/
	inout(Value)* opBinaryRight(string op)(string key) inout if(op == "in") {
		uint keysum = computeCheckSumI(key);
		auto idx = getIndex(m_fields[0 .. m_fieldCount], key, keysum);
		if( idx >= 0 ) return &m_fields[idx].value;
		idx = getIndex(m_extendedFields, key, keysum);
		if( idx >= 0 ) return &m_extendedFields[idx].value;
		return null;
	}
	/// ditto
	bool opBinaryRight(string op)(string key) inout if(op == "!in") {
		return !(key in this);
	}

	/** Iterates over all fields, including duplicates.
	*/
	int opApply(int delegate(ref string key, ref Value val) del)
	{
		foreach( ref kv; m_fields[0 .. m_fieldCount] ){
			string kcopy = kv.key;
			if( auto ret = del(kcopy, kv.value) )
				return ret;
		}
		foreach( ref kv; m_extendedFields ){
			string kcopy = kv.key;
			if( auto ret = del(kcopy, kv.value) )
				return ret;
		}
		return 0;
	}

	/// ditto
	int opApply(int delegate(ref Value val) del)
	{
		foreach( ref kv; m_fields[0 .. m_fieldCount] ){
			if( auto ret = del(kv.value) )
				return ret;
		}
		foreach( ref kv; m_extendedFields ){
			if( auto ret = del(kv.value) )
				return ret;
		}
		return 0;
	}
	
	Value[string] asAA() @property 
	{
		Value[string] aa;
		foreach (ref kv; m_fields[ 0 .. m_fieldCount] ) 
		{
			aa[kv.key] = kv.value;
		}
	return aa;
	}

	static if (is(typeof({ const(Value) v; Value w; w = v; }))) {
		/** Duplicates the header map.
		*/
		@property DictionaryList dup()
		const {
			DictionaryList ret;
			ret.m_fields[0 .. m_fieldCount] = m_fields[0 .. m_fieldCount];
			ret.m_fieldCount = m_fieldCount;
			ret.m_extendedFields = m_extendedFields.dup;
			return ret;
		}
	}

	private ptrdiff_t getIndex(in Field[] map, string key, uint keysum)
	const {
		foreach (i, ref const(Field) entry; map) {
			if (entry.keyCheckSum != keysum) continue;
			if (matches(entry.key, key)) return i;
		}
		return -1;
	}

	private static bool matches(string a, string b)
	{
		static if (case_sensitive) return a == b;
		else return icmp2(a, b) == 0;
	}
	
	// very simple check sum function with a good chance to match
	// strings with different case equal
	private static uint computeCheckSumI(string s)
	{
		uint csum = 0;
		static if (case_sensitive) foreach (char ch; s) csum += 357 * (csum + ch);
		foreach (char ch; s) csum += 347 * (csum + (ch & 0x1101_1111));
		return csum;
	}
}

unittest {
	DictionaryList!(int, true) a;
	a.addField("a", 1);
	a.addField("a", 2);
	assert(a["a"] == 1);
	assert(a.getAll("a") == [1, 2]);
	a["a"] = 3;
	assert(a["a"] == 3);
	assert(a.getAll("a") == [3, 2]);
	a.removeAll("a");
	assert(a.getAll("a").length == 0);
	assert(a.get("a", 4) == 4);
	a.addField("b", 2);
	a.addField("b", 1);
	a.remove("b");
	assert(a.getAll("b") == [1]);

	DictionaryList!(int, false) b;
	b.addField("a", 1);
	b.addField("A", 2);
	assert(b["A"] == 1);
	assert(b.getAll("a") == [1, 2]);
}
