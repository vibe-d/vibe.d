module app;

import tests.mongodb;
import tests.restclient;
import vibe.vibe;

void runTests()
{
	test_mongodb_general();
	test_rest_client();
	exitEventLoop();
}

extern(C) int getch();
int main()
{
	setLogLevel(LogLevel.Debug);
getch();
	runTask(toDelegate(&runTests));
	return runEventLoop();
}
