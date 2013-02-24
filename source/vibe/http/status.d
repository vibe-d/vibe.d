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
	continue_                    = 100,
	switchingProtocols           = 101,
	ok                           = 200,
	created                      = 201,
	accepted                     = 202,
	nonAuthoritativeInformation  = 203,
	noContent                    = 204,
	resetContent                 = 205,
	partialContent               = 206,
	multipleChoices              = 300,
	movedPermanently             = 301,
	found                        = 302,
	seeOther                     = 303,
	notModified                  = 304,
	useProxy                     = 305,
	temporaryRedirect            = 307,
	badRequest                   = 400,
	unauthorized                 = 401,
	paymentRequired              = 402,
	forbidden                    = 403,
	notFound                     = 404,
	methodNotAllowed             = 405,
	notAcceptable                = 406,
	proxyAuthenticationRequired  = 407,
	requestTimeout               = 408,
	conflict                     = 409,
	gone                         = 410,
	lengthRequired               = 411,
	preconditionFailed           = 412,
	requestEntityTooLarge        = 413,
	requestURITooLarge           = 414,
	unsupportedMediaType         = 415,
	requestedrangenotsatisfiable = 416,
	expectationFailed            = 417,
	internalServerError          = 500,
	notImplemented               = 501,
	badGateway                   = 502,
	serviceUnavailable           = 503,
	gatewayTimeout               = 504,
	httpVersionNotSupported      = 505,

	/// deprecated
	Continue = continue_,
	/// deprecated
	SwitchingProtocols = switchingProtocols,
	/// deprecated
	OK = ok,
	/// deprecated
	Created = created,
	/// deprecated
	Accepted = accepted,
	/// deprecated
	NonAuthoritativeInformation = nonAuthoritativeInformation,
	/// deprecated
	NoContent = noContent,
	/// deprecated
	ResetContent = resetContent,
	/// deprecated
	PartialContent = partialContent,
	/// deprecated
	MultipleChoices = multipleChoices,
	/// deprecated
	MovedPermanently = movedPermanently,
	/// deprecated
	Found = found,
	/// deprecated
	SeeOther = seeOther,
	/// deprecated
	NotModified = notModified,
	/// deprecated
	UseProxy = useProxy,
	/// deprecated
	TemporaryRedirect = temporaryRedirect,
	/// deprecated
	BadRequest = badRequest,
	/// deprecated
	Unauthorized = unauthorized,
	/// deprecated
	PaymentRequired = paymentRequired,
	/// deprecated
	Forbidden = forbidden,
	/// deprecated
	NotFound = notFound,
	/// deprecated
	MethodNotAllowed = methodNotAllowed,
	/// deprecated
	NotAcceptable = notAcceptable,
	/// deprecated
	ProxyAuthenticationRequired = proxyAuthenticationRequired,
	/// deprecated
	RequestTimeout = requestTimeout,
	/// deprecated
	Conflict = conflict,
	/// deprecated
	Gone = gone,
	/// deprecated
	LengthRequired = lengthRequired,
	/// deprecated
	PreconditionFailed = preconditionFailed,
	/// deprecated
	RequestEntityTooLarge = requestEntityTooLarge,
	/// deprecated
	RequestURITooLarge = requestURITooLarge,
	/// deprecated
	UnsupportedMediaType = unsupportedMediaType,
	/// deprecated
	Requestedrangenotsatisfiable = requestedrangenotsatisfiable,
	/// deprecated
	ExpectationFailed = expectationFailed,
	/// deprecated
	InternalServerError = internalServerError,
	/// deprecated
	NotImplemented = notImplemented,
	/// deprecated
	BadGateway = badGateway,
	/// deprecated
	ServiceUnavailable = serviceUnavailable,
	/// deprecated
	GatewayTimeout = gatewayTimeout,
	/// deprecated
	HTTPVersionNotSupported = httpVersionNotSupported,
}

/**
	Returns a standard text description of the specified HTTP status code.
*/
string httpStatusText(int code)
{
	switch(code)
	{
		default: break;
		case HttpStatus.continue_                    : return "Continue";
		case HttpStatus.switchingProtocols           : return "Switching Protocols";
		case HttpStatus.ok                           : return "OK";
		case HttpStatus.created                      : return "Created";
		case HttpStatus.accepted                     : return "Accepted";
		case HttpStatus.nonAuthoritativeInformation  : return "Non-Authoritative Information";
		case HttpStatus.noContent                    : return "No Content";
		case HttpStatus.resetContent                 : return "Reset Content";
		case HttpStatus.partialContent               : return "Partial Content";
		case HttpStatus.multipleChoices              : return "Multiple Choices";
		case HttpStatus.movedPermanently             : return "Moved Permanently";
		case HttpStatus.found                        : return "Found";
		case HttpStatus.seeOther                     : return "See Other";
		case HttpStatus.notModified                  : return "Not Modified";
		case HttpStatus.useProxy                     : return "Use Proxy";
		case HttpStatus.temporaryRedirect            : return "Temporary Redirect";
		case HttpStatus.badRequest                   : return "Bad Request";
		case HttpStatus.unauthorized                 : return "Unauthorized";
		case HttpStatus.paymentRequired              : return "Payment Required";
		case HttpStatus.forbidden                    : return "Forbidden";
		case HttpStatus.notFound                     : return "Not Found";
		case HttpStatus.methodNotAllowed             : return "Method Not Allowed";
		case HttpStatus.notAcceptable                : return "Not Acceptable";
		case HttpStatus.proxyAuthenticationRequired  : return "Proxy Authentication Required";
		case HttpStatus.requestTimeout               : return "Request Time-out";
		case HttpStatus.conflict                     : return "Conflict";
		case HttpStatus.gone                         : return "Gone";
		case HttpStatus.lengthRequired               : return "Length Required";
		case HttpStatus.preconditionFailed           : return "Precondition Failed";
		case HttpStatus.requestEntityTooLarge        : return "Request Entity Too Large";
		case HttpStatus.requestURITooLarge           : return "Request-URI Too Large";
		case HttpStatus.unsupportedMediaType         : return "Unsupported Media Type";
		case HttpStatus.requestedrangenotsatisfiable : return "Requested range not satisfiable";
		case HttpStatus.expectationFailed            : return "Expectation Failed";
		case HttpStatus.internalServerError          : return "Internal Server Error";
		case HttpStatus.notImplemented               : return "Not Implemented";
		case HttpStatus.badGateway                   : return "Bad Gateway";
		case HttpStatus.serviceUnavailable           : return "Service Unavailable";
		case HttpStatus.gatewayTimeout               : return "Gateway Time-out";
		case HttpStatus.httpVersionNotSupported      : return "HTTP Version not supported";
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
		case HttpStatus.requestEntityTooLarge:
		case HttpStatus.requestURITooLarge:
		case HttpStatus.requestTimeout:
			return true; 
	}
}
