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
		support string interpolations in filter blocks
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
	enum string StreamVariableName = "stream__";
	string function(string, int indent)[string] s_filters;
}

static this()
{
	registerDietTextFilter("css", &filterCSS);
	registerDietTextFilter("javascript", &filterJavaScript);
	registerDietTextFilter("markdown", &filterMarkdown);
}


@property string dietParser(string template_file)()
{
	TemplateBlock[] files;
	readFileRec!(template_file)(files);
	auto compiler = DietCompiler(&files[0], &files);
	return compiler.buildWriter();
}


/******************************************************************************/
/* Reading of input files                                                     */
/******************************************************************************/

private struct TemplateBlock {
	string name;
	int mode = 0; // -1: prepend, 0: replace, 1: append
	string indentStyle;
	Line[] lines;
}


private struct Line {
	string file;
	int number;
	string text;
}

void readFileRec(string FILE, ALREADY_READ...)(ref TemplateBlock[] dst)
{
	static if( !isPartOf!(FILE, ALREADY_READ)() ){
		enum LINES = removeEmptyLines(import(FILE), FILE);

		TemplateBlock ret;
		ret.name = FILE;
		ret.lines = LINES;
		ret.indentStyle = detectIndentStyle(ret.lines);

		enum DEPS = extractDependencies(LINES);
		dst ~= ret;
		readFilesRec!(DEPS, ALREADY_READ, FILE)(dst);
	}
}
void readFilesRec(alias FILES, ALREADY_READ...)(ref TemplateBlock[] dst)
{
	static if( FILES.length > 0 ){
		readFileRec!(FILES[0], ALREADY_READ)(dst);
		readFilesRec!(FILES[1 .. $], ALREADY_READ, FILES[0])(dst);
	}
}
bool isPartOf(string str, STRINGS...)()
{
	foreach( s; STRINGS )
		if( str == s )
			return true;
	return false;
}
string[] extractDependencies(in Line[] lines)
{
	string[] ret;
	foreach( ref ln; lines ){
		auto lnstr = ln.text.ctstrip();
		if( lnstr.startsWith("extends ") ) ret ~= lnstr[8 .. $].ctstrip() ~ ".dt";
		else if( lnstr.startsWith("include ") ) ret ~= lnstr[8 .. $].ctstrip() ~ ".dt";
	}
	return ret;
}

private string detectIndentStyle(in ref Line[] lines)
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


/******************************************************************************/
/* The Diet compiler                                                          */
/******************************************************************************/

private struct DietCompiler {
	private {
		size_t m_lineIndex = 0;
		TemplateBlock* block;
		TemplateBlock[]* files;
		TemplateBlock[]* blocks;
	}

	@property ref string indentStyle() { return block.indentStyle; }
	@property size_t lineCount() { return block.lines.length; }
	ref Line line(size_t ln) { return block.lines[ln]; }
	ref Line currLine() { return block.lines[m_lineIndex]; }
	ref string currLineText() { return block.lines[m_lineIndex].text; }
	Line[] lineRange(size_t from, size_t to) { return block.lines[from .. to]; }

	@disable this();

	this(TemplateBlock* block, TemplateBlock[]* files)
	{
		this.block = block;
		this.files = files;
	}

	string buildWriter()
	{
		bool in_string = false;
		string[] node_stack;
		auto ret = buildWriter(node_stack, in_string, 0);
		assert(node_stack.length == 0);
		return ret;
	}

	string buildWriter(ref string[] node_stack, ref bool in_string, int base_level)
	{
		if( lineCount == 0 ) return null;

		auto firstline = line(m_lineIndex);
		auto firstlinetext = firstline.text;

		string ret;
		ret ~= endString(in_string);
		ret ~= lineMarker(firstline);

		if( firstlinetext.startsWith("extends ") ){
			string layout_file = firstlinetext[8 .. $].ctstrip() ~ ".dt";
			auto extfile = getFile(layout_file);
			m_lineIndex++;

			// extract all blocks
			TemplateBlock[] subblocks;
			while( m_lineIndex < lineCount ){
				TemplateBlock subblock;

				// read block header
				string blockheader = line(m_lineIndex).text;
				size_t spidx = 0;
				auto mode = skipIdent(line(m_lineIndex).text, spidx, "");
				assertp(spidx > 0, "Expected block/append/prepend.");
				subblock.name = blockheader[spidx .. $].ctstrip();
				if( mode == "block" ) subblock.mode = 0;
				else if( mode == "append" ) subblock.mode = 1;
				else if( mode == "prepend" ) subblock.mode = -1;
				else assertp(false, "Expected block/append/prepend.");
				m_lineIndex++;

				// skip to next block
				auto block_start = m_lineIndex;
				while( m_lineIndex < lineCount ){
					auto lvl = indentLevel(line(m_lineIndex).text, indentStyle);
					if( lvl == 0 ) break;
					m_lineIndex++;
				}

				// append block to compiler
				subblock.lines = block.lines[block_start .. m_lineIndex];
				subblock.indentStyle = indentStyle;
				subblocks ~= subblock;
			}

			// execute compiler on layout file
			auto layoutcompiler = DietCompiler(extfile, files);
			layoutcompiler.blocks = &subblocks;
			ret ~= layoutcompiler.buildWriter(node_stack, in_string, base_level);
		} else {
			auto start_indent_level = indentLevel(firstlinetext, indentStyle);
			//assertp(start_indent_level == 0, "Indentation must start at level zero.");
			ret ~= buildBodyWriter(node_stack, in_string, base_level, start_indent_level);
		}

		ret ~= endString(in_string);
		return ret;
	}

	private string buildBodyWriter(ref string[] node_stack, ref bool in_string, int base_level, int start_indent_level)
	{
		string ret;

		assertp(node_stack.length >= base_level);

		for( ; m_lineIndex < lineCount; m_lineIndex++ ){
			auto curline = line(m_lineIndex);
			if( !in_string ) ret ~= lineMarker(curline);
			auto level = indentLevel(curline.text, indentStyle) - start_indent_level + base_level;
			assertp(level <= node_stack.length+1);
			auto ln = unindent(curline.text, indentStyle);
			assertp(ln.length > 0);
			int next_indent_level = (m_lineIndex+1 < lineCount ? indentLevel(line(m_lineIndex+1).text, indentStyle, false) - start_indent_level : 0) + base_level;

			assertp(node_stack.length >= level, cttostring(node_stack.length) ~ ">=" ~ cttostring(level));
			assertp(next_indent_level <= level+1, "The next line is indented by more than one level deeper. Please unindent accordingly.");

			if( ln[0] == '-' ){ // embedded D code
				assertp(ln[$-1] != '{', "Use indentation to nest D statements instead of braces.");
				ret ~= endString(in_string) ~ ln[1 .. $] ~ "{\n";
				node_stack ~= "-}";
			} else if( ln[0] == '|' ){ // plain text node
				ret ~= buildTextNodeWriter(node_stack, ln[1 .. ln.length], level, in_string);
			} else if( ln[0] == ':' ){ // filter node (filtered raw text)
				// find all child lines
				size_t next_tag = m_lineIndex+1;
				while( next_tag < lineCount &&
					indentLevel(line(next_tag).text, indentStyle, false) - start_indent_level > level-base_level )
				{
					next_tag++;
				}

				ret ~= buildFilterNodeWriter(node_stack, ln, level, base_level, in_string,
						lineRange(m_lineIndex+1, next_tag));

				// skip to the next tag
				//node_stack ~= "-";
				m_lineIndex = next_tag-1;
				next_indent_level = (m_lineIndex+1 < lineCount ? indentLevel(line(m_lineIndex+1).text, indentStyle, false) - start_indent_level : 0) + base_level;
			} else {
				size_t j = 0;
				auto tag = isAlpha(ln[0]) || ln[0] == '/' ? skipIdent(ln, j, "/:-_") : "div";
				if( ln.startsWith("!!! ") ) tag = "!!!";
				switch(tag){
					default:
						ret ~= buildHtmlNodeWriter(node_stack, tag, ln[j .. $], level, in_string, next_indent_level > level);
						break;
					case "!!!": // HTML Doctype header
						ret ~= buildSpecialTag!(node_stack)("!DOCTYPE html", level, in_string);
						break;
					case "//": // HTML comment
						skipWhitespace(ln, j);
						ret ~= startString(in_string) ~ "<!--" ~ ln[j .. $] ~ "\n";
						node_stack ~= "-->";
						break;
					case "//-": // non-output comment
						// find all child lines
						size_t next_tag = m_lineIndex+1;
						while( next_tag < lineCount &&
							indentLevel(line(next_tag).text, indentStyle, false) - start_indent_level > level-base_level )
						{
							next_tag++;
						}

						// skip to the next tag
						m_lineIndex = next_tag-1;
						next_indent_level = (m_lineIndex+1 < lineCount ? indentLevel(line(m_lineIndex+1).text, indentStyle, false) - start_indent_level : 0) + base_level;
						break;
					case "//if": // IE conditional comment
						skipWhitespace(ln, j);
						ret ~= buildSpecialTag!(node_stack)("!--[if "~ln[j .. $]~"]", level, in_string);
						node_stack ~= "<![endif]-->";
						break;
					case "block": // Block insertion place
						assertp(next_indent_level <= level, "Child elements for 'include' are not supported.");
						node_stack ~= "-";
						auto block = getBlock(ln[6 .. $].ctstrip());
						if( block ){
							if( block.mode == 1 ){
								// output defaults
							}
							auto blockcompiler = DietCompiler(block, files);
							ret ~= blockcompiler.buildWriter(node_stack, in_string, node_stack.length);

							if( block.mode == -1 ){
								// output defaults
							}
						} else {
							// output defaults
						}
						break;
					case "include": // Diet file include
						assertp(next_indent_level <= level, "Child elements for 'include' are not supported.");
						auto filename = ln[8 .. $].ctstrip() ~ ".dt";
						auto file = getFile(filename);
						auto includecompiler = DietCompiler(file, files);
						ret ~= includecompiler.buildWriter(node_stack, in_string, level);
						break;
					case "script":
					case "style":
						// pass all child lines to buildRawTag and continue with the next sibling
						size_t next_tag = m_lineIndex+1;
						while( next_tag < lineCount &&
							indentLevel(line(next_tag).text, indentStyle, false) - start_indent_level > level-base_level )
						{
							next_tag++;
						}
						ret ~= buildRawNodeWriter(node_stack, tag, ln[j .. $], level, base_level,
							in_string, lineRange(m_lineIndex+1, next_tag));
						m_lineIndex = next_tag-1;
						next_indent_level = (m_lineIndex+1 < lineCount ? indentLevel(line(m_lineIndex+1).text, indentStyle, false) - start_indent_level : 0) + base_level;
						break;
					case "each":
					case "for":
					case "if":
					case "unless":
					case "mixin":
						assertp(false, "'"~tag~"' is not supported.");
						break;
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
					str ~= node_stack[$-1];
					ret ~= startString(in_string);
					ret ~= dstringEscape(str);
				}
				node_stack.length = node_stack.length-1;
			}
		}

		return ret;
	}

	private string buildTextNodeWriter(ref string[] node_stack, in string textline, int level, ref bool in_string)
	{
		string ret;
		ret = endString(in_string);
		ret ~= StreamVariableName ~ ".write(\"\\n\", false);\n";
		if( textline.length >= 1 && textline[0] == '=' ){
			ret ~= StreamVariableName ~ ".write(htmlEscape(_toString(";
			ret ~= textline[1 .. $];
			ret ~= "))";
		} else if( textline.length >= 2 && textline[0 .. 2] == "!=" ){
			ret ~= StreamVariableName ~ ".write(_toString(";
			ret ~= textline[2 .. $];
			ret ~= ")";
		} else {
			ret ~= StreamVariableName ~ ".write(";
			ret ~= buildInterpolatedString(textline, false, false);
		}
		ret ~= ", false);\n";
		node_stack ~= "-";
		return ret;
	}

	private string buildHtmlNodeWriter(ref string[] node_stack, in ref string tag, in string line, int level, ref bool in_string, bool has_child_nodes)
	{
		// parse the HTML tag, leaving any trailing text as line[i .. $]
		size_t i;
		Tuple!(string, string)[] attribs;
		parseHtmlTag(line, i, attribs);

		// determine if we need a closing tag
		bool is_singular_tag = false;
		switch(tag){
			case "area", "base", "basefont", "br", "col", "embed", "frame",	"hr", "img", "input",
					"keygen", "link", "meta", "param", "source", "track", "wbr":
				is_singular_tag = true;
				break;
			default:
		}
		assertp(!(is_singular_tag && has_child_nodes), "Singular HTML element '"~tag~"' may not have children.");
		
		// parse any text contents (either using "= code" or as plain text)
		string textstring;
		bool textstring_isdynamic = true;
		if( i < line.length && line[i] == '=' ){
			textstring = "htmlEscape(_toString("~ctstrip(line[i+1 .. line.length])~"))";
		} else if( i+1 < line.length && line[i .. i+2] == "!=" ){
			textstring = "_toString("~ctstrip(line[i+2 .. line.length])~")";
		} else {
			if( hasInterpolations(line[i .. line.length]) ){
				textstring = buildInterpolatedString(line[i .. line.length], false, false);
			} else {
				textstring = dstringEscape(line[i .. line.length]);
				textstring_isdynamic = false;
			}
		}
		
		string tail;
		if( has_child_nodes ){
			node_stack ~= "</"~tag~">";
			tail = "";
		} else if( !is_singular_tag ) tail = "</" ~ tag ~ ">";
		
		string ret = buildHtmlTag(node_stack, tag, level, in_string, attribs, is_singular_tag);
		if( textstring_isdynamic ){
			ret ~= endString(in_string);
			ret ~= StreamVariableName~".write(" ~ textstring ~ ", false);\n";
		} else ret ~= startString(in_string) ~ textstring;
		if( tail.length ) ret ~= startString(in_string) ~ tail;
			
		return ret;
	}

	private string buildRawNodeWriter(ref string[] node_stack, in ref string tag, in string tagline, int level,
			int base_level, ref bool in_string, in Line[] lines)
	{
		// parse the HTML tag leaving any trailing text as tagline[i .. $]
		size_t i;
		Tuple!(string, string)[] attribs;
		parseHtmlTag(tagline, i, attribs);

		// write the tag
		string ret = buildHtmlTag(node_stack, tag, level, in_string, attribs, false);

		string indent_string = "\\t";
		foreach( j; 0 .. level ) if( node_stack[j][0] != '-' ) indent_string ~= "\\t";

		// write the block contents wrapped in a CDATA for old browsers
		ret ~= startString(in_string);
		if( tag == "script" ) ret ~= "\\n"~indent_string~"//<![CDATA[\\n";
		else ret ~= "\\n"~indent_string~"<!--\\n";

		// write out all lines
		void writeLine(string str){
			if( !hasInterpolations(str) )
				ret ~= indent_string ~ dstringEscape(str) ~ "\\n";
			else
				ret ~= indent_string ~ "\"" ~ buildInterpolatedString(str, true, true) ~ "\"\\n";
		}
		if( i < tagline.length ) writeLine(tagline[i .. $]);
		foreach( ln; lines ){
			// remove indentation
			string lnstr = ln.text[(level-base_level+1)*indentStyle.length .. $];
			writeLine(lnstr);
		}
		if( tag == "script" ) ret ~= indent_string~"//]]>\\n";
		else ret ~= indent_string~"-->\\n";
		ret ~= indent_string[0 .. $-2] ~ "</" ~ tag ~ ">";
		return ret;
	}

	private string buildFilterNodeWriter(ref string[] node_stack, in ref string tagline, int level,
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

	private void parseHtmlTag(in ref string line, out size_t i, out Tuple!(string, string)[] attribs)
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

	private string buildHtmlTag(ref string[] node_stack, in ref string tag, int level, ref bool in_string, ref Tuple!(string, string)[] attribs, bool is_singular_tag)
	{
		string tagstring = startString(in_string) ~ "\\n";
		assertp(node_stack.length >= level);
		foreach( j; 0 .. level ) if( node_stack[j][0] != '-' ) tagstring ~= "\\t";
		tagstring ~= "<" ~ tag;
		foreach( att; attribs ) tagstring ~= " "~att[0]~"=\\\"\"~"~buildInterpolatedString(att[1], false, false, true)~"~\"\\\"";
		tagstring ~= is_singular_tag ? "/>" : ">";
		return tagstring;
	}

	private void parseAttributes(in ref string str, ref Tuple!(string, string)[] attribs)
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

	private bool hasInterpolations(in ref string str)
	{
		size_t i = 0;
		while( i < str.length ){
			if( str[i] == '\\' ){
				i += 2;
				continue;
			}
			if( i+1 < str.length && (str[i] == '#' || str[i] == '!') ){
				if( str[i+1] == str[i] ){
					i += 2;
					continue;
				} else if( str[i+1] == '{' ){
					return true;
				}
			}
			i++;
		}
		return false;
	}

	private string buildInterpolatedString(in ref string str, bool prevconcat = false, bool nextconcat = false, bool escape_quotes = false)
	{
		string ret;
		int state = 0; // 0 == start, 1 == in string, 2 == out of string
		static immutable enter_string = ["\"", "", "~\""];
		static immutable enter_non_string = ["", "\"~", "~"];
		static immutable exit_string = ["", "\"", ""];
		size_t start = 0, i = 0;
		while( i < str.length ){
			// check for escaped characters
			if( str[i] == '\\' ){
				if( i > start ){
					ret ~= enter_string[state] ~ dstringEscape(str[start .. i]);
					state = 1;
				}
				i++;
				if( i < str.length ){
					ret ~= enter_string[state] ~ str[i];
					state = 1;
					i++;
				}
				start = i;
				continue;
			}

			if( (str[i] == '#' || str[i] == '!') && i+1 < str.length ){
				bool escape = str[i] == '#';
				if( i > start ){
					ret ~= enter_string[state] ~ dstringEscape(str[start .. i]);
					state = 1;
				}
				if( str[i+1] == str[i] ){ // just keeping alternative escaping for compatibility reasons
					ret ~= enter_string[state] ~ "#";
					state = 1;
					i += 2;
					start = i;
				} else if( str[i+1] == '{' ){
					i += 2;
					ret ~= enter_non_string[state];
					state = 2;
					if( escape && !escape_quotes ) ret ~= "htmlEscape(_toString(" ~ skipUntilClosingBrace(str, i) ~ "))";
					else if( escape ) ret ~= "htmlAttribEscape(_toString(" ~ skipUntilClosingBrace(str, i) ~ "))";
					else ret ~= "_toString(" ~ skipUntilClosingBrace(str, i) ~ ")";
					i++;
					start = i;
				} else i++;
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

	private string skipIdent(in ref string s, ref size_t idx, string additional_chars = null)
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

	private string skipWhitespace(in ref string s, ref size_t idx)
	{
		size_t start = idx;
		while( idx < s.length ){
			if( s[idx] == ' ' ) idx++;
			else break;
		}
		return s[start .. idx];
	}

	private string skipUntilClosingBrace(in ref string s, ref size_t idx)
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

	private string skipUntilClosingClamp(in ref string s, ref size_t idx)
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

	private string skipAttribString(in ref string s, ref size_t idx, char delimiter)
	{
		size_t start = idx;
		string ret;
		while( idx < s.length ){
			if( s[idx] == '\\' ){
				ret ~= s[idx]; // pass escape character through - will be handled later by buildInterpolatedString
				idx++;
				assertp(idx < s.length, "'\\' must be followed by something (escaped character)!");
				ret ~= s[idx];
			} else if( s[idx] == delimiter ) break;
			else ret ~= s[idx];
			idx++;
		}
		return ret;
	}

	private string unindent(in ref string str, in ref string indent)
	{
		size_t lvl = indentLevel(str, indent);
		return str[lvl*indent.length .. $];
	}

	private int indentLevel(in ref string s, in ref string indent, bool strict = true)
	{
		if( indent.length == 0 ) return 0;
		int l = 0;
		while( l+indent.length <= s.length && s[l .. l+indent.length] == indent )
			l += cast(int)indent.length;
		assertp(!strict || s[l] != ' ', "Indent is not a multiple of '"~indent~"'");
		return l / cast(int)indent.length;
	}

	private int indentLevel(in ref Line[] ln, string indent)
	{
		return ln.length == 0 ? 0 : indentLevel(ln[0].text, indent);
	}

	private void assertp(bool cond, string text = null, string file = __FILE__, int cline = __LINE__)
	{
		Line ln;
		if( m_lineIndex < lineCount ) ln = line(m_lineIndex);
		assert(cond, "template "~ln.file~" line "~cttostring(ln.number)~": "~text~"("~file~":"~cttostring(cline)~")");
	}

	private TemplateBlock* getFile(string filename)
	{
		foreach( i; 0 .. files.length )
			if( (*files)[i].name == filename )
				return &(*files)[i];
		assertp(false, "Bug: include input file "~filename~" not found in internal list!?");
		assert(false);
	}
	
	private TemplateBlock* getBlock(string name)
	{
		foreach( i; 0 .. blocks.length )
			if( (*blocks)[i].name == name )
				return &(*blocks)[i];
		return null;
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


private void assert_ln(in ref Line ln, bool cond, string text = null, string file = __FILE__, int line = __LINE__)
{
	assert(cond, "Error in template "~ln.file~" line "~cttostring(ln.number)
		~": "~text~"("~file~":"~cttostring(line)~")");
}


private string unindent(in ref string str, in ref string indent)
{
	size_t lvl = indentLevel(str, indent);
	return str[lvl*indent.length .. $];
}

private int indentLevel(in ref string s, in ref string indent)
{
	if( indent.length == 0 ) return 0;
	int l = 0;
	while( l+indent.length <= s.length && s[l .. l+indent.length] == indent )
		l += cast(int)indent.length;
	return l / cast(int)indent.length;
}

private string lineMarker(in ref Line ln)
{
	return "#line "~cttostring(ln.number)~" \""~ln.file~"\"\n";
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
private string dstringEscape(in ref string str)
{
	string ret;
	foreach( ch; str ) ret ~= dstringEscape(ch);
	return ret;
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