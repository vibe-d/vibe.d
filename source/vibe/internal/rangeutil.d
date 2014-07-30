module vibe.internal.rangeutil;

struct RangeCounter {
	import std.utf;
	long* length;

	this(long* _captureLength) {
		length = _captureLength;
	}

	void put(dchar ch) { *length += codeLength!char(ch); }
	void put(string str) { *length += str.length; }
}
