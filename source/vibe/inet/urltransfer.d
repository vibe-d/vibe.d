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
void download(Url url, scope void delegate(scope InputStream) callback, HttpClient client = null)
{
	assert(url.username.length == 0 && url.password.length == 0, "Auth not supported yet.");
	assert(url.schema == "http" || url.schema == "https", "Only http(s):// supported for now.");

	if(!client) client = new HttpClient();
	
	foreach( i; 0 .. 10 ){
		bool ssl = url.schema == "https";
		client.connect(url.host, url.port ? url.port : ssl ? 443 : 80, ssl);
		logTrace("connect to %s", url.host);
		bool done = false;
		client.request(
			(scope HttpClientRequest req) {
				req.requestUrl = url.localURI;
				logTrace("REQUESTING %s!", req.requestUrl);
			},
			(scope HttpClientResponse res) {
				logTrace("GOT ANSWER!");

				switch( res.statusCode ){
					default:
						throw new HttpStatusException(res.statusCode, "Server responded with "~httpStatusText(res.statusCode)~" for "~url.toString());
					case HttpStatus.OK:
						callback(res.bodyReader);
						done = true;
						break;
					case 300: .. case 399:
			logTrace("Status code: %s", res.statusCode);
						auto pv = "Location" in res.headers;
						enforce(pv !is null, "Server responded with redirect but did not specify the redirect location for "~url.toString());
						logDebug("Redirect to '%s'", *pv);
						if( startsWith((*pv), "http:") || startsWith((*pv), "https:") ){
			logTrace("parsing %s", *pv);
							url = Url.parse(*pv);
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
void download(string url, scope void delegate(scope InputStream) callback, HttpClient client = null)
{
	download(Url(url), callback, client);
}

/// ditto
void download(string url, string filename)
{
	download(url, (scope input){
		auto fil = openFile(filename, FileMode.CreateTrunc);
		scope(exit) fil.close();
		fil.write(input);
	});
}

/// ditto
void download(Url url, Path filename)
{
	download(url.toString(), filename.toNativeString());
}
