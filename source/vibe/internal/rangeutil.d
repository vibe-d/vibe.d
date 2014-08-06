module vibe.internal.rangeutil;

struct RangeCounter {
	import std.utf;
	long* length;

	this(long* _captureLength) { length = _captureLength; }

	void put(char ch) { (*length)++; }
	void put(string str) { *length += str.length; }
	void put(dchar ch) { *length += codeLength!char(ch); }
	void put(dstring str) { foreach (ch; str) put(ch); }
}

unittest {
	static long writeLength(ARGS...)(ARGS args) {
		long len = 0;
		auto rng = RangeCounter(&len);
		foreach (a; args) rng.put(a);
		return len;
	}
	assert(writeLength("hello", ' ', "world") == "hello world".length);
	assert(writeLength("h\u00E4llo", ' ', "world") == "h\u00E4llo world".length);
	assert(writeLength("hello", '\u00E4', "world") == "hello\u00E4world".length);
	assert(writeLength("h\u00E4llo", ' ', "world") == "h\u00E4llo world".length);
	assert(writeLength("h\u1000llo", '\u1000', "world") == "h\u1000llo\u1000world".length);
	auto test = "häl";
	assert(test.length == 4);
	assert(writeLength(test[0], test[1], test[2], test[3]) == test.length);
}
