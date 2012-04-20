/**
	Implements a compile-time Diet template parser.

	Diet templates are an more or less compatible incarnation of Jade templates but with
	embedded D source instead of JavaScript. The Jade language specification is found at
	$(LINK https://github.com/visionmedia/jade) and provides a good overview of all the supported
	features, as well as some that are not yet implemented for Diet templates.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.templ.diet;

public import vibe.stream.stream;

import std.array;
import std.conv;
import std.format;
import std.metastrings;
import std.typecons;
import std.variant;

/*
	TODO:
		htmlEscape is necessary in a few places to avoid corrupted html (e.g. in buildInterpolatedString)
		to!string and htmlEscape should not be used in conjunction with ~ at run time. instead,
		use filterHtmlEncode().
*/


/**
	Parses the given diet template at compile time and writes the resulting
	HTML code into 'stream'.

	Note that this function currently suffers from multiple DMD bugs in conjunction with local
	variables passed as alias template parameters.
*/
void parseDietFile(string template_file, ALIASES...)(OutputStream stream__)
{
	// some imports to make available by default inside templates
	import vibe.http.common;
	import vibe.utils.string;

	pragma(msg, "Compiling diet template '"~template_file~"'...");
	//pragma(msg, localAliases!(0, ALIASES));
	mixin(localAliases!(0, ALIASES));

	// Generate the D source code for the diet template
	mixin(dietParser!template_file);
	#line 52 "diet.d"
}

/**
	Compatibility version of parseDietFile().

	This function should only be called indiretly through HttpServerResponse.renderCompat().

*/
void parseDietFileCompat(string template_file, TYPES_AND_NAMES...)(OutputStream stream__, Variant[] args__)
{
	// some imports to make available by default inside templates
	import vibe.http.common;
	import vibe.utils.string;

	pragma(msg, "Compiling diet template '"~template_file~"' (compat)...");
	//pragma(msg, localAliasesCompat!(0, TYPES_AND_NAMES));
	mixin(localAliasesCompat!(0, TYPES_AND_NAMES));

	// Generate the D source code for the diet template
	mixin(dietParser!template_file);
	#line 73 "diet.d"
}

private @property string dietParser(string template_file)()
{
	// Preprocess the source for extensions
	static immutable text = removeEmptyLines(import(template_file), template_file);
	static immutable extname = extractExtensionName(text);
	static if( extname.length > 0 ){
		static immutable parsed_file = extname;
		static immutable parsed_text = removeEmptyLines(import(extname), extname);
		static immutable blocks = extractBlocks(text, parsed_text);
	} else {
		static immutable parsed_file = template_file;
		static immutable parsed_text = text;
		static immutable DietBlock[] blocks = [];
	}

	DietParser parser;
	parser.lines = parsed_text;
	parser.blocks = blocks;
	return parser.buildWriter();
}

private template localAliases(int i, ALIASES...)
{
	static if( i < ALIASES.length ){
		enum string localAliases = "alias ALIASES["~cttostring(i)~"] "~__traits(identifier, ALIASES[i])~";\n"
			~localAliases!(i+1, ALIASES);
	} else {
		enum string localAliases = "";
	}
}

private template localAliasesCompat(int i, TYPES_AND_NAMES...)
{
	static if( i+1 < TYPES_AND_NAMES.length ){
		enum string localAliasesCompat = "auto "~TYPES_AND_NAMES[i+1]~" = *args__["~cttostring(i/2)~"].peek!(TYPES_AND_NAMES["~cttostring(i)~"])();\n"
			~localAliasesCompat!(i+2, TYPES_AND_NAMES);
	} else {
		enum string localAliasesCompat = "";
	}
}

private string extractExtensionName(in Line[] text)
{
	auto header = text[0].text;
	if( header.length >= 8 && header[0 .. 8] == "extends " )
		return header[8 .. header.length] ~ ".dt";
	return "";
}

private struct DietBlock {
	string name;
	Line[] text;
}

private struct Line {
	string file;
	int number;
	string text;
}

private void assert_ln(Line ln, bool cond, string text = null, string file = __FILE__, int line = __LINE__)
{
	assert(cond, "Error in template "~ln.file~" line "~cttostring(ln.number)~": "~text~"("~file~":"~cttostring(line)~")");
}



private DietBlock[] extractBlocks(in Line[] template_text, in Line[] parent_text)
{
	string[] names;
	DietBlock[] blocks;
	extractBlocksFromExtension(template_text[1 .. template_text.length], names, blocks);

	string[] used_names;
	extractBlocksFromParent(parent_text, used_names);

	DietBlock[] ret;
	foreach( name; used_names ){
		bool found = false;
		foreach( i; 0 .. names.length )
			if( names[i] == name ){
				ret ~= blocks[i];
				found = true;
				break;
			}
		if( !found ) ret ~= DietBlock(name, null); // empty block if not given
	}
	return ret;
}

private void extractBlocksFromExtension(in Line[] text, ref string[] names, ref DietBlock[] blocks)
{
	for( size_t i = 0; i < text.length; ){
		string ln = text[i].text;
		assert_ln(text[i], ln.length > 6 && ln[0 .. 6] == "block ",
			"Inside an extension template, only 'block' tags are allowed at root level.");
		auto name = ln[6 .. ln.length];
		i++;
		Line[] block;
		while( i < text.length ){
			auto bln = text[i];
			assert_ln(bln, bln.text.length > 0); // empty lines should be removed here!
			if( bln.text[0] != '\t' ) break;
			block ~= bln;
			i++;
		}
		names ~= name;
		blocks ~= DietBlock(name, block);
	}
}

private void extractBlocksFromParent(in Line[] text, ref string[] names)
{
	for( size_t i = 0; i < text.length; i++ ){
		string ln = unindent(text[i].text);
		if( ln.length > 6 && ln[0 .. 6] == "block " ){
			auto name = ln[6 .. ln.length];
			names ~= name;		
		}
	}
}

private string lineMarker(Line ln)
{
	return "#line "~cttostring(ln.number)~" \""~ln.file~"\"\n";
}


private enum string StreamVariableName = "stream__";

private struct DietParser {
	private {
		size_t curline = 0;
		const(Line)[] lines;
		const(DietBlock)[] blocks;
	}

	this(in Line[] lines_, in DietBlock[] blocks_)
	{
		this.lines = lines_;
		this.blocks = blocks_;
	}

	string buildWriter()
	{
		const header = lines[curline].text;
		assertp(header == "!!! 5", "Only HTML 5 is supported ('!!! 5')!");
		string ret = lineMarker(lines[curline]);
		ret ~= StreamVariableName ~ ".write(\"<!DOCTYPE html>";
		bool in_string = true;
		string[] node_stack;
		curline++;

		auto next_indent_level = indentLevel(lines[curline].text);
		assertp(next_indent_level == 0, "Indentation must start at level zero.");

		ret ~= buildBodyWriter(node_stack, next_indent_level, in_string);
		
		ret ~= endString(in_string);
		
		assert(node_stack.length == 0);

		return ret;
	}

	void assertp(bool cond, string text = null, string file = __FILE__, int line = __LINE__)
	{
		Line ln;
		if( curline < lines.length ) ln = lines[curline];
		assert(cond, "template "~ln.file~" line "~cttostring(ln.number)~": "~text~"("~file~":"~cttostring(line)~")");
	}

	string buildBodyWriter(ref string[] node_stack, int base_level, ref bool in_string)
	{
		string ret;
		size_t blockidx = 0;

		assertp(node_stack.length >= base_level);

		for( ; curline < lines.length; curline++ ){
			auto current_line = lines[curline];

			if( !in_string ) ret ~= lineMarker(lines[curline]);
			auto level = indentLevel(lines[curline].text) + base_level;
			assertp(level <= node_stack.length+1);
			auto ln = unindent(lines[curline].text);
			assertp(ln.length > 0);
			int next_indent_level = (curline+1 < lines.length ? indentLevel(lines[curline+1].text) : 0) + base_level;

			assertp(node_stack.length >= level, cttostring(node_stack.length) ~ ">=" ~ cttostring(level));
			assertp(next_indent_level <= level+1, "Indentations may not skip child levels.");

			if( ln[0] == '-' ) ret ~= buildCodeNodeWriter(node_stack, ln[1 .. ln.length], level, in_string);
			else if( ln[0] == '|' ) ret ~= buildTextNodeWriter(node_stack, ln[1 .. ln.length], level, in_string);
			else {
				size_t j = 0;
				auto tag = isAlpha(ln[0]) || ln[0] == '/' ? skipIdent(ln, j, "/:-_") : "div";
				switch(tag){
					default:
						ret ~= buildHtmlNodeWriter(node_stack, tag, ln[j .. $], level, in_string, next_indent_level > level);
						break;
					case "block":
						// if this assertion triggers, we are probably inside a block and the block tries to insert another block
						assertp(!blocks.length || blockidx < blocks.length, "Blocks inside of extensions are not supported.");
						// but this should never happen:
						assertp(blockidx < blocks.length, "Less blocks than in template?!");
						node_stack ~= "-";
						if( blocks[blockidx].text.length ){
							DietParser parser;
							parser.lines = blocks[blockidx].text;
							ret ~= endString(in_string);
							ret ~= lineMarker(blocks[blockidx].text[0]);
							ret ~= parser.buildBodyWriter(node_stack, level, in_string);
						}
						blockidx++;
						break;
					case "//if":
						skipWhitespace(ln, j);
						ret ~= buildSpecialTag!(node_stack)("!--[if "~ln[j .. $]~"]", level, in_string);
						node_stack ~= "<![endif]-->";
						break;
					case "//":
					case "//-":
					case "each":
					case "for":
					case "if":
					case "unless":
					case "mixin":
					case "include":
						assertp(false, "'"~tag~"' is not supported.");
				}
			}
			
			// close all tags/blocks until we reach the level of the next line
			while( node_stack.length > next_indent_level ){
				if( node_stack[$-1][0] == '-' ){
					if( node_stack[$-1].length > 1 ){
						ret ~= endString(in_string);
						ret ~= node_stack[$-1][1 .. $] ~ "\n";
					}
				} else if( node_stack[$-1].length ){
					string str;
					if( node_stack[$-1] != "pre" ){
						str = "\n";
						foreach( j; 0 .. node_stack.length-1 ) if( node_stack[j][0] != '-' ) str ~= "\t";
					}
					str ~= node_stack[$-1][0] == '<' ? node_stack[$-1] : "</" ~ node_stack[$-1] ~ ">";
					ret ~= startString(in_string);
					ret ~= dstringEscape(str);
				}
				node_stack = node_stack[0 .. $-1];
			}
		}

		return ret;
	}

	string buildCodeNodeWriter(ref string[] node_stack, string line, int level, ref bool in_string)
	{
		string ret = endString(in_string) ~ ctstrip(line) ~ "{\n";
		node_stack ~= "-}";
		return ret;
	}

	string buildTextNodeWriter(ref string[] node_stack, string line, int level, ref bool in_string)
	{
		string ret;
		ret = endString(in_string);
		ret ~= StreamVariableName ~ ".write(\"\\n\", false);\n";
		if( line.length >= 1 && line[0] == '=' ){
			ret ~= StreamVariableName ~ ".write(htmlEscape(toString(";
			ret ~= line[1 .. $];
			ret ~= ")";
		} else if( line.length >= 2 && line[0 .. 2] == "!=" ){
			ret ~= StreamVariableName ~ ".write(toString(";
			ret ~= line[2 .. $];
		} else {
			ret ~= StreamVariableName ~ ".write(htmlEscape(";
			ret ~= buildInterpolatedString(line, false, false);
		}
		ret ~= "), false);\n";
		node_stack ~= "-";
		return ret;
	}

	string buildHtmlNodeWriter(ref string[] node_stack, string tag, string line, int level, ref bool in_string, bool has_child_nodes)
	{
		size_t i = 0;

		bool has_children = true;
		switch(tag){
			case "br", "hr", "img", "link":
				has_children = false;
				break;
			default:
		}

		assertp(has_children || !has_child_nodes, "Singular HTML tag '"~tag~"' may now have children.");

		string id;
		string classes;
		
		// parse #id and .classes
		while( i < line.length ){
			if( line[i] == '#' ){
				i++;
				assertp(id.length == 0, "Id may only be set once.");
				id = skipIdent(line, i, "-");
			} else if( line[i] == '.' ){
				i++;
				auto cls = skipIdent(line, i, "-");
				if( classes.length == 0 ) classes = cls;
				else classes ~= " " ~ cls;
			} else break;
		}
		
		// put #id and .classes into the attribs list
		Tuple!(string, string)[] attribs;
		if( id.length ) attribs ~= tuple("id", id);
		if( classes.length ) attribs ~= tuple("class", classes);
		
		// parse other attributes
		if( i < line.length && line[i] == '(' ){
			i++;
			string attribstring = skipUntilClosingClamp(line, i);
			parseAttributes(attribstring, attribs);
			i++;
		}

		// write the tag
		string tagstring = "\\n";
		assertp(node_stack.length >= level);
		foreach( j; 0 .. level ) if( node_stack[j][0] != '-' ) tagstring ~= "\\t";
		tagstring ~= "<" ~ tag;
		foreach( att; attribs ) tagstring ~= " "~att[0]~"=\\\"\"~htmlAttribEscape("~buildInterpolatedString(att[1])~")~\"\\\"";
		tagstring ~= ">";
		
		skipWhitespace(line, i);

		// parse any text contents (either using "= code" or as plain text)
		string textstring;
		bool textstring_isdynamic = true;
		if( i < line.length && line[i] == '=' ){
			textstring = "htmlEscape(toString("~ctstrip(line[i+1 .. line.length])~"))";
		} else if( i+1 < line.length && line[i .. i+2] == "!=" ){
			textstring = "toString("~ctstrip(line[i+2 .. line.length])~")";
		} else {
			if( hasInterpolations(line[i .. line.length]) ){
				textstring = "htmlEscape("~buildInterpolatedString(line[i .. line.length], false, false)~")";
			} else {
				textstring = dstringEscape(htmlEscape(line[i .. line.length]));
				textstring_isdynamic = false;
			}
		}
		
		string tail;
		if( has_child_nodes || !has_children ) tail = "";
		else tail = "</" ~ tag ~ ">";
		
		if( has_child_nodes ) node_stack ~= tag;
		
		string ret = startString(in_string) ~ tagstring;
		if( textstring_isdynamic ){
			ret ~= endString(in_string);
			ret ~= StreamVariableName~".write(" ~ textstring ~ ", false);\n";
		} else ret ~= textstring;
		if( tail.length ) ret ~= startString(in_string) ~ tail;
			
		return ret;
	}

	void parseAttributes(string str, ref Tuple!(string, string)[] attribs)
	{
		size_t i = 0;
		skipWhitespace(str, i);
		while( i < str.length ){
			string name = skipIdent(str, i, "-:");
			string value;
			skipWhitespace(str, i);
			if( str[i] == '=' ){
				i++;
				skipWhitespace(str, i);
				assertp(i < str.length, "'=' must be followed by attribute string.");
				assertp(str[i] == '\'' || str[i] == '"', "Expecting ''' or '\"' following '='.");
				auto delimiter = str[i];
				i++;
				value = skipAttribString(str, i, delimiter);
				i++;
				skipWhitespace(str, i);
			}
			
			assertp(i == str.length || str[i] == ',', "Unexpected text following attribute: '"~str~"'");
			if( i < str.length ){
				i++;
				skipWhitespace(str, i);
			}

			attribs ~= tuple(name, value);
		}
	}

	bool hasInterpolations(string str)
	{
		size_t i = 0;
		while( i < str.length ){
			if( str[i] == '#' ){
				if( str[i+1] == '#' ){
					i += 2;
				} else {
					assertp(str[i+1] == '{', "# must be followed by '{' or '#'.");
					return true;
				}
			} else i++;
		}
		return false;
	}

	string buildInterpolatedString(string str, bool prevconcat = false, bool nextconcat = false)
	{
		string ret;
		int state = 0; // 0 == start, 1 == in string, 2 == out of string
		static immutable enter_string = ["\"", "", "~\""];
		static immutable enter_non_string = ["", "\"~", "~"];
		static immutable exit_string = ["", "\"", ""];
		size_t start = 0, i = 0;
		while( i < str.length ){
			if( str[i] == '#' ){
				if( i > start ){
					ret ~= enter_string[state] ~ dstringEscape(str[start .. i]);
					state = 1;
				}
				if( str[i+1] == '#' ){
					ret ~= enter_string[state] ~ "#";
					state = 1;
					i += 2;
					start = i;
				} else if( str[i+1] == '{' ){
					i += 2;
					ret ~= enter_non_string[state];
					state = 2;
					ret ~= "toString(" ~ skipUntilClosingBrace(str, i) ~ ")";
					i++;
					start = i;
				} else assertp(false, "# must be followed by '{' or '#'.");
			} else i++;
		}
		if( i > start ){
			ret ~= enter_string[state] ~ dstringEscape(str[start .. i]);
			state = 1;
		}
		ret ~= exit_string[state];

		if( ret.length == 0 ){
			if( prevconcat && nextconcat ) return "~";
			else if( !prevconcat && !nextconcat ) return "\"\"";
			else return "";
		}
		return (prevconcat?"~":"") ~ ret ~ (nextconcat?"~":"");
	}

	string skipIdent(string s, ref size_t idx, string additional_chars = null)
	{
		size_t start = idx;
		while( idx < s.length ){
			if( isAlpha(s[idx]) ) idx++;
			else if( start != idx && s[idx] >= '0' && s[idx] <= '9' ) idx++;
			else {
				bool found = false;
				foreach( ch; additional_chars )
					if( s[idx] == ch ){
						found = true;
						idx++;
						break;
					}
				if( !found ){
					assertp(start != idx, "Expected identifier but got '"~s[idx]~"'.");
					return s[start .. idx];
				}
			}
		}
		assertp(start != idx, "Expected identifier but got nothing.");
		return s[start .. idx];
	}

	string skipWhitespace(string s, ref size_t idx)
	{
		size_t start = idx;
		while( idx < s.length ){
			if( s[idx] == ' ' ) idx++;
			else break;
		}
		return s[start .. idx];
	}

	string skipUntilClosingBrace(string s, ref size_t idx)
	{
		int level = 0;
		auto start = idx;
		while( idx < s.length ){
			if( s[idx] == '{' ) level++;
			else if( s[idx] == '}' ) level--;
			if( level < 0 ) return s[start .. idx];
			idx++;
		}
		assertp(false, "Missing closing brace");
		assert(false);
	}

	string skipUntilClosingClamp(string s, ref size_t idx)
	{
		int level = 0;
		auto start = idx;
		while( idx < s.length ){
			if( s[idx] == '(' ) level++;
			else if( s[idx] == ')' ) level--;
			if( level < 0 ) return s[start .. idx];
			idx++;
		}
		assertp(false, "Missing closing clamp");
		assert(false);
	}

	string skipAttribString(string s, ref size_t idx, char delimiter)
	{
		size_t start = idx;
		string ret;
		while( idx < s.length ){
			if( s[idx] == '\\' ){
				idx++;
				assertp(idx < s.length, "'\\' must be followed by something (escaped character)!");
				ret ~= s[idx];
			} else if( s[idx] == delimiter ) break;
			else ret ~= s[idx];
			idx++;
		}
		return ret;
	}
}


private string buildSpecialTag(alias node_stack)(string tag, int level, ref bool in_string)
{
	// write the tag
	string tagstring = "\\n";
	foreach( j; 0 .. level ) if( node_stack[j][0] != '-' ) tagstring ~= "\\t";
	tagstring ~= "<" ~ tag ~ ">";

	return startString(in_string) ~ tagstring;
}

private @property string startString(ref bool in_string){
	auto ret = in_string ? "" : StreamVariableName ~ ".write(\"";
	in_string = true;
	return ret;
}

private @property string endString(ref bool in_string){
	auto ret = in_string ? "\", false);\n" : "";
	in_string = false;
	return ret;
}





private string dstringEscape(char ch)
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
private string dstringEscape(string str)
{
	string ret;
	foreach( ch; str ) ret ~= dstringEscape(ch);
	return ret;
}

private string htmlAttribEscape(dchar ch)
{
	switch(ch){
		default: return htmlEscape(ch);
		case '\"': return "&quot;";
	}
}
private string htmlAttribEscape(string str)
{
	string ret;
	foreach( dchar ch; str ) ret ~= htmlAttribEscape(ch);
	return ret;
}

private string htmlEscape(dchar ch)
{
	switch(ch){
		default: return "&#" ~ cttostring(ch) ~ ";";
		case 'a': .. case 'z': goto case;
		case 'A': .. case 'Z': goto case;
		case '0': .. case '9': goto case;
		case ' ', '\t', '-', '_', '.', ':', ',', ';',
		     '#', '+', '*', '?', '=', '(', ')', '/', '!':
			return to!string(ch);
		case '\"': return "&quot;";
		case '<': return "&lt;";
		case '>': return "&gt;";
		case '&': return "&amp;";
	}
}
private string htmlEscape(string str)
{
	if( __ctfe ){
		string ret;
		foreach( dchar ch; str ) ret ~= htmlEscape(ch);
		return ret;
	} else {
		auto ret = appender!string();
		foreach( dchar ch; str ) ret.put(htmlEscape(ch));
		return ret.data;
	}
}



private string unindent(string str)
{
	size_t i = 0;
	while( i < str.length && str[i] == '\t' ) i++;
	return str[i .. str.length];
}

private int indentLevel(string s)
{
	int l = 0;
	while( l < s.length && s[l] == '\t' ) l++;
	return l;
}

private int indentLevel(in Line[] ln)
{
	return ln.length == 0 ? 0 : indentLevel(ln[0].text);
}

private bool isAlpha(char ch)
{
	switch( ch ){
		default: return false;
		case 'a': .. case 'z'+1: break;
		case 'A': .. case 'Z'+1: break;
	}
	return true;
}

/*private bool isAlphanum(char ch)
{
	switch( ch ){
		default: return false;
		case 'a': .. case 'z'+1: break;
		case 'A': .. case 'Z'+1: break;
		case '0': .. case '9'+1: break;
		case '_': break;
	}
	return true;
}*/

/*private bool isWhitespace(char ch)
{
	return ch == ' ';
}*/

private string toString(T)(T v)
{
	static if( is(T == string) ) return v;
	else static if( __traits(compiles, v.opCast!string()) ) return cast(string)v;
	else static if( __traits(compiles, v.toString()) ) return v.toString();
	else return to!string(v);
}

private string ctstrip(string s)
{
	size_t strt = 0, end = s.length;
	while( strt < s.length && s[strt] == ' ' ) strt++;
	while( end > 0 && s[end-1] == ' ' ) end--;
	return strt < end ? s[strt .. end] : null;
}

private string cttostring(T)(T x)
{
	static if( is(T == string) ) return x;
	else static if( is(T : long) || is(T : ulong) ){
		string s;
		do {
			s = cast(char)('0' + (x%10)) ~ s;
			x /= 10;
		} while (x>0);
		return s;
	} else {
		static assert(false, "Invalid type for cttostring: "~T.stringof);
	}
}

private string firstLine(string str)
{
	foreach( i; 0 .. str.length )
		if( str[i] == '\r' || str[i] == '\n' )
			return str[0 .. i];
	return str;
}

private string remainingLines(string str)
{
	for( size_t i = 0; i < str.length; i++ )
		if( str[i] == '\r' || str[i] == '\n' ){
			if( i+1 < str.length && (str[i+1] == '\n' || str[i+1] == '\r') && str[i] != str[i+1] )
				i++;
			return str[i+1 .. $];
		}
	return null;
}

private Line[] removeEmptyLines(string text, string file)
{
	Line[] ret;
	int num = 1;
	while(text.length > 0){
		auto ln = firstLine(text);
		if( unindent(ln).length > 0 ){
			ret ~= Line(file, num, ln);
		}
		text = remainingLines(text);
		num++;
	}
	return ret;
}
