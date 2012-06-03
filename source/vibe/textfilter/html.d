/**
	HTML character entity escaping.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.textfilter.html;

import std.array;
import std.conv;
import std.range;

private struct StringAppender {
	string data;
	void put(string s) { data ~= s; }
	void put(char ch) { data ~= ch; }
}

string htmlEscape(string str)
{
	if( __ctfe ){ // appender is a performance/memory hog in ctfe
		StringAppender dst;
		filterHtmlEscape(dst, str);
		return dst.data;
	} else {
		auto dst = appender!string();
		filterHtmlEscape(dst, str);
		return dst.data;
	}
}

void filterHtmlEscape(R)(ref R dst, string str)
{
	foreach( dchar ch; str )
		filterHtmlEscape(dst, ch, false);
}

string htmlAttribEscape(string str)
{
	if( __ctfe ){ // appender is a performance/memory hog in ctfe
		StringAppender dst;
		filterHtmlAttribEscape(dst, str);
		return dst.data;
	} else {
		auto dst = appender!string();
		filterHtmlAttribEscape(dst, str);
		return dst.data;
	}
}

void filterHtmlAttribEscape(R)(ref R dst, string str)
{
	foreach( dchar ch; str )
		filterHtmlEscape(dst, ch, true);
}

string filterHtmlAllEscape()(string str)
{
	if( __ctfe ){ // appender is a performance/memory hog in ctfe
		StringAppender dst;
		filterHtmlAllEscape(dst, str);
		return dst.data;
	} else {
		auto dst = appender!string();
		filterHtmlAllEscape(dst, str);
		return dst.data;
	}
}

void filterHtmlAllEscape(R)(ref R dst, string str)
{
	foreach( dchar ch; str ){
		dst.put("&#");
		dst.put(to!string(cast(int)ch)); 
		dst.put(';');
	}
}

void filterHtmlEscape(R)(ref R dst, dchar ch, bool escape_quotes = false)
{
	switch(ch){
		default:
			dst.put("&#");
			dst.put(to!string(cast(int)ch)); 
			dst.put(';');
			break;
		case '"':
			if( escape_quotes ) dst.put("&quot;");
			else dst.put('"');
			break;
		case 'a': .. case 'z': goto case;
		case 'A': .. case 'Z': goto case;
		case '0': .. case '9': goto case;
		case ' ', '\t', '-', '_', '.', ':', ',', ';',
		     '#', '+', '*', '?', '=', '(', ')', '/', '!',
		     '%' , '{', '}', '[', ']':
		    dst.put(cast(char)ch);
			break;
		case '<': dst.put("&lt;"); break;
		case '>': dst.put("&gt;"); break;
		case '&': dst.put("&amp;"); break;
	}
}

