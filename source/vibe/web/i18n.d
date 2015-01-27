/**
	Internationalization/translation support for the web interface module.

	Copyright: © 2014,2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.i18n;

import vibe.http.server : HTTPServerRequest;
import vibe.templ.parsertools;

import std.algorithm : canFind, min, startsWith;

/**
	Annotates an interface method or class with translation information.

	The translation context contains information about supported languages
	and the translated strings. Any translations will be automatically
	applied to Diet templates, as well as strings passed to
	$(D vibe.web.web.trWeb).

	By default, the "Accept-Language" header of the incoming request will be
	used to determine the language used. To override this behavior, add a
	static method $(D determineLanguage) to the translation context, which
	takes the request and returns a language string (see also the second
	example).
*/
@property TranslationContextAttribute!CONTEXT translationContext(CONTEXT)() { return TranslationContextAttribute!CONTEXT.init; }

///
unittest {
	struct TranslationContext {
		import std.typetuple;
		alias languages = TypeTuple!("en_US", "de_DE", "fr_FR");
		//mixin translationModule!"app";
		//mixin translationModule!"somelib";
	}

	@translationContext!TranslationContext
	class MyWebInterface {
		void getHome()
		{
			//render!("home.dt")
		}
	}
}

/// Defining a custom function for determining the language.
unittest {
	import vibe.http.server;

	struct TranslationContext {
		import std.typetuple;
		alias languages = TypeTuple!("en_US", "de_DE", "fr_FR");
		//mixin translationModule!"app";
		//mixin translationModule!"somelib";

		// use language settings from the session instead of using the
		// "Accept-Language" header
		static string determineLanguage(HTTPServerRequest req)
		{
			if (!req.session) return null; // use default language
			return req.session.get("language", "");
		}
	}

	@translationContext!TranslationContext
	class MyWebInterface {
		void getHome()
		{
			//render!("home.dt")
		}
	}
}


struct TranslationContextAttribute(CONTEXT) {
	alias Context = CONTEXT;
}

/*
doctype 5
html
	body
		p& Hello, World!
		p& This is a translated version of #{appname}.
	html
		p(class="Sasdasd")&.
			This is a complete paragraph of translated text.
*/

mixin template translationModule(string NAME)
{
	mixin template file_mixin(size_t i) {
		static if (i < languages.length) {
			enum components = extractDeclStrings(import(NAME~"."~languages[i]~".po"));
			mixin("enum "~languages[i]~"_"~NAME~" = components;");
			mixin file_mixin!(i+1);
		}
	}

	mixin file_mixin!0;
}

string tr(CTX, string LANG)(string msgid, string msgctxt = null) {
	return tr_plural!(CTX,LANG)(msgid, null, 0, msgctxt);
}

string tr_plural(CTX, string LANG)(string msgid, string msgid_plural, int n, string msgctxt = null) {
	static assert([CTX.languages].canFind(LANG), "Unknown language: "~LANG);

	foreach (i, mname; __traits(allMembers, CTX)) {
		static if (mname.startsWith(LANG~"_")) {
			enum langComponents = __traits(getMember, CTX, mname);
			foreach (entry; langComponents.messages) {
				if ((msgctxt is null) == (entry.msgctxt is null)) {
					if (msgctxt is null || entry.msgctxt == msgctxt) {
						if (entry.msgid == msgid) {
							if (msgid_plural !is null) {
								if (entry.msgid_plural !is null && entry.msgid_plural == msgid_plural) {
									static if (langComponents.nplurals_expr !is null && langComponents.plural_func_expr !is null) {
										mixin("int nplurals = "~langComponents.nplurals_expr~";");
										if (nplurals > 0) {
											mixin("int index = "~langComponents.plural_func_expr~";");
											return entry.msgstr_plural[index];
										}
										return entry.msgstr;
									}
									assert(false, "Plural translations are not supported when the po file does not contain an entry for Plural-Forms.");
								}
							} else {
								return entry.msgstr;
							}
						}
					}
				}
			}
		}
	}

	static if (is(typeof(CTX.enforceExistingKeys)) && CTX.enforceExistingKeys) {
		if (msgid_plural !is null) {
			if (msgctxt is null) {
				assert(false, "Missing translation keys for "~LANG~": "~msgid~"&"~msgid_plural);
			}
			assert(false, "Missing translation key for "~LANG~"; "~msgctxt~": "~msgid~"&"~msgid_plural);
		}

		if (msgctxt is null) {
			assert(false, "Missing translation key for "~LANG~": "~msgid);
		}
		assert(false, "Missing translation key for "~LANG~"; "~msgctxt~": "~msgid);
	} else {
		return msgid;
	}
}

package string determineLanguage(alias METHOD)(HTTPServerRequest req)
{
	import std.string : indexOf;
	import std.array;

	alias CTX = GetTranslationContext!METHOD;

	static if (!is(CTX == void)) {
		static if (is(typeof(CTX.determineLanguage(req)))) {
			static assert(is(typeof(CTX.determineLanguage(req)) == string),
				"determineLanguage in a translation context must return a language string.");
			return CTX.determineLanguage(req);
		} else {
			auto accept_lang = req.headers.get("Accept-Language", null);

			size_t csidx = 0;
			while (accept_lang.length) {
				auto cidx = accept_lang[csidx .. $].indexOf(',');
				if (cidx < 0) cidx = accept_lang.length;
				auto entry = accept_lang[csidx .. csidx + cidx];
				auto sidx = entry.indexOf(';');
				if (sidx < 0) sidx = entry.length;
				auto entrylang = entry[0 .. sidx];

				foreach (lang; CTX.languages) {
					if (entrylang == replace(lang, "_", "-")) return lang;
					if (entrylang == split(lang, "_")[0]) return lang; // FIXME: ensure that only one single-lang entry exists!
				}

				if (cidx >= accept_lang.length) break;
				accept_lang = accept_lang[cidx+1 .. $];
			}

			return null;
		}
	} else return null;
}

unittest { // make sure that the custom determineLanguage is called
	static struct CTX {
		static string determineLanguage(Object a) { return "test"; }
	}
	@translationContext!CTX
	static class Test {
		void test()
		{
		}
	}
	auto test = new Test;
	assert(determineLanguage!(test.test)(null) == "test");
}

package template GetTranslationContext(alias METHOD)
{
	import vibe.internal.meta.uda;

	alias PARENT = typeof(__traits(parent, METHOD).init);
	enum FUNCTRANS = findFirstUDA!(TranslationContextAttribute, METHOD);
	enum PARENTTRANS = findFirstUDA!(TranslationContextAttribute, PARENT);
	static if (FUNCTRANS.found) alias GetTranslationContext = FUNCTRANS.value.Context;
	else static if (PARENTTRANS.found) alias GetTranslationContext = PARENTTRANS.value.Context;
	else alias GetTranslationContext = void;
}

private struct DeclString {
	string msgctxt;
	string msgid;
	string msgid_plural;
	string msgstr;
	string[] msgstr_plural;
}

private struct LangComponents {
	DeclString[] messages;
	string nplurals_expr;
	string plural_func_expr;
}

// Example po header
/*
 * # Translation of kstars.po into Spanish.
 * # This file is distributed under the same license as the kdeedu package.
 * # Pablo de Vicente <pablo@foo.com>, 2005, 2006, 2007, 2008.
 * # Eloy Cuadra <eloy@bar.net>, 2007, 2008.
 * msgid ""
 * msgstr ""
 * "Project-Id-Version: kstars\n"
 * "Report-Msgid-Bugs-To: http://bugs.kde.org\n"
 * "POT-Creation-Date: 2008-09-01 09:37+0200\n"
 * "PO-Revision-Date: 2008-07-22 18:13+0200\n"
 * "Last-Translator: Eloy Cuadra <eloy@bar.net>\n"
 * "Language-Team: Spanish <kde-l10n-es@kde.org>\n"
 * "MIME-Version: 1.0\n"
 * "Content-Type: text/plain; charset=UTF-8\n"
 * "Content-Transfer-Encoding: 8bit\n"
 * "Plural-Forms: nplurals=2; plural=n != 1;\n"
 */

// PO format notes
/*
 * # - Translator comment
 * #: - source reference
 * #. - extracted comments
 * #, - flags such as "c-format" to indicate what king of substitutions may be present
 * #| msgid - previous string comment
 * #~ - obsolete message
 * msgctxt - disabmbiguating context, like variable scope (optional, defaults to null)
 * msgid - key to translate from (required)
 * msgid_plural - plural form of the msg id (optional)
 * msgstr - value to translate to (required)
 * msgstr[0] - indexed translation for handling the various plural forms
 * msgstr[1] - ditto
 * msgstr[2] - ditto and etc...
 */

LangComponents extractDeclStrings(string text) {
	DeclString[] declStrings;
	string nplurals_expr;
	string plural_func_expr;

	size_t i = 0;
	size_t j;
	while (true) {
		i = skipToDirective(i, text);
		if (i >= text.length) break;

		// msgctxt is an optional field
		string msgctxt = null;
		if (text.length - i >= 7 && text[i .. i+7] == "msgctxt") {
			i = skipWhitespace(i+7, text);
			j = skipString(i, text);
			msgctxt = dstringUnescape(wrapText(text[i+1 .. j-1]));
			i = skipToDirective(j, text);
		}

		// msgid is a required field
		string msgid = null;
		assert(text.length - i >= 5 && text[i .. i+5] == "msgid", "Expected 'msgid', got '"~text[i .. min(i+10, $)]~"'.");
		i = skipWhitespace(i+5, text);
		j = skipString(i, text);
		msgid = dstringUnescape(wrapText(text[i+1 .. j-1]));
		i = skipToDirective(j, text);

		// msgid_plural is an optional field
		string msgid_plural = null;
		if (text.length - i >= 12 && text[i .. i+12] == "msgid_plural") {
			i = skipWhitespace(i+12, text);
			j = skipString(i, text);
			msgid_plural = dstringUnescape(wrapText(text[i+1 .. j-1]));
			i = skipToDirective(j, text);
		}

		// msgstr is a required field
		assert(text.length - i >= 6 && text[i .. i+6] == "msgstr", "Expected 'msgstr', got '"~text[i .. min(i+10, $)]~"'.");
		i = skipWhitespace(i+6, text);
		j = skipString(i, text);
		auto txt = text[i+1 .. j-1];
		auto wrap = wrapText(txt);
		auto msgstr = dstringUnescape(wrap);
		i = skipToDirective(j, text);

		// msgstr[n] is a required field when msgid_plural is not null, and ignored otherwise
		string[] msgstr_plural;
		if (msgid_plural !is null) {
			while (text.length - i >= 6 && text[i .. i+6] == "msgstr") {
				i = skipIndex(i+6, text);
				i = skipWhitespace(i, text);
				j = skipString(i, text);

				string plural = dstringUnescape(wrapText(text[i+1 .. j-1]));
				i = skipLine(j, text);

				// Is it safe to assume that the entries are always sequential?
				msgstr_plural ~= plural;
			}
		}

		// Add the translation for the current language
		if (msgid == "") {
			nplurals_expr = parse_nplurals(msgstr);
			plural_func_expr = parse_plural_expression(msgstr);
		} else {
			declStrings ~= DeclString(msgctxt, msgid, msgid_plural, msgstr, msgstr_plural);
		}
	}

	return LangComponents(declStrings, nplurals_expr, plural_func_expr);
}

/// Verify that two simple messages can be read and parsed correctly
unittest {
	auto str = `
# first string
msgid "ordinal.1"
msgstr "first"

# second string
msgid "ordinal.2"
msgstr "second"`;

	auto components = extractDeclStrings(str);
	auto ds = components.messages;
	assert(2 == ds.length, "Not enough DeclStrings have been processed");
	assert(ds[0].msgid == "ordinal.1", "The first key is not right.");
	assert(ds[0].msgstr == "first", "The first value is not right.");
	assert(ds[1].msgid == "ordinal.2", "The second key is not right.");
	assert(ds[1].msgstr == "second", "The second value is not right.");
}

// Verify that the fields cannot be defined out of order
unittest {
	import core.exception : AssertError;
	import std.exception : assertThrown;

	auto str1 = `
# unexpected field ahead
msgstr "world"
msgid "hello"`;

	assertThrown!AssertError(extractDeclStrings(str1));
}

// Verify that string wrapping is handled correctly
unittest {
	auto str = `
# The following text is wrapped
msgid ""
"This is an example of text that "
"has been wrapped on two lines."
msgstr ""
"It should not matter where it takes place, "
"the strings should all be concatenated properly."`;

	auto components = extractDeclStrings(str);
	auto ds = components.messages;
	assert(1 == ds.length, "Expected one DeclString to have been processed.");
	assert(ds[0].msgid == "This is an example of text that has been wrapped on two lines.", "Failed to properly wrap the key");
	assert(ds[0].msgstr == "It should not matter where it takes place, the strings should all be concatenated properly.", "Failed to properly wrap the key");
}

// Verify that the message context is properly parsed
unittest {
	auto str1 = `
# "C" is for cookie
msgctxt "food"
msgid "C"
msgstr "C is for cookie, that's good enough for me."`;

	auto components1 = extractDeclStrings(str1);
	auto ds1 = components1.messages;
	assert(1 == ds1.length, "Expected one DeclString to have been processed.");
	assert(ds1[0].msgctxt == "food", "Expected a context of food");
	assert(ds1[0].msgid == "C", "Expected to find the letter C for the msgid.");
	assert(ds1[0].msgstr == "C is for cookie, that's good enough for me.", "Unexpected value encountered for the msgstr.");

	auto str2 = `
# No context validation
msgid "alpha"
msgstr "First greek letter."`;

	auto components2 = extractDeclStrings(str2);
	auto ds2 = components2.messages;
	assert(1 == ds2.length, "Expected one DeclString to have been processed.");
	assert(ds2[0].msgctxt is null, "Expected the context to be null when it is not defined.");
}

unittest {
	enum str = `
# "C" is for cookie
msgctxt "food"
msgid "C"
msgstr "C is for cookie, that's good enough for me."

# "C" is for language
msgctxt "lang"
msgid "C"
msgstr "Catalan"

# Just "C"
msgid "C"
msgstr "Third letter"
`;

	enum components = extractDeclStrings(str);

	struct TranslationContext {
		import std.typetuple;
		enum enforceExistingKeys = true;
		alias languages = TypeTuple!("en_US");

		// Note that this is normally handled by mixing in an external file.
		enum en_US_unittest = components;
	}

	auto newTr(string msgid, string msgcntxt = null) {
		return tr!(TranslationContext, "en_US")(msgid, msgcntxt);
	}

	assert(newTr("C", "food") == "C is for cookie, that's good enough for me.", "Unexpected translation based on context.");
	assert(newTr("C", "lang") == "Catalan", "Unexpected translation based on context.");
	assert(newTr("C") == "Third letter", "Unexpected translation based on context.");
}

unittest {
	enum str = `msgid ""
msgstr ""
"Project-Id-Version: kstars\\n"
"Plural-Forms: nplurals=2; plural=n != 1;\\n"

msgid "One file was deleted."
msgid_plural "Files were deleted."
msgstr "One file was deleted."
msgstr[0] "1 file was deleted"
msgstr[1] "%d files were deleted."

msgid "One file was created."
msgid_plural "Several files were created."
msgstr "One file was created."
msgstr[0] "1 file was created"
msgstr[1] "%d files were created."
`;

	import std.stdio;
	enum components = extractDeclStrings(str);

	struct TranslationContext {
		import std.typetuple;
		enum enforceExistingKeys = true;
		alias languages = TypeTuple!("en_US");

		// Note that this is normally handled by mixing in an external file.
		enum en_US_unittest2 = components;
	}
	
	auto newTr(string msgid, string msgid_plural, int count, string msgcntxt = null) {
		return tr_plural!(TranslationContext, "en_US")(msgid, msgid_plural, count, msgcntxt);
	}

	//writeln(newTr("", null, 1));
	writefln(newTr("One file was deleted.", "Files were deleted.", 1), 1);
	writefln(newTr("One file was deleted.", "Files were deleted.", 42), 42);
}

private size_t skipToDirective(size_t i, ref string text)
{
	while (i < text.length) {
		i = skipWhitespace(i, text);
		if (i < text.length && text[i] == '#') i = skipLine(i, text);
		else break;
	}
	return i;
}

private size_t skipWhitespace(size_t i, ref string text)
{
	while (i < text.length && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n' || text[i] == '\r'))
		i++;
	return i;
}

private size_t skipLine(size_t i, ref string text)
{
	while (i < text.length && text[i] != '\r' && text[i] != '\n') i++;
	if (i+1 < text.length && (text[i+1] == '\r' || text[i+1] == '\n') && text[i] != text[i+1]) i++;
	return i+1;
}

private size_t skipString(size_t i, ref string text)
{
	import std.conv : to;
	assert(text[i] == '"', "Expected to encounter the start of a string at position: "~to!string(i));
	i++;
	while (true) {
		assert(i < text.length, "Missing closing '\"' for string: "~text[i .. min($, 10)]);
		if (text[i] == '"') {
			if (i+1 < text.length) {
				auto j = skipWhitespace(i+1, text);
				if (j<text.length && text[j] == '"') return skipString(j, text);
			}
			return i+1;
		}
		if (text[i] == '\\') i += 2;
		else i++;
	}
}

private size_t skipIndex(size_t i, ref string text) {
	import std.conv : to;
	assert(text[i] == '[', "Expected to encounter a plural form of msgstr at position: "~to!string(i));
	for (; i<text.length; ++i) {
		if (text[i] == ']') {
			return i+1;
		}
	}
	assert(false, "Missing a ']' for a msgstr in a translation file.");
}

private string wrapText(string str)
{
	string ret;
	bool wrapped = false;

	for (size_t i=0; i<str.length; ++i) {
		if (str[i] == '\\') {
			ret ~= str[i..i+1];
			++i;
		} else if (str[i] == '"') {
			wrapped = true;
			size_t j = skipWhitespace(i+1, str);
			if (j < str.length && str[j] == '"') {
				i=j;
			}
		} else ret ~= str[i];
	}

	if (wrapped) return ret;
	return str;
}

private string parse_nplurals(string msgstr)
in { assert(msgstr, "An empty string cannot be parsed for Plural-Forms."); }
body {
	import std.string : indexOf, CaseSensitive;

	auto start = msgstr.indexOf("Plural-Forms:", CaseSensitive.no);
	if (start > -1) {
		auto beg = msgstr.indexOf("nplurals=", start+13, CaseSensitive.no);
		if (beg > -1) {
			auto end = msgstr.indexOf(';', beg+9, CaseSensitive.no);
			if (end > -1) {
				return msgstr[beg+9 .. end];
			}
			return msgstr[beg+9 .. $];
		}
	}

	return null;
}

unittest {
	auto res = parse_nplurals("Plural-Forms: nplurals=2; plural=n != 1;\n");
	assert(res == "2", "Failed to parse the correct number of plural forms for a language.");
}

private string parse_plural_expression(string msgstr)
in { assert(msgstr, "An empty string cannot be parsed for Plural-Forms."); }
body {
	import std.string : indexOf, CaseSensitive;

	auto start = msgstr.indexOf("Plural-Forms:", CaseSensitive.no);
	if (start > -1) {
		auto beg = msgstr.indexOf("plural=", start+13, CaseSensitive.no);
		if (beg > -1) {
			auto end = msgstr.indexOf(';', beg+7, CaseSensitive.no);
			if (end > -1) {
				return msgstr[beg+7 .. end];
			}
			return msgstr[beg+7 .. $];
		}
	}

	return null;
}

unittest {
	auto res = parse_plural_expression("Plural-Forms: nplurals=2; plural=n != 1;\n");
	assert(res == "n != 1", "Failed to parse the plural expression for a language.");
}
