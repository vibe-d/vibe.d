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
enum HTTPStatus {
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
	tooManyRequests              = 429,
	unavailableForLegalReasons   = 451,
	internalServerError          = 500,
	notImplemented               = 501,
	badGateway                   = 502,
	serviceUnavailable           = 503,
	gatewayTimeout               = 504,
	httpVersionNotSupported      = 505,
	// WebDAV status codes
	multiStatus                  = 207,
	unprocessableEntity          = 422,
	locked                       = 423,
	failedDependency             = 424,
	insufficientStorage          = 507,

	Continue = continue_, /// deprecated
	SwitchingProtocols = switchingProtocols, /// deprecated
	OK = ok, /// deprecated
	Created = created, /// deprecated
	Accepted = accepted, /// deprecated
	NonAuthoritativeInformation = nonAuthoritativeInformation, /// deprecated
	NoContent = noContent, /// deprecated
	ResetContent = resetContent, /// deprecated
	PartialContent = partialContent, /// deprecated
	MultipleChoices = multipleChoices, /// deprecated
	MovedPermanently = movedPermanently, /// deprecated
	Found = found, /// deprecated
	SeeOther = seeOther, /// deprecated
	NotModified = notModified, /// deprecated
	UseProxy = useProxy, /// deprecated
	TemporaryRedirect = temporaryRedirect, /// deprecated
	BadRequest = badRequest, /// deprecated
	Unauthorized = unauthorized, /// deprecated
	PaymentRequired = paymentRequired, /// deprecated
	Forbidden = forbidden, /// deprecated
	NotFound = notFound, /// deprecated
	MethodNotAllowed = methodNotAllowed, /// deprecated
	NotAcceptable = notAcceptable, /// deprecated
	ProxyAuthenticationRequired = proxyAuthenticationRequired, /// deprecated
	RequestTimeout = requestTimeout, /// deprecated
	Conflict = conflict, /// deprecated
	Gone = gone, /// deprecated
	LengthRequired = lengthRequired, /// deprecated
	PreconditionFailed = preconditionFailed, /// deprecated
	RequestEntityTooLarge = requestEntityTooLarge, /// deprecated
	RequestURITooLarge = requestURITooLarge, /// deprecated
	UnsupportedMediaType = unsupportedMediaType, /// deprecated
	Requestedrangenotsatisfiable = requestedrangenotsatisfiable, /// deprecated
	ExpectationFailed = expectationFailed, /// deprecated
	InternalServerError = internalServerError, /// deprecated
	NotImplemented = notImplemented, /// deprecated
	BadGateway = badGateway, /// deprecated
	ServiceUnavailable = serviceUnavailable, /// deprecated
	GatewayTimeout = gatewayTimeout, /// deprecated
	HTTPVersionNotSupported = httpVersionNotSupported, /// deprecated
}


@safe nothrow @nogc pure:

/**
	Returns a standard text description of the specified HTTP status code.
*/
string httpStatusText(int code)
{
	switch(code)
	{
		default: break;
		case HTTPStatus.continue_                    : return "Continue";
		case HTTPStatus.switchingProtocols           : return "Switching Protocols";
		case HTTPStatus.ok                           : return "OK";
		case HTTPStatus.created                      : return "Created";
		case HTTPStatus.accepted                     : return "Accepted";
		case HTTPStatus.nonAuthoritativeInformation  : return "Non-Authoritative Information";
		case HTTPStatus.noContent                    : return "No Content";
		case HTTPStatus.resetContent                 : return "Reset Content";
		case HTTPStatus.partialContent               : return "Partial Content";
		case HTTPStatus.multipleChoices              : return "Multiple Choices";
		case HTTPStatus.movedPermanently             : return "Moved Permanently";
		case HTTPStatus.found                        : return "Found";
		case HTTPStatus.seeOther                     : return "See Other";
		case HTTPStatus.notModified                  : return "Not Modified";
		case HTTPStatus.useProxy                     : return "Use Proxy";
		case HTTPStatus.temporaryRedirect            : return "Temporary Redirect";
		case HTTPStatus.badRequest                   : return "Bad Request";
		case HTTPStatus.unauthorized                 : return "Unauthorized";
		case HTTPStatus.paymentRequired              : return "Payment Required";
		case HTTPStatus.forbidden                    : return "Forbidden";
		case HTTPStatus.notFound                     : return "Not Found";
		case HTTPStatus.methodNotAllowed             : return "Method Not Allowed";
		case HTTPStatus.notAcceptable                : return "Not Acceptable";
		case HTTPStatus.proxyAuthenticationRequired  : return "Proxy Authentication Required";
		case HTTPStatus.requestTimeout               : return "Request Time-out";
		case HTTPStatus.conflict                     : return "Conflict";
		case HTTPStatus.gone                         : return "Gone";
		case HTTPStatus.lengthRequired               : return "Length Required";
		case HTTPStatus.preconditionFailed           : return "Precondition Failed";
		case HTTPStatus.requestEntityTooLarge        : return "Request Entity Too Large";
		case HTTPStatus.requestURITooLarge           : return "Request-URI Too Large";
		case HTTPStatus.unsupportedMediaType         : return "Unsupported Media Type";
		case HTTPStatus.requestedrangenotsatisfiable : return "Requested range not satisfiable";
		case HTTPStatus.expectationFailed            : return "Expectation Failed";
		case HTTPStatus.unavailableForLegalReasons   : return "Unavailable For Legal Reasons";
		case HTTPStatus.internalServerError          : return "Internal Server Error";
		case HTTPStatus.notImplemented               : return "Not Implemented";
		case HTTPStatus.badGateway                   : return "Bad Gateway";
		case HTTPStatus.serviceUnavailable           : return "Service Unavailable";
		case HTTPStatus.gatewayTimeout               : return "Gateway Time-out";
		case HTTPStatus.httpVersionNotSupported      : return "HTTP Version not supported";
		// WebDAV
		case HTTPStatus.multiStatus                  : return "Multi-Status";
		case HTTPStatus.unprocessableEntity          : return "Unprocessable Entity";
		case HTTPStatus.locked                       : return "Locked";
		case HTTPStatus.failedDependency             : return "Failed Dependency";
		case HTTPStatus.insufficientStorage          : return "Insufficient Storage";
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
bool justifiesConnectionClose(int status)
{
	switch(status) {
		default: return false;
		case HTTPStatus.requestEntityTooLarge:
		case HTTPStatus.requestURITooLarge:
		case HTTPStatus.requestTimeout:
			return true;
	}
}

/**
	Determines if status code is generally successful (>= 200 && < 300)
*/
bool isSuccessCode(HTTPStatus status)
{
	return status >= 200 && status < 300;
}

