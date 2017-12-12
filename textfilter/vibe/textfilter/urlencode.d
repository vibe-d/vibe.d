/**
	URL-encoding implementation

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger, Sönke Ludwig
*/
module vibe.textfilter.urlencode;

import vibe.utils.string;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;


/**
 * Returns:
 *   the URL encoded version of a given string, in a newly-allocated string.
 */
T[] urlEncode(T)(T[] str, const(char)[] allowed_chars = null) if (is(T[] : const(char)[]))
{
	auto dst = StringSliceAppender!(T[])(str);
	filterURLEncode(dst, str, allowed_chars);
	return dst.data;
}

@safe unittest {
	string s = "hello-world";
	assert(s.urlEncode().ptr == s.ptr);
}

private auto isCorrectHexNum(const(char)[] str)
@safe {
	foreach (char c; str) {
		switch(c) {
			case '0': .. case '9':
			case 'A': .. case 'F':
			case 'a': .. case 'f':
				break;
			default:
				return false;
		}
	}
	return true;
}

/** Checks whether a given string has valid URL encoding.
*/
bool isURLEncoded(const(char)[] str, const(char)[] reserved_chars = null)
@safe {
	for (size_t i = 0; i < str.length; i++) {
		switch (str[i]) {
			case '-':
			case '.':
			case '0': .. case '9':
			case 'A': .. case 'Z':
			case '_':
			case 'a': .. case 'z':
			case '~':
				break;
			case '%':
				if (i + 2 >= str.length)
					return false;
				if (!isCorrectHexNum(str[i+1 .. i+3]))
					return false;
				i += 2;
				break;
			default:
				if (reserved_chars.canFind(str[i]))
					return false;
				break;
		}
	}
	return true;
}

@safe unittest {
	assert(isURLEncoded("hello-world"));
	assert(isURLEncoded("he%2F%af"));
	assert(!isURLEncoded("hello world", " "));
	assert(!isURLEncoded("he%f"));
	assert(!isURLEncoded("he%fx"));
}

/** Returns the decoded version of a given URL encoded string.
*/
T[] urlDecode(T)(T[] str) if (is(T[] : const(char)[]))
{
	if (!str.anyOf("%")) return str;
	auto dst = StringSliceAppender!(T[])(str);
	filterURLDecode(dst, str);
	return dst.data;
}

/** Returns the form encoded version of a given string.

	Form encoding is the same as normal URL encoding, except that
	spaces are replaced by plus characters.

	Note that newlines should always be represented as \r\n sequences
	according to the HTTP standard.
*/
T[] formEncode(T)(T[] str, const(char)[] allowed_chars = null) if (is(T[] : const(char)[]))
{
	auto dst = StringSliceAppender!(T[])(str);
	filterURLEncode(dst, str, allowed_chars, true);
	return dst.data;
}

/** Returns the decoded version of a form encoded string.

	Form encoding is the same as normal URL encoding, except that
	spaces are replaced by plus characters.
*/
T[] formDecode(T)(T[] str) if (is(T[] : const(char)[]))
{
	if (!str.anyOf("%+")) return str;
	auto dst = StringSliceAppender!(T[])(str);
	filterURLDecode(dst, str, true);
	return dst.data;
}

/** Writes the URL encoded version of the given string to an output range.
*/
void filterURLEncode(R)(ref R dst, const(char)[] str,
                        const(char)[] allowed_chars = null,
                        bool form_encoding = false)
{
	while (str.length > 0) {
		switch (str[0]) {
			default:
				if (allowed_chars.canFind(str[0])) dst.put(str[0]);
				else {
					static if (is(typeof({ R a, b; b = a; })))
						formattedWrite(dst, "%%%02X", str[0]);
					else
						formattedWrite(() @trusted { return &dst; } (), "%%%02X", str[0]);
				}
				break;
			case ' ':
				if (form_encoding) {
					dst.put('+');
					break;
				}
				goto default;
			case 'A': .. case 'Z':
			case 'a': .. case 'z':
			case '0': .. case '9':
			case '-': case '_': case '.': case '~':
				dst.put(str[0]);
				break;
		}
		str = str[1 .. $];
	}
}


/** Writes the decoded version of the given URL encoded string to an output range.
*/
void filterURLDecode(R)(ref R dst, const(char)[] str, bool form_encoding = false)
{
	while( str.length > 0 ) {
		switch(str[0]) {
			case '%':
				enforce(str.length >= 3, "invalid percent encoding");
				auto hex = str[1..3];
				auto c = cast(char)parse!int(hex, 16);
				enforce(hex.length == 0, "invalid percent encoding");
				dst.put(c);
				str = str[3 .. $];
				break;
			case '+':
				if (form_encoding) {
					dst.put(' ');
					str = str[1 .. $];
					break;
				}
				goto default;
			default:
				dst.put(str[0]);
				str = str[1 .. $];
				break;
		}
	}
}


@safe unittest
{
	assert(urlEncode("\r\n") == "%0D%0A"); // github #65
	assert(urlEncode("This-is~a_test") == "This-is~a_test");
	assert(urlEncode("This is a test") == "This%20is%20a%20test");
	assert(urlEncode("This{is}test") == "This%7Bis%7Dtest");
	assert(formEncode("This is a test") == "This+is+a+test");
	assert(formEncode("this/test", "/") == "this/test");
	assert(formEncode("this/test") == "this%2Ftest");
	assert(urlEncode("%") == "%25");
	assert(urlEncode("!") == "%21");
	assert(urlDecode("%0D%0a") == "\r\n");
	assert(urlDecode("%c2%aE") == "®");
	assert(urlDecode("This+is%20a+test") == "This+is a+test");
	assert(formDecode("This+is%20a+test") == "This is a test");

	string a = "This~is a-test!\r\nHello, Wörld.. ";
	string aenc = urlEncode(a);
	assert(aenc == "This~is%20a-test%21%0D%0AHello%2C%20W%C3%B6rld..%20");
	assert(urlDecode(urlEncode(a)) == a);
}


private struct StringSliceAppender(S) {
	private {
		Appender!S m_appender;
		S m_source;
		size_t m_prefixLength;
	}

	this(S source)
	{
		m_source = source;
		if (m_source.length == 0)
			m_appender = appender!S();
	}

	@disable this(this);

	void put(char ch)
	{
		if (m_source.length) {
			if (m_prefixLength < m_source.length && m_source[m_prefixLength] == ch) {
				m_prefixLength++;
				return;
			}

			m_appender = appender!S();
			m_appender.put(m_source[0 .. m_prefixLength]);
			m_appender.put(ch);
			m_source = S.init;
		} else m_appender.put(ch);
	}

	void put(S s)
	{
		if (m_source.length) {
			foreach (char ch; s)
				put(ch);
		} else m_appender.put(s);
	}

	void put(dchar ch)
	{
		import std.encoding : encode;
		char[6] chars;
		auto n = encode(ch, chars[]);
		foreach (char c; chars[0 .. n]) put(c);
	}

	@property S data()
	{
		return m_source.length ? m_source[0 .. m_prefixLength] : m_appender.data;
	}
}

@safe unittest {
	string s = "foo";
	auto a = StringSliceAppender!string(s);
	a.put("f"); assert(a.data == "f"); assert(a.data.ptr is s.ptr);
	a.put('o'); assert(a.data == "fo"); assert(a.data.ptr is s.ptr);
	a.put('o'); assert(a.data == "foo"); assert(a.data.ptr is s.ptr);
	a.put('ä'); assert(a.data == "fooä");

	a = StringSliceAppender!string(s);
	a.put('f'); assert(a.data == "f"); assert(a.data.ptr is s.ptr);
	a.put("oobar"); assert(a.data == "foobar");

	a = StringSliceAppender!string(s);
	a.put(cast(dchar)'f'); assert(a.data == "f"); assert(a.data.ptr is s.ptr);
	a.put('b'); assert(a.data == "fb");

	a = StringSliceAppender!string(s);
	a.put('f'); assert(a.data == "f"); assert(a.data.ptr is s.ptr);
	a.put("b"); assert(a.data == "fb");

	a = StringSliceAppender!string(s);
	a.put('f'); assert(a.data == "f"); assert(a.data.ptr is s.ptr);
	a.put("ä"); assert(a.data == "fä");

	a = StringSliceAppender!string(s);
	a.put("bar"); assert(a.data == "bar");

	a = StringSliceAppender!string(s);
	a.put('b'); assert(a.data == "b");

	a = StringSliceAppender!string(s);
	a.put('ä'); assert(a.data == "ä");

	a = StringSliceAppender!string(s);
	a.put("foo"); assert(a.data == "foo"); assert(a.data.ptr is s.ptr);
	a.put("bar"); assert(a.data == "foobar");

	a = StringSliceAppender!string(s);
	a.put("foo"); assert(a.data == "foo"); assert(a.data.ptr is s.ptr);
	a.put('b'); assert(a.data == "foob");
}
