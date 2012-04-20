import vibe.d;

static this()
{
	//setLogLevel(LogLevel.Trace);

	auto res = download("http://golem.de/");


	logInfo("Response:");
	while( !res.empty ){
		auto ln = res.readLine();
		logInfo("%s", cast(string)ln);
	}
}
