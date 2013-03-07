module app;

import tests.mongodb;
import tests.restclient;
import vibe.vibe;

int main()
{ 
    test_mongodb_general();
    test_rest_client();

    setTimer(dur!"seconds"(5), {
        exitEventLoop();
    });

    return runEventLoop();
}
