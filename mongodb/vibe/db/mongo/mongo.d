/**
	MongoDB and MongoCollection classes and connections.

	Implementation_Note:

	The MongoDB driver implementation here is missing a number of API functions
	known from the JavaScript driver, but these can usually be implemented in
	terms of MongoDatabase.runCommand or MongoCollection.find. Since the
	official documentation is lacking in some places, it may be necessary to use
	a network sniffer to monitor what exectly needs to be sent. MongoDB has a
	dedicated utility for this called $(LINK2 http://docs.mongodb.org/manual/reference/program/mongosniff/ mongosniff).

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.mongo;

public import vibe.db.mongo.client;
public import vibe.db.mongo.settings;

import std.algorithm;

@safe:


/**
	Connects to a MongoDB instance.

	If the host/port form is used, default settings will be used, which enable
	safe updates, but no fsync. By specifying a URL instead, it is possible to
	fully customize the settings. See
	$(LINK http://www.mongodb.org/display/DOCS/Connections) for the complete set
	of options. Note that 'sslverifycertificate' is only present in some client
	bindings, including here.

	Note that the returned MongoClient uses a vibe.core.connectionpool.ConnectionPool
	internally to create and reuse connections as necessary. Thus, the
	MongoClient instance can - and should - be shared among all fibers in a
	thread by storing in in a thread local variable.

	Authentication:
		Authenticated connections are supported by using a URL connection string
		such as "mongodb://user:password@host". SCRAM-SHA-1 is used by default.

	Examples:
		---
		// connecting with default settings:
		auto client = connectMongoDB("127.0.0.1");
		auto users = client.getCollection("users");
		users.insert(Bson("peter"));
		---

		---
		// connecting using the URL form with custom settings
		auto client = connectMongoDB("mongodb://localhost/?slaveOk=true");
		---

		---
		// connecting with SSL encryption enabled and verification off
		auto client = connectMongoDB("mongodb://localhost/?ssl=true&sslverifycertificate=false");
		---

	Params:
		host = Specifies the host name or IP address of the MongoDB server.
		port = Can be used to specify the port of the MongoDB server if different from the default one.
		host_or_url = Can either be a host name, in which case the default port will be used, or a URL with the mongodb:// scheme.
		settings = An object containing the full set of possible configuration options.

	Returns:
		A new MongoClient instance that can be used to access the database.

 	Throws:
 		Throws an exception if a mongodb:// URL is given and the URL cannot be parsed.
 		An exception will not be thrown if called with a hostname and port.
*/
MongoClient connectMongoDB(string host, ushort port)
{
	assert(!host.startsWith("mongodb://"));
	return new MongoClient(host, port);
}
/// ditto
MongoClient connectMongoDB(string host_or_url)
{
	/* If this looks like a URL try to parse it that way. */
	if(host_or_url.startsWith("mongodb://")){
		return new MongoClient(host_or_url);
	} else {
		return new MongoClient(host_or_url, MongoClientSettings.defaultPort);
	}
}
/// ditto
MongoClient connectMongoDB(MongoClientSettings settings)
{
	return new MongoClient(settings);
}
