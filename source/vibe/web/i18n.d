/**

*/
module vibe.web.i18n;

import vibe.templ.parsertools;

import std.algorithm : canFind, min, startsWith;

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
		pragma(msg, "enum "~LANG~"_"~keyToIdentifier(decl_strings[i].key)~" = "~decl_strings[i].value~";");
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
			pragma(msg, __traits(getMember, CTX, mname));
			foreach (entry; __traits(getMember, CTX, mname))
				if (entry.key == key)
					return entry.value;
		}
	return key;
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
		if (text[i] == '#') i = skipLine(i, text);
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
	assert(text[i] == '"');
	i++;
	while (true) {
		assert(i < text.length);
		if (text[i] == '"') return i+1;
		if (text[i] == '\\') i += 2;
		else i++;
	}
}