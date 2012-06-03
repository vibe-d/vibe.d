/**
	URL-encode implementation

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger, Sönke Ludwig
*/
module vibe.textfilter.urlencode;

import std.array;
import std.conv;
import std.exception;
import std.format;


string urlEncode(string str)
{
	auto dst = appender!string();
	filterUrlEncode(dst, str);
	return dst.data;
}

string urlDecode(string str)
{
	auto dst = appender!string();
	filterUrlDecode(dst, str);
	return dst.data;
}

void filterUrlEncode(R)(ref R dst, string str) 
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
				formattedWrite(dst, "%%%x", str[0]);
		}
		str = str[1 .. $];
	}
}


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

