import vibe.vibe;

void main()
{
	auto client = new HttpClient;
	client.connect("www.google.com", 80);
	
	auto res = client.request((req){
			req.url = "/";
		});

	logInfo("Response: %d", res.statusCode);
	foreach( k, v; res.headers )
		logInfo("Header: %s: %s", k, v);

	(new NullOutputStream).write(res.bodyReader);
	client.disconnect();
}
