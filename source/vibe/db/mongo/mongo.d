/**
	MongoDB and MongoCollection classes and connections.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.mongo;

public import vibe.db.mongo.db;

import std.algorithm;

/**
	Connects to a MongoDB instance.

	Examples:
	---
	auto db = connectMongoDB("127.0.0.1");
	auto users = db["users"];
	users.insert(BSON("peter"));
	---
 
 	A mongodb URL can also be used as specified by http://www.mongodb.org/display/DOCS/Connections
    ---
    auto db = connectMongoDB("mongodb://localhost/?slaveOk=true");
    ---
  
 	Throws: an exception if a mongodb:// URL is given and the URL cannot be parsed. 
 	An exception will not be thrown if called with a hostname and port. 
*/
MongoDB connectMongoDB(string host, ushort port = MongoConnection.defaultPort)
{
	/* If this looks like a URL try to parse it that way. */
	if(host.startsWith("mongodb://")) 
	{
		return new MongoDB(host);
	} else {
		return new MongoDB(host, port);
	}
}

