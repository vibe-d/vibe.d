import vibe.db.mongo.mongo;
import vibe.db.mongo.client;
import vibe.core.core;
import vibe.core.log;
import std.conv;

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

	port = args[1].to!ushort;

	int authStep = 0;
	foreach (arg; args[2 .. $])
	{
		if (authStep == 1)
		{
			username = arg;
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

	MongoClientSettings settings = new MongoClientSettings;
	settings.hosts = [MongoHost("127.0.0.1", port)];
	settings.appName = "VibeConnectTest";
	if (username.length)
		settings.username = username;
	if (password.length)
		settings.digest = MongoClientSettings.makeDigest(username, password);

	MongoClient client;

	try
	{
		client = connectMongoDB(settings);
	}
	catch (MongoAuthException e)
	{
		if (failAuth)
			return 0;
		throw e;
	}
	catch (MongoDriverException e)
	{
		if (failConnect)
			return 0;
		throw e;
	}

	if (failConnect && !client)
	{
		throw new Exception("Expected connection failure, but none was thrown");
	}

	if (failAuth && !client)
	{
		throw new Exception("Expected authentication failure, but none was thrown");
	}

	assert(client);

	auto db = client.getDatabase("unittest");
	MongoCollection coll = db["collection"];

	auto objID = BsonObjectID.generate;

	try
	{
		coll.insert(Bson(["_id" : Bson(objID), "hello" : Bson("world")]));
	}
	catch (MongoDriverException e)
	{
		if (failDB)
			return 0;
		throw e;
	}

	if (failDB)
		throw new Exception("Expected insertion failure, but none was thrown");

	logInfo("Everything in DB (target=%s):", objID);
	foreach (v; coll.find())
		logInfo("\t%s", v);

	auto v = coll.findOne(["_id" : objID]);
	assert(v["hello"].get!string == "world",
			"Mongo server didn't operate as epxected. Got " ~ v["hello"].to!string ~ " instead of world!");

	return 0;
}
