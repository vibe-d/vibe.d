/**
	String validation routines

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.validation;

import vibe.utils.string;

import std.algorithm : canFind;
import std.exception;
import std.compiler;
import std.conv;
import std.string;
import std.utf;

static if (__VERSION__ >= 2060) // does not link pre 2.060
	import std.net.isemail;


/** Provides a simple email address validation.

	Note that the validation could be stricter in some cases than required. The user name
	is forced to be ASCII, which is not strictly required as of RFC 6531. It also does not
	allow quotiations for the user name part (RFC 5321).
	
	Invalid email adresses will cause an exception with the error description to be thrown.
*/
string validateEmail(string str, size_t max_length = 64)
{
	enforce(str.length <= max_length, "The email address may not be longer than "~to!string(max_length)~"characters.");
	auto at_idx = str.indexOf('@');
	enforce(at_idx > 0, "Email is missing the '@'.");
	validateIdent(str[0 .. at_idx], "!#$%&'*+-/=?^_`{|}~.(),:;<>@[\\]", "An email user name", false);
	
	auto domain = str[at_idx+1 .. $];
	auto dot_idx = domain.indexOf('.');
	enforce(dot_idx > 0 && dot_idx < str.length-2, "The email domain is not valid.");
	enforce(!domain.anyOf(" @,[](){}<>!\"'%&/\\?*#;:|"), "The email domain contains invalid characters.");
	
	static if (__VERSION__ >= 2060)
		enforce(isEmail(str) == EmailStatusCode.valid, "The email address is invalid.");
	
	return str;
}

unittest {
	assertNotThrown(validateEmail("0a0@b.com"));
	assertNotThrown(validateEmail("123@123.com"));
	assertThrown(validateEmail("§@b.com"));
}

/** Validates a user name string.

	User names may only contain ASCII letters and digits or any of the specified additional
	letters.
	
	Invalid user names will cause an exception with the error description to be thrown.
*/
string validateUserName(string str, int min_length = 3, int max_length = 32, string additional_chars = "-_", bool no_number_start = true)
{
	enforce(str.length >= min_length,
		"The user name must be at least "~to!string(min_length)~" characters long.");
	enforce(str.length <= max_length,
		"The user name must not be longer than "~to!string(max_length)~" characters.");
	validateIdent(str, additional_chars, "A user name", no_number_start);
	
	return str;
}

/** Validates an identifier string as used in most programming languages.

	The identifier must begin with a letter or with any of the additional_chars and may
	contain only ASCII letters and digits and any of the additional_chars.
	
	Invalid identifiers will cause an exception with the error description to be thrown.
*/
string validateIdent(string str, string additional_chars = "_", string entity_name = "An identifier", bool no_number_start = true)
{
	// NOTE: this is meant for ASCII identifiers only!
	foreach (i, char ch; str) {
		if (ch >= 'a' && ch <= 'z') continue;
		if (ch >= 'A' && ch <= 'Z') continue;
		if (ch >= '0' && ch <= '9') {
			if (!no_number_start || i > 0) continue;
			else throw new Exception(entity_name~" must not begin with a number."); 
		}	
		if (additional_chars.canFind(ch)) continue; 
		throw new Exception(entity_name~" may only contain numbers, letters and one of ("~additional_chars~")");
	}
	
	return str;
}

/** Checks a password for minimum complexity requirements
*/
string validatePassword(string str, string str_confirm, size_t min_length = 8, size_t max_length = 64)
{
	enforce(str.length >= min_length,
		"The password must be at least "~to!string(min_length)~" characters long.");
	enforce(str.length <= max_length,
		"The password must not be longer than "~to!string(max_length)~" characters.");
	enforce(str == str_confirm, "The password and the confirmation differ.");
	return str;
}

/** Checks if a string falls within the specified length range.
*/
string validateString(string str, size_t min_length = 0, size_t max_length = 0, string entity_name = "String")
{
	std.utf.validate(str);
	enforce(str.length >= min_length,
		entity_name~" must be at least "~to!string(min_length)~" characters long.");
	enforce(!max_length || str.length <= max_length,
		entity_name~" must not be longer than "~to!string(max_length)~" characters.");
	return str;
}
