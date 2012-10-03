﻿/**
	DietDoc/DDOC support routines

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.textfilter.ddoc;

public import vibe.data.json;

import vibe.core.log;
import vibe.utils.string;

import std.algorithm;
import std.array;
import std.conv;


private bool isProt(Json n, string prot){ return ("protection" in n ? n.protection.get!string : "public") == prot; }
private string multi(string word){ return word[$-1] == 's' ? word ~ "es" : word ~ "s"; }

/**
	Determines if a DDOCsteroids node contains a certain kind of child.
*/
bool isKind(string kind, Json n){ return n.kind == kind; }
/// ditto
Json[] getItemsForKind(string prot, string kind, Json n){ Json[] ret; foreach( dg; n.members[multi(kind)].opt!(Json[]) ) ret ~= dg.get!(Json[]); return ret; }
/// ditto
Json[] getItemGroupsForKind(string prot, string kind, Json n){ Json[] ret; foreach( dg; n.members[multi(kind)].opt!(Json[]) ) ret ~= dg; return ret; }
/// ditto
bool hasItemsForKind(string prot, string kind, Json n){ return (multi(kind) in n.members) !is null; }

/// ditto
bool isFunction(Json n){ return isKind("function", n); }
/// ditto
Json[] functions(Json n, string prot = "public"){ return getItemsForKind(prot, "function", n); }
/// ditto
bool hasFunctions(Json n, string prot = "public"){ return hasItemsForKind(prot, "function", n); }

/// ditto
bool isConstructor(Json n){ return isKind("constructor", n); }
/// ditto
Json[] constructors(Json n, string prot = "public"){ return getItemsForKind(prot, "constructor", n); }
/// ditto
bool hasConstructors(Json n, string prot = "public"){ return hasItemsForKind(prot, "constructor", n); }

/// ditto
bool isInterface(Json n){ return isKind("interface", n); }
/// ditto
Json[] interfaces(Json n, string prot = "public"){ return getItemsForKind(prot, "interface", n); }
/// ditto
bool hasInterfaces(Json n, string prot = "public"){ return hasItemsForKind(prot, "interface", n); }

/// ditto
bool isClass(Json n){ return isKind("class", n); }
/// ditto
Json[] classes(Json n, string prot = "public"){ return getItemsForKind(prot, "class", n); }
/// ditto
bool hasClasses(Json n, string prot = "public"){ return hasItemsForKind(prot, "class", n); }

/// ditto
bool isStruct(Json n){ return isKind("struct", n); }
/// ditto
Json[] structs(Json n, string prot = "public"){ return getItemsForKind(prot, "struct", n); }
/// ditto
bool hasStructs(Json n, string prot = "public"){ return hasItemsForKind(prot, "struct", n); }

/// ditto
bool isEnum(Json n){ return isKind("enum", n); }
/// ditto
Json[] enums(Json n, string prot = "public"){ return getItemsForKind(prot, "enum", n); }
/// ditto
bool hasEnums(Json n, string prot = "public"){ return hasItemsForKind(prot, "enum", n); }

/// ditto
bool isAlias(Json n){ return isKind("alias", n); }
/// ditto
Json[] aliases(Json n, string prot = "public"){ return getItemsForKind(prot, "alias", n); }
/// ditto
bool hasAliases(Json n, string prot = "public"){ return hasItemsForKind(prot, "alias", n); }

/// ditto
bool isVariable(Json n){ return isKind("variable", n); }
/// ditto
Json[] variables(Json n, string prot = "public"){ return getItemsForKind(prot, "variable", n); }
/// ditto
bool hasVariables(Json n, string prot = "public"){ return hasItemsForKind(prot, "variable", n); }


/**
	Takes a DDOC string and outputs formatted HTML.

	The hlevel parameter specifies the header level used for section names (&lt;h2&gt by default).
	By specifying a display_section callback it is also possible to output only certain sections.
*/
string formatDdocComment(string ddoc_, int hlevel = 2, bool delegate(string) display_section = null)
{
	auto dst = appender!string();
	filterDdocComment(dst, cast(string)ddoc_, hlevel, display_section);
	return dst.data;
}
/// ditto
string formatDdocComment(Json ddoc_, int hlevel = 2, bool delegate(string) display_section = null)
{
	if( ddoc_.type != Json.Type.String ) return null;
	return formatDdocComment(ddoc_.get!string, hlevel, display_section);
}
/// ditto
void filterDdocComment(R)(ref R dst, string ddoc, int hlevel = 2, bool delegate(string) display_section = null)
{
	auto lines = splitLines(ddoc);
	if( !lines.length ) return;

	string[string] macros;
	parseMacros(macros, s_standardMacros);

	int getLineType(int i)
	{
		auto ln = strip(lines[i]);
		if( ln.length == 0 ) return BLANK;
		else if( ln.length >= 3 && ln.allOf("-") ) return CODE;
		else if( ln.countUntil(':') > 0 && !ln[0 .. ln.countUntil(':')].anyOf(" \t") ) return SECTION;
		return TEXT;
	}

	int skipCodeBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) != CODE);
		return start+1;
	}

	int skipSection(int start)
	{
		while(start < lines.length && getLineType(start) != SECTION){
			if( getLineType(start) == CODE )
				start = skipCodeBlock(start);
			else start++;
		}
		return start;
	}

	int skipBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) == TEXT);
		return start;
	}


	int i = 0;

	// special case short description on the first line
	while( i < lines.length && getLineType(i) == BLANK ) i++;
	if( i < lines.length && getLineType(i) == TEXT ){
		auto j = skipBlock(i);
		if( !display_section || display_section("$Short") ){
			foreach( l; lines[i .. j] ){
				dst.put(l);
				dst.put("\n");
			}
		}
		i = j;
	}

	// first section is implicitly the long description
	{
		auto j = skipSection(i);
		if( !display_section || display_section("$Long") )
			parseSection(dst, "$Long", lines[i .. j], hlevel, macros);
		i = j;
	}

	// parse all other sections
	while( i < lines.length ){
		assert(getLineType(i) == SECTION);
		auto j = skipSection(i+1);
		auto pidx = lines[i].countUntil(':');
		auto sect = strip(lines[i][0 .. pidx]);
		lines[i] = strip(lines[i][pidx+1 .. $]);
		if( lines[i].empty ) i++;
		if( !display_section || display_section(sect) )
			parseSection(dst, sect, lines[i .. j], hlevel, macros);
		i = j;
	}
}

private enum {
	BLANK,
	TEXT,
	CODE,
	SECTION
}


/// private
private void parseSection(R)(ref R dst, string sect, string[] lines, int hlevel, string[string] macros)
{
	void putHeader(string hdr){
		dst.put("<section>");
		if( sect.length > 0 && sect[0] != '$' ){
			dst.put("<h"~to!string(hlevel)~">");
			dst.put(hdr);
			dst.put("</h"~to!string(hlevel)~">\n");
		}
	}

	void putFooter(){
		dst.put("</section>\n");
	}

	int getLineType(int i)
	{
		auto ln = strip(lines[i]);
		if( ln.length == 0 ) return BLANK;
		else if( ln.allOf("-") ) return CODE;
		else if( ln.countUntil(':') > 0 && !ln[0 .. ln.countUntil(':')].anyOf(" \t") ) return SECTION;
		return TEXT;
	}

	int skipBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) == TEXT);
		return start;
	}

	int skipCodeBlock(int start)
	{
		do {
			start++;
		} while(start < lines.length && getLineType(start) != CODE);
		return start;
	}

	switch( sect ){
		default:
			putHeader(sect);
			int i = 0;
			while( i < lines.length ){
				int lntype = getLineType(i);

				if( lntype == BLANK ){ i++; continue; }

				switch( lntype ){
					default: assert(false);
					case TEXT:
						dst.put("<p>");
						auto j = skipBlock(i);
						renderTextLine(dst, lines[i .. j].join("\n"), macros);
						dst.put("</p>\n");
						i = j;
						break;
					case CODE:
						dst.put("<pre class=\"code prettyprint\">");
						auto j = skipCodeBlock(i);
						auto base_indent = baseIndent(lines[i+1 .. j]);
						foreach( ln; lines[i+1 .. j] ){
							dst.put(ln.unindent(base_indent));
							dst.put("\n");
						}
						dst.put("</pre>\n");
						i = j+1;
						break;
				}
			}
			putFooter();
			break;
		case "Macros":
			parseMacros(macros, lines);
			break;
		case "Params":
			putHeader("Parameters");
			dst.put("<table><col class=\"caption\"><tr><th>Parameter name</th><th>Description</th></tr>\n");
			bool in_dt = false;
			foreach( ln; lines ){
				auto eidx = ln.countUntil("=");
				if( eidx < 0 ){
					if( in_dt ){
						dst.put(' ');
						dst.put(ln.strip());
					} else logWarn("Out of place text in param section: %s", ln.strip());
				} else {
					auto pname = ln[0 .. eidx].strip();
					auto pdesc = ln[eidx+1 .. $].strip();
					if( in_dt ) dst.put("</td></tr>\n");
					dst.put("<tr><td>");
					dst.put(pname);
					dst.put("</td><td>\n");
					dst.put(pdesc);
					in_dt = true;
				}
			}
			if( in_dt ) dst.put("</td>\n");
			dst.put("</tr></table>\n");
			putFooter();
			break;
	}

}

/// private
private void renderTextLine(R)(ref R dst, string line, string[string] macros, string[] params = null)
{
	while( line.length > 0 ){
		if( line[0] != '$' ){
			dst.put(line[0]);
			line = line[1 .. $];
			continue;
		}

		line = line[1 .. $];
		if( line.length < 1) continue;

		if( line[0] == '0'){
			foreach( i, p; params ){
				if( i > 0 ) dst.put(' ');
				dst.put(p);
			}
			line = line[1 .. $];
		} else if( line[0] >= '1' && line[0] <= '9' ){
			int pidx = line[0]-'1';
			if( pidx < params.length )
				dst.put(params[pidx]);
			line = line[1 .. $];
		} else if( line[0] == '+' ){
			bool got_comma = false;
			foreach( i, p; params ){
				if( !got_comma ){
					if( p == "," )
						got_comma = true;
					continue;
				}
				if( i > 0 ) dst.put(' ');
				dst.put(p);
			}
			line = line[1 .. $];
		} else if( line[0] == '(' ){
			line = line[1 .. $];
			int l = 1;
			size_t cidx = 0;
			for( cidx = 0; cidx < line.length && l > 0; cidx++ ){
				if( line[cidx] == '(' ) l++;
				else if( line[cidx] == ')' ) l--;
			}
			if( l > 0 ){
				logDebug("Unmatched parenthesis in DDOC comment.");
				continue;
			}
			if( cidx < 1 ){
				logDebug("Missing macro name in DDOC comment.");
				continue;
			}

			auto mnameidx = line[0 .. cidx-1].countUntilAny(" \t\r\n");

			if( mnameidx < 0 ){
				logDebug("Macro call in DDOC comment is missing macro name.");
				continue;
			}
			auto mname = line[0 .. mnameidx];

			auto argstext = appender!string();
			string[] args;
			if( mnameidx+1 < cidx ){
				renderTextLine(argstext, line[mnameidx+1 .. cidx-1], macros, params);
				args = splitParams(argstext.data());
			}

			logTrace("PARAMS: (%s) %s", mname, args);
			logTrace("MACROS: %s", macros);
			line = line[cidx .. $];

			if( auto pm = mname in macros )
				renderTextLine(dst, *pm, macros, args);
			else logDebug("Macro '%s' not found.", mname);
		}
	}
}

private string[] splitParams(string ln)
{
	ln = stripLeft(ln);
	string[] ret;
	while( ln.length ){
		ret ~= skipWhitespace(ln);
		ln = stripLeft(ln);
	}
	return ret;
}

private string skipWhitespace(ref string ln)
{
	string ret = ln;
	while( ln.length > 0 ){
		if( ln[0] == ' ' || ln[0] == '\t' )
			break;
		ln = ln[1 .. $];
	}
	return ret[0 .. ret.length - ln.length];
}

private void parseMacros(ref string[string] macros, in string[] lines)
{
	foreach( ln; lines ){
		auto pidx = ln.countUntil('=');
		if( pidx > 0 ){
			string name = strip(ln[0 .. pidx]);
			string value = strip(ln[pidx+1 .. $]);
			macros[name] = value;
		}
	}
}

private int baseIndent(string[] lines)
{
	if( lines.length == 0 ) return 0;
	int ret = int.max;
	foreach( ln; lines ){
		int i = 0;
		while( i < ln.length && (ln[i] == ' ' || ln[i] == '\t') )
			i++;
		if( i < ln.length ) ret = min(ret, i); 
	}
	return ret;
}

private string unindent(string ln, int amount)
{
	while( amount > 0 && ln.length > 0 && (ln[0] == ' ' || ln[0] == '\t') )
		ln = ln[1 .. $], amount--;
	return ln;
}

private immutable s_standardMacros = [
	"P = <p>$0</p>",
	"DL = <dl>$0</dl>",
	"DT = <dt>$0</dt>",
	"DD = <dd>$0</dd>",
	"TABLE = <table>$0</table>",
	"TR = <tr>$0</tr>",
	"TH = <th>$0</th>",
	"TD = <td>$0</td>",
	"OL = <ol>$0</ol>",
	"UL = <ul>$0</ul>",
	"LI = <li>$0</li>",
	"LINK = <a href=\"$0\">$0</a>",
	"LINK2 = <a href=\"$1\">$+</a>",
	"LPAREN= (",
	"RPAREN= )"
];
