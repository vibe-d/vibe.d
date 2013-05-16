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


/** Returns the HTML escaped version of a given string.
*/
string htmlEscape(string str)
{
	if( __ctfe ){ // appender is a performance/memory hog in ctfe
		StringAppender dst;
		filterHTMLEscape(dst, str);
		return dst.data;
	} else {
		auto dst = appender!string();
		filterHTMLEscape(dst, str);
		return dst.data;
	}
}


/** Writes the HTML escaped version of a given string to an output range.
*/
void filterHTMLEscape(R)(ref R dst, string str)
{
	foreach( dchar ch; str )
		filterHTMLEscape(dst, ch, HTMLEscapeFlags.escapeNewline);
}

/// Compatibility alias, will be deprecated soon.
alias filterHtmlEscape = filterHTMLEscape;


/** Returns the HTML escaped version of a given string (also escapes double quotes).
*/
string htmlAttribEscape(string str)
{
	if( __ctfe ){ // appender is a performance/memory hog in ctfe
		StringAppender dst;
		filterHTMLAttribEscape(dst, str);
		return dst.data;
	} else {
		auto dst = appender!string();
		filterHTMLAttribEscape(dst, str);
		return dst.data;
	}
}

/** Writes the HTML escaped version of a given string to an output range (also escapes double quotes).
*/
void filterHTMLAttribEscape(R)(ref R dst, string str)
{
	foreach( dchar ch; str )
		filterHTMLEscape(dst, ch, HTMLEscapeFlags.escapeNewline|HTMLEscapeFlags.escapeQuotes);
}

/// Compatibility alias, will be deprecated soon.
alias filterHtmlAttribEscape = filterHTMLAttribEscape;


/** Returns the HTML escaped version of a given string (escapes every character).
*/
string htmlAllEscape()(string str)
{
	if( __ctfe ){ // appender is a performance/memory hog in ctfe
		StringAppender dst;
		filterHTMLAllEscape(dst, str);
		return dst.data;
	} else {
		auto dst = appender!string();
		filterHTMLAllEscape(dst, str);
		return dst.data;
	}
}

/** Writes the HTML escaped version of a given string to an output range (escapes every character).
*/
void filterHTMLAllEscape(R)(ref R dst, string str)
{
	foreach( dchar ch; str ){
		dst.put("&#");
		dst.put(to!string(cast(int)ch)); 
		dst.put(';');
	}
}

/// Compatibility alias, will be deprecated soon.
alias filterHtmlAllEscape = filterHTMLAllEscape;


/**
	Minimally escapes a text so that no HTML tags appear in it.
*/
string htmlEscapeMin(string str)
{
	auto dst = appender!string();
	foreach( dchar ch; str )
		filterHTMLEscape(dst, ch, HTMLEscapeFlags.escapeMinimal);
	return dst.data();
}


/**
	Writes the HTML escaped version of a character to an output range.
*/
void filterHTMLEscape(R)(ref R dst, dchar ch, HTMLEscapeFlags flags = HTMLEscapeFlags.escapeNewline )
{
	switch(ch){
		default:
			if( flags & HTMLEscapeFlags.escapeUnknown ){
				dst.put("&#");
				dst.put(to!string(cast(int)ch)); 
				dst.put(';');
			} else dst.put(ch);
			break;
		case '"':
			if( flags & HTMLEscapeFlags.escapeQuotes ) dst.put("&quot;");
			else dst.put('"');
			break;
		case '\r', '\n':
			if( flags & HTMLEscapeFlags.escapeNewline ){
				dst.put("&#");
				dst.put(to!string(cast(int)ch)); 
				dst.put(';');
			} else dst.put(ch);
			break; 
		case 'a': .. case 'z': goto case;
		case 'A': .. case 'Z': goto case;
		case '0': .. case '9': goto case;
		case ' ', '\t', '-', '_', '.', ':', ',', ';',
		     '#', '+', '*', '?', '=', '(', ')', '/', '!',
		     '%' , '{', '}', '[', ']', '`', '´', '$', '^', '~':
		    dst.put(cast(char)ch);
			break;
		case '<': dst.put("&lt;"); break;
		case '>': dst.put("&gt;"); break;
		case '&': dst.put("&amp;"); break;
	}
}


enum HTMLEscapeFlags {
	escapeMinimal = 0,
	escapeQuotes = 1<<0,
	escapeNewline = 1<<1,
	escapeUnknown = 1<<2
}

/// Compatibility alias, will be deprecated soon.
alias HtmlEscapeFlags = HTMLEscapeFlags;

private struct StringAppender {
	string data;
	void put(string s) { data ~= s; }
	void put(char ch) { data ~= ch; }
	void put(dchar ch) {
		import std.utf;
		char[4] dst;
		data ~= dst[0 .. encode(dst, ch)];
	}
}
