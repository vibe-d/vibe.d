module examples.mongodb;

import vibe.d;
import std.array;

static this()
{
	runTask({
		logInfo("Connecting to DB...");
		auto db = connectMongoDB("localhost");
		auto coll = db["test.test"];

		logInfo("Querying DB...");
		Bson query = Bson(["name" : Bson("hans")]);
		auto result = coll.find(query);

		logInfo("Iterating results...");
		foreach( i, doc; result ){
			logInfo("Item %d: %s", i, (cast(Json)doc).toString());
		}
	});
}
