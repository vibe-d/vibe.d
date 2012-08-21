import vibe.vibe;

void main()
{
	auto res = download("http://google.com/");


	logInfo("Response: %s", cast(string)res.readAll());
}
