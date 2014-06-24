module vibe.web.validation;


/**
	Attribute for validating e-mail string parameters.
*/
ValidationAttribute validateEmail(string parameter)
{
	return ValidationAttribute(ValidationKind.email, parameter);
}

///
unittest {
	class WebService {
		@validateEmail("email")
		void postSetEmail(string email)
		{
			// The e-mail is validated here
			// ...
		}
	}
}


/**
	Attribute for validating password parameters.

	The password is currently checked for a minimum length of 8 characters and
	a maximum length of 64 characters.

	Params:
		parameter = Name of the parameter that needs to be validated
		confirmation_parameter = Name of a confirmation parameter that
			must equal the main parameter

	See_also: $(D vibe.utils.validation.validatePassword)
*/
ValidationAttribute validatePassword(string parameter, string confirmation_parameter)
{
	return ValidationAttribute(ValidationKind.password, parameter, confirmation_parameter);
}

///
unittest {
	class WebService {
		@validatePassword("password", "password_confirmation")
		void postSetPassword(string password, string password_confirmation)
		{
			// The password is validated here and confirmed
			// to match password_confirmation
			// ...
		}
	}
}


/**
	Determine if the given type is a validation attribute.
*/
template isValidationAttribute(T...) {
	enum isValidationAttribute = T.length == 1 && is(typeof(T[0]) == ValidationAttribute);
}


struct ValidationAttribute {
	ValidationKind kind;
	string parameter;
	string confirmationParameter; // for ValidationKind.password
	long min, max;
}

enum ValidationKind {
	email,
	userName,
	identifier,
	password,
	length
}
