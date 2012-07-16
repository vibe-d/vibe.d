/**
	Implements a compile-time Diet template parser.

	Diet templates are an more or less compatible incarnation of Jade templates but with
	embedded D source instead of JavaScript. The Diet syntax reference is found at
	$(LINK http://vibed.org/templates).

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.templ.diet;

public import vibe.stream.stream;

import vibe.core.file;
import vibe.templ.utils;
import vibe.textfilter.html;
import vibe.textfilter.markdown;
import vibe.utils.string;

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
	#line 57 "diet.d"
}

/**
	Compatibility version of parseDietFile().

	This function should only be called indiretly through HttpServerResponse.renderCompat().

*/
void parseDietFileCompat(string template_file, TYPES_AND_NAMES...)(OutputStream stream__, Variant[] args__...)
{
	// some imports to make available by default inside templates
	import vibe.http.common;
	import vibe.utils.string;

	pragma(msg, "Compiling diet template '"~template_file~"' (compat)...");
	//pragma(msg, localAliasesCompat!(0, TYPES_AND_NAMES));
	mixin(localAliasesCompat!(0, TYPES_AND_NAMES));

	// Generate the D source code for the diet template
	mixin(dietParser!template_file);
	#line 78 "diet.d"
}

/**
	Registers a new text filter for use in Diet templates.

	The filter will be available using :filtername inside of the template. The following filters are
	predefined: css, javascript, markdown
*/
void registerDietTextFilter(string name, string function(string, int indent) filter)
{
	s_filters[name] = filter;
}

/**************************************************************************************************/
/* private functions                                                                              */
/**************************************************************************************************/

private {
	string function(string, int indent)[string] s_filters;
}

static this()
{
	registerDietTextFilter("css", &filterCSS);
	registerDietTextFilter("javascript", &filterJavaScript);
	registerDietTextFilter("markdown", &filterMarkdown);
}

private @property string dietParser(string template_file)()
{
	// Preprocess the source for extensions
	static immutable text = removeEmptyLines(import(template_file), template_file);
	static immutable text_indent_style = detectIndentStyle(text);
	static immutable extname = extractExtensionName(text);
	static if( extname.length > 0 ){
		static immutable parsed_file = extname;
		static immutable parsed_text = removeEmptyLines(import(extname), extname);
		static immutable indent_style = detectIndentStyle(parsed_text);
		static immutable blocks = extractBlocks(text, text_indent_style, parsed_text, indent_style);
	} else {
		static immutable parsed_file = template_file;
		static immutable parsed_text = text;
		static immutable indent_style = text_indent_style;
		static immutable DietBlock[] blocks = [];
	}

	DietParser parser;
	parser.lines = parsed_text;
	parser.indentStyle = indent_style;
	parser.blocks = blocks;
	return parser.buildWriter();
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
	string indentStyle;
}

private struct Line {
	string file;
	int number;
	string text;
}

private void assert_ln(Line ln, bool cond, string text = null, string file = __FILE__, int line = __LINE__)
{
	assert(cond, "Error in template "~ln.file~" line "~cttostring(ln.number)
		~": "~text~"("~file~":"~cttostring(line)~")");
}



private DietBlock[] extractBlocks(in Line[] template_text, string indent_style,
	in Line[] parent_text, string parent_indent_style)
{
	string[] names;
	DietBlock[] blocks;
	extractBlocksFromExtension(template_text[1 .. template_text.length], names, blocks, indent_style);

	string[] used_names;
	extractBlocksFromParent(parent_text, used_names, parent_indent_style);

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

private void extractBlocksFromExtension(in Line[] text, ref string[] names, ref DietBlock[] blocks, string indent_style)
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
			if( bln.text[0] != '\t' && bln.text[0] != ' ' ) break;
			block ~= bln;
			i++;
		}
		names ~= name;
		blocks ~= DietBlock(name, block, indent_style);
	}
}

private void extractBlocksFromParent(in Line[] text, ref string[] names, string indent)
{
	for( size_t i = 0; i < text.length; i++ ){
		string ln = unindent(text[i].text, indent);
		if( ln.length > 6 && ln[0 .. 6] == "block " ){
			auto name = ln[6 .. ln.length];
			names ~= name;		
		}
	}
}

private string detectIndentStyle(in Line[] lines)
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
		string indentStyle = "\t";
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

		auto next_indent_level = indentLevel(lines[curline].text, indentStyle);
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
			if( !in_string ) ret ~= lineMarker(lines[curline]);
			auto level = indentLevel(lines[curline].text, indentStyle) + base_level;
			assertp(level <= node_stack.length+1);
			auto ln = unindent(lines[curline].text, indentStyle);
			assertp(ln.length > 0);
			int next_indent_level = (curline+1 < lines.length ? indentLevel(lines[curline+1].text, indentStyle) : 0) + base_level;

			assertp(node_stack.length >= level, cttostring(node_stack.length) ~ ">=" ~ cttostring(level));
			assertp(next_indent_level <= level+1, "Indentations may not skip child levels.");

			if( ln[0] == '-' ){ // embedded D code
				ret ~= buildCodeNodeWriter(node_stack, ln[1 .. ln.length], level, in_string);
			} else if( ln[0] == '|' ){ // plain text node
				ret ~= buildTextNodeWriter(node_stack, ln[1 .. ln.length], level, in_string);
			} else if( ln[0] == ':' ){ // filter node (filtered raw text)
				// find all child lines
				size_t next_tag = curline+1;
				while( next_tag < lines.length &&
					indentLevel(lines[next_tag].text, indentStyle) > level-base_level )
				{
					next_tag++;
				}

				ret ~= buildFilterNodeWriter(node_stack, ln, level, base_level, in_string,
						lines[curline+1 .. next_tag]);

				// skip to the next tag
				//node_stack ~= "-";
				curline = next_tag-1;
				next_indent_level = (curline+1 < lines.length ? indentLevel(lines[curline+1].text, indentStyle) : 0) + base_level;
			} else {
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
							parser.indentStyle = blocks[blockidx].indentStyle;
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
					case "script":
					case "style":
						// pass all child lines to buildRawTag and continue with the next sibling
						size_t next_tag = curline+1;
						while( next_tag < lines.length &&
							indentLevel(lines[next_tag].text, indentStyle) > level-base_level )
						{
							next_tag++;
						}
						ret ~= buildRawNodeWriter(node_stack, tag, ln[j .. $], level, base_level,
							in_string, lines[curline+1 .. next_tag]);
						curline = next_tag-1;
						next_indent_level = (curline+1 < lines.length ? indentLevel(lines[curline+1].text, indentStyle) : 0) + base_level;
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
		line = ctstrip(line);
		assertp(line.length == 0 || line[$-1] != '{', "Use indentation to nest D statements instead of braces.");
		string ret = endString(in_string) ~ line ~ "{\n";
		node_stack ~= "-}";
		return ret;
	}

	string buildTextNodeWriter(ref string[] node_stack, string line, int level, ref bool in_string)
	{
		string ret;
		ret = endString(in_string);
		ret ~= StreamVariableName ~ ".write(\"\\n\", false);\n";
		if( line.length >= 1 && line[0] == '=' ){
			ret ~= StreamVariableName ~ ".write(htmlEscape(_toString(";
			ret ~= line[1 .. $];
			ret ~= ")";
		} else if( line.length >= 2 && line[0 .. 2] == "!=" ){
			ret ~= StreamVariableName ~ ".write(_toString(";
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
		// parse the HTML tag, leaving any trailing text as line[i .. $]
		size_t i;
		Tuple!(string, string)[] attribs;
		parseHtmlTag(line, i, attribs);

		// determine if we need a closing tag
		bool has_children = true;
		switch(tag){
			case "area", "base", "basefont", "br", "col", "embed", "frame",	"hr", "img", "input",
					"link", "keygen", "meta", "param", "source", "track", "wbr":
				has_children = false;
				break;
			default:
		}
		assertp(has_children || !has_child_nodes, "Singular HTML tag '"~tag~"' may not have children.");
		
		// parse any text contents (either using "= code" or as plain text)
		string textstring;
		bool textstring_isdynamic = true;
		if( i < line.length && line[i] == '=' ){
			textstring = "htmlEscape(_toString("~ctstrip(line[i+1 .. line.length])~"))";
		} else if( i+1 < line.length && line[i .. i+2] == "!=" ){
			textstring = "_toString("~ctstrip(line[i+2 .. line.length])~")";
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
		
		string ret = buildHtmlTag(node_stack, tag, level, in_string, attribs);
		if( textstring_isdynamic ){
			ret ~= endString(in_string);
			ret ~= StreamVariableName~".write(" ~ textstring ~ ", false);\n";
		} else ret ~= startString(in_string) ~ textstring;
		if( tail.length ) ret ~= startString(in_string) ~ tail;
			
		return ret;
	}

	string buildRawNodeWriter(ref string[] node_stack, string tag, string tagline, int level,
			int base_level, ref bool in_string, in Line[] lines)
	{
		// parse the HTML tag leaving any trailing text as tagline[i .. $]
		size_t i;
		Tuple!(string, string)[] attribs;
		parseHtmlTag(tagline, i, attribs);

		// write the tag
		string ret = buildHtmlTag(node_stack, tag, level, in_string, attribs);

		string indent_string = "\\t";
		foreach( j; 0 .. level ) if( node_stack[j][0] != '-' ) indent_string ~= "\\t";

		// write the block contents wrapped in a CDATA for old browsers
		ret ~= startString(in_string);
		if( tag == "script" ) ret ~= "\\n"~indent_string~"//<![CDATA[\\n";
		else ret ~= "\\n"~indent_string~"<!--\\n";

		// write out all lines
		if( i < tagline.length )
			ret ~= indent_string ~ dstringEscape(tagline[i .. $]) ~ "\\n";
		foreach( ln; lines ){
			// remove indentation
			string lnstr = ln.text[(level-base_level+1)*indentStyle.length .. $];
			ret ~= indent_string ~ dstringEscape(lnstr) ~ "\\n";
		}
		if( tag == "script" ) ret ~= indent_string~"//]]>\\n";
		else ret ~= indent_string~"-->\\n";
		ret ~= indent_string[0 .. $-2] ~ "</" ~ tag ~ ">";
		return ret;
	}

	string buildFilterNodeWriter(ref string[] node_stack, string tagline, int level,
			int base_level, ref bool in_string, in Line[] lines)
	{
		string ret;

		// find all filters
		size_t j = 0;
		string[] filters;
		do {
			j++;
			filters ~= skipIdent(tagline, j);
			skipWhitespace(tagline, j);
		} while( j < tagline.length && tagline[j] == ':' );

		// assemble child lines to one string
		string content = tagline[j .. $];
		foreach( cln; lines ){
			if( content.length ) content ~= '\n';
			content ~= cln.text[(level-base_level+1)*indentStyle.length .. $];
		}

		// determine the current HTML indent level
		int indent = 0;
		foreach( i; 0 .. level ) if( node_stack[i][0] != '-' ) indent++;

		// compile-time filter whats possible
		filter_loop:
		foreach_reverse( f; filters ){
			switch(f){
				default: break filter_loop;
				case "css": content = filterCSS(content, indent); break;
				case "javascript": content = filterJavaScript(content, indent); break;
				case "markdown": content = filterMarkdown(content, indent); break;
			}
			filters.length = filters.length-1;
		}

		// the rest of the filtering will happen at run time
		ret ~= endString(in_string) ~ StreamVariableName~".write(";
		string filter_expr;
		foreach_reverse( flt; filters ) ret ~= "s_filters[\""~dstringEscape(flt)~"\"](";
		ret ~= "\"" ~ dstringEscape(content) ~ "\"";
		foreach( i; 0 .. filters.length ) ret ~= ", "~cttostring(indent)~")";
		ret ~= ");\n";

		return ret;
	}

	void parseHtmlTag(string line, out size_t i, out Tuple!(string, string)[] attribs)
	{
		i = 0;

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
		if( id.length ) attribs ~= tuple("id", id);
		
		// parse other attributes
		if( i < line.length && line[i] == '(' ){
			i++;
			string attribstring = skipUntilClosingClamp(line, i);
			parseAttributes(attribstring, attribs);
			i++;
		}

        // Add extra classes
        bool has_classes = false;
        if (attribs.length) {
            foreach (idx, att; attribs) {
                if (att[0] == "class") {
                    if( classes.length )
                        attribs[idx] = tuple("class", att[1]~" "~classes);
                    has_classes = true;
                    break;
                }
            }
        }

        if (!has_classes && classes.length ) attribs ~= tuple("class", classes);

		// skip until the optional tag text contents begin
		skipWhitespace(line, i);
	}

	string buildHtmlTag(ref string[] node_stack, string tag, int level, ref bool in_string, ref Tuple!(string, string)[] attribs)
	{
		string tagstring = startString(in_string) ~ "\\n";
		assertp(node_stack.length >= level);
		foreach( j; 0 .. level ) if( node_stack[j][0] != '-' ) tagstring ~= "\\t";
		tagstring ~= "<" ~ tag;
		foreach( att; attribs ) tagstring ~= " "~att[0]~"=\\\"\"~htmlAttribEscape("~buildInterpolatedString(att[1])~")~\"\\\"";
		tagstring ~= ">";
		return tagstring;
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
                if (str[i] == '\'' || str[i] == '"') {
                    auto delimiter = str[i];
                    i++;
                    value = skipAttribString(str, i, delimiter);
                    i++;
                    skipWhitespace(str, i);
                } else if(name == "class") { //Support special-case class
                    value = skipIdent(str, i, "_.");
                    value = "#{join("~value~",\" \")}";
                } else {
                    assertp(str[i] == '\'' || str[i] == '"', "Expecting ''' or '\"' following '='.");
                }
			}
			
			assertp(i == str.length || str[i] == ',', "Unexpected text following attribute: '"~str[0..i]~"' ('"~str[i..$]~"')");
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
			if( str[i] == '#' && str.length >= 2){
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
					ret ~= "_toString(" ~ skipUntilClosingBrace(str, i) ~ ")";
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

private string unindent(string str, string indent)
{
	size_t lvl = indentLevel(str, indent);
	return str[lvl*indent.length .. $];
}

private int indentLevel(string s, string indent)
{
	if( indent.length == 0 ) return 0;
	int l = 0;
	while( l+indent.length <= s.length && s[l .. l+indent.length] == indent )
		l += cast(int)indent.length;
	return l / cast(int)indent.length;
}

private int indentLevel(in Line[] ln, string indent)
{
	return ln.length == 0 ? 0 : indentLevel(ln[0].text, indent);
}

private string _toString(T)(T v)
{
	static if( is(T == string) ) return v;
	else static if( __traits(compiles, v.opCast!string()) ) return cast(string)v;
	else static if( __traits(compiles, v.toString()) ) return v.toString();
	else return to!string(v);
}

private string ctstrip(string s)
{
	size_t strt = 0, end = s.length;
	while( strt < s.length && (s[strt] == ' ' || s[strt] == '\t') ) strt++;
	while( end > 0 && (s[end-1] == ' ' || s[end-1] == '\t') ) end--;
	return strt < end ? s[strt .. end] : null;
}

private Line[] removeEmptyLines(string text, string file)
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

/**************************************************************************************************/
/* Compile time filters                                                                           */
/**************************************************************************************************/

string filterCSS(string text, int indent)
{
	auto lines = splitLines(text);

	string indent_string = "\n";
	while( indent-- > 0 ) indent_string ~= '\t';

	string ret = indent_string~"<style type=\"text/css\"><!--";
	indent_string = indent_string ~ '\t';
	foreach( ln; lines ) ret ~= indent_string ~ ln;
	indent_string = indent_string[0 .. $-1];
	ret ~= indent_string ~ "--></style>";

	return ret;
}


string filterJavaScript(string text, int indent)
{
	auto lines = splitLines(text);

	string indent_string = "\n";
	while( indent-- >= 0 ) indent_string ~= '\t';

	string ret = indent_string[0 .. $-1]~"<script type=\"text/javascript\">";
	ret ~= indent_string~"//<![CDATA[";
	foreach( ln; lines ) ret ~= indent_string ~ ln;
	ret ~= indent_string ~ "//]]>"~indent_string[0 .. $-1]~"</script>";

	return ret;
}

string filterMarkdown(string text, int indent)
{
	return vibe.textfilter.markdown.filterMarkdown(text);
}