import vibe.core.log;
import vibe.db.mongo.mongo;
static if (__VERSION__ >= 2076)
	import std.datetime.stopwatch;
else
	import std.datetime;
import std.string : format;


Duration runTimed(scope void delegate() del)
{
	StopWatch sw;
	sw.start();
	del();
	sw.stop();
	static if (__VERSION__ >= 2076)
		return sw.peek;
	else
		return cast(Duration) sw.peek;
}

void main()
{
	enum nqueries = 100_000;

	struct Item {
		BsonObjectID _id;
		int i;
		double d;
		//string s;
	}

	auto db = connectMongoDB("localhost").getDatabase("test");
	auto coll = db["benchmark"];
	coll.remove();
	foreach (i; 0 .. 10) {
		Item itm;
		itm._id = BsonObjectID.generate();
		itm.i = i;
		itm.d = i * 1.3;
		//itm.s = "Hello, World!";
		coll.insert(itm);
	}

	logInfo("Running queries...");
	auto dur_query = runTimed({
		struct Q { int i; }
		foreach (i; 0 .. nqueries) {
			auto res = coll.find!Item(Q(5));
			res.front;
			//logInfo("%s %s", res.front.d, res.front.s);
			res.popFront();
		}
	});

	logInfo("  %s queries: %s", nqueries, dur_query);
}
