/**
	DietDoc/DDOC support routines

	Copyright: © 2012 Sönke Ludwig
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


bool isProt(Json n, string prot){ return ("protection" in n ? n.protection.get!string : "public") == prot; }
string multi(string word){ return word[$-1] == 's' ? word ~ "es" : word ~ "s"; }

bool isKind(string kind, Json n){ return n.kind == kind; }
Json[] getItemsForKind(string prot, string kind, Json n){ Json[] ret; foreach( dg; n.members[multi(kind)].opt!(Json[]) ) ret ~= dg.get!(Json[]); return ret; }
bool hasItemsForKind(string prot, string kind, Json n){ return (multi(kind) in n.members) !is null; }

bool isFunction(Json n){ return isKind("function", n); }
Json[] functions(Json n, string prot = "public"){ return getItemsForKind(prot, "function", n); }
bool hasFunctions(Json n, string prot = "public"){ return hasItemsForKind(prot, "function", n); }

bool isConstructor(Json n){ return isKind("constructor", n); }
Json[] constructors(Json n, string prot = "public"){ return getItemsForKind(prot, "constructor", n); }
bool hasConstructors(Json n, string prot = "public"){ return hasItemsForKind(prot, "constructor", n); }

bool isInterface(Json n){ return isKind("interface", n); }
Json[] interfaces(Json n, string prot = "public"){ return getItemsForKind(prot, "interface", n); }
bool hasInterfaces(Json n, string prot = "public"){ return hasItemsForKind(prot, "interface", n); }

bool isClass(Json n){ return isKind("class", n); }
Json[] classes(Json n, string prot = "public"){ return getItemsForKind(prot, "class", n); }
bool hasClasses(Json n, string prot = "public"){ return hasItemsForKind(prot, "class", n); }

bool isStruct(Json n){ return isKind("struct", n); }
Json[] structs(Json n, string prot = "public"){ return getItemsForKind(prot, "struct", n); }
bool hasStructs(Json n, string prot = "public"){ return hasItemsForKind(prot, "struct", n); }

bool isEnum(Json n){ return isKind("enum", n); }
Json[] enums(Json n, string prot = "public"){ return getItemsForKind(prot, "enum", n); }
bool hasEnums(Json n, string prot = "public"){ return hasItemsForKind(prot, "enum", n); }

bool isAlias(Json n){ return isKind("alias", n); }
Json[] aliases(Json n, string prot = "public"){ return getItemsForKind(prot, "alias", n); }
bool hasAliases(Json n, string prot = "public"){ return hasItemsForKind(prot, "alias", n); }

bool isVariable(Json n){ return isKind("variable", n); }
Json[] variables(Json n, string prot = "public"){ return getItemsForKind(prot, "variable", n); }
bool hasVariables(Json n, string prot = "public"){ return hasItemsForKind(prot, "variable", n); }


string formatDdocComment(Json ddoc_, int hlevel = 2, bool delegate(string) display_section = null)
{
	if( ddoc_.type != Json.Type.String ) return null;
	auto dst = appender!string();
	filterDdocComment(dst, cast(string)ddoc_, hlevel, display_section);
	return dst.data;
}

void filterDdocComment(R)(ref R dst, string ddoc, int hlevel = 2, bool delegate(string) display_section = null)
{
	auto lines = splitLines(ddoc);
	if( !lines.length ) return;

	string[string] macros;
	parseMacros(macros, s_standardMacros);

	enum {
		BLANK,
		TEXT,
		CODE,
		SECTION
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

	bool skip_section;

	// first section is implicitly the long description
	while( i < lines.length && getLineType(i) == BLANK ) i++;
	if( i < lines.length && getLineType(i) != SECTION ){
		skip_section = display_section && !display_section("$Long");
	}

	while( i < lines.length ){
		int lntype = getLineType(i);

		if( lntype == BLANK ){ i++; continue; }
		if( lntype != SECTION && skip_section ){ i++; continue; }

		switch( lntype ){
			default: assert(false);
			case TEXT:
				dst.put("<p>");
				auto j = skipBlock(i);
				foreach( ln; lines[i .. j] ){
					renderTextLine(dst, ln, macros);
					dst.put("\n");
				}
				dst.put("</p>\n");
				i = j;
				break;
			case CODE:
				dst.put("<pre class=\"code prettyprint lang-d\">");
				auto j = skipCodeBlock(i);
				auto base_indent = baseIndent(lines[i+1 .. j]);
				foreach( ln; lines[i+1 .. j] ){
					dst.put(ln.unindent(base_indent));
					dst.put("\n");
				}
				dst.put("</pre>\n");
				i = j+1;
				break;
			case SECTION:
				auto pidx = lines[i].countUntil(':');
				auto sect = strip(lines[i][0 .. pidx]);

				if( sect == "Macros" ){
					auto j = skipBlock(i);
					parseMacros(macros, lines[i+1 .. j]);
					i = j;
					break;
				}

				skip_section = display_section && !display_section(sect);
				if( !skip_section ){
					dst.put("<h"~to!string(hlevel)~">");
					dst.put(sect);
					dst.put("</h"~to!string(hlevel)~">\n");
				}
				auto rest = strip(lines[i][pidx+1 .. $]);
				auto j = skipBlock(i);
				if( rest.length && !skip_section ){
					dst.put("<p>\n");
					renderTextLine(dst, rest, macros);
					dst.put("\n");
					foreach( ln; lines[i+1 .. j] ){
						renderTextLine(dst, ln, macros);
						dst.put("\n");
					}
					dst.put("</p>\n");
				}
				i = j;
				break;
		}
	}
}

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
			auto cidx = line.countUntil(')');
			if( cidx < 0 ) continue;
			auto args = splitParams(line[1 .. cidx]);
			logDebug("PARAMS: %s", args);
			logDebug("MACROS: %s", macros);
			line = line[cidx+1 .. $];

			if( args.length < 1 ) continue;

			if( auto pm = args[0] in macros ){
				renderTextLine(dst, *pm, macros, args[1 .. $]);
			}
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
