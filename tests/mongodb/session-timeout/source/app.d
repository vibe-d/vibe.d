/// Requires a mongo service running on localhost; port via args[1].
/// Verifies the server-advertised logicalSessionTimeoutMinutes flows through the
/// driver's real path: the live hello reply parses into ServerDescription, the
/// data-bearing filter accepts the node, and logicalSessionTimeout computes the
/// timeout. The harness's mongod reports the default 30 minutes (the startup
/// parameter localLogicalSessionTimeoutMinutes is not runtime-settable), so this
/// confirms the path against REAL server data with the default value.

module app;

import vibe.data.bson;
import vibe.db.mongo.mongo;
import vibe.db.mongo.settings;
import vibe.db.mongo.connection : ServerDescription;   // public-imported from impl.serverdescription
import vibe.db.mongo.topology : logicalSessionTimeout;

import core.time : minutes;
import std.conv : to;

void main(string[] args)
{
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;

	auto client = connectMongoDB("mongodb://127.0.0.1:" ~ port.to!string ~ "/");
	auto hello = client.getDatabase("admin").runCommandChecked(Bson(["hello": Bson(1)]));

	assert(hello["logicalSessionTimeoutMinutes"].type != Bson.Type.null_,
		"the server advertises logicalSessionTimeoutMinutes");

	auto desc = deserializeBson!ServerDescription(hello);
	assert(!desc.logicalSessionTimeoutMinutes.isNull,
		"the driver parses logicalSessionTimeoutMinutes from the hello reply");
	assert(desc.isDataBearing,
		"the standalone server is a data-bearing node");

	auto timeout = logicalSessionTimeout([desc]);
	assert(!timeout.isNull,
		"a data-bearing server advertising a timeout yields a topology timeout");
	assert(timeout.get == desc.logicalSessionTimeoutMinutes.get.minutes,
		"the computed timeout equals the server-advertised value");
	assert(timeout.get == 30.minutes,
		"the default mongod advertises a 30 minute logical session timeout");
}
