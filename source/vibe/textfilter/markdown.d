/**
	Markdown parser implementation

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.textfilter.markdown;

import vibe.core.log;
import vibe.textfilter.html;
import vibe.utils.string;

import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.string;

/*
	TODO:
		detect inline HTML tags
*/

version(MarkdownTest)
{
	int main()
	{
		import std.file;
		setLogLevel(LogLevel.Trace);
		auto text = readText("test.txt");
		auto result = appender!string();
		filterMarkdown(result, text);
		foreach( ln; splitLines(result.data) )
			logInfo(ln);
		return 0;
	}
}

/** Returns a Markdown filtered HTML string.
*/
string filterMarkdown()(string str)
{
	auto dst = appender!string();
	filterMarkdown(dst, str);
	return dst.data;
}


/** Markdown filters the given string and writes the corresponding HTML to an output range.
*/
void filterMarkdown(R)(ref R dst, string src)
{
	auto all_lines = splitLines(src);
	auto links = scanForReferences(all_lines);
	auto lines = parseLines(all_lines);
	Block root_block;
	parseBlocks(root_block, lines, null);
	writeBlock(dst, root_block, links);
}

private {
	immutable s_blockTags = ["div", "ol", "p", "pre", "section", "table", "ul"];
}

private enum IndentType {
	White,
	Quote
}

private enum LineType {
	Undefined,
	Blank,
	Plain,
	Hline,
	AtxHeader,
	SetextHeader,
	UList,
	OList,
	HtmlBlock
}

private struct Line {
	LineType type;
	IndentType[] indent;
	string text;
	string unindented;

	string unindent(size_t n)
	{
		assert(n <= indent.length);
		string ln = text;
		foreach( i; 0 .. n ){
			final switch(indent[i]){
				case IndentType.White:
					if( ln[0] == ' ' ) ln = ln[4 .. $];
					else ln = ln[1 .. $];
					break;
				case IndentType.Quote:
					ln = ln.stripLeft()[1 .. $];
					break;
			}
		}
		return ln;
	}
}

private Line[] parseLines(ref string[] lines)
{
	Line[] ret;
	while( !lines.empty ){
		auto ln = lines.front;
		lines.popFront();

		Line lninfo;
		lninfo.text = ln;

		while( ln.length > 0 ){
			if( ln[0] == '\t' ){
				lninfo.indent ~= IndentType.White;
				ln.popFront();
			} else if( ln.startsWith("    ") ){
				lninfo.indent ~= IndentType.White;
				ln.popFrontN(4);
			} else {
				ln = ln.stripLeft();
				if( ln.startsWith(">") ){
					lninfo.indent ~= IndentType.Quote;
					ln.popFront();
				} else break;
			}
		}
		lninfo.unindented = ln;

		if( isAtxHeaderLine(ln) ) lninfo.type = LineType.AtxHeader;
		else if( isSetextHeaderLine(ln) ) lninfo.type = LineType.SetextHeader;
		else if( isOListLine(ln) ) lninfo.type = LineType.OList;
		else if( isUListLine(ln) ) lninfo.type = LineType.UList;
		else if( isHlineLine(ln) ) lninfo.type = LineType.Hline;
		else if( isLineBlank(ln) ) lninfo.type = LineType.Blank;
		else if( isHtmlBlockLine(ln) ) lninfo.type = LineType.HtmlBlock;
		else lninfo.type = LineType.Plain;

		ret ~= lninfo;
	}
	return ret;
}

private enum BlockType {
	Plain,
	Text,
	Paragraph,
	Header,
	OList,
	UList,
	ListItem,
	Code,
	Quote
}

private struct Block {
	BlockType type;
	string[] text;
	Block[] blocks;
	size_t headerLevel;
}

private void parseBlocks(ref Block root, ref Line[] lines, IndentType[] base_indent)
{
	if( base_indent.length == 0 ) root.type = BlockType.Text;
	else if( base_indent[$-1] == IndentType.Quote ) root.type = BlockType.Quote;

	while( !lines.empty ){
		auto ln = lines.front;

		if( ln.type == LineType.Blank ){
			lines.popFront();
			continue;
		}

		if( ln.indent != base_indent ){
			if( ln.indent.length < base_indent.length || ln.indent[0 .. base_indent.length] != base_indent )
				return;

			auto cindent = base_indent ~ IndentType.White;
			if( ln.indent == cindent ){
				Block cblock;
				cblock.type = BlockType.Code;
				while( !lines.empty && lines.front.indent.length >= cindent.length
						&& lines.front.indent[0 .. cindent.length] == cindent)
				{
					cblock.text ~= lines.front.unindent(cindent.length);
					lines.popFront();
				}
				root.blocks ~= cblock;
			} else {
				Block subblock;
				parseBlocks(subblock, lines, ln.indent[0 .. base_indent.length+1]);
				root.blocks ~= subblock;
			}
		} else {
			Block b;
			final switch(ln.type){
				case LineType.Undefined: assert(false);
				case LineType.Blank: assert(false);
				case LineType.Plain:
					if( lines.length >= 2 && lines[1].type == LineType.SetextHeader ){
						auto setln = lines[1].unindented;
						b.type = BlockType.Header;
						b.text = [ln.unindented];
						b.headerLevel = setln.strip()[0] == '=' ? 1 : 2;
						lines.popFrontN(2);
					} else {
						b.type = BlockType.Paragraph;
						b.text = skipText(lines, base_indent);
					}
					break;
				case LineType.Hline:
					b.type = BlockType.Plain;
					b.text = ["<hr>"];
					lines.popFront();
					break;
				case LineType.AtxHeader:
					b.type = BlockType.Header;
					string hl = ln.unindented;
					b.headerLevel = 0;
					while( hl.length > 0 && hl[0] == '#' ){
						b.headerLevel++;
						hl = hl[1 .. $];
					}
					while( hl.length > 0 && (hl[$-1] == '#' || hl[$-1] == ' ') )
						hl = hl[0 .. $-1];
					b.text = [hl];
					lines.popFront();
					break;
				case LineType.SetextHeader:
					lines.popFront();
					break;
				case LineType.UList:
				case LineType.OList:
					b.type = ln.type == LineType.UList ? BlockType.UList : BlockType.OList;
					auto itemindent = base_indent ~ IndentType.White;
					bool firstItem = true, paraMode = false;
					while(!lines.empty && lines.front.type == ln.type && lines.front.indent == base_indent ){
						Block itm;
						itm.text = skipText(lines, itemindent);
						itm.text[0] = removeListPrefix(itm.text[0], ln.type);

						// emit <p></p> if there are blank lines between the items
						if( firstItem && !lines.empty && lines.front.type == LineType.Blank )
							paraMode = true;
						firstItem = false;
						if( paraMode ){
							Block para;
							para.type = BlockType.Paragraph;
							para.text = itm.text;
							itm.blocks ~= para;
							itm.text = null;
						}

						parseBlocks(itm, lines, itemindent);
						itm.type = BlockType.ListItem;
						b.blocks ~= itm;
					}
					break;
				case LineType.HtmlBlock:
					int nestlevel = 0;
					auto starttag = parseHtmlBlockLine(ln.unindented);
					if( !starttag.isHtmlBlock || !starttag.open )
						break;

					b.type = BlockType.Plain;
					while(!lines.empty){
						if( lines.front.indent.length < base_indent.length ) break;
						if( lines.front.indent[0 .. base_indent.length] != base_indent ) break;

						auto str = lines.front.unindent(base_indent.length);
						auto taginfo = parseHtmlBlockLine(str);
						b.text ~= lines.front.unindent(base_indent.length);
						lines.popFront();
						if( taginfo.isHtmlBlock && taginfo.tagName == starttag.tagName )
							nestlevel += taginfo.open ? 1 : -1;
						if( nestlevel <= 0 ) break;
					}
					break;
			}
			root.blocks ~= b;
		}
	}
}

private string[] skipText(ref Line[] lines, IndentType[] indent)
{
	static bool matchesIndent(IndentType[] indent, IndentType[] base_indent)
	{
		if( indent.length > base_indent.length ) return false;
		if( indent != base_indent[0 .. indent.length] ) return false;
		auto qidx = base_indent.retro().countUntil(IndentType.Quote);
		if( qidx >= 0 ){
			qidx = base_indent.length-1 - qidx;
			if( indent.length <= qidx ) return false;
		}
		return true;
	}

	string[] ret;

	while(true){
		ret ~= lines.front.unindent(min(indent.length, lines.front.indent.length));
		lines.popFront();

		if( lines.empty || !matchesIndent(lines.front.indent, indent) || lines.front.type != LineType.Plain )
			return ret;
	}
}

/// private
private void writeBlock(R)(ref R dst, ref const Block block, LinkRef[string] links)
{
	final switch(block.type){
		case BlockType.Plain:
			foreach( ln; block.text ){
				dst.put(ln);
				dst.put("\n");
			}
			foreach(b; block.blocks)
				writeBlock(dst, b, links);
			break;
		case BlockType.Text:
			foreach( ln; block.text ){
				writeMarkdownEscaped(dst, ln, links);
				dst.put("\n");
			}
			foreach(b; block.blocks)
				writeBlock(dst, b, links);
			break;
		case BlockType.Paragraph:
			assert(block.blocks.length == 0);
			dst.put("<p>");
			foreach( ln; block.text ){
				writeMarkdownEscaped(dst, ln, links);
				dst.put("\n");
			}
			dst.put("</p>\n");
			break;
		case BlockType.Header:
			assert(block.blocks.length == 0);
			auto nstr = to!string(block.headerLevel);
			dst.put("<h");
			dst.put(nstr);
			dst.put(">");
			assert(block.text.length == 1);
			writeMarkdownEscaped(dst, block.text[0], links);
			dst.put("</h");
			dst.put(nstr);
			dst.put(">\n");
			break;
		case BlockType.OList:
			dst.put("<ol>\n");
			foreach(b; block.blocks)
				writeBlock(dst, b, links);
			dst.put("</ol>\n");
			break;
		case BlockType.UList:
			dst.put("<ul>\n");
			foreach(b; block.blocks)
				writeBlock(dst, b, links);
			dst.put("</ul>\n");
			break;
		case BlockType.ListItem:
			dst.put("<li>");
			foreach(ln; block.text){
				writeMarkdownEscaped(dst, ln, links);
				dst.put("\n");
			}
			foreach(b; block.blocks)
				writeBlock(dst, b, links);
			dst.put("</li>\n");
			break;
		case BlockType.Code:
			assert(block.blocks.length == 0);
			dst.put("<code><pre>");
			foreach(ln; block.text){
				filterHtmlEscape(dst, ln);
				dst.put("\n");
			}
			dst.put("</pre></code>");
			break;
		case BlockType.Quote:
			dst.put("<quot>");
			foreach(ln; block.text){
				writeMarkdownEscaped(dst, ln, links);
				dst.put("\n");
			}
			foreach(b; block.blocks)
				writeBlock(dst, b, links);
			dst.put("</quot>\n");
			break;
	}
}

/// private
private void writeMarkdownEscaped(R)(ref R dst, string ln, in LinkRef[string] linkrefs)
{
	bool br = ln.endsWith("  ");
	while( ln.length > 0 ){
		switch( ln[0] ){
			default:
				dst.put(ln[0]);
				ln = ln[1 .. $];
				break;
			case '\\':
				if( ln.length >= 2 ){
					switch(ln[1]){
						default:
							dst.put(ln[0 .. 2]);
							ln = ln[2 .. $];
							break;
						case '\'', '`', '*', '_', '{', '}', '[', ']',
							'(', ')', '#', '+', '-', '.', '!':
							dst.put(ln[1]);
							ln = ln[2 .. $];
							break;
					}
				} else {
					dst.put(ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '_':
			case '*':
				string text;
				if( auto em = parseEmphasis(ln, text) ){
					dst.put(em == 1 ? "<em>" : em == 2 ? "<strong>" : "<strong><em>");
					filterHtmlEscape(dst, text);
					dst.put(em == 1 ? "</em>" : em == 2 ? "</strong>": "</em></strong>");
				} else {
					dst.put(ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '`':
				string code;
				if( parseInlineCode(ln, code) ){
					dst.put("<code>");
					filterHtmlEscape(dst, code);
					dst.put("</code>");
				} else {
					dst.put(ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '[':
				Link link;
				if( parseLink(ln, link, linkrefs) ){
					dst.put("<a href=\"");
					filterHtmlEscape(dst, link.url);
					dst.put("\"");
					if( link.title.length ){
						dst.put(" title=\"");
						filterHtmlEscape(dst, link.title);
						dst.put("\"");
					}
					dst.put(">");
					filterHtmlEscape(dst, link.text);
					dst.put("</a>");
				} else {
					dst.put(ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '!':
				Link link;
				if( parseLink(ln, link, linkrefs) ){
					dst.put("<img src=\"");
					filterHtmlEscape(dst, link.title);
					dst.put(link.url);
					dst.put("\" alt=\"");
					filterHtmlEscape(dst, link.text);
					dst.put("\"");
					if( link.title.length ){
						dst.put(" title=\"");
						filterHtmlEscape(dst, link.title);
						dst.put("\"");
					}
					dst.put(">");
				} else if( ln.length >= 2 ){
					dst.put(ln[0 .. 2]);
					ln = ln[2 .. $];
				} else {
					dst.put(ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '<':
				string url;
				if( parseAutoLink(ln, url) ){
					bool is_email = url.startsWith("mailto:");
					dst.put("<a href=\"");
					if( is_email ) filterHtmlAllEscape(dst, url);
					else filterHtmlEscape(dst, url);
					dst.put("\">");
					if( is_email ) filterHtmlAllEscape(dst, url[7 .. $]);
					else filterHtmlEscape(dst, url);
					dst.put("</a>");
				} else {
					dst.put(ln[0]);
					ln = ln[1 .. $];
				}
				break;
		}
	}
	if( br ) dst.put("<br/>");
}

/// private
private void outputHeaderLine(R)(ref R dst, string ln, string hln)
{
	hln = stripLeft(hln);
	string htype;
	if( hln.length > 0 ){ // Setext style header
		htype = hln[0] == '=' ? "1" : "2";
	} else { // atx style header
		size_t lvl = 0;
		while( ln.length > 0 && ln[0] == '#' ){
			lvl++;
			ln = ln[1 .. $];
		}
		htype = to!string(lvl);
		while( ln.length > 0 && (ln[$-1] == '#' || ln[$-1] == ' ') )
			ln = ln[0 .. $-1];
	}
	dst.put("<h");
	dst.put(htype);
	dst.put('>');
	outputLine(dst, ln, MarkdownState.Text, null);
	dst.put("</h");
	dst.put(htype);
	dst.put(">\n");
}

/// private
private void enterBlockQuote(R)(ref R dst)
{
	dst.put("<blockquote>");
}

/// private
private void exitBlockQuote(R)(ref R dst)
{
	dst.put("</blockquote>");
}

private bool isLineBlank(string ln)
{
	return allOf(ln, " \t");
}

private bool isSetextHeaderLine(string ln)
{
	ln = stripLeft(ln);
	if( ln.length < 1 ) return false;
	if( ln[0] == '=' ) return allOf(ln, " \t=");
	if( ln[0] == '-' ) return allOf(ln, " \t-");
	return false;
}

private bool isAtxHeaderLine(string ln)
{
	ln = stripLeft(ln);
	return ln.startsWith("#");
}

private bool isHlineLine(string ln)
{
	if( allOf(ln, " -") && count(ln, '-') >= 3 ) return true;
	if( allOf(ln, " *") && count(ln, '*') >= 3 ) return true;
	return false;
}

private bool isQuoteLine(string ln)
{
	return ln.stripLeft().startsWith(">");
}

private size_t getQuoteLevel(string ln)
{
	size_t level = 0;
	ln = stripLeft(ln);
	while( ln.length > 0 && ln[0] == '>' ){
		level++;
		ln = stripLeft(ln[1 .. $]);
	}
	return level;
}

private bool isUListLine(string ln)
{
	ln = stripLeft(ln);
	if( ln.length < 2 ) return false;
	if( "*+-".countUntil(ln[0]) < 0 ) return false;
	if( ln[1] != ' ' && ln[1] != '\t' ) return false;
	return true;
}

private bool isOListLine(string ln)
{
	ln = stripLeft(ln);
	if( ln.length < 1 ) return false;
	if( ln[0] < '0' || ln[0] > '9' ) return false;
	ln = ln[1 .. $];
	while( ln.length > 0 && ln[0] >= '0' && ln[0] <= '9' )
		ln = ln[1 .. $];
	if( ln.length < 2 ) return false;
	if( ln[0] != '.' ) return false;
	if( ln[1] != ' ' && ln[1] != '\t' )
		return false;
	return true;
}

private string removeListPrefix(string str, LineType tp)
{
	switch(tp){
		default: assert(false);
		case LineType.OList: // skip bullets and output using normal escaping
			auto idx = str.countUntil('.');
			assert(idx > 0);
			return str[idx+1 .. $].stripLeft();
		case LineType.UList:
			return stripLeft(str.stripLeft()[1 .. $]);
	}
}


private auto parseHtmlBlockLine(string ln)
{
	struct HtmlBlockInfo {
		bool isHtmlBlock;
		string tagName;
		bool open;
	}

	HtmlBlockInfo ret;
	ret.isHtmlBlock = false;
	ret.open = true;

	ln = strip(ln);
	if( ln.length < 3 ) return ret;
	if( ln[0] != '<' ) return ret;
	if( ln[1] == '/' ){
		ret.open = false;
		ln = ln[1 .. $];
	}
	if( !isAlpha(ln[1]) ) return ret;
	ln = ln[1 .. $];
	size_t idx = 0;
	while( idx < ln.length && ln[idx] != ' ' && ln[idx] != '>' )
		idx++;
	ret.tagName = ln[0 .. idx];
	ln = ln[idx .. $];

	auto eidx = ln.countUntil('>');
	if( eidx < 0 ) return ret;
	if( eidx != ln.length-1 ) return ret;

	if( s_blockTags.countUntil(ret.tagName) < 0 ) return ret;

	ret.isHtmlBlock = true;
	return ret;
}

private bool isHtmlBlockLine(string ln)
{
	auto bi = parseHtmlBlockLine(ln);
	return bi.isHtmlBlock && bi.open;
}

private bool isHtmlBlockCloseLine(string ln)
{
	auto bi = parseHtmlBlockLine(ln);
	return bi.isHtmlBlock && !bi.open;
}

private string getHtmlTagName(string ln)
{
	return parseHtmlBlockLine(ln).tagName;
}

private bool isLineIndented(string ln)
{
	return ln.startsWith("\t") || ln.startsWith("    ");
}

private string unindentLine(string ln)
{
	if( ln.startsWith("\t") ) return ln[1 .. $];
	if( ln.startsWith("    ") ) return ln[4 .. $];
	assert(false);
}

private int parseEmphasis(ref string str, ref string text)
{
	string pstr = str;
	if( pstr.length < 3 ) return false;

	string ctag;
	if( pstr.startsWith("***") ) ctag = "***";
	else if( pstr.startsWith("**") ) ctag = "**";
	else if( pstr.startsWith("*") ) ctag = "*";
	else if( pstr.startsWith("___") ) ctag = "___";
	else if( pstr.startsWith("__") ) ctag = "__";
	else if( pstr.startsWith("_") ) ctag = "_";
	else return false;

	pstr = pstr[ctag.length .. $];

	auto cidx = pstr.countUntil(ctag);
	if( cidx < 1 ) return false;

	text = pstr[0 .. cidx];

	str = pstr[cidx+ctag.length .. $];
	return cast(int)ctag.length;
}

private bool parseInlineCode(ref string str, ref string code)
{
	string pstr = str;
	if( pstr.length < 3 ) return false;
	string ctag;
	if( pstr.startsWith("``") ) ctag = "``";
	else if( pstr.startsWith("`") ) ctag = "`";
	else return false;
	pstr = pstr[ctag.length .. $];

	auto cidx = pstr.countUntil(ctag);
	if( cidx < 1 ) return false;

	code = pstr[0 .. cidx];
	str = pstr[cidx+ctag.length .. $];
	return true;
}

private bool parseLink(ref string str, ref Link dst, in LinkRef[string] linkrefs)
{
	string pstr = str;
	if( pstr.length < 3 ) return false;
	// ignore img-link prefix
	if( pstr[0] == '!' ) pstr = pstr[1 .. $];

	// parse the text part [text]
	if( pstr[0] != '[' ) return false;
	pstr = pstr[1 .. $];
	auto cidx = pstr.countUntil(']');
	if( cidx < 1 ) return false;
	string refid;
	dst.text = pstr[0 .. cidx];
	pstr = pstr[cidx+1 .. $];

	// parse either (link '['"title"']') or '[' ']'[refid]
	if( pstr.length < 3 ) return false;
	if( pstr[0] == '('){
		pstr = pstr[1 .. $];
		cidx = pstr.countUntil(')');
		auto spidx = pstr.countUntil(' ');
		if( spidx > 0 && spidx < cidx ){
			dst.url = pstr[0 .. spidx];
			dst.title = pstr[spidx+1 .. cidx];
			if( dst.title.length < 2 ) return false;
			if( !dst.title.startsWith("\"") || !dst.title.endsWith("\"") ) return false;
			dst.title = dst.title[1 .. $-1];
		} else {
			dst.url = pstr[0 .. cidx];
			dst.title = null;
		}
		pstr = pstr[cidx+1 .. $];
	} else {
		if( pstr[0] == ' ' ) pstr = pstr[1 .. $];
		if( pstr[0] != '[' ) return false;
		pstr = pstr[1 .. $];
		cidx = pstr.countUntil("]");
		if( cidx < 0 ) return false;
		if( cidx == 0 ) refid = dst.text;
		else refid = pstr[0 .. cidx];
		pstr = pstr[cidx+1 .. $];
	}


	if( refid.length > 0 ){
		auto pr = toLower(refid) in linkrefs;
		if( !pr ){
			logDebug("[LINK REF NOT FOUND: '%s'", refid);
			return false;
		}
		dst.url = pr.url;
		dst.title = pr.title;
	}

	str = pstr;
	return true;
}

private bool parseAutoLink(ref string str, ref string url)
{
	string pstr = str;
	if( pstr.length < 3 ) return false;
	if( pstr[0] != '<' ) return false;
	pstr = pstr[1 .. $];
	auto cidx = pstr.countUntil('>');
	if( cidx < 0 ) return false;
	url = pstr[0 .. cidx];
	if( anyOf(url, " \t") ) return false;
	str = pstr[cidx+1 .. $];
	if( url.countUntil('@') > 0 ) url = "mailto:"~url;
	return true;
}

private LinkRef[string] scanForReferences(ref string[] lines)
{
	LinkRef[string] ret;
	bool[size_t] reflines;

	// search for reference definitions:
	//   [refid] link "opt text"
	//   [refid] <link> "opt text"
	//   "opt text", 'opt text', (opt text)
	//   line must not be indented
	foreach( lnidx, ln; lines ){
		if( isLineIndented(ln) ) continue;
		ln = strip(ln);
		if( !ln.startsWith("[") ) continue;
		ln = ln[1 .. $];

		auto idx = ln.countUntil("]:");
		if( idx < 0 ) continue;
		string refid = ln[0 .. idx];
		ln = stripLeft(ln[idx+2 .. $]);

		string url;
		if( ln.startsWith("<") ){
			idx = ln.countUntil(">");
			if( idx < 0 ) continue;
			url = ln[1 .. idx];
			ln = ln[idx+1 .. $];
		} else {
			idx = ln.countUntil(' ');
			if( idx > 0 ){
				url = ln[0 .. idx];
				ln = ln[idx+1 .. $];
			} else {
				idx = ln.countUntil('\t');
				if( idx < 0 ){
					url = ln;
					ln = ln[$ .. $];
				} else {
					url = ln[0 .. idx];
					ln = ln[idx+1 .. $];
				}
			}
		}
		ln = stripLeft(ln);

		string title;
		if( ln.length >= 3 ){
			if( ln[0] == '(' && ln[$-1] == ')' || ln[0] == '\"' && ln[$-1] == '\"' || ln[0] == '\'' && ln[$-1] == '\'' )
				title = ln[1 .. $-1];
		}

		ret[toLower(refid)] = LinkRef(refid, url, title);
		reflines[lnidx] = true;

		logTrace("[detected ref on line %d]", lnidx+1);
	}

	// remove all lines containing references
	auto nonreflines = appender!(string[])();
	nonreflines.reserve(lines.length);
	foreach( i, ln; lines )
		if( i !in reflines )
			nonreflines.put(ln);
	lines = nonreflines.data();

	return ret;
}

private struct LinkRef {
	string id;
	string url;
	string title;
}

private struct Link {
	string text;
	string url;
	string title;
}
