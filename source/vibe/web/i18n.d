/**
	Internationalization/translation support for the web interface module.

	Copyright: © 2014 RejectedSoftware e.K.
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
		static string determineLanguage(scope HTTPServerRequest req)
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
			enum decl_strings = extractDeclStrings(import(NAME~"."~languages[i]~".po"));
			mixin("enum "~languages[i]~"_"~NAME~" = decl_strings;");
			//mixin decls_mixin!(languages[i], 0);
			mixin file_mixin!(i+1);
		}
	}

	mixin file_mixin!0;
}

string tr(CTX, string LANG)(string key, string context = null)
{
	static assert([CTX.languages].canFind(LANG), "Unknown language: "~LANG);

	foreach (i, mname; __traits(allMembers, CTX))
		static if (mname.startsWith(LANG~"_")) {
			foreach (entry; __traits(getMember, CTX, mname))
				if ((context is null) == (entry.context is null))
					if (context is null || entry.context == context)
						if (entry.key == key)
							return entry.value;
		}

	static if (is(typeof(CTX.enforceExistingKeys)) && CTX.enforceExistingKeys)
		assert(false, "Missing translation key for "~LANG~": "~key);
	else return key;
}

package string determineLanguage(alias METHOD)(scope HTTPServerRequest req)
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
	string context;
	string key;
	string value;
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

// TODO: Handle plural translations
DeclString[] extractDeclStrings(string text)
{
	DeclString[] ret;

	size_t i = 0;
	while (true) {
		i = skipToDirective(i, text);
		if (i >= text.length) break;

		string context = null;
		if (text.length - i >= 7 && text[i .. i+7] == "msgctxt") {
			i = skipWhitespace(i+7, text);

			auto icntxt = skipString(i, text);
			context = dstringUnescape(wrapText(text[i+1 .. icntxt-1]));
			i = skipToDirective(icntxt, text);
		}

		assert(text.length - i >= 5 && text[i .. i+5] == "msgid", "Expected 'msgid', got '"~text[i .. min(i+10, $)]~"'.");
		i += 5;

		i = skipWhitespace(i, text);

		auto iknext = skipString(i, text);
		auto key = dstringUnescape(wrapText(text[i+1 .. iknext-1]));
		i = iknext;

		i = skipToDirective(i, text);

		assert(text.length - i >= 6 && text[i .. i+6] == "msgstr", "Expected 'msgstr', got '"~text[i .. min(i+10, $)]~"'.");
		i += 6;

		i = skipWhitespace(i, text);

		auto ivnext = skipString(i, text);
		auto value = dstringUnescape(wrapText(text[i+1 .. ivnext-1]));
		i = ivnext;

		ret ~= DeclString(context, key, value);
	}

	return ret;
}

// Verify that two simple messages can be read and parsed correctly
unittest {
	auto str = `
# first string
msgid "ordinal.1"
msgstr "first"

# second string
msgid "ordinal.2"
msgstr "second"`;

	auto ds = extractDeclStrings(str);
	assert(2 == ds.length, "Not enough DeclStrings have been processed");
	assert(ds[0].key == "ordinal.1", "The first key is not right.");
	assert(ds[0].value == "first", "The first value is not right.");
	assert(ds[1].key == "ordinal.2", "The second key is not right.");
	assert(ds[1].value == "second", "The second value is not right.");
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

	auto ds = extractDeclStrings(str);
	assert(1 == ds.length, "Expected one DeclString to have been processed.");
	assert(ds[0].key == "This is an example of text that has been wrapped on two lines.", "Failed to properly wrap the key");
	assert(ds[0].value == "It should not matter where it takes place, the strings should all be concatenated properly.", "Failed to properly wrap the key");
}

// Verify that string wrapping and unescaping is handled correctly on example of PO headers
unittest {
	auto str = `
# English translations for ThermoWebUI package.
# This file is put in the public domain.
# Automatically generated, 2015.
#
msgid ""
msgstr ""
"Project-Id-Version: PROJECT VERSION\n"
"Report-Msgid-Bugs-To: developer@example.com\n"
"POT-Creation-Date: 2015-04-13 17:55+0600\n"
"PO-Revision-Date: 2015-04-13 14:13+0600\n"
"Last-Translator: Automatically generated\n"
"Language-Team: none\n"
"Language: en\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\n"
`;
	auto expected = `Project-Id-Version: PROJECT VERSION
Report-Msgid-Bugs-To: developer@example.com
POT-Creation-Date: 2015-04-13 17:55+0600
PO-Revision-Date: 2015-04-13 14:13+0600
Last-Translator: Automatically generated
Language-Team: none
Language: en
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8
Content-Transfer-Encoding: 8bit
Plural-Forms: nplurals=2; plural=(n != 1);
`;

	auto ds = extractDeclStrings(str);
	assert(1 == ds.length, "Expected one DeclString to have been processed.");
	assert(ds[0].key == "", "Failed to properly wrap or unescape the key");
	assert(ds[0].value == expected, "Failed to properly wrap or unescape the value");
}

// Verify that the message context is properly parsed
unittest {
	auto str1 = `
# "C" is for cookie
msgctxt "food"
msgid "C"
msgstr "C is for cookie, that's good enough for me."`;

	auto ds1 = extractDeclStrings(str1);
	assert(1 == ds1.length, "Expected one DeclString to have been processed.");
	assert(ds1[0].context == "food", "Expected a context of food");
	assert(ds1[0].key == "C", "Expected to find the letter C for the msgid.");
	assert(ds1[0].value == "C is for cookie, that's good enough for me.", "Unexpected value encountered for the msgstr.");

	auto str2 = `
# No context validation
msgid "alpha"
msgstr "First greek letter."`;

	auto ds2 = extractDeclStrings(str2);
	assert(1 == ds2.length, "Expected one DeclString to have been processed.");
	assert(ds2[0].context is null, "Expected the context to be null when it is not defined.");
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

	enum ds = extractDeclStrings(str);

	struct TranslationContext {
		import std.typetuple;
		enum enforceExistingKeys = true;
		alias languages = TypeTuple!("en_US");
		enum en_US_unittest = ds;
	}

	auto newTr(string msgid, string msgcntxt = null) {
		return tr!(TranslationContext, "en_US")(msgid, msgcntxt);
	}

	assert(newTr("C", "food") == "C is for cookie, that's good enough for me.", "Unexpected translation based on context.");
	assert(newTr("C", "lang") == "Catalan", "Unexpected translation based on context.");
	assert(newTr("C") == "Third letter", "Unexpected translation based on context.");
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
	size_t istart = i;
	assert(text[i] == '"');
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

private string wrapText(string str)
{
	string ret;
	bool wrapped = false;

	for (size_t i=0; i<str.length; ++i) {
		if (str[i] == '\\') {
			assert(i+1 < str.length, "The string ends with the escape char: " ~ str);
			ret ~= str[i..i+2];
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
