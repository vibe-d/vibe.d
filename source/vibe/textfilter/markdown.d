/**
	Markdown parser implementation

	Copyright: © 2012 Sönke Ludwig
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
import std.string;

/*
	TODO:
		detect inline HTML tags
		no p inside li when there is no newline
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

string filterMarkdown()(string str)
{
	auto dst = appender!string();
	filterMarkdown(dst, str);
	return dst.data;
}

void filterMarkdown(R)(ref R dst, string src)
{
	auto lines = splitLines(src);
	auto references = scanForReferences(lines);

	bool skip_next_line = false;

	MarkdownState[] state = [];
	for( size_t lnidx = 0; lnidx < lines.length; lnidx++ ){
		string ln = lines[lnidx];
		logTrace("[line %d: %s]", lnidx+1, ln);
		// skips Setext style headers...
		if( skip_next_line ){
			logTrace("[skipping line %d: %s]", lnidx+1, ln);
			skip_next_line = false;
			continue;
		}

		// gather some basic information about the line and unindent if indented
		bool is_indented = isLineIndented(ln);
		bool is_blank = isLineBlank(ln);
		bool list_ended = !is_blank && !is_indented && state.length == 1;
		bool is_atx_header = false;
		bool is_hline = false;
		if( is_indented ){
			ln = unindentLine(ln);

			// if we are inside a list, indentation is one level deeper
			if( state.length > 0 && (state[0] == MarkdownState.OList || state[0] == MarkdownState.UList) )
			{
				is_indented = isLineIndented(ln);
				if( is_indented)
					ln = unindentLine(ln);
			}
		} else if( isAtxHeaderLine(ln) ){
			is_atx_header = isAtxHeaderLine(ln);
			is_blank = true;
		} else if( isHlineLine(ln) ){
			is_hline = true;
			is_blank = true;
		}

		// detect HTML block tags
		if( !is_indented && isHtmlBlockLine(ln) ){
			int depth = 1;
			dst.put(ln);
			dst.put('\n');
			string openingtag = getHtmlTagName(ln);
			while( depth > 0 ){
				ln = lines[++lnidx];
				dst.put(ln);
				dst.put('\n');
				if( isHtmlBlockLine(ln) && getHtmlTagName(ln) == openingtag ) depth++;
				else if( isHtmlBlockCloseLine(ln) && getHtmlTagName(ln) == openingtag) depth--;
			}
			continue;
		}

		// determine the type of this line
		MarkdownState newstate;
		if( is_indented ) newstate = MarkdownState.Code;
		else if( is_blank ) newstate = MarkdownState.Blank;
		else if( isQuoteLine(ln) ) newstate = cast(MarkdownState)(MarkdownState.Quote0 + getQuoteLevel(ln));
		else if( isUListLine(ln) ) newstate = MarkdownState.UList;
		else if( isOListLine(ln) ) newstate = MarkdownState.OList;
		else newstate = MarkdownState.Text;

		logTrace("[detected state after %s: %s]", state, newstate);
		// if the next line is a Setext style header, exit all states, output the header and skip the next line
		if( newstate == MarkdownState.Text && lnidx+1 < lines.length && isSetextHeaderLine(lines[lnidx+1]) ){
			logTrace("[header at line %d: %s]", lnidx+1, ln);
			foreach_reverse( st; state ) exitState(dst, st);
			state.length = 0;
			outputHeaderLine(dst, ln, lines[lnidx+1]);
			skip_next_line = true;
			continue;
		}

		// behave according the the state transition table:
		//
		//                 Blank   Text          Code          QuoteM          OList
		//[Text]           []      [Text]        [Code]        [QuoteM]        [OList Text]
		//[Code]           []      [Text]        [Code]        [QuoteM]        [OList Text]
		//[QuoteN]         []      [Text]        [Code]        [QuoteM]        [OList Text]
		//[OList]          [OList] [OList, Text] [OList, Code] [OList, QuoteM] [OList Text]
		//[OList, Text]    [OList] [OList, Text] [OList, Code] [OList, QuoteM] [OList Text]
		//[OList, QuoteN]  [OList] [OList, Text] [OList, Code] [OList, QuoteM] [OList Text]
		//[OList, Code]    [OList] [OList, Text] [OList, Code] [OList, QuoteM] [OList Text]
		//[UList]          [UList] [UList, Text] [UList, Code] [UList, QuoteM] [OList Text]
		//[UList, Text]    [UList] [UList, Text] [UList, Code] [UList, QuoteM] [OList Text]
		//[UList, QuoteN]  [UList] [UList, Text] [UList, Code] [UList, QuoteM] [OList Text]
		//[UList, Code]    [UList] [UList, Text] [UList, Code] [UList, QuoteM] [OList Text]

		// if we have a list bullet or number, start a new list or make a new list item
		if( newstate == MarkdownState.OList || newstate == MarkdownState.UList ){
			if( state.length == 0 || state[0] != newstate ){
				logTrace("[enter list at line %d: %s]", lnidx+1, ln);
				foreach_reverse( st; state ) exitState(dst, st);
				state = [enterState(dst, newstate)];
				state ~= enterState(dst, MarkdownState.Text);
			} else {
				logTrace("[new list item at line %d: %s]", lnidx+1, ln);
				if( state.length > 1 ){
					exitState(dst, state[$-1]);
					state = state[0 .. $-1];
				}
				dst.put("</li>\n\t<li>");
				state ~= enterState(dst, MarkdownState.Text);
			}
			outputLine(dst, ln, newstate, references);
			continue;
		}

		// unchanged states just potentially output the line's text
		if( state.length > 0 && state[$-1] == newstate ){
			logTrace("[neutral at line %d: %s]", lnidx+1, ln);
			outputLine(dst, ln, newstate, references);
			continue;
		}

		// blank lines terminate the innermost state, except if we are in a list outside of text
		// special lines (headers, hr lines) always terminate the whole state
		if( newstate == MarkdownState.Blank ){
			if( is_atx_header || is_hline ){
				foreach_reverse( s; state ) exitState(dst, s);
				state.length = 0;
	
				if( is_atx_header ){
					outputHeaderLine(dst, ln, null);
				} else if( is_hline ){
					dst.put("<hr>\n");
				}
			} else if( state.length > 0 && state[$-1] != MarkdownState.OList && state[$-1] != MarkdownState.UList ){
				logTrace("[exit non-list at line %d: %s]", lnidx+1, ln);
				exitState(dst, state[$-1]);
				state = state[0 .. $-1];
			}
			continue;
		}

		// if we are in list state and the list is closed, exit all states -> neutral state
		if( state.length > 0 && (state[0] == MarkdownState.OList || state[0] == MarkdownState.UList)
			&& newstate != state[0] && list_ended )
		{
			logTrace("[exit list at line %d: %s]", lnidx+1, ln);
			foreach_reverse( st; state ) exitState(dst, st);
			state.length = 0;
		}

		// if we are in neutral state, just enter the new state
		if( state.length == 0 ){
			logTrace("[enter new state %s at line %d: %s]", newstate, lnidx+1, ln);
			state ~= enterState(dst, newstate);
			if( newstate == MarkdownState.OList || newstate == MarkdownState.UList  )
				state ~= enterState(dst, MarkdownState.Text);
			outputLine(dst, ln, newstate, references);
			continue;
		}


		// handle nested quote level transitions
		if( state[$-1] > MarkdownState.Quote0 && newstate > MarkdownState.Quote0 ){
			logTrace("[quote level changed at line %d: %s]", lnidx+1, ln);
			if( newstate > state[$-1] ){
				foreach( i; 0 .. newstate-state[$-1] )
					enterBlockQuote(dst);
			}
			if( newstate < state[$-1] ){
				foreach( i; 0 .. state[$-1]-newstate )
					exitBlockQuote(dst);
			}
			outputLine(dst, ln, newstate, references);
			state[$-1] = newstate;
			continue;
		}

		// for the rest, exit the deepest state and enter the new state
		if( (state[0] == MarkdownState.UList || state[0] == MarkdownState.OList) && state.length == 1){
			logTrace("[inner state pushed at line %d: %s -> %s]", lnidx+1, state, newstate);
			state ~= enterState(dst, newstate);
		} else {
			logTrace("[inner state changed at line %d: %s -> %s]", lnidx+1, state, newstate);
			exitState(dst, state[$-1]);
			state[$-1] = enterState(dst, newstate);
		}
		outputLine(dst, ln, newstate, references);
	}

	logTrace("[all lines processed]");
	// exit all states after all lines have been processed
	foreach_reverse( st; state ) exitState(dst, st);
}


private {
	immutable s_blockTags = ["div", "ol", "p", "pre", "section", "table", "ul"];
}

private enum MarkdownState {
	Blank,
	Text,
	Code,
	OList,
	UList,
	Quote0,
	Quote1,
}

private MarkdownState enterState(R)(ref R dst, MarkdownState state)
{
	switch(state){
		default:
			assert(state > MarkdownState.Quote0);
			foreach( i; 0 .. state - MarkdownState.Quote0 )
				dst.put("<blockquote>\n");
			break;
		case MarkdownState.Blank: break;
		case MarkdownState.Text: dst.put("<p>"); break;
		case MarkdownState.Code: dst.put("<pre><code>"); break;
		case MarkdownState.OList: dst.put("<ol>\n\t<li>"); break;
		case MarkdownState.UList: dst.put("<ul>\n\t<li>"); break;
	}
	return state;
}

private void exitState(R)(ref R dst, MarkdownState state)
{
	switch(state){
		default:
			assert(state > MarkdownState.Quote0);
			foreach( i; 0 .. state - MarkdownState.Quote0 )
				dst.put("</blockquote>\n");
			break;
		case MarkdownState.Blank: break;
		case MarkdownState.Text: dst.put("</p>\n"); break;
		case MarkdownState.Code: dst.put("</code></pre>\n"); break;
		case MarkdownState.OList: dst.put("</li>\n</ol>\n"); break;
		case MarkdownState.UList: dst.put("</li>\n</ul>\n"); break;
	}
}

private void outputLine(R)(ref R dst, string ln, MarkdownState state, in LinkRef[string] linkrefs)
{
	switch(state){
		case MarkdownState.Blank: break;
		default:
			assert(state > MarkdownState.Quote0);
			ln = stripLeft(ln);
			while( ln.length > 0 && ln[0] == '>' )
				ln = ln[1 .. $].stripLeft();
			goto case MarkdownState.Text;
		case MarkdownState.OList: // skip bullets and output using normal escaping
			auto idx = ln.countUntil('.');
			assert(idx > 0);
			ln = ln[idx+1 .. $].stripLeft();
			goto case MarkdownState.Text;
		case MarkdownState.UList:
			ln = stripLeft(ln.stripLeft()[1 .. $]);
			goto case MarkdownState.Text;
		case MarkdownState.Text: // output using normal escaping
			writeMarkdownEscaped(dst, ln, linkrefs);
			if( ln.endsWith("  ") ) dst.put("<br>");
			dst.put('\n');
			break;
		case MarkdownState.Code: // output without escaping
			filterHtmlEscape(dst, ln);
			dst.put('\n');
			break;
	}
}

private void writeMarkdownEscaped(R)(ref R dst, string ln, in LinkRef[string] linkrefs)
{
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
}

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

private void enterBlockQuote(R)(ref R dst)
{
	dst.put("<blockquote>");
}

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
	if( ln.length < 1 ) return false;
	return "*+-".countUntil(ln[0]) >= 0;
}

private bool isOListLine(string ln)
{
	ln = stripLeft(ln);
	if( ln.length < 1 ) return false;
	if( ln[0] < '0' || ln[0] > '9' ) return false;
	ln = ln[1 .. $];
	while( ln.length > 0 && ln[0] >= '0' && ln[0] <= '9' )
		ln = ln[1 .. $];
	return ln.length > 0 && ln[0] == '.';
}


auto parseHtmlBlockLine(string ln)
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

	auto eidx = ln.countUntil(">");
	if( eidx < 0 ) return ret;
	if( eidx != ln.length-1 ) return ret;

	if( s_blockTags.countUntil(ret.tagName) < 0 ) return ret;

	ret.isHtmlBlock = true;
	return ret;
}

bool isHtmlBlockLine(string ln)
{
	auto bi = parseHtmlBlockLine(ln);
	return bi.isHtmlBlock && bi.open;
}

bool isHtmlBlockCloseLine(string ln)
{
	auto bi = parseHtmlBlockLine(ln);
	return bi.isHtmlBlock && !bi.open;
}

string getHtmlTagName(string ln)
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

bool parseAutoLink(ref string str, ref string url)
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
	size_t[] reflines;

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
		reflines ~= lnidx;

		logTrace("[detected ref on line %d]", lnidx+1);
	}

	// remove all lines containing references
	foreach_reverse( i; reflines )
		lines = lines[0 .. i] ~ lines[i+1 .. $];

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
