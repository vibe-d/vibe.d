import vibe.d;

static this()
{
	auto conn = connectTcp("time-b.timefreq.bldrdoc.gov", 13);
	conn.readLine(0, "\n"); // skip first newline
	logInfo("The time is: %s", cast(string)conn.readAll(0, "\n"));
}
