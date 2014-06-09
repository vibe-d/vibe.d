/**
	Downloading and uploading of data from/to URLs.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.urltransfer;

import vibe.core.log;
import vibe.core.file;
import vibe.http.client;
import vibe.inet.url;
import vibe.core.stream;

import std.exception;
import std.string;


/**
	Downloads a file from the specified URL.

	Any redirects will be followed until the actual file resource is reached or if the redirection
	limit of 10 is reached. Note that only HTTP(S) is currently supported.
*/
void download(URL url, scope void delegate(scope InputStream) callback, HTTPClient client = null)
{
	assert(url.username.length == 0 && url.password.length == 0, "Auth not supported yet.");
	assert(url.schema == "http" || url.schema == "https", "Only http(s):// supported for now.");

	if(!client) client = new HTTPClient();
	
	foreach( i; 0 .. 10 ){
		bool ssl = url.schema == "https";
		client.connect(url.host, url.port ? url.port : ssl ? 443 : 80, ssl);
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
						callback(res.bodyReader);
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
							url = URL(*pv);
						} else url.localURI = *pv;
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
void download(string url, scope void delegate(scope InputStream) callback, HTTPClient client = null)
{
	download(URL(url), callback, client);
}

/// ditto
void download(string url, string filename)
{
	download(url, (scope input){
		auto fil = openFile(filename, FileMode.createTrunc);
		scope(exit) fil.close();
		fil.write(input);
	});
}

/// ditto
void download(URL url, Path filename)
{
	download(url.toString(), filename.toNativeString());
}
