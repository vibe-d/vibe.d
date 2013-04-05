import vibe.core.log;
import vibe.http.client;


void main()
{
	auto client = new HTTPClient;
	client.connect("www.google.com", 80);
	
	auto res = client.request((req){
			req.url = "/";
		});

	logInfo("Response: %d", res.statusCode);
	foreach (k, v; res.headers)
		logInfo("Header: %s: %s", k, v);

	(new NullOutputStream).write(res.bodyReader);
	client.disconnect();
}
