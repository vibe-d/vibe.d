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

int main()
{
	setLogLevel(LogLevel.Debug);
	runTask(toDelegate(&runTests));
	return runEventLoop();
}
