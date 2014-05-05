/**
	URL-encoding implementation

	Copyright: © 2012-2014 RejectedSoftware e.K.
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


/** Returns the URL encoded version of a given string.
*/
string urlEncode(string str, string allowed_chars = null)
@safe {
	auto dst = appender!string();
	dst.reserve(str.length);
	filterURLEncode(dst, str, allowed_chars);
	return dst.data;
}

/** Returns the decoded version of a given URL encoded string.
*/
string urlDecode(string str)
@safe {
	if (!str.anyOf("%")) return str;
	auto dst = appender!string();
	dst.reserve(str.length);
	filterURLDecode(dst, str);
	return dst.data;
}

/** Returns the form encoded version of a given string.

	Form encoding is the same as normal URL encoding, except that
	spaces are replaced by plus characters.

	Note that newlines should always be represented as \r\n sequences
	according to the HTTP standard.
*/
string formEncode(string str, string allowed_chars = null)
@safe {
	auto dst = appender!string();
	dst.reserve(str.length);
	filterURLEncode(dst, str, allowed_chars, true);
	return dst.data;
}

/** Returns the decoded version of a form encoded string.

	Form encoding is the same as normal URL encoding, except that
	spaces are replaced by plus characters.
*/
string formDecode(string str)
@safe {
	if (!str.anyOf("%+")) return str;
	auto dst = appender!string();
	dst.reserve(str.length);
	filterURLDecode(dst, str, true);
	return dst.data;
}

/** Writes the URL encoded version of the given string to an output range.
*/
void filterURLEncode(R)(ref R dst, string str, string allowed_chars = null, bool form_encoding = false) 
{
	while( str.length > 0 ) {
		switch(str[0]) {
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
			default:
				if (allowed_chars.canFind(str[0])) dst.put(str[0]);
				else formattedWrite(dst, "%%%02X", str[0]);
		}
		str = str[1 .. $];
	}
}


/** Writes the decoded version of the given URL encoded string to an output range.
*/
void filterURLDecode(R)(ref R dst, string str, bool form_encoding = false) 
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
	assert(urlEncode("This{is}test") == "This%7Bis%7Dtest", urlEncode("This{is}test"));
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
