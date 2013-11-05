import vibe.core.log;
import vibe.http.client;


void main()
{
	requestHTTP("http://www.google.com/",
		(scope req) {
		},
		(scope res) {
			logInfo("Response: %d", res.statusCode);
			foreach (k, v; res.headers)
				logInfo("Header: %s: %s", k, v);
		}
	);
}
