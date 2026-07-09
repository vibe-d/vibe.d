/// Requires a mongo service (>= 5.0) running on localhost; port via args[1].
/// Verifies MongoDB Stable API (Versioned API) support end-to-end: connection-string
/// parsing of apiVersion/apiStrict/apiDeprecationErrors, that the driver transmits the
/// fields on the wire, and that the server enforces them.

module app;

import vibe.data.bson;
import vibe.db.mongo.mongo;
import vibe.db.mongo.settings;
import vibe.db.mongo.impl.serverapi : ServerApi, ServerApiVersion;

import std.conv : to;

void main(string[] args)
{
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;

	testUriParsing();
	testApiVersionAccepted(port);
	testApiStrictEnforced(port);
}

/// The connection string populates and validates the Stable API config.
void testUriParsing()
{
	MongoClientSettings withVersion;
	assert(parseMongoDBUrl(withVersion, "mongodb://localhost/?apiVersion=1"));
	assert(!withVersion.serverApi.isNull, "apiVersion=1 populates the server API config");
	assert(withVersion.serverApi.get.apiVersion == ServerApiVersion.v1);

	MongoClientSettings withFlags;
	assert(parseMongoDBUrl(withFlags,
		"mongodb://localhost/?apiVersion=1&apiStrict=true&apiDeprecationErrors=true"));
	assert(withFlags.serverApi.get.strict.get == true, "apiStrict=true is parsed");
	assert(withFlags.serverApi.get.deprecationErrors.get == true, "apiDeprecationErrors=true is parsed");

	MongoClientSettings none;
	assert(parseMongoDBUrl(none, "mongodb://localhost"));
	assert(none.serverApi.isNull, "no apiVersion leaves the config unset");

	MongoClientSettings badVersion;
	assert(!parseMongoDBUrl(badVersion, "mongodb://localhost/?apiVersion=2"),
		"an unsupported apiVersion value is rejected");

	MongoClientSettings flagWithoutVersion;
	assert(!parseMongoDBUrl(flagWithoutVersion, "mongodb://localhost/?apiStrict=true"),
		"apiStrict without apiVersion is rejected");
}

/// A Stable-API command runs when the driver declares apiVersion=1.
void testApiVersionAccepted(ushort port)
{
	auto client = connectMongoDB("mongodb://127.0.0.1:" ~ port.to!string ~ "/?apiVersion=1");
	auto reply = client.getDatabase("admin").runCommandChecked(Bson(["ping": Bson(1)]));
	assert(reply["ok"].get!double == 1.0, "ping under apiVersion=1 must succeed");
}

/// apiStrict makes the server reject a command outside Stable API v1, proving the
/// driver actually transmits apiVersion+apiStrict (the control run, without them,
/// shows the same command normally succeeds). Servers before 5.0 predate the
/// Stable API and silently ignore the fields, so the enforcement check is skipped.
void testApiStrictEnforced(ushort port)
{
	auto control = connectMongoDB("mongodb://127.0.0.1:" ~ port.to!string ~ "/");
	auto controlReply = control.getDatabase("admin").runCommandChecked(Bson(["serverStatus": Bson(1)]));
	assert(controlReply["ok"].get!double == 1.0, "serverStatus succeeds without apiStrict");

	auto buildInfo = control.getDatabase("admin").runCommandChecked(Bson(["buildInfo": Bson(1)]));
	if (buildInfo["versionArray"][0].get!int < 5)
		return;

	auto strict = connectMongoDB("mongodb://127.0.0.1:" ~ port.to!string ~ "/?apiVersion=1&apiStrict=true");
	bool rejected = false;
	try
		strict.getDatabase("admin").runCommandChecked(Bson(["serverStatus": Bson(1)]));
	catch (Exception e)
		rejected = true;
	assert(rejected, "serverStatus (not in API Version 1) must be rejected under apiStrict=true");
}
