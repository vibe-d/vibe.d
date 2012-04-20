/**
	HTML character entity escaping.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.textfilter.html;

import std.array;
import std.conv;


string htmlEscape(string str)
{
	auto dst = appender!string();
	filterHtmlEscape(dst, str);
	return dst.data;
}

void filterHtmlEscape(R)(ref R dst, string str)
{
	foreach( dchar ch; str ){
		switch(ch){
			default:
				dst.put("&#");
				dst.put(to!string(cast(int)ch)); 
				dst.put(';');
				break;
			case 'a': .. case 'z': goto case;
			case 'A': .. case 'Z': goto case;
			case '0': .. case '9': goto case;
			case ' ', '\t', '-', '_', '.', ':', ',', ';',
			     '#', '+', '*', '?', '=', '(', ')', '/', '!':
			    dst.put(to!string(ch));
				break;
			case '\"': dst.put("&quot;"); break;
			case '<': dst.put("&lt;"); break;
			case '>': dst.put("&gt;"); break;
			case '&': dst.put("&amp;"); break;
		}
	}
}

string filterHtmlAllEscape()(string str)
{
	auto dst = appender!string();
	filterHtmlAllEscape(dst, str);
	return dst.data;
}

void filterHtmlAllEscape(R)(ref R dst, string str)
{
	foreach( dchar ch; str ){
		dst.put("&#");
		dst.put(to!string(cast(int)ch)); 
		dst.put(';');
	}
}
