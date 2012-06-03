/**
	List of all standard HTTP status codes.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger
*/
module vibe.http.status;

/**
	Definitions of all standard HTTP status codes.
*/
enum HttpStatus {
	Continue                     = 100,
	SwitchingProtocols           = 101,
	OK                           = 200,
	Created                      = 201,
	Accepted                     = 202,
	NonAuthoritativeInformation  = 203,
	NoContent                    = 204,
	ResetContent                 = 205,
	PartialContent               = 206,
	MultipleChoices              = 300,
	MovedPermanently             = 301,
	Found                        = 302,
	SeeOther                     = 303,
	NotModified                  = 304,
	UseProxy                     = 305,
	TemporaryRedirect            = 307,
	BadRequest                   = 400,
	Unauthorized                 = 401,
	PaymentRequired              = 402,
	Forbidden                    = 403,
	NotFound                     = 404,
	MethodNotAllowed             = 405,
	NotAcceptable                = 406,
	ProxyAuthenticationRequired  = 407,
	RequestTimeout               = 408,
	Conflict                     = 409,
	Gone                         = 410,
	LengthRequired               = 411,
	PreconditionFailed           = 412,
	RequestEntityTooLarge        = 413,
	RequestURITooLarge           = 414,
	UnsupportedMediaType         = 415,
	Requestedrangenotsatisfiable = 416,
	ExpectationFailed            = 417,
	InternalServerError          = 500,
	NotImplemented               = 501,
	BadGateway                   = 502,
	ServiceUnavailable           = 503,
	GatewayTimeout               = 504,
	HTTPVersionNotSupported      = 505,
}

/**
	Returns a standard text description of the specified HTTP status code.
*/
string httpStatusText(int code)
{
	switch(code)
	{
		default: break;
		case HttpStatus.Continue                     : return "Continue";
		case HttpStatus.SwitchingProtocols           : return "Switching Protocols";
		case HttpStatus.OK                           : return "OK";
		case HttpStatus.Created                      : return "Created";
		case HttpStatus.Accepted                     : return "Accepted";
		case HttpStatus.NonAuthoritativeInformation  : return "Non-Authoritative Information";
		case HttpStatus.NoContent                    : return "No Content";
		case HttpStatus.ResetContent                 : return "Reset Content";
		case HttpStatus.PartialContent               : return "Partial Content";
		case HttpStatus.MultipleChoices              : return "Multiple Choices";
		case HttpStatus.MovedPermanently             : return "Moved Permanently";
		case HttpStatus.Found                        : return "Found";
		case HttpStatus.SeeOther                     : return "See Other";
		case HttpStatus.NotModified                  : return "Not Modified";
		case HttpStatus.UseProxy                     : return "Use Proxy";
		case HttpStatus.TemporaryRedirect            : return "Temporary Redirect";
		case HttpStatus.BadRequest                   : return "Bad Request";
		case HttpStatus.Unauthorized                 : return "Unauthorized";
		case HttpStatus.PaymentRequired              : return "Payment Required";
		case HttpStatus.Forbidden                    : return "Forbidden";
		case HttpStatus.NotFound                     : return "Not Found";
		case HttpStatus.MethodNotAllowed             : return "Method Not Allowed";
		case HttpStatus.NotAcceptable                : return "Not Acceptable";
		case HttpStatus.ProxyAuthenticationRequired  : return "Proxy Authentication Required";
		case HttpStatus.RequestTimeout               : return "Request Time-out";
		case HttpStatus.Conflict                     : return "Conflict";
		case HttpStatus.Gone                         : return "Gone";
		case HttpStatus.LengthRequired               : return "Length Required";
		case HttpStatus.PreconditionFailed           : return "Precondition Failed";
		case HttpStatus.RequestEntityTooLarge        : return "Request Entity Too Large";
		case HttpStatus.RequestURITooLarge           : return "Request-URI Too Large";
		case HttpStatus.UnsupportedMediaType         : return "Unsupported Media Type";
		case HttpStatus.Requestedrangenotsatisfiable : return "Requested range not satisfiable";
		case HttpStatus.ExpectationFailed            : return "Expectation Failed";
		case HttpStatus.InternalServerError          : return "Internal Server Error";
		case HttpStatus.NotImplemented               : return "Not Implemented";
		case HttpStatus.BadGateway                   : return "Bad Gateway";
		case HttpStatus.ServiceUnavailable           : return "Service Unavailable";
		case HttpStatus.GatewayTimeout               : return "Gateway Time-out";
		case HttpStatus.HTTPVersionNotSupported      : return "HTTP Version not supported";
	}
	if( code >= 600 ) return "Unknown";
	if( code >= 500 ) return "Unknown server error";
	if( code >= 400 ) return "Unknown error";
	if( code >= 300 ) return "Unknown redirection";
	if( code >= 200 ) return "Unknown success";
	if( code >= 100 ) return "Unknown information";
	return "Unknown";
}

/**
	Determines if the given status code justifies closing the connection (e.g. evil big request bodies) 
*/
bool justifiesConnectionClose(int status) {
	switch(status) {
		default: return false;
		case HttpStatus.RequestEntityTooLarge:
		case HttpStatus.RequestURITooLarge:
		case HttpStatus.RequestTimeout:
			return true; 
	}
}
