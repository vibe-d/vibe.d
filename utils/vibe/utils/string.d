/**
	Utility functions for string processing

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.string;

public import std.string;

import vibe.utils.array;
import vibe.internal.utilallocator;

import std.algorithm;
import std.array;
import std.ascii;
import std.format;
import std.uni;
import std.utf;
import core.exception;


/**
	Takes a string with possibly invalid UTF8 sequences and outputs a valid UTF8 string as near to
	the original as possible.
*/
string sanitizeUTF8(in ubyte[] str)
@safe pure {
	import std.utf;
	auto ret = appender!string();
	ret.reserve(str.length);

	size_t i = 0;
	while (i < str.length) {
		dchar ch = str[i];
		try ch = std.utf.decode(cast(const(char[]))str, i);
		catch( UTFException ){ i++; }
		//catch( AssertError ){ i++; }
		char[4] dst;
		auto len = std.utf.encode(dst, ch);
		ret.put(dst[0 .. len]);
	}

	return ret.data;
}

/**
	Strips the byte order mark of an UTF8 encoded string.
	This is useful when the string is coming from a file.
*/
inout(char)[] stripUTF8Bom(inout(char)[] str)
@safe pure nothrow {
	if (str.length >= 3 && str[0 .. 3] == [0xEF, 0xBB, 0xBF])
		return str[3 ..$];
	return str;
}


/**
	Checks if all characters in 'str' are contained in 'chars'.
*/
bool allOf(const(char)[] str, const(char)[] chars)
@safe pure {
	foreach (dchar ch; str)
		if (!chars.canFind(ch))
			return false;
	return true;
}

ptrdiff_t indexOfCT(Char)(in Char[] s, dchar c, CaseSensitive cs = CaseSensitive.yes)
@safe pure {
	if (__ctfe) {
		if (cs == CaseSensitive.yes) {
			foreach (i, dchar ch; s)
				if (ch == c)
					return i;
		} else {
			c = std.uni.toLower(c);
			foreach (i, dchar ch; s)
				if (std.uni.toLower(ch) == c)
					return i;
		}
		return -1;
	} else return std.string.indexOf(s, c, cs);
}
ptrdiff_t indexOfCT(Char)(in Char[] s, in Char[] needle)
{
	if (__ctfe) {
		if (s.length < needle.length) return -1;
		foreach (i; 0 .. s.length - needle.length)
			if (s[i .. i+needle.length] == needle)
				return i;
		return -1;
	} else return std.string.indexOf(s, needle);
}

/**
	Checks if any character in 'str' is contained in 'chars'.
*/
bool anyOf(const(char)[] str, const(char)[] chars)
@safe pure {
	foreach (ch; str)
		if (chars.canFind(ch))
			return true;
	return false;
}


/// ASCII whitespace trimming (space and tab)
inout(char)[] stripLeftA(inout(char)[] s)
@safe pure nothrow {
	while (s.length > 0 && (s[0] == ' ' || s[0] == '\t'))
		s = s[1 .. $];
	return s;
}

/// ASCII whitespace trimming (space and tab)
inout(char)[] stripRightA(inout(char)[] s)
@safe pure nothrow {
	while (s.length > 0 && (s[$-1] == ' ' || s[$-1] == '\t'))
		s = s[0 .. $-1];
	return s;
}

/// ASCII whitespace trimming (space and tab)
inout(char)[] stripA(inout(char)[] s)
@safe pure nothrow {
	return stripLeftA(stripRightA(s));
}

/// Finds the first occurence of any of the characters in `chars`
sizediff_t indexOfAny(const(char)[] str, const(char)[] chars)
@safe pure {
	foreach (i, char ch; str)
		if (chars.canFind(ch))
			return i;
	return -1;
}
alias countUntilAny = indexOfAny;

/**
	Finds the closing bracket (works with any of '[', '$(LPAREN)', '<', '{').

	Params:
		str = input string
		nested = whether to skip nested brackets
	Returns:
		The index of the closing bracket or -1 for unbalanced strings
		and strings that don't start with a bracket.
*/
sizediff_t matchBracket(const(char)[] str, bool nested = true)
@safe pure nothrow {
	if (str.length < 2) return -1;

	char open = str[0], close = void;
	switch (str[0]) {
		case '[': close = ']'; break;
		case '(': close = ')'; break;
		case '<': close = '>'; break;
		case '{': close = '}'; break;
		default: return -1;
	}

	size_t level = 1;
	foreach (i, char c; str[1 .. $]) {
		if (nested && c == open) ++level;
		else if (c == close) --level;
		if (level == 0) return i + 1;
	}
	return -1;
}

@safe unittest
{
	static struct Test { string str; sizediff_t res; }
	enum tests = [
		Test("[foo]", 4), Test("<bar>", 4), Test("{baz}", 4),
		Test("[", -1), Test("[foo", -1), Test("ab[f]", -1),
		Test("[foo[bar]]", 9), Test("[foo{bar]]", 8),
	];
	foreach (test; tests)
		assert(matchBracket(test.str) == test.res);
	assert(matchBracket("[foo[bar]]", false) == 8);
	static assert(matchBracket("[foo]") == 4);
}

/// Same as std.string.format, just using an allocator.
string formatAlloc(ARGS...)(IAllocator alloc, string fmt, ARGS args)
{
	auto app = AllocAppender!string(alloc);
	formattedWrite(() @trusted { return &app; } (), fmt, args);
	return () @trusted { return app.data; } ();
}

/// Special version of icmp() with optimization for ASCII characters
int icmp2(const(char)[] a, const(char)[] b)
@safe pure {
	size_t i = 0, j = 0;

	// fast skip equal prefix
	size_t min_len = min(a.length, b.length);
	while( i < min_len && a[i] == b[i] ) i++;
	if( i > 0 && (a[i-1] & 0x80) ) i--; // don't stop half-way in a UTF-8 sequence
	j = i;

	// compare the differing character and the rest of the string
	while(i < a.length && j < b.length){
		uint ac = cast(uint)a[i];
		uint bc = cast(uint)b[j];
		if( !((ac | bc) & 0x80) ){
			i++;
			j++;
			if( ac >= 'A' && ac <= 'Z' ) ac += 'a' - 'A';
			if( bc >= 'A' && bc <= 'Z' ) bc += 'a' - 'A';
			if( ac < bc ) return -1;
			else if( ac > bc ) return 1;
		} else {
			dchar acp = decode(a, i);
			dchar bcp = decode(b, j);
			if( acp != bcp ){
				acp = std.uni.toLower(acp);
				bcp = std.uni.toLower(bcp);
				if( acp < bcp ) return -1;
				else if( acp > bcp ) return 1;
			}
		}
	}

	if( i < a.length ) return 1;
	else if( j < b.length ) return -1;

	assert(i == a.length || j == b.length, "Strings equal but we didn't fully compare them!?");
	return 0;
}
