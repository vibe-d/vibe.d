import vibe.core.log;
import vibe.db.mongo.mongo;

import std.array;

void main()
{
	logInfo("Connecting to DB...");
	auto db = connectMongoDB("localhost").getDatabase("test");
	auto coll = db["test"];

	logInfo("Querying DB...");
	Bson query = Bson(["name" : Bson("hans")]);
	auto result = coll.find(query);

	logInfo("Iterating results...");
	foreach (i, doc; result.byPair)
		logInfo("Item %d: %s", i, doc.toJson().toString());
}
