/**
	Contains useful functions for template the template parser implementations.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.templ.parsertools;

import vibe.utils.string;

import std.traits;


struct Line {
	string file;
	int number;
	string text;
}


void assert_ln(in ref Line ln, bool cond, string text = null, string file = __FILE__, int line = __LINE__)
{
	assert(cond, "Error in template "~ln.file~" line "~_toString(ln.number)
		~": "~text~"("~file~":"~_toString(line)~")");
}


string unindent(in ref string str, in ref string indent)
{
	size_t lvl = indentLevel(str, indent);
	return str[lvl*indent.length .. $];
}

int indentLevel(in ref string s, in ref string indent)
{
	if( indent.length == 0 ) return 0;
	int l = 0;
	while( l+indent.length <= s.length && s[l .. l+indent.length] == indent )
		l += cast(int)indent.length;
	return l / cast(int)indent.length;
}


string lineMarker(in ref Line ln)
{
	if( ln.number < 0 ) return null;
	return "#line "~_toString(ln.number)~" \""~ln.file~"\"\n";
}


string dstringEscape(char ch)
{
	switch(ch){
		default: return ""~ch;
		case '\\': return "\\\\";
		case '\r': return "\\r";
		case '\n': return "\\n";
		case '\t': return "\\t";
		case '\"': return "\\\"";
	}
}

string sanitizeEscaping(string str)
{
	str = dstringUnescape(str);
	return dstringEscape(str);
}

string dstringEscape(in ref string str)
{
	string ret;
	foreach( ch; str ) ret ~= dstringEscape(ch);
	return ret;
}

string dstringUnescape(in string str)
{
	string ret;
	size_t i, start = 0;
	for( i = 0; i < str.length; i++ )
		if( str[i] == '\\' ){
			if( i > start ){
				if( start > 0 ) ret ~= str[start .. i];
				else ret = str[0 .. i];
			}
			assert(i+1 < str.length, "The string ends with the escape char: " ~ str);
			switch(str[i+1]){
				default: ret ~= str[i+1]; break;
				case 'r': ret ~= '\r'; break;
				case 'n': ret ~= '\n'; break;
				case 't': ret ~= '\t'; break;
			}
			i++;
			start = i+1;
		}

	if( i > start ){
		if( start == 0 ) return str;
		else ret ~= str[start .. i];
	}
	return ret;
}


string ctstrip(string s)
{
	size_t strt = 0, end = s.length;
	while( strt < s.length && (s[strt] == ' ' || s[strt] == '\t') ) strt++;
	while( end > 0 && (s[end-1] == ' ' || s[end-1] == '\t') ) end--;
	return strt < end ? s[strt .. end] : null;
}

string detectIndentStyle(in ref Line[] lines)
{
	// search for the first indented line
	foreach( i; 0 .. lines.length ){
		// empty lines should have been removed
		assert(lines[0].text.length > 0);

		// tabs are used
		if( lines[i].text[0] == '\t' ) return "\t";

		// spaces are used -> count the number
		if( lines[i].text[0] == ' ' ){
			size_t cnt = 0;
			while( lines[i].text[cnt] == ' ' ) cnt++;
			return lines[i].text[0 .. cnt];
		}
	}

	// default to tabs if there are no indented lines
	return "\t";
}

Line[] removeEmptyLines(string text, string file)
{
	text = stripUTF8Bom(text);

	Line[] ret;
	int num = 1;
	size_t idx = 0;

	while(idx < text.length){
		// start end end markers for the current line
		size_t start_idx = idx;
		size_t end_idx = text.length;

		// search for EOL
		while( idx < text.length ){
			if( text[idx] == '\r' || text[idx] == '\n' ){
				end_idx = idx;
				if( idx+1 < text.length && text[idx .. idx+2] == "\r\n" ) idx++;
				idx++;
				break;
			}
			idx++;
		}

		// add the line if not empty
		auto ln = text[start_idx .. end_idx];
		if( ctstrip(ln).length > 0 )
			ret ~= Line(file, num, ln);

		num++;
	}
	return ret;
}

/// private
private string _toString(T)(T x)
{
	static if( is(T == string) ) return x;
	else static if( is(T : long) || is(T : ulong) ){
		Unqual!T tmp = x;
		string s;
		do {
			s = cast(char)('0' + (tmp%10)) ~ s;
			tmp /= 10;
		} while(tmp > 0);
		return s;
	} else {
		static assert(false, "Invalid type for cttostring: "~T.stringof);
	}
}
