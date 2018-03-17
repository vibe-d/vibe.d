/**
	Downloading and uploading of data from/to URLs.

	Note that this module is scheduled for deprecation and will be replaced by
	another module in the future. All functions are defined as templates to
	avoid this dependency issue when building the library.

	Copyright: © 2012-2015 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.urltransfer;

import vibe.core.log;
import vibe.core.file;
import vibe.inet.url;
import vibe.core.stream;
import vibe.internal.interfaceproxy : asInterface;

import std.exception;
import std.string;


/**
	Downloads a file from the specified URL.

	Any redirects will be followed until the actual file resource is reached or if the redirection
	limit of 10 is reached. Note that only HTTP(S) is currently supported.
*/
void download(HTTPClient_ = void*)(URL url, scope void delegate(scope InputStream) callback, HTTPClient_ client_ = null)
{
	import vibe.http.client;

	assert(url.username.length == 0 && url.password.length == 0, "Auth not supported yet.");
	assert(url.schema == "http" || url.schema == "https", "Only http(s):// supported for now.");

	HTTPClient client;
	static if (is(HTTPClient_ == HTTPClient)) client = client_;
	if (!client) client = new HTTPClient();
	scope (exit) {
		if (client_ is null) // disconnect default client
			client.disconnect();
	}

	if (!url.port)
		url.port = url.defaultPort;

	foreach( i; 0 .. 10 ){
		client.connect(url.host, url.port, url.schema == "https");
		logTrace("connect to %s", url.host);
		bool done = false;
		client.request(
			(scope HTTPClientRequest req) {
				req.requestURL = url.localURI;
				logTrace("REQUESTING %s!", req.requestURL);
			},
			(scope HTTPClientResponse res) {
				logTrace("GOT ANSWER!");

				switch( res.statusCode ){
					default:
						throw new HTTPStatusException(res.statusCode, "Server responded with "~httpStatusText(res.statusCode)~" for "~url.toString());
					case HTTPStatus.OK:
						done = true;
						callback(res.bodyReader.asInterface!InputStream);
						break;
					case HTTPStatus.movedPermanently:
					case HTTPStatus.found:
					case HTTPStatus.seeOther:
					case HTTPStatus.temporaryRedirect:
						logTrace("Status code: %s", res.statusCode);
						auto pv = "Location" in res.headers;
						enforce(pv !is null, "Server responded with redirect but did not specify the redirect location for "~url.toString());
						logDebug("Redirect to '%s'", *pv);
						if( startsWith((*pv), "http:") || startsWith((*pv), "https:") ){
							logTrace("parsing %s", *pv);
							auto nurl = URL(*pv);
							if (!nurl.port)
								nurl.port = nurl.defaultPort;
							if (url.host != nurl.host || url.schema != nurl.schema ||
								url.port != nurl.port)
								client.disconnect();
							url = nurl;
						} else
							url.localURI = *pv;
						break;
				}
			}
		);
		if (done) return;
	}
	enforce(false, "Too many redirects!");
	assert(false);
}

/// ditto
void download(HTTPClient_ = void*)(string url, scope void delegate(scope InputStream) callback, HTTPClient_ client_ = null)
{
	download(URL(url), callback, client_);
}

/// ditto
void download()(string url, string filename)
{
	download(url, (scope input){
		auto fil = openFile(filename, FileMode.createTrunc);
		scope(exit) fil.close();
		fil.write(input);
	});
}

/// ditto
void download()(URL url, NativePath filename)
{
	download(url.toString(), filename.toNativeString());
}
