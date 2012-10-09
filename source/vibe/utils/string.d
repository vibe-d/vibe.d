/**
	Utility functions for string processing

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.string;

public import std.string;

import std.algorithm;
import std.array;
import std.format;
import std.uni;
import std.utf;
import core.exception;


/**
	Takes a string with possibly invalid UTF8 sequences and outputs a valid UTF8 string as near to
	the original as possible.
*/
string sanitizeUTF8(in ubyte[] str)
{
	import std.utf;
	auto ret = appender!string();
	ret.reserve(str.length);

	size_t i = 0;
	while( i < str.length ){
		dchar ch = str[i];
		try ch = std.utf.decode(cast(string)str, i);
		catch( UTFException ){ i++; }
		catch( AssertError ){ i++; }
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
string stripUTF8Bom(string str)
{
	if( str.length >= 3 && str[0 .. 3] == [0xEF, 0xBB, 0xBF] )
		return str[3 ..$];
	return str;
}

/**
	Joins an array of strings using 'linesep' as the line separator (\n by default).
*/
string joinLines(string[] strs, string linesep = "\n")
{
	auto len = 0;
	foreach( i, s; strs ){
		if( i > 0 ) len += linesep.length;
		len += s.length;
	}
	auto ret = appender!string();
	ret.reserve(len);
	foreach( i, s; strs ){
		if( i > 0 ) ret.put(linesep);
		ret.put(s);
	}
	return ret.data;
}

/**
	Checks if all characters in 'str' are contained in 'chars'.
*/
bool allOf(string str, string chars)
{
	foreach( ch; str )
		if( chars.countUntil(ch) < 0 )
			return false;
	return true;
}

/**
	Checks if any character in 'str' is contained in 'chars'.
*/
bool anyOf(string str, string chars)
{
	foreach( ch; str )
		if( chars.countUntil(ch) >= 0 )
			return true;
	return false;
}

/// ASCII alpha character check
bool isAlpha(char ch)
{
	switch( ch ){
		default: return false;
		case 'a': .. case 'z'+1: break;
		case 'A': .. case 'Z'+1: break;
	}
	return true;
}

/// ASCII whitespace trimming (space and tab)
string stripLeftA(string s)
{
	while( s.length > 0 && (s[0] == ' ' || s[0] == '\t') )
		s = s[1 .. $];
	return s;
}

/// ASCII whitespace trimming (space and tab)
string stripRightA(string s)
{
	while( s.length > 0 && (s[$-1] == ' ' || s[$-1] == '\t') )
		s = s[0 .. $-1];
	return s;
}

/// ASCII whitespace trimming (space and tab)
string stripA(string s)
{
	return stripLeftA(stripRightA(s));
}

/// Finds the first occurence of any of the characters in `chars`
sizediff_t countUntilAny(string str, string chars)
{
	foreach( i, char ch; str )
		if( chars.countUntil(ch) >= 0 )
			return i;
	return -1;
}

/// Formats a string using formattedWrite() and returns it.
string formatString(ARGS...)(string format, ARGS args)
{
	auto dst = appender!string();
	formattedWrite(dst, format, args);
	return dst.data;
}

/// Special version of icmp() with optimization for ASCII characters
int icmp2(string a, string b)
{
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
				acp = toLower(acp);
				bcp = toLower(bcp);
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
