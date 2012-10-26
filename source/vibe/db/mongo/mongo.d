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

	If the host/port form is used, default settings will be used, which enable
	safe updates, but no fsync. By specifying a URL instead, it is possible to
	fully customize the settings. See
	$(LINK http://www.mongodb.org/display/DOCS/Connections) for the complete set
	of options.

	Examples:
		---
		// connecting with default settings:
		auto db = connectMongoDB("127.0.0.1");
		auto users = db["users"];
		users.insert(Bson("peter"));
		---

		---
		// connectiong using the URL form with custom settings
		auto db = connectMongoDB("mongodb://localhost/?slaveOk=true");
		---

	Params:
		host = Specifies the host name or IP address of the MongoDB server.
		port = Can be used to specify the port of the MongoDB server if different from the default one.
		host_or_url = Can either be a host name, in which case the default port will be used, or a URL with the mongodb:// scheme.

	Returns:
		A new MongoDB instance that can be used to access the database.
  
 	Throws:
 		Throws an exception if a mongodb:// URL is given and the URL cannot be parsed.
 		An exception will not be thrown if called with a hostname and port. 
*/
MongoDB connectMongoDB(string host, ushort port)
{
	assert(!host.startsWith("mongodb://"));
	return new MongoDB(host, port);
}
/// ditto
MongoDB connectMongoDB(string host_or_url)
{
	/* If this looks like a URL try to parse it that way. */
	if(host_or_url.startsWith("mongodb://")){
		return new MongoDB(host_or_url);
	} else {
		return new MongoDB(host_or_url, MongoConnection.defaultPort);
	}
}

