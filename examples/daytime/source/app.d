import vibe.core.log;
import vibe.core.net;
import vibe.stream.operations;

void main()
{
	auto conn = connectTCP("time-b.timefreq.bldrdoc.gov", 13);
	conn.readLine(256, "\n"); // skip first newline
	logInfo("The time is: %s", cast(string)conn.readLine(256, "\n"));
}
