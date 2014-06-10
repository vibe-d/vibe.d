/**
	Implements a compile-time Diet template parser.

	Diet templates are an more or less compatible incarnation of Jade templates but with
	embedded D source instead of JavaScript. The Diet syntax reference is found at
	$(LINK http://vibed.org/templates/diet).

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.templ.diet;

public import vibe.core.stream;

import vibe.core.file;
import vibe.templ.parsertools;
import vibe.templ.utils;
import vibe.textfilter.html;
static import vibe.textfilter.markdown;
import vibe.utils.string;

import core.vararg;
import std.ascii : isAlpha;
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

	Note that this function suffers from multiple compiler bugsin conjunction with local
	variables passed as alias template parameters up to DMD 2.063.2. DMD 2.064 supposedly
	has these fixed.
*/
void compileDietFile(string template_file, ALIASES...)(OutputStream stream__)
{
	compileDietFileIndent!(template_file, 0, ALIASES)(stream__);
}
/// ditto
void compileDietFileIndent(string template_file, size_t indent, ALIASES...)(OutputStream stream__)
{
	// some imports to make available by default inside templates
	import vibe.http.common;
	import vibe.utils.string;
	version (GNU) import std.typetuple;

	pragma(msg, "Compiling diet template '"~template_file~"'...");
	static if (ALIASES.length > 0 && __VERSION__ < 2064) {
		pragma(msg, "Warning: using render!() or parseDietFile!() with aliases is unsafe,");
		pragma(msg, "         please consider using renderCompat!()/parseDietFileCompat!()");
		pragma(msg, "         on DMD versions prior to 2.064.");
	}
	//pragma(msg, localAliases!(0, ALIASES));
	mixin(localAliases!(0, ALIASES));

	static if (is(typeof(diet_translate__))) alias TRANSLATE = TypeTuple!(diet_translate__);
	else alias TRANSLATE = TypeTuple!();

	// Generate the D source code for the diet template
	//pragma(msg, dietParser!template_file(indent));
	static if (is(typeof(diet_translate__)))
		mixin(dietParser!(template_file, diet_translate__)(indent));
	else
		mixin(dietParser!template_file(indent));
}

/// compatibility alias
alias compileDietFile parseDietFile;

/**
	Compatibility version of parseDietFile().

	This function should only be called indirectly through HTTPServerResponse.renderCompat().

*/
void compileDietFileCompat(string template_file, TYPES_AND_NAMES...)(OutputStream stream__, ...)
{
	compileDietFileCompatV!(template_file, TYPES_AND_NAMES)(stream__, _argptr, _arguments);
}
/// ditto
void compileDietFileCompatV(string template_file, TYPES_AND_NAMES...)(OutputStream stream__, va_list _argptr, TypeInfo[] _arguments)
{
	// some imports to make available by default inside templates
	import vibe.http.common;
	import vibe.utils.string;

	pragma(msg, "Compiling diet template '"~template_file~"' (compat)...");
	//pragma(msg, localAliasesCompat!(0, TYPES_AND_NAMES));
	mixin(localAliasesCompat!(0, TYPES_AND_NAMES));

	static if (is(typeof(diet_translate__))) alias TRANSLATE = TypeTuple!(diet_translate__);
	else alias TRANSLATE = TypeTuple!();

	// Generate the D source code for the diet template
	//pragma(msg, dietParser!template_file());
	mixin(dietParser!template_file(0));
}

/// compatibility alias
alias compileDietFileCompat parseDietFileCompat;

/**
	Generates a diet template compiler to use as a mixin.

	This can be used as an alternative to compileDietFile or compileDietFileCompat. It allows
	the template to use all symbols visible in the enclosing scope. In situations where many
	variables from the calling function's scope are used within the template, it can reduce the
	amount of code required for invoking the template.

	Note that even if this method of using diet templates can reduce the amount of source code. It
	is generally recommended to use compileDietFile(Compat) instead, as those
	facilitate a cleaner interface between D code and diet code by explicity documenting the
	symbols usable inside of the template and thus avoiding unwanted, hidden dependencies. A
	possible alternative for passing many variables is to pass a struct or class value to
	compileDietFile(Compat).

	Examples:
	---
	void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
	{
		int this_variable_is_automatically_visible_to_the_template;
		mixin(compileDietFileMixin!("index.dt", "res.bodyWriter"));
	}
	---
*/
template compileDietFileMixin(string template_file, string stream_variable, size_t base_indent = 0)
{
	enum compileDietFileMixin = "OutputStream stream__ = "~stream_variable~";\n" ~ dietParser!template_file(base_indent);
}


/**
	The same as compileDietFile, but taking a Diet source code string instead of a file name.
*/
void compileDietString(string diet_code, ALIASES...)(OutputStream stream__)
{
	// some imports to make available by default inside templates
	import vibe.http.common;
	import vibe.utils.string;
	import std.typetuple;
	
	//pragma(msg, localAliases!(0, ALIASES));
	mixin(localAliases!(0, ALIASES));

	// Generate the D source code for the diet template
	//pragma(msg, dietParser!template_file());
	static if (is(typeof(diet_translate__))) alias TRANSLATE = TypeTuple!(diet_translate__);
	else alias TRANSLATE = TypeTuple!();

	mixin(dietStringParser!(diet_code, "__diet_code__", TRANSLATE)(0));
}


/**
	Registers a new text filter for use in Diet templates.

	The filter will be available using :filtername inside of the template. The following filters are
	predefined: css, javascript, markdown
*/
void registerDietTextFilter(string name, string function(string, size_t indent) filter)
{
	s_filters[name] = filter;
}


/**************************************************************************************************/
/* private functions                                                                              */
/**************************************************************************************************/

private {
	enum string StreamVariableName = "stream__";
	string function(string, size_t indent)[string] s_filters;
}

static this()
{
	registerDietTextFilter("css", &filterCSS);
	registerDietTextFilter("javascript", &filterJavaScript);
	registerDietTextFilter("markdown", &filterMarkdown);
	registerDietTextFilter("htmlescape", &filterHtmlEscape);
}


private string dietParser(string template_file, TRANSLATE...)(size_t base_indent)
{
	TemplateBlock[] files;
	readFileRec!(template_file)(files);
	auto compiler = DietCompiler!TRANSLATE(&files[0], &files, new BlockStore);
	return compiler.buildWriter(base_indent);
}

private string dietStringParser(string diet_code, string name, TRANSLATE...)(size_t base_indent)
{
	enum LINES = removeEmptyLines(diet_code, name);

	TemplateBlock ret;
	ret.name = name;
	ret.lines = LINES;
	ret.indentStyle = detectIndentStyle(ret.lines);

	TemplateBlock[] files;
	files ~= ret;
	readFilesRec!(extractDependencies(LINES), name)(files);

	auto compiler = DietCompiler!TRANSLATE(&files[0], &files, new BlockStore);
	return compiler.buildWriter(base_indent);
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

private class BlockStore {
	TemplateBlock[] blocks;
}


/// private
private void readFileRec(string FILE, ALREADY_READ...)(ref TemplateBlock[] dst)
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

/// private
private void readFilesRec(alias FILES, ALREADY_READ...)(ref TemplateBlock[] dst)
{
	static if( FILES.length > 0 ){
		readFileRec!(FILES[0], ALREADY_READ)(dst);
		readFilesRec!(FILES[1 .. $], ALREADY_READ, FILES[0])(dst);
	}
}

/// private
private bool isPartOf(string str, STRINGS...)()
{
	foreach( s; STRINGS )
		if( str == s )
			return true;
	return false;
}

private string[] extractDependencies(in Line[] lines)
{
	string[] ret;
	foreach (ref ln; lines) {
		auto lnstr = ln.text.ctstrip();
		if (lnstr.startsWith("extends ")) ret ~= lnstr[8 .. $].ctstrip() ~ ".dt";
	}
	return ret;
}


/******************************************************************************/
/* The Diet compiler                                                          */
/******************************************************************************/

private class OutputContext {
	enum State {
		Code,
		String
	}
	struct Node {
		string tag;
		bool inner;
		bool outer;
		alias tag this;
	}

	State m_state = State.Code;
	Node[] m_nodeStack;
	string m_result;
	Line m_line = Line(null, -1, null);
	size_t m_baseIndent;
	bool m_isHTML5;

	this(size_t base_indent = 0)
	{
		m_baseIndent = base_indent;
	}

	void markInputLine(in ref Line line)
	{
		if( m_state == State.Code ){
			m_result ~= lineMarker(line);
		} else {
			m_line = Line(line.file, line.number, null);
		}
	}

	@property size_t stackSize() const { return m_nodeStack.length; }

	void pushNode(string str, bool inner = true, bool outer = true) { m_nodeStack ~= Node(str, inner, outer); }
	void pushDummyNode() { pushNode("-"); }

	void popNodes(int next_indent_level, ref bool prepend_whitespaces)
	{
		// close all tags/blocks until we reach the level of the next line
		while( m_nodeStack.length > next_indent_level ){
			auto top = m_nodeStack[$-1];
			if( top[0] == '-' ){
				if( top.length > 1 ){
					writeCodeLine(top[1 .. $]);
				}
			} else if( top.length ){
				if( top.inner && prepend_whitespaces && top != "</pre>" ){
					writeString("\n");
					writeIndent(m_nodeStack.length-1);
				}

				writeString(top);
				prepend_whitespaces = top.outer;
			}
			m_nodeStack.length--;
		}
	}

	// TODO: avoid runtime allocations by replacing htmlEscape/_toString calls with
	//       filtering functions
	void writeRawString(string str) { enterState(State.String); m_result ~= str; }
	void writeString(string str) { writeRawString(dstringEscape(str)); }
	void writeStringHtmlEscaped(string str) { writeString(htmlEscape(str)); }
	void writeIndent(size_t stack_depth = size_t.max)
	{
		import std.algorithm : min;
		string str;
		foreach (i; 0 .. m_baseIndent) str ~= '\t';
		foreach (j; 0 .. min(m_nodeStack.length, stack_depth)) if (m_nodeStack[j][0] != '-') str ~= '\t';
		writeRawString(str);
	}

	void writeStringExpr(string str) { writeCodeLine(StreamVariableName~".write("~str~");"); }
	void writeStringExprHtmlEscaped(string str) { writeStringExpr("htmlEscape("~str~")"); }
	void writeStringExprHtmlAttribEscaped(string str) { writeStringExpr("htmlAttribEscape("~str~")"); }

	void writeExpr(string str) { writeStringExpr("_toString("~str~")"); }
	void writeExprHtmlEscaped(string str) { writeStringExprHtmlEscaped("_toString("~str~")"); }
	void writeExprHtmlAttribEscaped(string str) { writeStringExprHtmlAttribEscaped("_toString("~str~")"); }

	void writeCodeLine(string stmt)
	{
		if( !enterState(State.Code) )
			m_result ~= lineMarker(m_line);
		m_result ~= stmt ~ "\n";
	}

	private bool enterState(State state)
	{
		if( state == m_state ) return false;

		if( state != m_state.Code ) enterState(State.Code);

		final switch(state){
			case State.Code:
				if( m_state == State.String ) m_result ~= "\");\n";
				else m_result ~= ");\n";
				m_result ~= lineMarker(m_line);
				break;
			case State.String:
				m_result ~= StreamVariableName ~ ".write(\"";
				break;
		}

		m_state = state;
		return true;
	}
}

private struct DietCompiler(TRANSLATE...)
	if(TRANSLATE.length <= 1)
{
	private {
		size_t m_lineIndex = 0;
		TemplateBlock* m_block;
		TemplateBlock[]* m_files;
		BlockStore m_blocks;
	}

	@property ref string indentStyle() { return m_block.indentStyle; }
	@property size_t lineCount() { return m_block.lines.length; }
	ref Line line(size_t ln) { return m_block.lines[ln]; }
	ref Line currLine() { return m_block.lines[m_lineIndex]; }
	ref string currLineText() { return m_block.lines[m_lineIndex].text; }
	Line[] lineRange(size_t from, size_t to) { return m_block.lines[from .. to]; }

	@disable this();

	this(TemplateBlock* block, TemplateBlock[]* files, BlockStore blocks)
	{
		m_block = block;
		m_files = files;
		m_blocks = blocks;
	}

	string buildWriter(size_t base_indent)
	{
		auto output = new OutputContext(base_indent);
		buildWriter(output, 0);
		assert(output.m_nodeStack.length == 0, "Template writer did not consume all nodes!?");
		return output.m_result;
	}

	void buildWriter(OutputContext output, int base_level)
	{
		assert(m_blocks !is null, "Trying to compile template with no blocks specified.");

		while(true){
			if( lineCount == 0 ) return;
			auto firstline = line(m_lineIndex);
			auto firstlinetext = firstline.text;

			if( firstlinetext.startsWith("extends ") ){
				string layout_file = firstlinetext[8 .. $].ctstrip() ~ ".dt";
				auto extfile = getFile(layout_file);
				m_lineIndex++;

				// extract all blocks
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
						auto lvl = indentLevel(line(m_lineIndex).text, indentStyle, false);
						if( lvl == 0 ) break;
						m_lineIndex++;
					}

					// append block to compiler
					subblock.lines = lineRange(block_start, m_lineIndex);
					subblock.indentStyle = indentStyle;
					m_blocks.blocks ~= subblock;

					//output.writeString("<!-- found block "~subblock.name~" in "~line(0).file ~ "-->\n");
				}

				// change to layout file and start over
				m_block = extfile;
				m_lineIndex = 0;
			} else {
				auto start_indent_level = indentLevel(firstlinetext, indentStyle);
				//assertp(start_indent_level == 0, "Indentation must start at level zero.");
				buildBodyWriter(output, base_level, start_indent_level);
				break;
			}
		}

		output.enterState(OutputContext.State.Code);
	}

	private void buildBodyWriter(OutputContext output, int base_level, int start_indent_level)
	{
		assert(m_blocks !is null, "Trying to compile template body with no blocks specified.");

		assertp(output.stackSize >= base_level);

		int computeNextIndentLevel(){
			return (m_lineIndex+1 < lineCount ? indentLevel(line(m_lineIndex+1).text, indentStyle, false) - start_indent_level : 0) + base_level;
		}

		bool prepend_whitespaces = true;

		for( ; m_lineIndex < lineCount; m_lineIndex++ ){
			auto curline = line(m_lineIndex);
			output.markInputLine(curline);
			auto level = indentLevel(curline.text, indentStyle) - start_indent_level + base_level;
			assertp(level <= output.stackSize+1);
			auto ln = unindent(curline.text, indentStyle);
			assertp(ln.length > 0);
			int next_indent_level = computeNextIndentLevel();

			assertp(output.stackSize >= level, cttostring(output.stackSize) ~ ">=" ~ cttostring(level));
			assertp(next_indent_level <= level+1, "The next line is indented by more than one level deeper. Please unindent accordingly.");

			if( ln[0] == '-' ){ // embedded D code
				assertp(ln[$-1] != '{', "Use indentation to nest D statements instead of braces.");
				output.writeCodeLine(ln[1 .. $] ~ "{");
				output.pushNode("-}");
			} else if( ln[0] == '|' ){ // plain text node
				buildTextNodeWriter(output, ln[1 .. ln.length], level, prepend_whitespaces);
			} else if( ln[0] == ':' ){ // filter node (filtered raw text)
				// find all child lines
				size_t next_tag = m_lineIndex+1;
				while( next_tag < lineCount &&
					indentLevel(line(next_tag).text, indentStyle, false) - start_indent_level > level-base_level )
				{
					next_tag++;
				}

				buildFilterNodeWriter(output, ln, curline.number, level + start_indent_level - base_level,
						lineRange(m_lineIndex+1, next_tag));

				// skip to the next tag
				//output.pushDummyNode();
				m_lineIndex = next_tag-1;
				next_indent_level = computeNextIndentLevel();
			} else {
				size_t j = 0;
				auto tag = isAlpha(ln[0]) || ln[0] == '/' ? skipIdent(ln, j, "/:-_") : "div";

				if (ln.startsWith("!!! ")) {
					//output.writeCodeLine(`pragma(msg, "\"!!!\" is deprecated, use \"doctype\" instead.");`);
					tag = "doctype";
					j += 4;
				}

				switch(tag){
					default:
						if (buildHtmlNodeWriter(output, tag, ln[j .. $], level, next_indent_level > level, prepend_whitespaces)) {
							// tag had a '.' appended. treat child nodes as plain text
							size_t next_tag = m_lineIndex + 1;
							size_t unindent_count = level + start_indent_level - base_level + 1;
							size_t last_line_number = curline.number;
							while( next_tag < lineCount &&
							      indentLevel(line(next_tag).text, indentStyle, false) - start_indent_level > level-base_level )
							{
								// TODO: output all empty lines between this and the previous one
								foreach (i; last_line_number+1 .. line(next_tag).number) output.writeString("\n");
								last_line_number = line(next_tag).number;
								buildTextNodeWriter(output, unindent(line(next_tag++).text, indentStyle, unindent_count), level, prepend_whitespaces);
							}
							m_lineIndex = next_tag - 1;
							next_indent_level = computeNextIndentLevel();
						}
						break;
					case "doctype": // HTML Doctype header
						buildDoctypeNodeWriter(output, ln, j, level);
						break;
					case "//": // HTML comment
						skipWhitespace(ln, j);
						output.writeString("<!-- " ~ htmlEscape(ln[j .. $]));
						output.pushNode(" -->");
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
						next_indent_level = computeNextIndentLevel();
						break;
					case "//if": // IE conditional comment
						skipWhitespace(ln, j);
						buildSpecialTag(output, "!--[if "~ln[j .. $]~"]", level);
						output.pushNode("<![endif]-->");
						break;
					case "block": // Block insertion place
						assertp(next_indent_level <= level, "Child elements for 'include' are not supported.");
						output.pushDummyNode();
						auto block = getBlock(ln[6 .. $].ctstrip());
						if( block ){
							output.writeString("<!-- using block " ~ ln[6 .. $] ~ " in " ~ curline.file ~ "-->");
							if( block.mode == 1 ){
								// output defaults
							}
							auto blockcompiler = new DietCompiler(block, m_files, m_blocks);
							/*blockcompiler.m_block = block;
							blockcompiler.m_blocks = m_blocks;*/
							blockcompiler.buildWriter(output, cast(int)output.m_nodeStack.length);

							if( block.mode == -1 ){
								// output defaults
							}
						} else {
							// output defaults
							output.writeString("<!-- Default block " ~ ln[6 .. $] ~ " in " ~ curline.file ~ "-->");
						}
						break;
					case "include": // Diet file include
						assertp(next_indent_level <= level, "Child elements for 'include' are not supported.");
						auto content = ln[8 .. $].ctstrip();
						if (content.startsWith("#{")) {
							assertp(content.endsWith("}"), "Missing closing '}'.");
							output.writeCodeLine("mixin(dietStringParser!("~content[2 .. $-1]~", \""~replace(content, `"`, `'`)~"\", TRANSLATE)("~to!string(level)~"));");
						} else {
							output.writeCodeLine("mixin(dietParser!(\""~content~".dt\", TRANSLATE)("~to!string(level)~"));");
						}
						break;
					case "script":
					case "style":
						// determine if this is a plain css/JS tag (without a trailing .) and output a warning
						// for using deprecated behavior
						auto tagline = ln[j .. $];
						HTMLAttribute[] attribs;
						size_t tli;
						auto wst = parseHtmlTag(tagline, tli, attribs);
						tagline = tagline[0 .. tli];
						if (wst.block_tag) goto default;
						enum legacy_types = [`"text/css"`, `"text/javascript"`, `'text/javascript'`, `'text/css'`];
						bool is_legacy_type = true;
						foreach (i, ref a; attribs)
							if (a.key == "type") {
								is_legacy_type = false;
								foreach (t; legacy_types)
									if (a.value == t) {
										is_legacy_type = true;
										break;
									}
								break;
							}
						if (!is_legacy_type) goto default;

						output.writeCodeLine(`pragma(msg, "`~dstringEscape(currLine.file)~`:`~currLine.number.to!string~
							`: Warning: Use an explicit text block '`~tag~dstringEscape(tagline)~
							`.' for embedded css/javascript - old behavior will be removed soon.");`);

						if (next_indent_level <= level) {
							buildHtmlNodeWriter(output, tag, ln[j .. $], level, false, prepend_whitespaces);
						} else {
							// pass all child lines to buildRawTag and continue with the next sibling
							size_t next_tag = m_lineIndex+1;
							while( next_tag < lineCount &&
								indentLevel(line(next_tag).text, indentStyle, false) - start_indent_level > level-base_level )
							{
								next_tag++;
							}
							buildRawNodeWriter(output, tag, ln[j .. $], level, base_level,
								lineRange(m_lineIndex+1, next_tag));
							m_lineIndex = next_tag-1;
							next_indent_level = computeNextIndentLevel();
						}
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
			output.popNodes(next_indent_level, prepend_whitespaces);
		}
	}

	private void buildTextNodeWriter(OutputContext output, in string textline, int level, ref bool prepend_whitespaces)
	{
		if(prepend_whitespaces) output.writeString("\n");
		if( textline.length >= 1 && textline[0] == '=' ){
			output.writeExprHtmlEscaped(textline[1 .. $]);
		} else if( textline.length >= 2 && textline[0 .. 2] == "!=" ){
			output.writeExpr(textline[2 .. $]);
		} else {
			buildInterpolatedString(output, textline);
		}
		output.pushDummyNode();
		prepend_whitespaces = true;
	}

	private void buildDoctypeNodeWriter(OutputContext output, string ln, size_t j, int level)
	{
		skipWhitespace(ln, j);
		output.m_isHTML5 = false;

		string doctype_str = "!DOCTYPE html";
		switch (ln[j .. $]) {
			case "5":
			case "":
			case "html":
				output.m_isHTML5 = true;
				break;
			case "xml":
				doctype_str = `?xml version="1.0" encoding="utf-8" ?`;
				break;
			case "transitional":
				doctype_str = `!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" `
					~ `"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd`;
				break;
			case "strict":
				doctype_str = `!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" `
					~ `"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"`;
				break;
			case "frameset":
				doctype_str = `!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" `
					~ `"http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd"`;
				break;
			case "1.1":
				doctype_str = `!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" `
					~ `"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd"`;
				break;
			case "basic":
				doctype_str = `!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" `
					~ `"http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd"`;
				break;
			case "mobile":
				doctype_str = `!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" `
					~ `"http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd"`;
				break;
			default:
				doctype_str = "!DOCTYPE " ~ ln[j .. $];
			break;
		}
		buildSpecialTag(output, doctype_str, level);
	}

	private bool buildHtmlNodeWriter(OutputContext output, in ref string tag, in string line, int level, bool has_child_nodes, ref bool prepend_whitespaces)
	{
		// parse the HTML tag, leaving any trailing text as line[i .. $]
		size_t i;
		HTMLAttribute[] attribs;
		auto ws_type = parseHtmlTag(line, i, attribs);

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

		// opening tag
		buildHtmlTag(output, tag, level, attribs, is_singular_tag, ws_type.outer && prepend_whitespaces);

		// parse any text contents (either using "= code" or as plain text)
		if( i < line.length && line[i] == '=' ){
			output.writeExprHtmlEscaped(ctstrip(line[i+1 .. line.length]));
		} else if( i+1 < line.length && line[i .. i+2] == "!=" ){
			output.writeExpr(ctstrip(line[i+2 .. line.length]));
		} else {
			string rawtext = line[i .. line.length];
			static if (TRANSLATE.length > 0) if (ws_type.isTranslated) rawtext = TRANSLATE[0](rawtext);
			if (hasInterpolations(rawtext)) {
				buildInterpolatedString(output, rawtext);
			} else {
				output.writeRawString(sanitizeEscaping(rawtext));
			}
		}

		// closing tag
		if( has_child_nodes ) output.pushNode("</" ~ tag ~ ">", ws_type.inner, ws_type.outer);
		else if( !is_singular_tag ) output.writeString("</" ~ tag ~ ">");
		prepend_whitespaces = has_child_nodes ? ws_type.inner : ws_type.outer;

		return ws_type.block_tag;
	}

	private void buildRawNodeWriter(OutputContext output, in ref string tag, in string tagline, int level,
			int base_level, in Line[] lines)
	{
		// parse the HTML tag leaving any trailing text as tagline[i .. $]
		size_t i;
		HTMLAttribute[] attribs;
		parseHtmlTag(tagline, i, attribs);

		// write the tag
		buildHtmlTag(output, tag, level, attribs, false);

		string indent_string = "\t";
		foreach (j; 0 .. output.m_baseIndent) indent_string ~= '\t';
		foreach (j; 0 .. level ) if( output.m_nodeStack[j][0] != '-') indent_string ~= '\t';

		// write the block contents wrapped in a CDATA for old browsers
		if( tag == "script" ) output.writeString("\n"~indent_string~"//<![CDATA[\n");
		else output.writeString("\n"~indent_string~"<!--\n");

		// write out all lines
		void writeLine(string str){
			if( !hasInterpolations(str) ){
				output.writeString(indent_string ~ str ~ "\n");
			} else {
				output.writeString(indent_string);
				buildInterpolatedString(output, str);
			}
		}
		if( i < tagline.length ) writeLine(tagline[i .. $]);
		foreach( j; 0 .. lines.length ){
			// remove indentation
			string lnstr = lines[j].text[(level-base_level+1)*indentStyle.length .. $];
			writeLine(lnstr);
		}
		if( tag == "script" ) output.writeString(indent_string~"//]]>\n");
		else output.writeString(indent_string~"-->\n");
		output.writeString(indent_string[0 .. $-1] ~ "</" ~ tag ~ ">");
	}

	private void buildFilterNodeWriter(OutputContext output, in ref string tagline, int tagline_number,
		int indent, in Line[] lines)
	{
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
		int lc = content.length ? tagline_number : tagline_number+1;
		foreach( i; 0 .. lines.length ){
			while( lc < lines[i].number ){ // DMDBUG: while(lc++ < lines[i].number) silently loops and only executes the last iteration
				content ~= '\n';
				lc++;
			}
			content ~= lines[i].text[(indent+1)*indentStyle.length .. $];
		}

		auto out_indent = output.m_baseIndent + indent;

		// compile-time filter whats possible
		filter_loop:
		foreach_reverse( f; filters ){
			bool found = true;
			switch(f){
				default: found = false; break;//break filter_loop;
				case "css": content = filterCSS(content, out_indent); break;
				case "javascript": content = filterJavaScript(content, out_indent); break;
				case "markdown": content = filterMarkdown(content, out_indent); break;
				case "htmlescape": content = filterHtmlEscape(content, out_indent); break;
			}
			if (found) filters.length = filters.length-1;
			else break;
		}

		// the rest of the filtering will happen at run time
		string filter_expr;
		foreach_reverse( flt; filters ) filter_expr ~= "s_filters[\""~dstringEscape(flt)~"\"](";
		filter_expr ~= "\"" ~ dstringEscape(content) ~ "\"";
		foreach( i; 0 .. filters.length ) filter_expr ~= ", "~cttostring(out_indent)~")";

		output.writeStringExpr(filter_expr);
	}

	private auto parseHtmlTag(in ref string line, out size_t i, out HTMLAttribute[] attribs)
	{
		struct WSType {
			bool inner = true;
			bool outer = true;
			bool block_tag = false;
			bool isTranslated;
		}

		i = 0;

		string id;
		string classes;

		WSType ws_type;

		// parse #id and .classes
		while( i < line.length ){
			if( line[i] == '#' ){
				i++;
				assertp(id.length == 0, "Id may only be set once.");
				id = skipIdent(line, i, "-_");

				// put #id and .classes into the attribs list
				if( id.length ) attribs ~= HTMLAttribute("id", '"'~id~'"');
			} else if (line[i] == '&') {
				i++;
				assertp(i >= line.length || line[i] == ' ' || line[i] == '.');
				ws_type.isTranslated = true;
			} else if( line[i] == '.' ){
				i++;
				// check if tag ends with dot
				if (i == line.length || line[i] == ' ') {
					i = line.length;
					ws_type.block_tag = true;
					break;
				}
				auto cls = skipIdent(line, i, "-_");
				if( classes.length == 0 ) classes = cls;
				else classes ~= " " ~ cls;
			} else if (line[i] == '(') {
				// parse other attributes
				i++;
				string attribstring = skipUntilClosingClamp(line, i);
				parseAttributes(attribstring, attribs);
				i++;
			} else break;
		}

		// parse whitespaces removal tokens
		for(; i < line.length; i++) {
			if(line[i] == '<') ws_type.inner = false;
			else if(line[i] == '>') ws_type.outer = false;
			else break;
		}

		// add special attribute for extra classes that is handled by buildHtmlTag
		if( classes.length ){
			bool has_class = false;
			foreach( a; attribs )
				if( a.key == "class" ){
					has_class = true;
					break;
				}

			if( has_class ) attribs ~= HTMLAttribute("$class", classes);
			else attribs ~= HTMLAttribute("class", "\"" ~ classes ~ "\"");
		}

		// skip until the optional tag text contents begin
		skipWhitespace(line, i);

		return ws_type;
	}

	private void buildHtmlTag(OutputContext output, in ref string tag, int level, ref HTMLAttribute[] attribs, bool is_singular_tag, bool outer_whitespaces = true)
	{
		if (outer_whitespaces) {
			output.writeString("\n");
			assertp(output.stackSize >= level);
			output.writeIndent(level);
		}
		output.writeString("<" ~ tag);
		foreach( att; attribs ){
			if( att.key[0] == '$' ) continue; // ignore special attributes
			if( isStringLiteral(att.value) ){
				output.writeString(" "~att.key~"=\"");
				if( !hasInterpolations(att.value) ) output.writeString(htmlAttribEscape(dstringUnescape(att.value[1 .. $-1])));
				else buildInterpolatedString(output, att.value[1 .. $-1], true);

				// output extra classes given as .class
				if( att.key == "class" ){
					foreach( a; attribs )
						if( a.key == "$class" ){
							output.writeString(" " ~ a.value);
							break;
						}
				}

				output.writeString("\"");
			} else {
				output.writeCodeLine("static if(is(typeof("~att.value~") == bool)){ if("~att.value~"){");
				if (!output.m_isHTML5)
					output.writeString(` `~att.key~`="`~att.key~`"`);
				else
					output.writeString(` `~att.key);
				output.writeCodeLine("}} else static if(is(typeof("~att.value~") == string[])){\n");
				output.writeString(` `~att.key~`="`);
				output.writeExprHtmlAttribEscaped(`join(`~att.value~`, " ")`);
				output.writeString(`"`);
				output.writeCodeLine("} else static if(is(typeof("~att.value~") == string)) {");
				output.writeCodeLine("if ("~att.value~"){");
				output.writeString(` `~att.key~`="`);
				output.writeExprHtmlAttribEscaped(att.value);
				output.writeString(`"`);
				output.writeCodeLine("}");
				output.writeCodeLine("} else {");
				output.writeString(` `~att.key~`="`);
				output.writeExprHtmlAttribEscaped(att.value);
				output.writeString(`"`);
				output.writeCodeLine("}");
			}
		}

		output.writeString(is_singular_tag ? "/>" : ">");
	}

	private void parseAttributes(in ref string str, ref HTMLAttribute[] attribs)
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
				value = skipExpression(str, i);
				if( isStringLiteral(value) && value[0] == '\'' ){
					value = '"' ~ value[1 .. $-1] ~ '"';
				}
			} else value = "true";

			assertp(i == str.length || str[i] == ',', "Unexpected text following attribute: '"~str[0..i]~"' ('"~str[i..$]~"')");
			if( i < str.length ){
				i++;
				skipWhitespace(str, i);
			}

			if (name == "class" && value == `""`) continue;
			attribs ~= HTMLAttribute(name, value);
		}
	}

	private bool hasInterpolations(in char[] str)
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

	private void buildInterpolatedString(OutputContext output, string str, bool escape_quotes = false)
	{
		size_t start = 0, i = 0;
		while( i < str.length ){
			// check for escaped characters
			if( str[i] == '\\' ){
				if( i > start ) output.writeString(str[start .. i]);
				output.writeRawString(sanitizeEscaping(str[i .. i+2]));
				i += 2;
				start = i;
				continue;
			}

			if( (str[i] == '#' || str[i] == '!') && i+1 < str.length ){
				bool escape = str[i] == '#';
				if( i > start ){
					output.writeString(str[start .. i]);
					start = i;
				}
				assertp(str[i+1] != str[i], "Please use \\ to escape # or ! instead of ## or !!.");
				if( str[i+1] == '{' ){
					i += 2;
					auto expr = dstringUnescape(skipUntilClosingBrace(str, i));
					if( escape && !escape_quotes ) output.writeExprHtmlEscaped(expr);
					else if( escape ) output.writeExprHtmlAttribEscaped(expr);
					else output.writeExpr(expr);
					i++;
					start = i;
				} else i++;
			} else i++;
		}

		if( i > start ) output.writeString(str[start .. i]);
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
		while( idx < s.length ){
			if( s[idx] == '\\' ){
				// pass escape character through - will be handled later by buildInterpolatedString
				idx++;
				assertp(idx < s.length, "'\\' must be followed by something (escaped character)!");
			} else if( s[idx] == delimiter ) break;
			idx++;
		}
		return s[start .. idx];
	}

	private string skipExpression(in ref string s, ref size_t idx)
	{
		string clamp_stack;
		size_t start = idx;
		while( idx < s.length ){
			switch( s[idx] ){
				default: break;
				case ',':
					if( clamp_stack.length == 0 )
						return s[start .. idx];
					break;
				case '"', '\'':
					idx++;
					skipAttribString(s, idx, s[idx-1]);
					break;
				case '(': clamp_stack ~= ')'; break;
				case '[': clamp_stack ~= ']'; break;
				case '{': clamp_stack ~= '}'; break;
				case ')', ']', '}':
					if( s[idx] == ')' && clamp_stack.length == 0 )
						return s[start .. idx];
					assertp(clamp_stack.length > 0 && clamp_stack[$-1] == s[idx],
						"Unexpected '"~s[idx]~"'");
					clamp_stack.length--;
					break;
			}
			idx++;
		}

		assertp(clamp_stack.length == 0, "Expected '"~clamp_stack[$-1]~"' before end of attribute expression.");
		return s[start .. $];
	}

	private string unindent(in ref string str, in ref string indent)
	{
		size_t lvl = indentLevel(str, indent);
		return str[lvl*indent.length .. $];
	}

	private string unindent(in ref string str, in ref string indent, size_t level)
	{
		assert(level <= indentLevel(str, indent));
		return str[level*indent.length .. $];
	}

	private int indentLevel(in ref string s, in ref string indent, bool strict = true)
	{
		if( indent.length == 0 ) return 0;
		assertp(!strict || (s[0] != ' ' && s[0] != '\t') || s[0] == indent[0],
			"Indentation style is inconsistent with previous lines.");
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

	private void assertp(bool cond, lazy string text = null, string file = __FILE__, int cline = __LINE__)
	{
		Line ln;
		if( m_lineIndex < lineCount ) ln = line(m_lineIndex);
		assert(cond, "template "~ln.file~" line "~cttostring(ln.number)~": "~text~"("~file~":"~cttostring(cline)~")");
	}

	private TemplateBlock* getFile(string filename)
	{
		foreach( i; 0 .. m_files.length )
			if( (*m_files)[i].name == filename )
				return &(*m_files)[i];
		assertp(false, "Bug: include input file "~filename~" not found in internal list!?");
		assert(false);
	}

	private TemplateBlock* getBlock(string name)
	{
		foreach( i; 0 .. m_blocks.blocks.length )
			if( m_blocks.blocks[i].name == name )
				return &m_blocks.blocks[i];
		return null;
	}
}

private struct HTMLAttribute {
	string key;
	string value;
}

/// private
private void buildSpecialTag(OutputContext output, string tag, int level)
{
	output.writeString("\n");
	output.writeIndent(level);
	output.writeString("<" ~ tag ~ ">");
}

private bool isStringLiteral(string str)
{
	size_t i = 0;
	while( i < str.length && (str[i] == ' ' || str[i] == '\t') ) i++;
	if( i >= str.length ) return false;
	char delimiter = str[i];
	if( delimiter != '"' && delimiter != '\'' ) return false;
	while( i < str.length && str[i] != delimiter ){
		if( str[i] == '\\' ) i++;
		i++;
	}
	return i < str.length;
}

/// Internal function used for converting an interpolation expression to string
string _toString(T)(T v)
{
	static if( is(T == string) ) return v;
	else static if( __traits(compiles, v.opCast!string()) ) return cast(string)v;
	else static if( __traits(compiles, v.toString()) ) return v.toString();
	else return to!string(v);
}

unittest {
	static string compile(string diet, ALIASES...)() {
		import vibe.stream.memory;
		auto dst = new MemoryOutputStream;
		compileDietString!(diet, ALIASES)(dst);
		return strip(cast(string)(dst.data));
	}

	assert(compile!(`!!! 5`) == `<!DOCTYPE html>`, `_`~compile!(`!!! 5`)~`_`);
	assert(compile!(`!!! html`) == `<!DOCTYPE html>`);
	assert(compile!(`doctype html`) == `<!DOCTYPE html>`);
	assert(compile!(`p= 5`) == `<p>5</p>`);
	assert(compile!(`script= 5`) == `<script>5</script>`);
	assert(compile!(`style= 5`) == `<style>5</style>`);
	assert(compile!(`include #{"p Hello"}`) == "<p>Hello</p>");

	// issue 372
	assert(compile!(`div(class="")`) == `<div></div>`);
	assert(compile!(`div.foo(class="")`) == `<div class="foo"></div>`);
	assert(compile!(`div.foo(class="bar")`) == `<div class="bar foo"></div>`);
	assert(compile!(`div(class="foo")`) == `<div class="foo"></div>`);
	assert(compile!(`div#foo(class='')`) == `<div id="foo"></div>`);

	// issue 520
	assert(compile!("- auto cond = true;\ndiv(someattr=cond ? \"foo\" : null)") == "<div someattr=\"foo\"></div>");
	assert(compile!("- auto cond = false;\ndiv(someattr=cond ? \"foo\" : null)") == "<div></div>");
	assert(compile!("- auto cond = false;\ndiv(someattr=cond ? true : false)") == "<div></div>");
	assert(compile!("- auto cond = true;\ndiv(someattr=cond ? true : false)") == "<div someattr=\"someattr\"></div>");
	assert(compile!("doctype html\n- auto cond = true;\ndiv(someattr=cond ? true : false)") 
		== "<!DOCTYPE html>\n<div someattr></div>");
	assert(compile!("doctype html\n- auto cond = false;\ndiv(someattr=cond ? true : false)") 
		== "<!DOCTYPE html>\n<div></div>");

	// issue 510
	assert(compile!("pre.test\n\tfoo") == "<pre class=\"test\">\n\t<foo></foo></pre>");
	assert(compile!("pre.test.\n\tfoo") == "<pre class=\"test\">\nfoo</pre>");
	assert(compile!("pre.test. foo") == "<pre class=\"test\"></pre>");
	assert(compile!("pre().\n\tfoo") == "<pre>\nfoo</pre>");
	assert(compile!("pre#foo.test(data-img=\"sth\",class=\"meh\"). something\n\tmeh") ==
	       "<pre id=\"foo\" data-img=\"sth\" class=\"meh test\">\nmeh</pre>");
}


/**************************************************************************************************/
/* Compile time filters                                                                           */
/**************************************************************************************************/

private string filterCSS(string text, size_t indent)
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


private string filterJavaScript(string text, size_t indent)
{
	auto lines = splitLines(text);

	string indent_string = "\n";
	while( indent-- > 0 ) indent_string ~= '\t';

	string ret = indent_string[0 .. $-1]~"<script type=\"text/javascript\">";
	ret ~= indent_string~"//<![CDATA[";
	foreach( ln; lines ) ret ~= indent_string ~ ln;
	ret ~= indent_string ~ "//]]>"~indent_string[0 .. $-1]~"</script>";

	return ret;
}

private string filterMarkdown(string text, size_t)
{
	// TODO: indent
	return vibe.textfilter.markdown.filterMarkdown(text);
}

private string filterHtmlEscape(string text, size_t)
{
	// TODO: indent
	return htmlEscape(text);
}
