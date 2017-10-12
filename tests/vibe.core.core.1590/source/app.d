import std.stdio;
import std.socket;
import std.datetime;
import std.functional;
import core.time;
import vibe.core.core;
import vibe.core.log;
import vibe.core.concurrency;
import vibe.core.connectionpool;

class Conn {}

void main()
{
    runTask({
        // create pool with 2 max connections
        bool[int] results;
        auto pool = new ConnectionPool!Conn({ return new Conn; }, 2);
        auto task = Task.getThis(); // main task
        void worker(int id) {
            {
                auto conn = pool.lockConnection(); // <-- worker(4) hangs here
                sleep(1.msecs); // <-- important, without sleep everything works fine
            }
            task.send(id); // send signal to the main task
        }
        // run 4 tasks (2 * pool max connections)
        runTask(&worker, 1);
        runTask(&worker, 2);
        runTask(&worker, 3);
        runTask(&worker, 4);

        // wait for first signal and run one more task
        results[receiveOnly!int] = true;
        runTask(&worker, 5);

        // wait for other signals
        results[receiveOnly!int] = true;
        results[receiveOnly!int] = true;
        results[receiveOnly!int] = true;
        results[receiveOnly!int] = true;

        foreach (r; results.byKey)
            assert(r >= 1 && r <= 5);

        exitEventLoop();
    });

    setTimer(1.seconds, { assert(false, "Test has hung."); });

    runEventLoop();
}

