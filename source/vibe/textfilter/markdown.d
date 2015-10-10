/**
	Markdown parser implementation

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.textfilter.markdown;

import vibe.core.log;
import vibe.textfilter.html;
import vibe.utils.string;

import std.algorithm : canFind, countUntil, min;
import std.array;
import std.format;
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
string filterMarkdown()(string str, MarkdownFlags flags)
{
	scope settings = new MarkdownSettings;
	settings.flags = flags;
	return filterMarkdown(str, settings);
}
/// ditto
string filterMarkdown()(string str, scope MarkdownSettings settings = null)
@trusted { // Appender not @safe as of 2.065
	auto dst = appender!string();
	filterMarkdown(dst, str, settings);
	return dst.data;
}


/** Markdown filters the given string and writes the corresponding HTML to an output range.
*/
void filterMarkdown(R)(ref R dst, string src, MarkdownFlags flags)
{
	scope settings = new MarkdownSettings;
	settings.flags = flags;
	filterMarkdown(dst, src, settings);
}
/// ditto
void filterMarkdown(R)(ref R dst, string src, scope MarkdownSettings settings = null)
{
	auto defsettings = new MarkdownSettings;
	if (!settings) settings = defsettings;

	auto all_lines = splitLines(src);
	auto links = scanForReferences(all_lines);
	auto lines = parseLines(all_lines, settings);
	Block root_block;
	parseBlocks(root_block, lines, null, settings);
	writeBlock(dst, root_block, links, settings);
}

final class MarkdownSettings {
	/// Controls the capabilities of the parser.
	MarkdownFlags flags = MarkdownFlags.vanillaMarkdown;

	/// Heading tags will start at this level.
	size_t headingBaseLevel = 1;

	/// Called for every link/image URL to perform arbitrary transformations.
	string delegate(string url_or_path, bool is_image) urlFilter;
}

enum MarkdownFlags {
	none = 0,
	keepLineBreaks = 1<<0,
	backtickCodeBlocks = 1<<1,
	noInlineHtml = 1<<2,
	//noLinks = 1<<3,
	//allowUnsafeHtml = 1<<4,
	vanillaMarkdown = none,
	forumDefault = keepLineBreaks|backtickCodeBlocks|noInlineHtml
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
	HtmlBlock,
	CodeBlockDelimiter
}

private struct Line {
	LineType type;
	IndentType[] indent;
	string text;
	string unindented;

	string unindent(size_t n)
	pure @safe {
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

private Line[] parseLines(ref string[] lines, scope MarkdownSettings settings)
pure @safe {
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

		if( (settings.flags & MarkdownFlags.backtickCodeBlocks) && isCodeBlockDelimiter(ln) ) lninfo.type = LineType.CodeBlockDelimiter;
		else if( isAtxHeaderLine(ln) ) lninfo.type = LineType.AtxHeader;
		else if( isSetextHeaderLine(ln) ) lninfo.type = LineType.SetextHeader;
		else if( isHlineLine(ln) ) lninfo.type = LineType.Hline;
		else if( isOListLine(ln) ) lninfo.type = LineType.OList;
		else if( isUListLine(ln) ) lninfo.type = LineType.UList;
		else if( isLineBlank(ln) ) lninfo.type = LineType.Blank;
		else if( !(settings.flags & MarkdownFlags.noInlineHtml) && isHtmlBlockLine(ln) ) lninfo.type = LineType.HtmlBlock;
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

private void parseBlocks(ref Block root, ref Line[] lines, IndentType[] base_indent, scope MarkdownSettings settings)
pure @safe {
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
				parseBlocks(subblock, lines, ln.indent[0 .. base_indent.length+1], settings);
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

						parseBlocks(itm, lines, itemindent, settings);
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
				case LineType.CodeBlockDelimiter:
					lines.popFront(); // TODO: get language from line
					b.type = BlockType.Code;
					while(!lines.empty){
						if( lines.front.indent.length < base_indent.length ) break;
						if( lines.front.indent[0 .. base_indent.length] != base_indent ) break;
						if( lines.front.type == LineType.CodeBlockDelimiter ){
							lines.popFront();
							break;
						}
						b.text ~= lines.front.unindent(base_indent.length);
						lines.popFront();
					}
					break;
			}
			root.blocks ~= b;
		}
	}
}

private string[] skipText(ref Line[] lines, IndentType[] indent)
pure @safe {
	static bool matchesIndent(IndentType[] indent, IndentType[] base_indent)
	{
		if( indent.length > base_indent.length ) return false;
		if( indent != base_indent[0 .. indent.length] ) return false;
		sizediff_t qidx = -1;
		foreach_reverse (i, tp; base_indent) if (tp == IndentType.Quote) { qidx = i; break; }
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
private void writeBlock(R)(ref R dst, ref const Block block, LinkRef[string] links, scope MarkdownSettings settings)
{
	final switch(block.type){
		case BlockType.Plain:
			foreach( ln; block.text ){
				dst.put(ln);
				dst.put("\n");
			}
			foreach(b; block.blocks)
				writeBlock(dst, b, links, settings);
			break;
		case BlockType.Text:
			writeMarkdownEscaped(dst, block, links, settings);
			foreach(b; block.blocks)
				writeBlock(dst, b, links, settings);
			break;
		case BlockType.Paragraph:
			assert(block.blocks.length == 0);
			dst.put("<p>");
			writeMarkdownEscaped(dst, block, links, settings);
			dst.put("</p>\n");
			break;
		case BlockType.Header:
			assert(block.blocks.length == 0);
			auto hlvl = block.headerLevel + (settings ? settings.headingBaseLevel-1 : 0);
			dst.formattedWrite("<h%s>", hlvl);
			assert(block.text.length == 1);
			writeMarkdownEscaped(dst, block.text[0], links, settings);
			dst.formattedWrite("</h%s>\n", hlvl);
			break;
		case BlockType.OList:
			dst.put("<ol>\n");
			foreach(b; block.blocks)
				writeBlock(dst, b, links, settings);
			dst.put("</ol>\n");
			break;
		case BlockType.UList:
			dst.put("<ul>\n");
			foreach(b; block.blocks)
				writeBlock(dst, b, links, settings);
			dst.put("</ul>\n");
			break;
		case BlockType.ListItem:
			dst.put("<li>");
			writeMarkdownEscaped(dst, block, links, settings);
			foreach(b; block.blocks)
				writeBlock(dst, b, links, settings);
			dst.put("</li>\n");
			break;
		case BlockType.Code:
			assert(block.blocks.length == 0);
			dst.put("<pre class=\"prettyprint\"><code>");
			foreach(ln; block.text){
				filterHTMLEscape(dst, ln);
				dst.put("\n");
			}
			dst.put("</code></pre>");
			break;
		case BlockType.Quote:
			dst.put("<blockquote>");
			writeMarkdownEscaped(dst, block, links, settings);
			foreach(b; block.blocks)
				writeBlock(dst, b, links, settings);
			dst.put("</blockquote>\n");
			break;
	}
}

private void writeMarkdownEscaped(R)(ref R dst, ref const Block block, in LinkRef[string] links, scope MarkdownSettings settings)
{
	auto lines = cast(string[])block.text;
	auto text = settings.flags & MarkdownFlags.keepLineBreaks ? lines.join("<br>") : lines.join("\n");
	writeMarkdownEscaped(dst, text, links, settings);
	if (lines.length) dst.put("\n");
}

/// private
private void writeMarkdownEscaped(R)(ref R dst, string ln, in LinkRef[string] linkrefs, scope MarkdownSettings settings)
{
	string filterLink(string lnk, bool is_image) {
		return settings.urlFilter ? settings.urlFilter(lnk, is_image) : lnk;
	}

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
					filterHTMLEscape(dst, text, HTMLEscapeFlags.escapeMinimal);
					dst.put(em == 1 ? "</em>" : em == 2 ? "</strong>": "</em></strong>");
				} else {
					dst.put(ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '`':
				string code;
				if( parseInlineCode(ln, code) ){
					dst.put("<code class=\"prettyprint\">");
					filterHTMLEscape(dst, code, HTMLEscapeFlags.escapeMinimal);
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
					filterHTMLAttribEscape(dst, filterLink(link.url, false));
					dst.put("\"");
					if( link.title.length ){
						dst.put(" title=\"");
						filterHTMLAttribEscape(dst, link.title);
						dst.put("\"");
					}
					dst.put(">");
					writeMarkdownEscaped(dst, link.text, linkrefs, settings);
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
					filterHTMLAttribEscape(dst, filterLink(link.url, true));
					dst.put("\" alt=\"");
					filterHTMLAttribEscape(dst, link.text);
					dst.put("\"");
					if( link.title.length ){
						dst.put(" title=\"");
						filterHTMLAttribEscape(dst, link.title);
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
			case '>':
				if( settings.flags & MarkdownFlags.noInlineHtml ) dst.put("&gt;");
				else dst.put(ln[0]);
				ln = ln[1 .. $];
				break;
			case '<':
				string url;
				if( parseAutoLink(ln, url) ){
					bool is_email = url.startsWith("mailto:");
					dst.put("<a href=\"");
					if( is_email ) filterHTMLAllEscape(dst, url);
					else filterHTMLAttribEscape(dst, filterLink(url, false));
					dst.put("\">");
					if( is_email ) filterHTMLAllEscape(dst, url[7 .. $]);
					else filterHTMLEscape(dst, url, HTMLEscapeFlags.escapeMinimal);
					dst.put("</a>");
				} else {
					if (ln.startsWith("<br>")) {
						// always support line breaks, since we embed them here ourselves!
						dst.put("<br>");
						ln = ln[4 .. $];
					} else {
						if( settings.flags & MarkdownFlags.noInlineHtml ) dst.put("&lt;");
						else dst.put(ln[0]);
						ln = ln[1 .. $];
					}
				}
				break;
		}
	}
	if( br ) dst.put("<br/>");
}

private bool isLineBlank(string ln)
pure @safe {
	return allOf(ln, " \t");
}

private bool isSetextHeaderLine(string ln)
pure @safe {
	ln = stripLeft(ln);
	if( ln.length < 1 ) return false;
	if( ln[0] == '=' ){
		while(!ln.empty && ln.front == '=') ln.popFront();
		return allOf(ln, " \t");
	}
	if( ln[0] == '-' ){
		while(!ln.empty && ln.front == '-') ln.popFront();
		return allOf(ln, " \t");
	}
	return false;
}

private bool isAtxHeaderLine(string ln)
pure @safe {
	ln = stripLeft(ln);
	size_t i = 0;
	while( i < ln.length && ln[i] == '#' ) i++;
	if( i < 1 || i > 6 || i >= ln.length ) return false;
	return ln[i] == ' ';
}

private bool isHlineLine(string ln)
pure @safe {
	if( allOf(ln, " -") && count(ln, '-') >= 3 ) return true;
	if( allOf(ln, " *") && count(ln, '*') >= 3 ) return true;
	if( allOf(ln, " _") && count(ln, '_') >= 3 ) return true;
	return false;
}

private bool isQuoteLine(string ln)
pure @safe {
	return ln.stripLeft().startsWith(">");
}

private size_t getQuoteLevel(string ln)
pure @safe {
	size_t level = 0;
	ln = stripLeft(ln);
	while( ln.length > 0 && ln[0] == '>' ){
		level++;
		ln = stripLeft(ln[1 .. $]);
	}
	return level;
}

private bool isUListLine(string ln)
pure @safe {
	ln = stripLeft(ln);
	if (ln.length < 2) return false;
	if (!canFind("*+-", ln[0])) return false;
	if (ln[1] != ' ' && ln[1] != '\t') return false;
	return true;
}

private bool isOListLine(string ln)
pure @safe {
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
pure @safe {
	switch(tp){
		default: assert(false);
		case LineType.OList: // skip bullets and output using normal escaping
			auto idx = str.indexOfCT('.');
			assert(idx > 0);
			return str[idx+1 .. $].stripLeft();
		case LineType.UList:
			return stripLeft(str.stripLeft()[1 .. $]);
	}
}


private auto parseHtmlBlockLine(string ln)
pure @safe {
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
	import std.ascii : isAlpha;
	if( !isAlpha(ln[1]) ) return ret;
	ln = ln[1 .. $];
	size_t idx = 0;
	while( idx < ln.length && ln[idx] != ' ' && ln[idx] != '>' )
		idx++;
	ret.tagName = ln[0 .. idx];
	ln = ln[idx .. $];

	auto eidx = ln.indexOf('>');
	if( eidx < 0 ) return ret;
	if( eidx != ln.length-1 ) return ret;

	if (!s_blockTags.canFind(ret.tagName)) return ret;

	ret.isHtmlBlock = true;
	return ret;
}

private bool isHtmlBlockLine(string ln)
pure @safe {
	auto bi = parseHtmlBlockLine(ln);
	return bi.isHtmlBlock && bi.open;
}

private bool isHtmlBlockCloseLine(string ln)
pure @safe {
	auto bi = parseHtmlBlockLine(ln);
	return bi.isHtmlBlock && !bi.open;
}

private bool isCodeBlockDelimiter(string ln)
pure @safe {
	return ln.startsWith("```");
}

private string getHtmlTagName(string ln)
pure @safe {
	return parseHtmlBlockLine(ln).tagName;
}

private bool isLineIndented(string ln)
pure @safe {
	return ln.startsWith("\t") || ln.startsWith("    ");
}

private string unindentLine(string ln)
pure @safe {
	if( ln.startsWith("\t") ) return ln[1 .. $];
	if( ln.startsWith("    ") ) return ln[4 .. $];
	assert(false);
}

private int parseEmphasis(ref string str, ref string text)
pure @safe {
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

	auto cidx = () @trusted { return pstr.indexOf(ctag); }();
	if( cidx < 1 ) return false;

	text = pstr[0 .. cidx];

	str = pstr[cidx+ctag.length .. $];
	return cast(int)ctag.length;
}

private bool parseInlineCode(ref string str, ref string code)
pure @safe {
	string pstr = str;
	if( pstr.length < 3 ) return false;
	string ctag;
	if( pstr.startsWith("``") ) ctag = "``";
	else if( pstr.startsWith("`") ) ctag = "`";
	else return false;
	pstr = pstr[ctag.length .. $];

	auto cidx = () @trusted { return pstr.indexOf(ctag); }();
	if( cidx < 1 ) return false;

	code = pstr[0 .. cidx];
	str = pstr[cidx+ctag.length .. $];
	return true;
}

private bool parseLink(ref string str, ref Link dst, in LinkRef[string] linkrefs)
pure @safe {
	string pstr = str;
	if( pstr.length < 3 ) return false;
	// ignore img-link prefix
	if( pstr[0] == '!' ) pstr = pstr[1 .. $];

	// parse the text part [text]
	if( pstr[0] != '[' ) return false;
	auto cidx = pstr.matchBracket();
	if( cidx < 1 ) return false;
	string refid;
	dst.text = pstr[1 .. cidx];
	pstr = pstr[cidx+1 .. $];

	// parse either (link '['"title"']') or '[' ']'[refid]
	if( pstr.length < 2 ) return false;
	if( pstr[0] == '('){
		cidx = pstr.matchBracket();
		if( cidx < 1 ) return false;
		auto inner = pstr[1 .. cidx];
		immutable qidx = inner.indexOfCT('"');
		import std.ascii : isWhite;
		if( qidx > 1 && inner[qidx - 1].isWhite()){
			dst.url = inner[0 .. qidx].stripRight();
			immutable len = inner[qidx .. $].lastIndexOf('"');
			if( len == 0 ) return false;
			assert(len > 0);
			dst.title = inner[qidx + 1 .. qidx + len];
		} else {
			dst.url = inner.stripRight();
			dst.title = null;
		}
		if (dst.url.startsWith("<") && dst.url.endsWith(">"))
			dst.url = dst.url[1 .. $-1];
		pstr = pstr[cidx+1 .. $];
	} else {
		if( pstr[0] == ' ' ) pstr = pstr[1 .. $];
		if( pstr[0] != '[' ) return false;
		pstr = pstr[1 .. $];
		cidx = pstr.indexOfCT(']');
		if( cidx < 0 ) return false;
		if( cidx == 0 ) refid = dst.text;
		else refid = pstr[0 .. cidx];
		pstr = pstr[cidx+1 .. $];
	}


	if( refid.length > 0 ){
		auto pr = toLower(refid) in linkrefs;
		if( !pr ){
			debug if (!__ctfe) logDebug("[LINK REF NOT FOUND: '%s'", refid);
			return false;
		}
		dst.url = pr.url;
		dst.title = pr.title;
	}

	str = pstr;
	return true;
}

@safe unittest
{
	static void testLink(string s, Link exp, in LinkRef[string] refs)
	{
		Link link;
		assert(parseLink(s, link, refs), s);
		assert(link == exp);
	}
	LinkRef[string] refs;
	refs["ref"] = LinkRef("ref", "target", "title");

	testLink(`[link](target)`, Link("link", "target"), null);
	testLink(`[link](target "title")`, Link("link", "target", "title"), null);
	testLink(`[link](target  "title")`, Link("link", "target", "title"), null);
	testLink(`[link](target "title"  )`, Link("link", "target", "title"), null);

	testLink(`[link](target)`, Link("link", "target"), null);
	testLink(`[link](target "title")`, Link("link", "target", "title"), null);

	testLink(`[link][ref]`, Link("link", "target", "title"), refs);
	testLink(`[ref][]`, Link("ref", "target", "title"), refs);

	testLink(`[link[with brackets]](target)`, Link("link[with brackets]", "target"), null);
	testLink(`[link[with brackets]][ref]`, Link("link[with brackets]", "target", "title"), refs);

	testLink(`[link](/target with spaces )`, Link("link", "/target with spaces"), null);
	testLink(`[link](/target with spaces "title")`, Link("link", "/target with spaces", "title"), null);

	testLink(`[link](white-space  "around title" )`, Link("link", "white-space", "around title"), null);
	testLink(`[link](tabs	"around title"	)`, Link("link", "tabs", "around title"), null);

	testLink(`[link](target "")`, Link("link", "target", ""), null);
	testLink(`[link](target-no-title"foo" )`, Link("link", "target-no-title\"foo\"", ""), null);

	testLink(`[link](<target>)`, Link("link", "target"), null);

	auto failing = [
		`text`, `[link](target`, `[link]target)`, `[link]`,
		`[link(target)`, `link](target)`, `[link] (target)`,
		`[link][noref]`, `[noref][]`
	];
	Link link;
	foreach (s; failing)
		assert(!parseLink(s, link, refs), s);
}

private bool parseAutoLink(ref string str, ref string url)
pure @safe {
	string pstr = str;
	if( pstr.length < 3 ) return false;
	if( pstr[0] != '<' ) return false;
	pstr = pstr[1 .. $];
	auto cidx = pstr.indexOf('>');
	if( cidx < 0 ) return false;
	url = pstr[0 .. cidx];
	if( anyOf(url, " \t") ) return false;
	if( !anyOf(url, ":@") ) return false;
	str = pstr[cidx+1 .. $];
	if( url.indexOf('@') > 0 ) url = "mailto:"~url;
	return true;
}

private LinkRef[string] scanForReferences(ref string[] lines)
pure @safe {
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

		auto idx = () @trusted { return ln.indexOf("]:"); }();
		if( idx < 0 ) continue;
		string refid = ln[0 .. idx];
		ln = stripLeft(ln[idx+2 .. $]);

		string url;
		if( ln.startsWith("<") ){
			idx = ln.indexOfCT('>');
			if( idx < 0 ) continue;
			url = ln[1 .. idx];
			ln = ln[idx+1 .. $];
		} else {
			idx = ln.indexOfCT(' ');
			if( idx > 0 ){
				url = ln[0 .. idx];
				ln = ln[idx+1 .. $];
			} else {
				idx = ln.indexOfCT('\t');
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

		debug if (!__ctfe) logTrace("[detected ref on line %d]", lnidx+1);
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

@safe unittest { // alt and title attributes
	assert(filterMarkdown("![alt](http://example.org/image)")
		== "<p><img src=\"http://example.org/image\" alt=\"alt\">\n</p>\n");
	assert(filterMarkdown("![alt](http://example.org/image \"Title\")")
		== "<p><img src=\"http://example.org/image\" alt=\"alt\" title=\"Title\">\n</p>\n");
}

@safe unittest { // complex links
	assert(filterMarkdown("their [install\ninstructions](<http://www.brew.sh>) and")
		== "<p>their <a href=\"http://www.brew.sh\">install\ninstructions</a> and\n</p>\n");
	assert(filterMarkdown("[![Build Status](https://travis-ci.org/rejectedsoftware/vibe.d.png)](https://travis-ci.org/rejectedsoftware/vibe.d)")
		== "<p><a href=\"https://travis-ci.org/rejectedsoftware/vibe.d\"><img src=\"https://travis-ci.org/rejectedsoftware/vibe.d.png\" alt=\"Build Status\"></a>\n</p>\n");
}

@safe unittest { // check CTFE-ability
	enum res = filterMarkdown("### some markdown\n[foo][]\n[foo]: /bar");
	assert(res == "<h3> some markdown</h3>\n<p><a href=\"/bar\">foo</a>\n</p>\n", res);
}

@safe unittest { // correct line breaks in restrictive mode
	auto res = filterMarkdown("hello\nworld", MarkdownFlags.forumDefault);
	assert(res == "<p>hello<br>world\n</p>\n", res);
}

/*@safe unittest { // code blocks and blockquotes
	assert(filterMarkdown("\tthis\n\tis\n\tcode") ==
		"<pre><code>this\nis\ncode</code></pre>\n");
	assert(filterMarkdown("    this\n    is\n    code") ==
		"<pre><code>this\nis\ncode</code></pre>\n");
	assert(filterMarkdown("    this\n    is\n\tcode") ==
		"<pre><code>this\nis</code></pre>\n<pre><code>code</code></pre>\n");
	assert(filterMarkdown("\tthis\n\n\tcode") ==
		"<pre><code>this\n\ncode</code></pre>\n");
	assert(filterMarkdown("\t> this") ==
		"<pre><code>&gt; this</code></pre>\n");
	assert(filterMarkdown(">     this") ==
		"<blockquote><pre><code>this</code></pre></blockquote>\n");
	assert(filterMarkdown(">     this\n    is code") ==
		"<blockquote><pre><code>this\nis code</code></pre></blockquote>\n");
}*/
