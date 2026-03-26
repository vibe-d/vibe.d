/**
	SASLprep profile (RFC 4013) for password normalization.

	Implements the StringPrep (RFC 3454) tables needed for SASL
	password preparation used by SCRAM authentication.

	Copyright: © 2012-2016 Nicolas Gurrola
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Nicolas Gurrola
*/
module vibe.db.mongo.saslprep;

import std.conv;
import std.exception;
import std.format;
import std.uni;

@safe:

/**
 * SASLprep profile (RFC 4013) for password normalization.
 *
 * Applies the following steps:
 * 1. Map: non-ASCII spaces to U+0020, "commonly mapped to nothing" removed
 * 2. Normalize: NFKC
 * 3. Prohibit: check for prohibited characters
 * 4. Check bidi: ensure no mixed LTR/RTL without proper framing
 *
 * For ASCII-only input, returns the string unchanged (fast path).
 */
package string saslPrep(string input)
{
	if (isAscii(input))
	{
		foreach (char c; input)
		{
			enforce(c >= 0x20 && c != 0x7F, "SASLprep prohibited character U+" ~ format("%04X", cast(uint)c));
		}
		return input;
	}

	dchar[] mapped;
	mapped.reserve(input.length);

	foreach (dchar ch; input)
	{
		if (isNonAsciiSpace(ch)) {
			mapped ~= ' ';
		} else if (!isCommonlyMappedToNothing(ch)) {
			mapped ~= ch;
		}
	}

	auto normalized = normalize!NFKC(mapped);
	string result = normalized.to!string;

	foreach (dchar ch; result)
	{
		enforce(!isProhibited(ch), "SASLprep prohibited character U+" ~ format("%04X", cast(uint)ch));
	}

	enforceBidi(result);

	return result;
}

private bool isAscii(string s) @nogc pure nothrow
{
	foreach (char c; s)
	{
		if (c > 0x7E)
			return false;
	}
	return true;
}

/// RFC 3454 C.1.2 - Non-ASCII space characters mapped to U+0020
private bool isNonAsciiSpace(dchar ch) @nogc pure nothrow
{
	switch (ch)
	{
		case 0x00A0: // NO-BREAK SPACE
		case 0x1680: // OGHAM SPACE MARK
		case 0x2000: // EN QUAD
		case 0x2001: // EM QUAD
		case 0x2002: // EN SPACE
		case 0x2003: // EM SPACE
		case 0x2004: // THREE-PER-EM SPACE
		case 0x2005: // FOUR-PER-EM SPACE
		case 0x2006: // SIX-PER-EM SPACE
		case 0x2007: // FIGURE SPACE
		case 0x2008: // PUNCTUATION SPACE
		case 0x2009: // THIN SPACE
		case 0x200A: // HAIR SPACE
		case 0x202F: // NARROW NO-BREAK SPACE
		case 0x205F: // MEDIUM MATHEMATICAL SPACE
		case 0x3000: // IDEOGRAPHIC SPACE
			return true;
		default:
			return false;
	}
}

/// RFC 3454 B.1 - Commonly mapped to nothing
private bool isCommonlyMappedToNothing(dchar ch) @nogc pure nothrow
{
	switch (ch)
	{
		case 0x00AD: // SOFT HYPHEN
		case 0x034F: // COMBINING GRAPHEME JOINER
		case 0x1806: // MONGOLIAN TODO SOFT HYPHEN
		case 0x180B: // MONGOLIAN FREE VARIATION SELECTOR ONE
		case 0x180C: // MONGOLIAN FREE VARIATION SELECTOR TWO
		case 0x180D: // MONGOLIAN FREE VARIATION SELECTOR THREE
		case 0x200B: // ZERO WIDTH SPACE
		case 0x200C: // ZERO WIDTH NON-JOINER
		case 0x200D: // ZERO WIDTH JOINER
		case 0xFE00: // VARIATION SELECTOR-1
		case 0xFE01: // VARIATION SELECTOR-2
		case 0xFE02: // VARIATION SELECTOR-3
		case 0xFE03: // VARIATION SELECTOR-4
		case 0xFE04: // VARIATION SELECTOR-5
		case 0xFE05: // VARIATION SELECTOR-6
		case 0xFE06: // VARIATION SELECTOR-7
		case 0xFE07: // VARIATION SELECTOR-8
		case 0xFE08: // VARIATION SELECTOR-9
		case 0xFE09: // VARIATION SELECTOR-10
		case 0xFE0A: // VARIATION SELECTOR-11
		case 0xFE0B: // VARIATION SELECTOR-12
		case 0xFE0C: // VARIATION SELECTOR-13
		case 0xFE0D: // VARIATION SELECTOR-14
		case 0xFE0E: // VARIATION SELECTOR-15
		case 0xFE0F: // VARIATION SELECTOR-16
		case 0xFEFF: // ZERO WIDTH NO-BREAK SPACE
			return true;
		default:
			return false;
	}
}

/// RFC 3454 C.2.1, C.2.2, C.3-C.9 - Prohibited characters
private bool isProhibited(dchar ch) @nogc pure nothrow
{
	// C.2.1 ASCII control characters
	if (ch <= 0x001F || ch == 0x007F)
		return true;

	// C.2.2 Non-ASCII control characters
	if ((ch >= 0x0080 && ch <= 0x009F) ||
		ch == 0x06DD || ch == 0x070F ||
		ch == 0x180E ||
		(ch >= 0x200C && ch <= 0x200D) ||
		(ch >= 0x2028 && ch <= 0x2029) ||
		(ch >= 0x2060 && ch <= 0x2063) ||
		(ch >= 0x206A && ch <= 0x206F) ||
		ch == 0xFEFF ||
		(ch >= 0xFFF9 && ch <= 0xFFFC) ||
		(ch >= 0x1D173 && ch <= 0x1D17A))
		return true;

	// C.3 Private use
	if ((ch >= 0xE000 && ch <= 0xF8FF) ||
		(ch >= 0xF0000 && ch <= 0xFFFFD) ||
		(ch >= 0x100000 && ch <= 0x10FFFD))
		return true;

	// C.4 Non-character code points
	if ((ch >= 0xFDD0 && ch <= 0xFDEF) ||
		(ch & 0xFFFF) == 0xFFFE || (ch & 0xFFFF) == 0xFFFF)
		return true;

	// C.5 Surrogate codes (shouldn't appear in valid UTF, but check anyway)
	if (ch >= 0xD800 && ch <= 0xDFFF)
		return true;

	// C.7 Inappropriate for canonical representation
	if (ch >= 0x2FF0 && ch <= 0x2FFB)
		return true;

	// C.8 Change display properties or are deprecated
	if (ch == 0x0340 || ch == 0x0341 || ch == 0x200E || ch == 0x200F ||
		ch == 0x202A || ch == 0x202B || ch == 0x202C || ch == 0x202D ||
		ch == 0x202E || ch == 0x206A || ch == 0x206B || ch == 0x206C ||
		ch == 0x206D || ch == 0x206E || ch == 0x206F)
		return true;

	// C.9 Tagging characters
	if (ch == 0xE0001 || (ch >= 0xE0020 && ch <= 0xE007F))
		return true;

	return false;
}

/// RFC 3454 D.1/D.2 - Bidirectional check
private void enforceBidi(string s)
{
	bool hasRandALCat = false;
	bool hasLCat = false;
	dchar first = dchar.init;
	dchar last = dchar.init;

	foreach (dchar ch; s)
	{
		if (first == dchar.init)
			first = ch;
		last = ch;

		if (isRandALCat(ch))
			hasRandALCat = true;
		if (isLCat(ch))
			hasLCat = true;
	}

	if (hasRandALCat)
	{
		enforce(!hasLCat, "SASLprep bidirectional check failed: mixed R/AL and L characters");
		enforce(isRandALCat(first) && isRandALCat(last),
			"SASLprep bidirectional check failed: string with R/AL must start and end with R/AL");
	}
}

/// RFC 3454 D.1 - Characters with bidirectional property "R" or "AL"
private bool isRandALCat(dchar ch) @nogc pure nothrow
{
	if (ch >= 0x0590 && ch <= 0x05FF) return true; // Hebrew
	if (ch >= 0x0600 && ch <= 0x06FF) return true; // Arabic
	if (ch >= 0x0700 && ch <= 0x074F) return true; // Syriac
	if (ch >= 0x0780 && ch <= 0x07BF) return true; // Thaana
	if (ch >= 0xFB1D && ch <= 0xFB4F) return true; // Hebrew Presentation Forms
	if (ch >= 0xFB50 && ch <= 0xFDFF) return true; // Arabic Presentation Forms-A
	if (ch >= 0xFE70 && ch <= 0xFEFF) return true; // Arabic Presentation Forms-B
	return false;
}

/// RFC 3454 D.2 - Characters with bidirectional property "L"
private bool isLCat(dchar ch) @nogc pure nothrow
{
	if (ch >= 0x0041 && ch <= 0x005A) return true; // A-Z
	if (ch >= 0x0061 && ch <= 0x007A) return true; // a-z
	if (ch >= 0x00C0 && ch <= 0x00D6) return true; // Latin Extended
	if (ch >= 0x00D8 && ch <= 0x00F6) return true;
	if (ch >= 0x00F8 && ch <= 0x0220) return true;
	if (ch >= 0x0222 && ch <= 0x0233) return true;
	if (ch >= 0x0250 && ch <= 0x02AD) return true; // IPA Extensions
	if (ch >= 0x0388 && ch <= 0x03CE) return true; // Greek
	if (ch >= 0x03D0 && ch <= 0x03F6) return true;
	if (ch >= 0x0400 && ch <= 0x0482) return true; // Cyrillic
	if (ch >= 0x048A && ch <= 0x04CE) return true;
	if (ch >= 0x04D0 && ch <= 0x04F9) return true;
	return false;
}

/// saslPrep returns ASCII strings unchanged
unittest
{
	assert(saslPrep("pencil") == "pencil");
	assert(saslPrep("pencil") is "pencil");
}

/// saslPrep normalizes non-ASCII space U+00A0 to regular space
unittest
{
	assert(saslPrep("p\u00A0s") == "p s");
}

/// saslPrep removes soft hyphen (commonly mapped to nothing)
unittest
{
	assert(saslPrep("p\u00ADs") == "ps");
}

/// saslPrep applies NFKC normalization
unittest
{
	// U+2126 OHM SIGN normalizes to U+03A9 GREEK CAPITAL LETTER OMEGA under NFKC
	assert(saslPrep("\u2126") == "\u03A9");
}

/// saslPrep rejects ASCII control characters
unittest
{
	import std.exception : assertThrown;
	assertThrown!Exception(saslPrep("bad\x00char"));
	assertThrown!Exception(saslPrep("bad\x07char"));
}
