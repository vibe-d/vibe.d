/**
	Markdown parser implementation

	Copyright: © 2012-2019 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.textfilter.markdown;

import vibe.textfilter.html;

import std.algorithm : any, all, canFind, countUntil, min;
import std.array;
import std.format;
import std.range;
import std.utf : byCodeUnit;
import std.string;

/*
	TODO:
		detect inline HTML tags
*/


/** Returns a Markdown filtered HTML string.
*/
string filterMarkdown()(string str, MarkdownFlags flags)
@trusted { // scope class is not @safe for DMD 2.072
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
	if (!settings) settings = new MarkdownSettings;

	auto all_lines = splitLines(src);
	auto links = scanForReferences(all_lines);
	auto lines = parseLines(all_lines, settings);
	Block root_block;
	parseBlocks(root_block, lines, null, settings);
	writeBlock(dst, root_block, links, settings);
}

/**
	Returns the hierarchy of sections
*/
Section[] getMarkdownOutline(string markdown_source, scope MarkdownSettings settings = null)
{
	import std.conv : to;

	if (!settings) settings = new MarkdownSettings;
	auto all_lines = splitLines(markdown_source);
	auto lines = parseLines(all_lines, settings);
	Block root_block;
	parseBlocks(root_block, lines, null, settings);
	Section root;

	foreach (ref sb; root_block.blocks) {
		if (sb.type == BlockType.header) {
			auto s = &root;
			while (true) {
				if (s.subSections.length == 0) break;
				if (s.subSections[$-1].headingLevel >= sb.headerLevel) break;
				s = &s.subSections[$-1];
			}
			s.subSections ~= Section(sb.headerLevel, sb.text[0], sb.text[0].asSlug.to!string);
		}
	}

	return root.subSections;
}

///
unittest {
	import std.conv : to;
	assert (getMarkdownOutline("## first\n## second\n### third\n# fourth\n### fifth") ==
		[
			Section(2, " first", "first"),
			Section(2, " second", "second", [
				Section(3, " third", "third")
			]),
			Section(1, " fourth", "fourth", [
				Section(3, " fifth", "fifth")
			])
		]
	);
}

final class MarkdownSettings {
	/// Controls the capabilities of the parser.
	MarkdownFlags flags = MarkdownFlags.vanillaMarkdown;

	/// Heading tags will start at this level.
	size_t headingBaseLevel = 1;

	/// Called for every link/image URL to perform arbitrary transformations.
	string delegate(string url_or_path, bool is_image) urlFilter;

	/// White list of URI schemas that can occur in link/image targets
	string[] allowedURISchemas = ["http", "https", "ftp", "mailto"];
}

enum MarkdownFlags {
	/** Same as `vanillaMarkdown`
	*/
	none = 0,

	/** Convert line breaks into hard line breaks in the output

		This option is useful when operating on text that may be formatted as
		plain text, without having Markdown in mind, while still improving
		the appearance of the text in many cases. A common example would be
		to format e-mails or newsgroup posts.
	*/
	keepLineBreaks = 1<<0,

	/** Support fenced code blocks.
	*/
	backtickCodeBlocks = 1<<1,

	/** Disable support for embedded HTML
	*/
	noInlineHtml = 1<<2,
	//noLinks = 1<<3,
	//allowUnsafeHtml = 1<<4,

	/** Support table definitions

		The syntax is based on Markdown Extra and GitHub flavored Markdown.
	*/
	tables = 1<<5,

	/** Support HTML attributes after links

		Links or images directly followed by `{ … }` allow regular HTML
		attributes to added to the generated HTML element.
	*/
	attributes = 1<<6,

	/** Recognize figure definitions

		Figures can be defined using a modified list syntax:

		```
		- %%%
			This is the figure content

			- ###
				This is optional caption content
		```

		Just like for lists, arbitrary blocks can be nested within figure and
		figure caption blocks. If only a single paragraph is present within a
		figure caption block, the paragraph text will be emitted without the
		surrounding `<p>` tags. The same is true for figure blocks that contain
		only a single paragraph and any number of additional figure caption
		blocks.
	*/
	figures = 1<<7,

	/** Support only standard Markdown features

		Note that the parser is not fully CommonMark compliant at the moment,
		but this is the general idea behind this option.
	*/
	vanillaMarkdown = none,

	/** Default set of flags suitable for use within an online forum
	*/
	forumDefault = keepLineBreaks|backtickCodeBlocks|noInlineHtml|tables
}

struct Section {
	size_t headingLevel;
	string caption;
	string anchor;
	Section[] subSections;
}

private {
	immutable s_blockTags = ["div", "ol", "p", "pre", "section", "table", "ul"];
}

private enum IndentType {
	white,
	quote
}

private enum LineType {
	undefined,
	blank,
	plain,
	hline,
	atxHeader,
	setextHeader,
	tableSeparator,
	uList,
	oList,
	figure,
	figureCaption,
	htmlBlock,
	codeBlockDelimiter
}

private struct Line {
	LineType type;
	IndentType[] indent;
	string text;
	string unindented;

	string unindent(size_t n)
	pure @safe {
		assert (n <= indent.length);
		string ln = text;
		foreach (i; 0 .. n) {
			final switch(indent[i]){
				case IndentType.white:
					if (ln[0] == ' ') ln = ln[4 .. $];
					else ln = ln[1 .. $];
					break;
				case IndentType.quote:
					ln = ln.stripLeft()[1 .. $];
					if (ln.startsWith(' '))
						ln.popFront();
					break;
			}
		}
		return ln;
	}
}

private Line[] parseLines(string[] lines, scope MarkdownSettings settings)
pure @safe {
	Line[] ret;
	while( !lines.empty ){
		auto ln = lines.front;
		lines.popFront();

		Line lninfo;
		lninfo.text = ln;

		while (ln.length > 0) {
			if (ln[0] == '\t') {
				lninfo.indent ~= IndentType.white;
				ln.popFront();
			} else if (ln.startsWith("    ")) {
				lninfo.indent ~= IndentType.white;
				ln.popFrontN(4);
			} else {
				if (ln.stripLeft().startsWith(">")) {
					lninfo.indent ~= IndentType.quote;
					ln = ln.stripLeft();
					ln.popFront();
					if (ln.startsWith(' '))
						ln.popFront();
				} else break;
			}
		}
		lninfo.unindented = ln;

		if ((settings.flags & MarkdownFlags.backtickCodeBlocks) && isCodeBlockDelimiter(ln))
			lninfo.type = LineType.codeBlockDelimiter;
		else if(isAtxHeaderLine(ln)) lninfo.type = LineType.atxHeader;
		else if(isSetextHeaderLine(ln)) lninfo.type = LineType.setextHeader;
		else if((settings.flags & MarkdownFlags.tables) && isTableSeparatorLine(ln))
			lninfo.type = LineType.tableSeparator;
		else if(isHlineLine(ln)) lninfo.type = LineType.hline;
		else if(isOListLine(ln)) lninfo.type = LineType.oList;
		else if(isUListLine(ln)) {
			if (settings.flags & MarkdownFlags.figures) {
				auto suff = removeListPrefix(ln, LineType.uList);
				if (suff == "%%%") lninfo.type = LineType.figure;
				else if (suff == "###") lninfo.type = LineType.figureCaption;
				else lninfo.type = LineType.uList;
			} else lninfo.type = LineType.uList;
		} else if(isLineBlank(ln)) lninfo.type = LineType.blank;
		else if(!(settings.flags & MarkdownFlags.noInlineHtml) && isHtmlBlockLine(ln))
			lninfo.type = LineType.htmlBlock;
		else lninfo.type = LineType.plain;

		ret ~= lninfo;
	}
	return ret;
}

unittest {
	import std.conv : to;
	auto s = new MarkdownSettings;
	s.flags = MarkdownFlags.forumDefault;
	auto lns = [">```D"];
	assert (parseLines(lns, s) == [Line(LineType.codeBlockDelimiter, [IndentType.quote], lns[0], "```D")]);
	lns = ["> ```D"];
	assert (parseLines(lns, s) == [Line(LineType.codeBlockDelimiter, [IndentType.quote], lns[0], "```D")]);
	lns = [">    ```D"];
	assert (parseLines(lns, s) == [Line(LineType.codeBlockDelimiter, [IndentType.quote], lns[0], "   ```D")]);
	lns = [">     ```D"];
	assert (parseLines(lns, s) == [Line(LineType.codeBlockDelimiter, [IndentType.quote, IndentType.white], lns[0], "```D")]);
	lns = [">test"];
	assert (parseLines(lns, s) == [Line(LineType.plain, [IndentType.quote], lns[0], "test")]);
	lns = ["> test"];
	assert (parseLines(lns, s) == [Line(LineType.plain, [IndentType.quote], lns[0], "test")]);
	lns = [">    test"];
	assert (parseLines(lns, s) == [Line(LineType.plain, [IndentType.quote], lns[0], "   test")]);
	lns = [">     test"];
	assert (parseLines(lns, s) == [Line(LineType.plain, [IndentType.quote, IndentType.white], lns[0], "test")]);
}

private enum BlockType {
	plain,
	text,
	paragraph,
	header,
	table,
	oList,
	uList,
	listItem,
	code,
	quote,
	figure,
	figureCaption
}

private struct Block {
	BlockType type;
	Attribute[] attributes;
	string[] text;
	Block[] blocks;
	size_t headerLevel;
	Alignment[] columns;
}

private struct Attribute {
	string attribute;
	string value;
}

private enum Alignment {
	none = 0,
	left = 1<<0,
	right = 1<<1,
	center = left | right
}

private void parseBlocks(ref Block root, ref Line[] lines, IndentType[] base_indent, scope MarkdownSettings settings)
pure @safe {
	import std.conv : to;
	import std.algorithm.comparison : among;

	if (base_indent.length == 0) root.type = BlockType.text;
	else if (base_indent[$-1] == IndentType.quote) root.type = BlockType.quote;

	while (!lines.empty) {
		auto ln = lines.front;

		if (ln.type == LineType.blank) {
			lines.popFront();
			continue;
		}

		if (ln.indent != base_indent) {
			if (ln.indent.length < base_indent.length
				|| ln.indent[0 .. base_indent.length] != base_indent)
			{
				return;
			}

			auto cindent = base_indent ~ IndentType.white;
			if (ln.indent == cindent) {
				Block cblock;
				cblock.type = BlockType.code;
				while (!lines.empty && (lines.front.unindented.strip.empty
					|| lines.front.indent.length >= cindent.length
					&& lines.front.indent[0 .. cindent.length] == cindent))
				{
					cblock.text ~= lines.front.indent.length >= cindent.length
						? lines.front.unindent(cindent.length) : "";
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
			final switch (ln.type) {
				case LineType.undefined: assert (false);
				case LineType.blank: assert (false);
				case LineType.plain:
					if (lines.length >= 2 && lines[1].type == LineType.setextHeader) {
						auto setln = lines[1].unindented;
						b.type = BlockType.header;
						b.text = [ln.unindented];
						if (settings.flags & MarkdownFlags.attributes)
							parseAttributeString(skipAttributes(b.text[0]), b.attributes);
						if (!b.attributes.canFind!(a => a.attribute == "id"))
							b.attributes ~= Attribute("id", asSlug(b.text[0]).to!string);
						b.headerLevel = setln.strip()[0] == '=' ? 1 : 2;
						lines.popFrontN(2);
					} else if (lines.length >= 2 && lines[1].type == LineType.tableSeparator
						&& ln.unindented.indexOf('|') >= 0)
					{
						auto setln = lines[1].unindented;
						b.type = BlockType.table;
						b.text = [ln.unindented];
						foreach (c; getTableColumns(setln)) {
							Alignment a = Alignment.none;
							if (c.startsWith(':')) a |= Alignment.left;
							if (c.endsWith(':')) a |= Alignment.right;
							b.columns ~= a;
						}

						lines.popFrontN(2);
						while (!lines.empty && lines[0].unindented.indexOf('|') >= 0) {
							b.text ~= lines.front.unindented;
							lines.popFront();
						}
					} else {
						b.type = BlockType.paragraph;
						b.text = skipText(lines, base_indent);
					}
					break;
				case LineType.hline:
					b.type = BlockType.plain;
					b.text = ["<hr>"];
					lines.popFront();
					break;
				case LineType.atxHeader:
					b.type = BlockType.header;
					string hl = ln.unindented;
					b.headerLevel = 0;
					while (hl.length > 0 && hl[0] == '#') {
						b.headerLevel++;
						hl = hl[1 .. $];
					}

					if (settings.flags & MarkdownFlags.attributes)
						parseAttributeString(skipAttributes(hl), b.attributes);
					if (!b.attributes.canFind!(a => a.attribute == "id"))
						b.attributes ~= Attribute("id", asSlug(hl).to!string);

					while (hl.length > 0 && (hl[$-1] == '#' || hl[$-1] == ' '))
						hl = hl[0 .. $-1];
					b.text = [hl];
					lines.popFront();
					break;
				case LineType.setextHeader:
					lines.popFront();
					break;
				case LineType.tableSeparator:
					lines.popFront();
					break;
				case LineType.figure:
				case LineType.figureCaption:
					b.type = ln.type == LineType.figure
						? BlockType.figure : BlockType.figureCaption;

					auto itemindent = base_indent ~ IndentType.white;
					lines.popFront();
					parseBlocks(b, lines, itemindent, settings);
					break;
				case LineType.uList:
				case LineType.oList:
					b.type = ln.type == LineType.uList ? BlockType.uList : BlockType.oList;

					auto itemindent = base_indent ~ IndentType.white;
					bool paraMode = false;

					// look ahead to determine whether the list is in paragraph
					// mode (one or multiple <p></p> nested within each item
					bool couldBeParaMode = false;
					foreach (pln; lines[1 .. $]) {
						if (pln.type == LineType.blank) {
							couldBeParaMode = true;
							continue;
						}
						if (!pln.indent.startsWith(base_indent)) break;
						if (pln.indent == base_indent) {
							if (pln.type == ln.type)
								paraMode = couldBeParaMode;
							break;
						}
					}

					while (!lines.empty && lines.front.type == ln.type
						&& lines.front.indent == base_indent)
					{
						Block itm;
						itm.text = skipText(lines, itemindent);
						itm.text[0] = removeListPrefix(itm.text[0], ln.type);

						if (paraMode) {
							Block para;
							para.type = BlockType.paragraph;
							para.text = itm.text;
							itm.blocks ~= para;
							itm.text = null;
						}

						parseBlocks(itm, lines, itemindent, settings);
						itm.type = BlockType.listItem;
						b.blocks ~= itm;
					}
					break;
				case LineType.htmlBlock:
					int nestlevel = 0;
					auto starttag = parseHtmlBlockLine(ln.unindented);
					if (!starttag.isHtmlBlock || !starttag.open)
						break;

					b.type = BlockType.plain;
					while (!lines.empty) {
						if (lines.front.indent.length < base_indent.length)
							break;
						if (lines.front.indent[0 .. base_indent.length] != base_indent)
							break;

						auto str = lines.front.unindent(base_indent.length);
						auto taginfo = parseHtmlBlockLine(str);
						b.text ~= lines.front.unindent(base_indent.length);
						lines.popFront();
						if (taginfo.isHtmlBlock && taginfo.tagName == starttag.tagName)
							nestlevel += taginfo.open ? 1 : -1;
						if (nestlevel <= 0) break;
					}
					break;
				case LineType.codeBlockDelimiter:
					lines.popFront(); // TODO: get language from line
					b.type = BlockType.code;
					while (!lines.empty) {
						if (lines.front.indent.length < base_indent.length)
							break;
						if (lines.front.indent[0 .. base_indent.length] != base_indent)
							break;
						if (lines.front.type == LineType.codeBlockDelimiter) {
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
		if (indent.length > base_indent.length) return false;
		if (indent != base_indent[0 .. indent.length]) return false;
		sizediff_t qidx = -1;
		foreach_reverse (i, tp; base_indent)
			if (tp == IndentType.quote) {
				qidx = i;
				break;
			}
		if (qidx >= 0) {
			qidx = base_indent.length-1 - qidx;
			if( indent.length <= qidx ) return false;
		}
		return true;
	}

	// return value is used in variables that don't get bounds checks on the
	// first element, so we should return at least one
	if (lines.empty)
		return [""];

	string[] ret;

	while (true) {
		ret ~= lines.front.unindent(min(indent.length, lines.front.indent.length));
		lines.popFront();

		if (lines.empty || !matchesIndent(lines.front.indent, indent)
			|| lines.front.type != LineType.plain)
		{
			return ret;
		}
	}
}

/// private
private void writeBlock(R)(ref R dst, ref const Block block, LinkRef[string] links, scope MarkdownSettings settings)
{
	final switch (block.type) {
		case BlockType.plain:
			foreach (ln; block.text) {
				put(dst, ln);
				put(dst, "\n");
			}
			foreach (b; block.blocks)
				writeBlock(dst, b, links, settings);
			break;
		case BlockType.text:
			writeMarkdownEscaped(dst, block, links, settings);
			foreach (b; block.blocks)
				writeBlock(dst, b, links, settings);
			break;
		case BlockType.paragraph:
			assert (block.blocks.length == 0);
			put(dst, "<p>");
			writeMarkdownEscaped(dst, block, links, settings);
			put(dst, "</p>\n");
			break;
		case BlockType.header:
			assert (block.blocks.length == 0);
			assert (block.text.length == 1);
			auto hlvl = block.headerLevel + (settings ? settings.headingBaseLevel-1 : 0);
			dst.writeTag(block.attributes, "h", hlvl);
			writeMarkdownEscaped(dst, block.text[0], links, settings);
			dst.formattedWrite("</h%s>\n", hlvl);
			break;
		case BlockType.table:
			import std.algorithm.iteration : splitter;

			static string[Alignment.max+1] alstr = ["", " align=\"left\"", " align=\"right\"", " align=\"center\""];

			put(dst, "<table>\n");
			put(dst, "<tr>");
			size_t i = 0;
			foreach (col; block.text[0].getTableColumns()) {
				put(dst, "<th");
				put(dst, alstr[block.columns[i]]);
				put(dst, '>');
				dst.writeMarkdownEscaped(col, links, settings);
				put(dst, "</th>");
				if (i + 1 < block.columns.length)
					i++;
			}
			put(dst, "</tr>\n");
			foreach (ln; block.text[1 .. $]) {
				put(dst, "<tr>");
				i = 0;
				foreach (col; ln.getTableColumns()) {
					put(dst, "<td");
					put(dst, alstr[block.columns[i]]);
					put(dst, '>');
					dst.writeMarkdownEscaped(col, links, settings);
					put(dst, "</td>");
					if (i + 1 < block.columns.length)
						i++;
				}
				put(dst, "</tr>\n");
			}
			put(dst, "</table>\n");
			break;
		case BlockType.oList:
			put(dst, "<ol>\n");
			foreach (b; block.blocks)
				writeBlock(dst, b, links, settings);
			put(dst, "</ol>\n");
			break;
		case BlockType.uList:
			put(dst, "<ul>\n");
			foreach (b; block.blocks)
				writeBlock(dst, b, links, settings);
			put(dst, "</ul>\n");
			break;
		case BlockType.listItem:
			put(dst, "<li>");
			writeMarkdownEscaped(dst, block, links, settings);
			foreach (b; block.blocks)
				writeBlock(dst, b, links, settings);
			put(dst, "</li>\n");
			break;
		case BlockType.code:
			assert (block.blocks.length == 0);
			put(dst, "<pre class=\"prettyprint\"><code>");
			foreach (ln; block.text) {
				filterHTMLEscape(dst, ln);
				put(dst, "\n");
			}
			put(dst, "</code></pre>\n");
			break;
		case BlockType.quote:
			put(dst, "<blockquote>");
			writeMarkdownEscaped(dst, block, links, settings);
			foreach (b; block.blocks)
				writeBlock(dst, b, links, settings);
			put(dst, "</blockquote>\n");
			break;
		case BlockType.figure:
			put(dst, "<figure>");
			bool omit_para = block.blocks.count!(b => b.type != BlockType.figureCaption) == 1;
			foreach (b; block.blocks) {
				if (b.type == BlockType.paragraph && omit_para) {
					writeMarkdownEscaped(dst, b, links, settings);
				} else writeBlock(dst, b, links, settings);
			}
			put(dst, "</figure>\n");
			break;
		case BlockType.figureCaption:
			put(dst, "<figcaption>");
			if (block.blocks.length == 1 && block.blocks[0].type == BlockType.paragraph) {
				writeMarkdownEscaped(dst, block.blocks[0], links, settings);
			} else {
				foreach (b; block.blocks)
					writeBlock(dst, b, links, settings);
			}
			put(dst, "</figcaption>\n");
			break;
	}
}

private void writeMarkdownEscaped(R)(ref R dst, ref const Block block, in LinkRef[string] links, scope MarkdownSettings settings)
{
	auto lines = () @trusted { return cast(string[])block.text; } ();
	auto text = settings.flags & MarkdownFlags.keepLineBreaks ? lines.join("<br>") : lines.join("\n");
	writeMarkdownEscaped(dst, text, links, settings);
	if (lines.length) put(dst, "\n");
}

/// private
private void writeMarkdownEscaped(R)(ref R dst, string ln, in LinkRef[string] linkrefs, scope MarkdownSettings settings)
{
	bool isAllowedURI(string lnk) {
		auto idx = lnk.indexOf('/');
		auto cidx = lnk.indexOf(':');
		// always allow local URIs
		if (cidx < 0 || idx >= 0 && cidx > idx) return true;
		return settings.allowedURISchemas.canFind(lnk[0 .. cidx]);
	}

	string filterLink(string lnk, bool is_image) {
		if (isAllowedURI(lnk))
			return settings.urlFilter ? settings.urlFilter(lnk, is_image) : lnk;
		return "#"; // replace link with unknown schema with dummy URI
	}

	bool br = ln.endsWith("  ");
	while (ln.length > 0) {
		switch (ln[0]) {
			default:
				put(dst, ln[0]);
				ln = ln[1 .. $];
				break;
			case '\\':
				if (ln.length >= 2) {
					switch (ln[1]) {
						default:
							put(dst, ln[0 .. 2]);
							ln = ln[2 .. $];
							break;
						case '\'', '`', '*', '_', '{', '}', '[', ']',
							'(', ')', '#', '+', '-', '.', '!':
							put(dst, ln[1]);
							ln = ln[2 .. $];
							break;
					}
				} else {
					put(dst, ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '_':
			case '*':
				string text;
				if (auto em = parseEmphasis(ln, text)) {
					put(dst, em == 1 ? "<em>" : em == 2 ? "<strong>" : "<strong><em>");
					put(dst, text);
					put(dst, em == 1 ? "</em>" : em == 2 ? "</strong>": "</em></strong>");
				} else {
					put(dst, ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '`':
				string code;
				if (parseInlineCode(ln, code)) {
					put(dst, "<code class=\"prettyprint\">");
					filterHTMLEscape(dst, code, HTMLEscapeFlags.escapeMinimal);
					put(dst, "</code>");
				} else {
					put(dst, ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '[':
				Link link;
				Attribute[] attributes;
				if (parseLink(ln, link, linkrefs,
					settings.flags & MarkdownFlags.attributes ? &attributes : null))
				{
					attributes ~= Attribute("href", filterLink(link.url, false));
					if (link.title.length)
						attributes ~= Attribute("title", link.title);
					dst.writeTag(attributes, "a");
					writeMarkdownEscaped(dst, link.text, linkrefs, settings);
					put(dst, "</a>");
				} else {
					put(dst, ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '!':
				Link link;
				Attribute[] attributes;
				if (parseLink(ln, link, linkrefs,
					settings.flags & MarkdownFlags.attributes ? &attributes : null))
				{
					attributes ~= Attribute("src", filterLink(link.url, true));
					attributes ~= Attribute("alt", link.text);
					if (link.title.length)
						attributes ~= Attribute("title", link.title);
					dst.writeTag(attributes, "img");
				} else if( ln.length >= 2 ){
					put(dst, ln[0 .. 2]);
					ln = ln[2 .. $];
				} else {
					put(dst, ln[0]);
					ln = ln[1 .. $];
				}
				break;
			case '>':
				if (settings.flags & MarkdownFlags.noInlineHtml) put(dst, "&gt;");
				else put(dst, ln[0]);
				ln = ln[1 .. $];
				break;
			case '<':
				string url;
				if (parseAutoLink(ln, url)) {
					bool is_email = url.startsWith("mailto:");
					put(dst, "<a href=\"");
					if (is_email) filterHTMLAllEscape(dst, url);
					else filterHTMLAttribEscape(dst, filterLink(url, false));
					put(dst, "\">");
					if (is_email) filterHTMLAllEscape(dst, url[7 .. $]);
					else filterHTMLEscape(dst, url, HTMLEscapeFlags.escapeMinimal);
					put(dst, "</a>");
				} else {
					if (ln.startsWith("<br>")) {
						// always support line breaks, since we embed them here ourselves!
						put(dst, "<br/>");
						ln = ln[4 .. $];
					} else if(ln.startsWith("<br/>")) {
						put(dst, "<br/>");
						ln = ln[5 .. $];
					} else {
						if (settings.flags & MarkdownFlags.noInlineHtml)
							put(dst, "&lt;");
						else put(dst, ln[0]);
						ln = ln[1 .. $];
					}
				}
				break;
		}
	}
	if (br) put(dst, "<br/>");
}

private void writeTag(R, ARGS...)(ref R dst, string name, ARGS name_additions)
{
	writeTag(dst, cast(Attribute[])null, name, name_additions);
}

private void writeTag(R, ARGS...)(ref R dst, scope const(Attribute)[] attributes, string name, ARGS name_additions)
{
	dst.formattedWrite("<%s", name);
	foreach (add; name_additions)
		dst.formattedWrite("%s", add);
	foreach (a; attributes) {
		dst.formattedWrite(" %s=\"", a.attribute);
		dst.filterHTMLAttribEscape(a.value);
		put(dst, '\"');
	}
	put(dst, '>');
}

private bool isLineBlank(string ln)
pure @safe {
	return allOf(ln, " \t");
}

private bool isSetextHeaderLine(string ln)
pure @safe {
	ln = stripLeft(ln);
	if (ln.length < 1) return false;
	if (ln[0] == '=') {
		while (!ln.empty && ln.front == '=') ln.popFront();
		return isLineBlank(ln);
	}
	if (ln[0] == '-') {
		while (!ln.empty && ln.front == '-') ln.popFront();
		return isLineBlank(ln);
	}
	return false;
}

private bool isAtxHeaderLine(string ln)
pure @safe {
	ln = stripLeft(ln);
	size_t i = 0;
	while (i < ln.length && ln[i] == '#') i++;
	if (i < 1 || i > 6 || i >= ln.length) return false;
	return ln[i] == ' ';
}

private bool isTableSeparatorLine(string ln)
pure @safe {
	import std.algorithm.iteration : splitter;

	ln = strip(ln);
	if (ln.startsWith("|")) ln = ln[1 .. $];
	if (ln.endsWith("|")) ln = ln[0 .. $-1];

	auto cols = ln.splitter('|');
	size_t cnt = 0;
	foreach (c; cols) {
		c = c.strip();
		if (c.startsWith(':')) c = c[1 .. $];
		if (c.endsWith(':')) c = c[0 .. $-1];
		if (c.length < 3 || !c.allOf("-"))
			return false;
		cnt++;
	}
	return cnt >= 2;
}

unittest {
	assert(isTableSeparatorLine("|----|---|"));
	assert(isTableSeparatorLine("|:----:|---|"));
	assert(isTableSeparatorLine("---|----"));
	assert(isTableSeparatorLine("| --- | :---- |"));
	assert(!isTableSeparatorLine("| ---- |"));
	assert(!isTableSeparatorLine("| -- | -- |"));
	assert(!isTableSeparatorLine("| --- - | ---- |"));
}

private auto getTableColumns(string line)
pure @safe nothrow {
	import std.algorithm.iteration : map, splitter;

	if (line.startsWith("|")) line = line[1 .. $];
	if (line.endsWith("|")) line = line[0 .. $-1];
	return line.splitter('|').map!(s => s.strip());
}

private size_t countTableColumns(string line)
pure @safe {
	return getTableColumns(line).count();
}

private bool isHlineLine(string ln)
pure @safe {
	if (allOf(ln, " -") && count(ln, '-') >= 3) return true;
	if (allOf(ln, " *") && count(ln, '*') >= 3) return true;
	if (allOf(ln, " _") && count(ln, '_') >= 3) return true;
	return false;
}

private bool allOf(string str, const(char)[] ascii_chars)
pure @safe nothrow {
	return str.byCodeUnit.all!(ch => ascii_chars.byCodeUnit.canFind(ch));
}

private bool isQuoteLine(string ln)
pure @safe {
	return ln.stripLeft().startsWith(">");
}

private size_t getQuoteLevel(string ln)
pure @safe {
	size_t level = 0;
	ln = stripLeft(ln);
	while (ln.length > 0 && ln[0] == '>') {
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
	if (ln.length < 1) return false;
	if (ln[0] < '0' || ln[0] > '9') return false;
	ln = ln[1 .. $];
	while (ln.length > 0 && ln[0] >= '0' && ln[0] <= '9')
		ln = ln[1 .. $];
	if (ln.length < 2) return false;
	if (ln[0] != '.') return false;
	if (ln[1] != ' ' && ln[1] != '\t')
		return false;
	return true;
}

private string removeListPrefix(string str, LineType tp)
pure @safe {
	switch (tp) {
		default: assert (false);
		case LineType.oList: // skip bullets and output using normal escaping
			auto idx = str.indexOf('.');
			assert (idx > 0);
			return str[idx+1 .. $].stripLeft();
		case LineType.uList:
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
	if (ln.length < 3) return ret;
	if (ln[0] != '<') return ret;
	if (ln[1] == '/') {
		ret.open = false;
		ln = ln[1 .. $];
	}
	import std.ascii : isAlpha;
	if (!isAlpha(ln[1])) return ret;
	ln = ln[1 .. $];
	size_t idx = 0;
	while (idx < ln.length && ln[idx] != ' ' && ln[idx] != '>')
		idx++;
	ret.tagName = ln[0 .. idx];
	ln = ln[idx .. $];

	auto eidx = ln.indexOf('>');
	if (eidx < 0) return ret;
	if (eidx != ln.length-1) return ret;

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
	return ln.stripLeft.startsWith("```");
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
	if (ln.startsWith("\t")) return ln[1 .. $];
	if (ln.startsWith("    ")) return ln[4 .. $];
	assert (false);
}

private int parseEmphasis(ref string str, ref string text)
pure @safe {
	string pstr = str;
	if (pstr.length < 3) return false;

	string ctag;
	if (pstr.startsWith("***")) ctag = "***";
	else if (pstr.startsWith("**")) ctag = "**";
	else if (pstr.startsWith("*")) ctag = "*";
	else if (pstr.startsWith("___")) ctag = "___";
	else if (pstr.startsWith("__")) ctag = "__";
	else if (pstr.startsWith("_")) ctag = "_";
	else return false;

	pstr = pstr[ctag.length .. $];

	auto cidx = () @trusted { return pstr.indexOf(ctag); }();
	if (cidx < 1) return false;

	text = pstr[0 .. cidx];

	str = pstr[cidx+ctag.length .. $];
	return cast(int)ctag.length;
}

private bool parseInlineCode(ref string str, ref string code)
pure @safe {
	string pstr = str;
	if (pstr.length < 3) return false;
	string ctag;
	if (pstr.startsWith("``")) ctag = "``";
	else if (pstr.startsWith("`")) ctag = "`";
	else return false;
	pstr = pstr[ctag.length .. $];

	auto cidx = () @trusted { return pstr.indexOf(ctag); }();
	if (cidx < 1) return false;

	code = pstr[0 .. cidx];
	str = pstr[cidx+ctag.length .. $];
	return true;
}

private bool parseLink(ref string str, ref Link dst, scope const(LinkRef[string]) linkrefs, scope Attribute[]* attributes)
pure @safe {
	string pstr = str;
	if (pstr.length < 3) return false;
	// ignore img-link prefix
	if (pstr[0] == '!') pstr = pstr[1 .. $];

	// parse the text part [text]
	if (pstr[0] != '[') return false;
	auto cidx = pstr.matchBracket();
	if (cidx < 1) return false;
	string refid;
	dst.text = pstr[1 .. cidx];
	pstr = pstr[cidx+1 .. $];

	// parse either (link '['"title"']') or '[' ']'[refid]
	if (pstr.length < 2) return false;
	if (pstr[0] == '(') {
		cidx = pstr.matchBracket();
		if (cidx < 1) return false;
		auto inner = pstr[1 .. cidx];
		immutable qidx = inner.indexOf('"');
		import std.ascii : isWhite;
		if (qidx > 1 && inner[qidx - 1].isWhite()) {
			dst.url = inner[0 .. qidx].stripRight();
			immutable len = inner[qidx .. $].lastIndexOf('"');
			if (len == 0) return false;
			assert (len > 0);
			dst.title = inner[qidx + 1 .. qidx + len];
		} else {
			dst.url = inner.stripRight();
			dst.title = null;
		}
		if (dst.url.startsWith("<") && dst.url.endsWith(">"))
			dst.url = dst.url[1 .. $-1];
		pstr = pstr[cidx+1 .. $];

		if (attributes) {
			if (pstr.startsWith('{')) {
				auto idx = pstr.indexOf('}');
				if (idx > 0) {
					parseAttributeString(pstr[1 .. idx], *attributes);
					pstr = pstr[idx+1 .. $];
				}
			}
		}
	} else {
		if (pstr[0] == ' ') pstr = pstr[1 .. $];
		if (pstr[0] != '[') return false;
		pstr = pstr[1 .. $];
		cidx = pstr.indexOf(']');
		if (cidx < 0) return false;
		if (cidx == 0) refid = dst.text;
		else refid = pstr[0 .. cidx];
		pstr = pstr[cidx+1 .. $];
	}

	if (refid.length > 0) {
		auto pr = toLower(refid) in linkrefs;
		if (!pr) {
			return false;
		}
		dst.url = pr.url;
		dst.title = pr.title;
		if (attributes) *attributes ~= pr.attributes;
	}

	str = pstr;
	return true;
}

@safe unittest
{
	static void testLink(string s, Link exp, in LinkRef[string] refs)
	{
		Link link;
		assert (parseLink(s, link, refs, null), s);
		assert (link == exp);
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
		assert (!parseLink(s, link, refs, null), s);
}

@safe unittest { // attributes
	void test(string s, LinkRef[string] refs, bool parse_atts, string exprem, Link explnk, Attribute[] expatts...)
	@safe {
		Link lnk;
		Attribute[] atts;
		parseLink(s, lnk, refs, parse_atts ? () @trusted { return &atts; } () : null);
		assert (lnk == explnk);
		assert (s == exprem);
		assert (atts == expatts);
	}

	test("[foo](bar){.baz}", null, false, "{.baz}", Link("foo", "bar", ""));
	test("[foo](bar){.baz}", null, true, "", Link("foo", "bar", ""), Attribute("class", "baz"));

	auto refs = ["bar": LinkRef("bar", "url", "title", [Attribute("id", "hid")])];
	test("[foo][bar]", refs, false, "", Link("foo", "url", "title"));
	test("[foo][bar]", refs, true, "", Link("foo", "url", "title"), Attribute("id", "hid"));
}

private bool parseAutoLink(ref string str, ref string url)
pure @safe {
	import std.algorithm.searching : all;
	import std.ascii : isAlphaNum;

	string pstr = str;
	if (pstr.length < 3) return false;
	if (pstr[0] != '<') return false;
	pstr = pstr[1 .. $];
	auto cidx = pstr.indexOf('>');
	if (cidx < 0) return false;

	url = pstr[0 .. cidx];
	if (url.any!(ch => ch == ' ' || ch == '\t')) return false;
	auto atidx = url.indexOf('@');
	auto colonidx = url.indexOf(':');
	if (atidx < 0 && colonidx < 0) return false;

	str = pstr[cidx+1 .. $];
	if (atidx < 0) return true;
	if (colonidx < 0 || colonidx > atidx ||
		!url[0 .. colonidx].all!(ch => ch.isAlphaNum))
			url = "mailto:" ~ url;
	return true;
}

unittest {
	void test(bool expected, string str, string url)
	{
		string strcpy = str;
		string outurl;
		if (!expected) {
			assert (!parseAutoLink(strcpy, outurl));
			assert (outurl.length == 0);
			assert (strcpy == str);
		} else {
			assert (parseAutoLink(strcpy, outurl));
			assert (outurl == url);
			assert (strcpy.length == 0);
		}
	}

	test(true, "<http://foo/>", "http://foo/");
	test(false, "<http://foo/", null);
	test(true, "<mailto:foo@bar>", "mailto:foo@bar");
	test(true, "<foo@bar>", "mailto:foo@bar");
	test(true, "<proto:foo@bar>", "proto:foo@bar");
	test(true, "<proto:foo@bar:123>", "proto:foo@bar:123");
	test(true, "<\"foo:bar\"@baz>", "mailto:\"foo:bar\"@baz");
}

private string skipAttributes(ref string line)
@safe pure {
	auto strs = line.stripRight;
	if (!strs.endsWith("}")) return null;

	auto idx = strs.lastIndexOf('{');
	if (idx < 0) return null;

	auto ret = strs[idx+1 .. $-1];
	line = strs[0 .. idx];
	return ret;
}

unittest {
	void test(string inp, string outp, string att)
	{
		auto ratt = skipAttributes(inp);
		assert (ratt == att, ratt);
		assert (inp == outp, inp);
	}

	test(" foo ", " foo ", null);
	test("foo {bar}", "foo ", "bar");
	test("foo {bar}  ", "foo ", "bar");
	test("foo bar} ", "foo bar} ", null);
	test(" {bar} foo ", " {bar} foo ", null);
	test(" fo {o {bar} ", " fo {o ", "bar");
	test(" fo {o} {bar} ", " fo {o} ", "bar");
}

private void parseAttributeString(string attributes, ref Attribute[] dst)
@safe pure {
	import std.algorithm.iteration : splitter;

	// TODO: handle custom attributes (requires a different approach than splitter)

	foreach (el; attributes.splitter(' ')) {
		el = el.strip;
		if (!el.length) continue;
		if (el[0] == '#') {
			auto idx = dst.countUntil!(a => a.attribute == "id");
			if (idx >= 0) dst[idx].value = el[1 .. $];
			else dst ~= Attribute("id", el[1 .. $]);
		} else if (el[0] == '.') {
			auto idx = dst.countUntil!(a => a.attribute == "class");
			if (idx >= 0) dst[idx].value ~= " " ~ el[1 .. $];
			else dst ~= Attribute("class", el[1 .. $]);
		}
	}
}

unittest {
	void test(string str, Attribute[] atts...)
	{
		Attribute[] res;
		parseAttributeString(str, res);
		assert (res == atts, format("%s: %s", str, res));
	}

	test("");
	test(".foo", Attribute("class", "foo"));
	test("#foo", Attribute("id", "foo"));
	test("#foo #bar", Attribute("id", "bar"));
	test(".foo .bar", Attribute("class", "foo bar"));
	test("#foo #bar", Attribute("id", "bar"));
	test(".foo #bar .baz", Attribute("class", "foo baz"), Attribute("id", "bar"));
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
	foreach (lnidx, ln; lines) {
		if (isLineIndented(ln)) continue;
		ln = strip(ln);
		if (!ln.startsWith("[")) continue;
		ln = ln[1 .. $];

		auto idx = () @trusted { return ln.indexOf("]:"); }();
		if (idx < 0) continue;
		string refid = ln[0 .. idx];
		ln = stripLeft(ln[idx+2 .. $]);

		string attstr = ln.skipAttributes();

		string url;
		if (ln.startsWith("<")) {
			idx = ln.indexOf('>');
			if (idx < 0) continue;
			url = ln[1 .. idx];
			ln = ln[idx+1 .. $];
		} else {
			idx = ln.indexOf(' ');
			if (idx > 0) {
				url = ln[0 .. idx];
				ln = ln[idx+1 .. $];
			} else {
				idx = ln.indexOf('\t');
				if (idx < 0) {
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
		if (ln.length >= 3) {
			if (ln[0] == '(' && ln[$-1] == ')'
				|| ln[0] == '\"' && ln[$-1] == '\"'
				|| ln[0] == '\'' && ln[$-1] == '\'' )
			{
				title = ln[1 .. $-1];
			}
		}

		LinkRef lref;
		lref.id = refid;
		lref.url = url;
		lref.title = title;
		parseAttributeString(attstr, lref.attributes);
		ret[toLower(refid)] = lref;
		reflines[lnidx] = true;
	}

	// remove all lines containing references
	auto nonreflines = appender!(string[])();
	nonreflines.reserve(lines.length);
	foreach (i, ln; lines)
		if (i !in reflines)
			nonreflines.put(ln);
	lines = nonreflines.data();

	return ret;
}


/**
	Generates an identifier suitable to use as within a URL.

	The resulting string will contain only ASCII lower case alphabetic or
	numeric characters, as well as dashes (-). Every sequence of
	non-alphanumeric characters will be replaced by a single dash. No dashes
	will be at either the front or the back of the result string.
*/
auto asSlug(R)(R text)
	if (isInputRange!R && is(typeof(R.init.front) == dchar))
{
	static struct SlugRange {
		private {
			R _input;
			bool _dash;
		}

		this(R input)
		{
			_input = input;
			skipNonAlphaNum();
		}

		@property bool empty() const { return _dash ? false : _input.empty; }
		@property char front() const {
			if (_dash) return '-';

			char r = cast(char)_input.front;
			if (r >= 'A' && r <= 'Z') return cast(char)(r + ('a' - 'A'));
			return r;
		}

		void popFront()
		{
			if (_dash) {
				_dash = false;
				return;
			}

			_input.popFront();
			auto na = skipNonAlphaNum();
			if (na && !_input.empty)
				_dash = true;
		}

		private bool skipNonAlphaNum()
		{
			bool have_skipped = false;
			while (!_input.empty) {
				switch (_input.front) {
					default:
						_input.popFront();
						have_skipped = true;
						break;
					case 'a': .. case 'z':
					case 'A': .. case 'Z':
					case '0': .. case '9':
						return have_skipped;
				}
			}
			return have_skipped;
		}
	}
	return SlugRange(text);
}

unittest {
	import std.algorithm : equal;
	assert ("".asSlug.equal(""));
	assert (".,-".asSlug.equal(""));
	assert ("abc".asSlug.equal("abc"));
	assert ("aBc123".asSlug.equal("abc123"));
	assert ("....aBc...123...".asSlug.equal("abc-123"));
}


/**
	Finds the closing bracket (works with any of '[', '$(LPAREN)', '<', '{').

	Params:
		str = input string
		nested = whether to skip nested brackets
	Returns:
		The index of the closing bracket or -1 for unbalanced strings
		and strings that don't start with a bracket.
*/
private sizediff_t matchBracket(const(char)[] str, bool nested = true)
@safe pure nothrow {
	if (str.length < 2) return -1;

	char open = str[0], close = void;
	switch (str[0]) {
		case '[': close = ']'; break;
		case '(': close = ')'; break;
		case '<': close = '>'; break;
		case '{': close = '}'; break;
		default: return -1;
	}

	size_t level = 1;
	foreach (i, char c; str[1 .. $]) {
		if (nested && c == open) ++level;
		else if (c == close) --level;
		if (level == 0) return i + 1;
	}
	return -1;
}

@safe unittest
{
	static struct Test { string str; sizediff_t res; }
	enum tests = [
		Test("[foo]", 4), Test("<bar>", 4), Test("{baz}", 4),
		Test("[", -1), Test("[foo", -1), Test("ab[f]", -1),
		Test("[foo[bar]]", 9), Test("[foo{bar]]", 8),
	];
	foreach (test; tests)
		assert(matchBracket(test.str) == test.res);
	assert(matchBracket("[foo[bar]]", false) == 8);
	static assert(matchBracket("[foo]") == 4);
}


private struct LinkRef {
	string id;
	string url;
	string title;
	Attribute[] attributes;
}

private struct Link {
	string text;
	string url;
	string title;
}

@safe unittest { // alt and title attributes
	assert (filterMarkdown("![alt](http://example.org/image)")
		== "<p><img src=\"http://example.org/image\" alt=\"alt\">\n</p>\n");
	assert (filterMarkdown("![alt](http://example.org/image \"Title\")")
		== "<p><img src=\"http://example.org/image\" alt=\"alt\" title=\"Title\">\n</p>\n");
}

@safe unittest { // complex links
	assert (filterMarkdown("their [install\ninstructions](<http://www.brew.sh>) and")
		== "<p>their <a href=\"http://www.brew.sh\">install\ninstructions</a> and\n</p>\n");
	assert (filterMarkdown("[![Build Status](https://travis-ci.org/rejectedsoftware/vibe.d.png)](https://travis-ci.org/rejectedsoftware/vibe.d)")
		== "<p><a href=\"https://travis-ci.org/rejectedsoftware/vibe.d\"><img src=\"https://travis-ci.org/rejectedsoftware/vibe.d.png\" alt=\"Build Status\"></a>\n</p>\n");
}

@safe unittest { // check CTFE-ability
	enum res = filterMarkdown("### some markdown\n[foo][]\n[foo]: /bar");
	assert (res == "<h3 id=\"some-markdown\"> some markdown</h3>\n<p><a href=\"/bar\">foo</a>\n</p>\n", res);
}

@safe unittest { // correct line breaks in restrictive mode
	auto res = filterMarkdown("hello\nworld", MarkdownFlags.forumDefault);
	assert (res == "<p>hello<br/>world\n</p>\n", res);
}

/*@safe unittest { // code blocks and blockquotes
	assert (filterMarkdown("\tthis\n\tis\n\tcode") ==
		"<pre><code>this\nis\ncode</code></pre>\n");
	assert (filterMarkdown("    this\n    is\n    code") ==
		"<pre><code>this\nis\ncode</code></pre>\n");
	assert (filterMarkdown("    this\n    is\n\tcode") ==
		"<pre><code>this\nis</code></pre>\n<pre><code>code</code></pre>\n");
	assert (filterMarkdown("\tthis\n\n\tcode") ==
		"<pre><code>this\n\ncode</code></pre>\n");
	assert (filterMarkdown("\t> this") ==
		"<pre><code>&gt; this</code></pre>\n");
	assert (filterMarkdown(">     this") ==
		"<blockquote><pre><code>this</code></pre></blockquote>\n");
	assert (filterMarkdown(">     this\n    is code") ==
		"<blockquote><pre><code>this\nis code</code></pre></blockquote>\n");
}*/

@safe unittest {
	assert (filterMarkdown("## Hello, World!") == "<h2 id=\"hello-world\"> Hello, World!</h2>\n", filterMarkdown("## Hello, World!"));
}

@safe unittest { // tables
	assert (filterMarkdown("foo|bar\n---|---", MarkdownFlags.tables)
		== "<table>\n<tr><th>foo</th><th>bar</th></tr>\n</table>\n");
	assert (filterMarkdown(" *foo* | bar \n---|---\n baz|bam", MarkdownFlags.tables)
		== "<table>\n<tr><th><em>foo</em></th><th>bar</th></tr>\n<tr><td>baz</td><td>bam</td></tr>\n</table>\n");
	assert (filterMarkdown("|foo|bar|\n---|---\n baz|bam", MarkdownFlags.tables)
		== "<table>\n<tr><th>foo</th><th>bar</th></tr>\n<tr><td>baz</td><td>bam</td></tr>\n</table>\n");
	assert (filterMarkdown("foo|bar\n|---|---|\nbaz|bam", MarkdownFlags.tables)
		== "<table>\n<tr><th>foo</th><th>bar</th></tr>\n<tr><td>baz</td><td>bam</td></tr>\n</table>\n");
	assert (filterMarkdown("foo|bar\n---|---\n|baz|bam|", MarkdownFlags.tables)
		== "<table>\n<tr><th>foo</th><th>bar</th></tr>\n<tr><td>baz</td><td>bam</td></tr>\n</table>\n");
	assert (filterMarkdown("foo|bar|baz\n:---|---:|:---:\n|baz|bam|bap|", MarkdownFlags.tables)
		== "<table>\n<tr><th align=\"left\">foo</th><th align=\"right\">bar</th><th align=\"center\">baz</th></tr>\n"
		~ "<tr><td align=\"left\">baz</td><td align=\"right\">bam</td><td align=\"center\">bap</td></tr>\n</table>\n");
	assert (filterMarkdown(" |bar\n---|---", MarkdownFlags.tables)
		== "<table>\n<tr><th></th><th>bar</th></tr>\n</table>\n");
	assert (filterMarkdown("foo|bar\n---|---\nbaz|", MarkdownFlags.tables)
		== "<table>\n<tr><th>foo</th><th>bar</th></tr>\n<tr><td>baz</td></tr>\n</table>\n");
}

@safe unittest { // issue #1527 - blank lines in code blocks
	assert (filterMarkdown("    foo\n\n    bar\n") ==
		"<pre class=\"prettyprint\"><code>foo\n\nbar\n</code></pre>\n");
}

@safe unittest {
	assert (filterMarkdown("> ```\r\n> test\r\n> ```", MarkdownFlags.forumDefault) ==
		"<blockquote><pre class=\"prettyprint\"><code>test\n</code></pre>\n</blockquote>\n");
}

@safe unittest { // issue #1845 - malicious URI targets
	assert (filterMarkdown("[foo](javascript:foo) ![bar](javascript:bar) <javascript:baz>", MarkdownFlags.forumDefault) ==
		"<p><a href=\"#\">foo</a> <img src=\"#\" alt=\"bar\"> <a href=\"#\">javascript:baz</a>\n</p>\n");
	assert (filterMarkdown("[foo][foo] ![foo][foo]\n[foo]: javascript:foo", MarkdownFlags.forumDefault) ==
		"<p><a href=\"#\">foo</a> <img src=\"#\" alt=\"foo\">\n</p>\n");
	assert (filterMarkdown("[foo](javascript%3Abar)", MarkdownFlags.forumDefault) ==
		"<p><a href=\"javascript%3Abar\">foo</a>\n</p>\n");

	// extra XSS regression tests
	assert (filterMarkdown("[<script></script>](bar)", MarkdownFlags.forumDefault) ==
		"<p><a href=\"bar\">&lt;script&gt;&lt;/script&gt;</a>\n</p>\n");
	assert (filterMarkdown("[foo](\"><script></script><span foo=\")", MarkdownFlags.forumDefault) ==
		"<p><a href=\"&quot;&gt;&lt;script&gt;&lt;/script&gt;&lt;span foo=&quot;\">foo</a>\n</p>\n");
	assert (filterMarkdown("[foo](javascript&#58;bar)", MarkdownFlags.forumDefault) ==
		"<p><a href=\"javascript&amp;#58;bar\">foo</a>\n</p>\n");
}

@safe unittest { // issue #2132 - table with more columns in body goes out of array bounds
	assert (filterMarkdown("| a | b |\n|--------|--------|\n|   c    | d  | e |", MarkdownFlags.tables) ==
		"<table>\n<tr><th>a</th><th>b</th></tr>\n<tr><td>c</td><td>d</td><td>e</td></tr>\n</table>\n");
}

@safe unittest { // lists
	assert (filterMarkdown("- foo\n- bar") ==
		"<ul>\n<li>foo\n</li>\n<li>bar\n</li>\n</ul>\n");
	assert (filterMarkdown("- foo\n\n- bar") ==
		"<ul>\n<li><p>foo\n</p>\n</li>\n<li><p>bar\n</p>\n</li>\n</ul>\n");
	assert (filterMarkdown("1. foo\n2. bar") ==
		"<ol>\n<li>foo\n</li>\n<li>bar\n</li>\n</ol>\n");
	assert (filterMarkdown("1. foo\n\n2. bar") ==
		"<ol>\n<li><p>foo\n</p>\n</li>\n<li><p>bar\n</p>\n</li>\n</ol>\n");
	assert (filterMarkdown("1. foo\n\n\tbar\n\n2. bar\n\n\tbaz\n\n") ==
		"<ol>\n<li><p>foo\n</p>\n<p>bar\n</p>\n</li>\n<li><p>bar\n</p>\n<p>baz\n</p>\n</li>\n</ol>\n");
}

@safe unittest { // figures
	assert (filterMarkdown("- %%%") == "<ul>\n<li>%%%\n</li>\n</ul>\n");
	assert (filterMarkdown("- ###") == "<ul>\n<li>###\n</li>\n</ul>\n");
	assert (filterMarkdown("- %%%", MarkdownFlags.figures) == "<figure></figure>\n");
	assert (filterMarkdown("- ###", MarkdownFlags.figures) == "<figcaption></figcaption>\n");
	assert (filterMarkdown("- %%%\n\tfoo\n\n\t- ###\n\t\tbar", MarkdownFlags.figures) ==
		"<figure>foo\n<figcaption>bar\n</figcaption>\n</figure>\n");
	assert (filterMarkdown("- %%%\n\tfoo\n\n\tbar\n\n\t- ###\n\t\tbaz", MarkdownFlags.figures) ==
		"<figure><p>foo\n</p>\n<p>bar\n</p>\n<figcaption>baz\n</figcaption>\n</figure>\n");
	assert (filterMarkdown("- %%%\n\tfoo\n\n\t- ###\n\t\tbar\n\n\t\tbaz", MarkdownFlags.figures) ==
		"<figure>foo\n<figcaption><p>bar\n</p>\n<p>baz\n</p>\n</figcaption>\n</figure>\n");
	assert (filterMarkdown("- %%%\n\t1. foo\n\t2. bar\n\n\t- ###\n\t\tbaz", MarkdownFlags.figures) ==
		"<figure><ol>\n<li>foo\n</li>\n<li>bar\n</li>\n</ol>\n<figcaption>baz\n</figcaption>\n</figure>\n");
	assert (filterMarkdown("- foo\n- %%%", MarkdownFlags.figures) == "<ul>\n<li>foo\n</li>\n</ul>\n<figure></figure>\n");
	assert (filterMarkdown("- foo\n\n- %%%", MarkdownFlags.figures) == "<ul>\n<li>foo\n</li>\n</ul>\n<figure></figure>\n");
}

@safe unittest { // HTML entities
	assert(filterMarkdown("&nbsp;") == "<p>&nbsp;\n</p>\n");
	assert(filterMarkdown("*&nbsp;*") == "<p><em>&nbsp;</em>\n</p>\n");
	assert(filterMarkdown("`&nbsp;`") == "<p><code class=\"prettyprint\">&amp;nbsp;</code>\n</p>\n");
}

