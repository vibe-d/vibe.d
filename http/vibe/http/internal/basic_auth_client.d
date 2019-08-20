/**
	Implements HTTP Basic Auth for client.

	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.http.internal.basic_auth_client;

import vibe.http.common;
import std.base64;

@safe:

/**
	Augments the given HTTP request with an HTTP Basic Auth header.
*/
void addBasicAuth(scope HTTPRequest req, string user, string password)
{
	string pwstr = user ~ ":" ~ password;
	string authstr = () @trusted { return cast(string)Base64.encode(cast(ubyte[])pwstr); } ();
	req.headers["Authorization"] = "Basic " ~ authstr;
}
