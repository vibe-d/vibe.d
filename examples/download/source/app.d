import vibe.vibe;

void main()
{
	download("http://google.com/", (scope res){
		logInfo("Response: %s", cast(string)res.readAll());
	});
}
