import vibe.d;

shared static this ()
{
    runTask(() => runTestSuite());
}

void runTestSuite ()
{
    auto count = getCaseCount();
    logInfo("We're going to run %d test cases...", count);

    foreach (currCase; 1 .. count)
    {
        auto url = URL("ws://127.0.0.1:9001/runCase?agent=vibe.d&case="
                       ~ to!string(currCase));
        logInfo("Running test case %d/%d", currCase, count);
        connectWebSocket(
            url, (scope ws) {
                while (ws.waitForData) {
                    ws.receive((scope message) {
                        ws.send(message.readAll);
                    });
                }
            });
    }
}


size_t getCaseCount (string base_addr = "ws://127.0.0.1:9001")
{
    size_t ret;
    auto url = URL(base_addr ~ "/getCaseCount");
    connectWebSocket(
        url, (scope ws) {
            while (ws.waitForData) {
                ret = ws.receiveText.to!size_t;
            }
        });
    return ret;
}
