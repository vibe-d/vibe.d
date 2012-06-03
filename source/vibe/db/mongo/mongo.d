/**
	MongoDB and MongoCollection classes and connections.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.mongo;

public import vibe.db.mongo.db;


/**
	Connects to a MongoDB instance.

	Examples:
	---
	auto db = connectMongoDB("127.0.0.1")
	auto users = db["users"];
	users.insert(BSON("peter"));
	---
*/
MongoDB connectMongoDB(string host, ushort port = MongoDB.defaultPort)
{
	return new MongoDB(host, port);
}

