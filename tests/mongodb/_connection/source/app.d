import vibe.db.mongo.mongo;
import vibe.db.mongo.client;
import vibe.core.core;
import vibe.core.log;
import core.time;
import std.conv;
import std.exception;

int main(string[] args)
{
	bool failConnect, failDB, failAuth;
	string username, password;
	ushort port;

	if (args.length < 2)
	{
		logError("Usage: %s [port] (failconnect) (faildb) (failauth) (auth [username] [password])",
				args[0]);
		return 1;
	}

	runTask({ sleep(10.seconds); assert(false, "Timeout exceeded"); });

	port = args[1].to!ushort;
	MongoClientSettings settings = new MongoClientSettings;

	int authStep = 0;
	foreach (arg; args[2 .. $])
	{
		if (authStep == 1)
		{
			username = arg;
			authStep = 2;
		}
		else if (authStep == 2)
		{
			password = arg;
			authStep = 0;
		}
		else
		{
			if (arg == "failconnect")
				failConnect = true;
			else if (arg == "faildb")
				failDB = true;
			else if (arg == "failauth")
				failAuth = true;
			else if (arg == "auth")
				authStep = 1;
			else
				logError("Unknown argument '%s'", arg);
		}
	}

	settings.hosts = [MongoHost("127.0.0.1", port)];
	settings.appName = "VibeConnectTest";
	if (username.length)
		settings.username = username;
	if (password.length)
		settings.digest = MongoClientSettings.makeDigest(username, password);

	MongoClient client;

	try
	{
		logInfo("Trying to connect to %(%s, %)", settings.hosts);
		client = connectMongoDB(settings);
	}
	catch (MongoAuthException e)
	{
		if (failAuth)
		{
			logInfo("Got expected failure in authenticating: %s", e.msg);
			return 0;
		}
		throw e;
	}
	catch (MongoDriverException e)
	{
		if (failConnect)
		{
			logInfo("Got expected failure in connection: %s", e.msg);
			return 0;
		}
		throw e;
	}

	if (failConnect)
		enforce(!client, "Expected connection failure, but none was thrown");

	if (failAuth)
		enforce(!client, "Expected authentication failure, but none was thrown");

	assert(!failConnect);
	assert(!failAuth);
	assert(client);

	logInfo("Accessing collection unittest.collection");
	auto db = client.getDatabase("unittest");
	MongoCollection coll = db["collection"];

	auto objID = BsonObjectID.generate;

	try
	{
		logInfo(`Trying to insert {"_id": "%s", "hello": "world"}`, objID);
		coll.insert(Bson(["_id": Bson(objID), "hello": Bson("world")]));
	}
	catch (MongoDriverException e)
	{
		if (failDB)
		{
			logInfo("Got expected failure in inserting: %s", e.msg);
			return 0;
		}
		throw e;
	}

	// TODO: implement writeConcern so this can be tested properly!
	// if (failDB)
	// 	throw new Exception("Expected insertion failure, but none was thrown");
	if (failDB)
	{
		bool exists;
		try
		{
			exists = !coll.findOne(["_id": objID]).isNull;
		}
		catch (MongoDriverException)
		{
			// auth fail, is ok if we expect insert not to work until writeConcern is implemented
		}
		enforce(!exists, "Expected insertion failure, but item got inserted");
		return 0;
	}

	logInfo("Everything in DB (target=%s):", objID);
	foreach (v; coll.find())
		logInfo("\t%s", v);

	auto v = coll.findOne(["_id": objID]);
	assert(!v.isNull, "Just-inserted entry is not added to the database");
	assert(v["hello"].get!string == "world",
			"Mongo server didn't operate as epxected. Got " ~ v["hello"].to!string ~ " instead of world!");
	logInfo(`just-inserted {"hello": "world"} entry found`);

	logInfo("All tests passed");
	return 0;
}
