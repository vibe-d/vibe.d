/**
	String input validation routines

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.utils.validation;

import vibe.utils.string;

import std.algorithm : canFind;
import std.array : appender;
import std.compiler;
import std.conv;
import std.exception;
import std.format;
import std.net.isemail;
import std.range : isOutputRange;
import std.string;
import std.utf;

@safe:

// TODO: add nothrow to the exception-less versions (but formattedWrite isn't nothrow)


/** Provides a simple email address validation.

	Note that the validation could be stricter in some cases than required. The user name
	is forced to be ASCII, which is not strictly required as of RFC 6531. It also does not
	allow quotiations for the user name part (RFC 5321).

	Invalid email adresses will cause an exception with the error description to be thrown.
*/
string validateEmail()(string str, size_t max_length = 64)
{
	auto err = appender!string();
	enforce(validateEmail(err, str, max_length), err.data);
	return str;
}
/// ditto
bool validateEmail(R)(ref R error_sink, string str, size_t max_length = 64)
	if (isOutputRange!(R, char))
{
	if (str.length > max_length) {
		error_sink.formattedWrite("The email address may not be longer than %s characters.", max_length);
		return false;
	}
	auto at_idx = str.indexOf('@');
	if (at_idx < 0) {
		error_sink.put("Email is missing the '@'.");
		return false;
	}

	if (!validateIdent(error_sink, str[0 .. at_idx], "!#$%&'*+-/=?^_`{|}~.(),:;<>@[\\]", "An email user name", false))
		return false;

	auto domain = str[at_idx+1 .. $];
	auto dot_idx = domain.indexOf('.');
	if (dot_idx <= 0 || dot_idx >= str.length-2) {
		error_sink.put("The email domain is not valid.");
		return false;
	}
	if (domain.anyOf(" @,[](){}<>!\"'%&/\\?*#;:|")) {
		error_sink.put("The email domain contains invalid characters.");
		return false;
	}

	if (() @trusted { return !isEmail(str); }()) {
		error_sink.put("The email address is invalid.");
		return false;
	}

	return true;
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
string validateUserName()(string str, int min_length = 3, int max_length = 32, string additional_chars = "-_", bool no_number_start = true)
{
	auto err = appender!string();
	enforce(validateUserName(err, str, min_length, max_length, additional_chars, no_number_start), err.data);
	return str;
}
/// ditto
bool validateUserName(R)(ref R error_sink, string str, int min_length = 3, int max_length = 32, string additional_chars = "-_", bool no_number_start = true)
	if (isOutputRange!(R, char))
{
	// FIXME: count graphemes instead of code units!
	if (str.length < min_length) {
		error_sink.formattedWrite("The user name must be at least %s characters long.", min_length);
		return false;
	}

	if (str.length > max_length) {
		error_sink.formattedWrite("The user name must not be longer than %s characters.", max_length);
		return false;
	}

	if (!validateIdent(error_sink, str, additional_chars, "A user name", no_number_start))
		return false;

	return true;
}

/** Validates an identifier string as used in most programming languages.

	The identifier must begin with a letter or with any of the additional_chars and may
	contain only ASCII letters and digits and any of the additional_chars.

	Invalid identifiers will cause an exception with the error description to be thrown.
*/
string validateIdent()(string str, string additional_chars = "_", string entity_name = "An identifier", bool no_number_start = true)
{
	auto err = appender!string();
	enforce(validateIdent(err, str, additional_chars, entity_name, no_number_start), err.data);
	return str;
}
/// ditto
bool validateIdent(R)(ref R error_sink, string str, string additional_chars = "_", string entity_name = "An identifier", bool no_number_start = true)
	if (isOutputRange!(R, char))
{
	// NOTE: this is meant for ASCII identifiers only!
	foreach (i, char ch; str) {
		if (ch >= 'a' && ch <= 'z') continue;
		if (ch >= 'A' && ch <= 'Z') continue;
		if (ch >= '0' && ch <= '9') {
			if (!no_number_start || i > 0) continue;
			else {
				error_sink.formattedWrite("%s must not begin with a number.", entity_name);
				return false;
			}
		}
		if (additional_chars.canFind(ch)) continue;
		error_sink.formattedWrite("%s may only contain numbers, letters and one of (%s)", entity_name, additional_chars);
		return false;
	}

	return true;
}

/** Checks a password for minimum complexity requirements
*/
string validatePassword()(string str, string str_confirm, size_t min_length = 8, size_t max_length = 64)
{
	auto err = appender!string();
	enforce(validatePassword(err, str, str_confirm, min_length, max_length), err.data);
	return str;
}
/// ditto
bool validatePassword(R)(ref R error_sink, string str, string str_confirm, size_t min_length = 8, size_t max_length = 64)
	if (isOutputRange!(R, char))
{
	// FIXME: count graphemes instead of code units!
	if (str.length < min_length) {
		error_sink.formattedWrite("The password must be at least %s characters long.", min_length);
		return false;
	}

	if (str.length > max_length) {
		error_sink.formattedWrite("The password must not be longer than %s characters.", max_length);
		return false;
	}

	if (str != str_confirm) {
		error_sink.put("The password and the confirmation differ.");
		return false;
	}

	return true;
}

/** Checks if a string falls within the specified length range.
*/
string validateString(string str, size_t min_length = 0, size_t max_length = 0, string entity_name = "String")
{
	auto err = appender!string();
	enforce(validateString(err, str, min_length, max_length, entity_name), err.data);
	return str;
}
/// ditto
bool validateString(R)(ref R error_sink, string str, size_t min_length = 0, size_t max_length = 0, string entity_name = "String")
	if (isOutputRange!(R, char))
{
	try std.utf.validate(str);
	catch (Exception e) {
		error_sink.put(e.msg);
		return false;
	}

	// FIXME: count graphemes instead of code units!
	if (str.length < min_length) {
		error_sink.formattedWrite("%s must be at least %s characters long.", entity_name, min_length);
		return false;
	}

	if (max_length > 0 && str.length > max_length) {
		error_sink.formattedWrite("%s must not be longer than %s characters.", entity_name, max_length);
		return false;
	}

	return true;
}
