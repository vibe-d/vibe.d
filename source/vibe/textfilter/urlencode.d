/**
	URL-encode implementation

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger, Sönke Ludwig
*/
module vibe.textfilter.urlencode;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.format;


/** Returns the URL encoded version of a given string.
*/
string urlEncode(string str)
{
	auto dst = appender!string();
	dst.reserve(str.length);
	filterUrlEncode(dst, str);
	return dst.data;
}

/** Returns the decoded version of a given URL encoded string.
*/
string urlDecode(string str)
{
	auto dst = appender!string();
	dst.reserve(str.length);
	filterUrlDecode(dst, str);
	return dst.data;
}

/** Writes the URL encoded version of the given string to an output range.
*/
void filterUrlEncode(R)(ref R dst, string str, string allowed_chars = null) 
{
	while( str.length > 0 ) {
		switch(str[0]) {
			case ' ':
				dst.put('+');
				break;
			case 'A': .. case 'Z'+1:
			case 'a': .. case 'z'+1:
			case '0': .. case '9'+1:
			case '-': case '_': case '.': case '~':
				dst.put(str[0]);
				break;
			default:
				if( allowed_chars.countUntil(str[0]) >= 0 ) dst.put(str[0]);
				else formattedWrite(dst, "%%%02X", str[0]);
		}
		str = str[1 .. $];
	}
}


/** Writes the decoded version of the given URL encoded string to an output range.
*/
void filterUrlDecode(R)(ref R dst, string str) 
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
				dst.put(' ');
				str = str[1 .. $];
				break;
			default:
				dst.put(str[0]);
				str = str[1 .. $];
		}
	}
}


unittest
{
	assert(urlEncode("\r\n") == "%0D%0A"); // github #65
	assert(urlEncode("This-is~a_test") == "This-is~a_test");
	assert(urlEncode("This is a test") == "This+is+a+test");
	assert(urlEncode("%") == "%25");
	assert(urlEncode("!") == "%21");
	assert(urlDecode("%0D%0a") == "\r\n");
	assert(urlDecode("%c2%aE") == "®");
	assert(urlDecode("This+is%20a+test") == "This is a test");

	string a = "This~is a-test!\r\nHello, Wörld.. ";
	string aenc = urlEncode(a);
	assert(aenc == "This~is+a-test%21%0D%0AHello%2C+W%C3%B6rld..+");
	assert(urlDecode(urlEncode(a)) == a);
}
