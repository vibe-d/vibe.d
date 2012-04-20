module examples.mongodb;

import vibe.d;
import std.array;

static this()
{
//	setLogLevel(LogLevel.Trace);

	runTask({
		logInfo("Connecting to DB...");
		auto db = connectMongoDB("localhost");
		auto coll = db["test.test"];

		logInfo("Querying DB...");
		BSON query = BSON(["name" : BSON("hans")]);
		auto result = coll.find(query);

		logInfo("Iterating results...");
		foreach( i, doc; result ){
			logInfo("Item %d: %s", i, (cast(JSON)doc).toString());
		}
	});
}
