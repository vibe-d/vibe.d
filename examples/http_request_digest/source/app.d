import vibe.core.log;
import vibe.http.auth.digest_auth;
import vibe.http.client;

import std.algorithm;
import std.format;
import std.random;

enum username = "bond";
enum password = "007";

void main()
{
	auto url = URL("http://httpbin.org/digest-auth/auth/" ~ username ~ "/" ~ password ~ "/MD5");
	requestHTTP(url,
		(scope req) {
		},
		(scope res) {
			logInfo("Response: %d", res.statusCode);
			foreach (k, v; res.headers)
				logInfo("Header: %s: %s", k, v);

			auto pc = "Set-Cookie" in res.headers;

			if (res.statusCode == 401 && res.headers["WWW-Authenticate"]) {
				auto auth = res.headers["WWW-Authenticate"];
				if (auth.startsWith("Digest ")) {
					requestHTTP(url,
						(scope req) {
							auto resp = createDigestAuthHeader(
								HTTPMethod.GET, url, username, password, DigestAuthParams(auth),
								format("%08x", uniform!int), 1);
								logInfo("Digest request: %s", resp);
							req.headers["Authorization"] = resp;
							if (pc !is null) req.headers["Cookie"] = *pc;
						},
						(scope res) {
							logInfo("Response: %d", res.statusCode);
							foreach (k, v; res.headers)
								logInfo("Header: %s: %s", k, v);
						}
					);
				}
			}
		}
	);
}
