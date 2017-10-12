/**
	Parameter validation types transparently supported for web interface methods.

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.web.validation;

import vibe.utils.validation;

import std.array : appender;
import std.typecons : Nullable;


/**
	Validated e-mail parameter type.

	See_also: $(D vibe.utils.validation.validateEmail)
*/
struct ValidEmail {
	private string m_value;

	private this(string value) { m_value = value; }
	@disable this();

	string toString() const pure nothrow @safe { return m_value; }
	alias toString this;

	static Nullable!ValidEmail fromStringValidate(string str, string* error)
	{
		// work around disabled default construction
		Nullable!ValidEmail ret = Nullable!ValidEmail(ValidEmail(null));
		ret.nullify();

		auto err = appender!string(); // TODO: avoid allocations when possible
		if (validateEmail(err, str)) ret = ValidEmail(str);
		else *error = err.data;
		return ret;
	}
}

///
unittest {
	class WebService {
		void setEmail(ValidEmail email)
		{
			// email is enforced to be valid here
		}

		void updateProfileInfo(Nullable!ValidEmail email, Nullable!string full_name)
		{
			// email is optional, but always valid
			// full_name is optional and not validated
		}
	}
}


/**
	Validated user name parameter type.

	See_also: $(D vibe.utils.validation.validateUsername)
*/
struct ValidUsername {
	private string m_value;

	private this(string value) { m_value = value; }
	@disable this();

	string toString() const pure nothrow @safe { return m_value; }
	alias toString this;

	static Nullable!ValidUsername fromStringValidate(string str, string* error)
	{
		// work around disabled default construction
		Nullable!ValidUsername ret = Nullable!ValidUsername(ValidUsername(null));
		ret.nullify();

		auto err = appender!string(); // TODO: avoid allocations when possible
		if (validateUserName(err, str)) ret = ValidUsername(str);
		else *error = err.data;
		return ret;
	}
}

///
unittest {
	class WebService {
		void setUsername(ValidUsername username)
		{
			// username is enforced to be valid here
		}

		void updateProfileInfo(Nullable!ValidUsername username, Nullable!string full_name)
		{
			// username is optional, but always valid
			// full_name is optional and not validated
		}
	}
}


/**
	Validated password parameter.

	See_also: $(D vibe.utils.validation.validatePassword)
*/
struct ValidPassword {
	private string m_value;

	private this(string value) { m_value = value; }
	@disable this();

	string toString() const pure nothrow @safe { return m_value; }
	alias toString this;

	static Nullable!ValidPassword fromStringValidate(string str, string* error)
	{
		// work around disabled default construction
		Nullable!ValidPassword ret = Nullable!ValidPassword(ValidPassword(null));
		ret.nullify();

		auto err = appender!string(); // TODO: avoid allocations when possible
		if (validatePassword(err, str, str)) ret = ValidPassword(str);
		else *error = err.data;
		return ret;
	}
}


/**
	Ensures that the parameter value matches that of another parameter.
*/
struct Confirm(string CONFIRMED_PARAM)
{
	enum confirmedParameter = CONFIRMED_PARAM;

	private string m_value;

	string toString() const pure nothrow @safe { return m_value; }
	alias toString this;

	static Confirm fromString(string str) { return Confirm(str); }
}

///
unittest {
	class WebService {
		void setPassword(ValidPassword password, Confirm!"password" password_confirmation)
		{
			// password is valid and guaranteed to equal password_confirmation
		}

		void setProfileInfo(string full_name, Nullable!ValidPassword password, Nullable!(Confirm!"password") password_confirmation)
		{
			// Password is valid and guaranteed to equal password_confirmation
			// It is allowed for both, password and password_confirmation
			// to be absent at the same time, but not for only one of them.
		}
	}
}
