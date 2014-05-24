/**

*/
module vibe.web.i18n;

import vibe.http.server : HTTPServerRequest;
import vibe.templ.parsertools;

import std.algorithm : canFind, min, startsWith;


/**
	Annotates an interface method or class with translation information.

	The translation context contains information about supported languages
	and the translated strings.
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
	mixin template decls_mixin(string LANG, size_t i) {
		mixin("enum "~LANG~"_"~keyToIdentifier(decl_strings[i].key)~" = "~decl_strings[i].value~";");
	}

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

string tr(CTX, string LANG)(string key)
{
	static assert([CTX.languages].canFind(LANG), "Unknown language: "~LANG);

	foreach (i, mname; __traits(allMembers, CTX))
		static if (mname.startsWith(LANG~"_")) {
			foreach (entry; __traits(getMember, CTX, mname))
				if (entry.key == key)
					return entry.value;
		}

	static if (is(typeof(CTX.enforceExistingKeys)) && CTX.enforceExistingKeys)
		assert(false, "Missing translation key for "~LANG~": "~key);
	else return key;
}

package string determineLanguage(alias METHOD)(HTTPServerRequest req)
{
	import std.string : indexOf;
	import std.array;

	alias CTX = GetTranslationContext!METHOD;

	static if (!is(CTX == void)) {
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
				if (entrylang == split(lang, "-")[0]) return lang; // FIXME: ensure that only one single-lang entry exists!
			}
			
			if (cidx >= accept_lang.length) break;
			accept_lang = accept_lang[cidx+1 .. $];
		}
	}

	return null;
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
	string key;
	string value;
}

string keyToIdentifier(string key)
{
	enum hexdigits = "0123456789ABCDEF";
	string ret;
	size_t istart = 0;
	foreach (i; 0 .. key.length) {
		auto ch = key[i];
		if (!(ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z')) {
			if (i > istart) ret ~= key[istart .. i];
			istart = i+1;
			ret ~= "_"~hexdigits[ch%0xF]~hexdigits[ch/0x100];
		}
	}
	if (istart < key.length) ret ~= key[istart .. $];
	return ret;
}

DeclString[] extractDeclStrings(string text)
{
	DeclString[] ret;

	size_t i = 0;
	while (true) {
		i = skipToDirective(i, text);
		if (i >= text.length) break;

		assert(text.length - i >= 5 && text[i .. i+5] == "msgid", "Expected 'msgid', got '"~text[i .. min(i+10, $)]~"'.");
		i += 5;

		i = skipWhitespace(i, text);

		auto iknext = skipString(i, text);
		auto key = dstringUnescape(text[i+1 .. iknext-1]);
		i = iknext;

		i = skipToDirective(i, text);

		assert(text.length - i >= 6 && text[i .. i+6] == "msgstr", "Expected 'msgstr', got '"~text[i .. min(i+10, $)]~"'.");
		i += 6;

		i = skipWhitespace(i, text);

		auto ivnext = skipString(i, text);
		auto value = dstringUnescape(text[i+1 .. ivnext-1]);
		i = ivnext;

		ret ~= DeclString(key, value);
	}

	return ret;
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
		if (text[i] == '"') return i+1;
		if (text[i] == '\\') i += 2;
		else i++;
	}
}