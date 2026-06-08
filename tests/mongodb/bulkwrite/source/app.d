/// Requires a MongoDB 8.0+ service running on localhost (server-level bulkWrite).
/// Self-skips on older servers. Uses the `test` database.

module app;

import vibe.core.log;
import vibe.data.bson;
import vibe.db.mongo.mongo;

import std.conv : to;

/// MongoDB 8.0 introduced the server-level `bulkWrite` command (WireVersion.v80 = 25).
enum bulkWriteWireVersion = 25;

int serverWireVersion(MongoClient client)
{
	auto hello = client.getDatabase("admin").runCommandChecked(Bson(["hello": Bson(1)]));
	return hello["maxWireVersion"].get!int;
}

void runTest(ushort port)
{
	MongoClient client = connectMongoDB("127.0.0.1", port);

	int maxWire;
	try
		maxWire = serverWireVersion(client);
	catch (Exception e) {
		logWarn("Could not determine server wire version (%s); skipping bulkWrite test", e.msg);
		return;
	}

	if (maxWire < bulkWriteWireVersion) {
		logInfo("Server wire version %s < %s (MongoDB 8.0); skipping bulkWrite test",
			maxWire, bulkWriteWireVersion);
		return;
	}

	logInfo("Server supports bulkWrite (wire %s); running cross-collection test", maxWire);

	auto pizzas = client.getCollection("test.bulk_pizzas");
	auto orders = client.getCollection("test.bulk_orders");
	try pizzas.drop; catch (Exception) {}
	try orders.drop; catch (Exception) {}

	// --- cross-collection bulk write, verbose results ---
	auto pizzaId = BsonObjectID.generate();
	ClientBulkWriteModel[] models = [
		ClientBulkWriteModel.insertOne("test.bulk_pizzas",
			Bson(["_id": Bson(pizzaId), "type": Bson("cheese"), "price": Bson(10)])),
		ClientBulkWriteModel.insertOne("test.bulk_orders",
			Bson(["item": Bson("cheese"), "qty": Bson(2)])),
		ClientBulkWriteModel.updateOne("test.bulk_pizzas",
			Bson(["_id": Bson(pizzaId)]), Bson(["$set": Bson(["price": Bson(12)])])),
	];

	ClientBulkWriteOptions options;
	options.verboseResults = true;

	auto result = client.bulkWrite(models, options);

	assert(result.acknowledged, "bulk write not acknowledged");
	assert(result.insertedCount == 2, "insertedCount=" ~ result.insertedCount.to!string);
	assert(result.matchedCount == 1, "matchedCount=" ~ result.matchedCount.to!string);
	assert(result.modifiedCount == 1, "modifiedCount=" ~ result.modifiedCount.to!string);
	assert(result.hasVerboseResults, "expected verbose results");
	assert(0 in result.insertResults, "no insert result for op 0");
	assert(result.insertResults[0].insertedId == pizzaId, "insert result id mismatch");
	assert(2 in result.updateResults, "no update result for op 2");
	assert(result.updateResults[2].modifiedCount == 1, "update result modifiedCount mismatch");

	// the writes actually landed in BOTH collections, and the update applied
	auto storedPizza = pizzas.findOne(Bson(["_id": Bson(pizzaId)]));
	assert(storedPizza.type != Bson.Type.null_, "inserted pizza not found");
	assert(storedPizza["price"].get!int == 12, "pizza price was not updated to 12");

	auto storedOrder = orders.findOne(Bson(["item": Bson("cheese")]));
	assert(storedOrder.type != Bson.Type.null_, "inserted order not found");

	logInfo("cross-collection verbose bulkWrite OK");

	// --- a duplicate _id surfaces as a write error with a partial result ---
	bool threw = false;
	try
		client.bulkWrite([
			ClientBulkWriteModel.insertOne("test.bulk_pizzas", Bson(["type": Bson("vegan")])),
			ClientBulkWriteModel.insertOne("test.bulk_pizzas", Bson(["_id": Bson(pizzaId)])), // duplicate
		]);
	catch (MongoClientBulkWriteException e) {
		threw = true;
		assert(e.writeErrors.length >= 1, "expected at least one write error");
		assert(!e.partialResult.isNull, "expected a partial result on the exception");
		logInfo("duplicate-key bulkWrite threw as expected: %s write error(s)", e.writeErrors.length);
	}
	assert(threw, "expected duplicate-key bulkWrite to throw MongoClientBulkWriteException");

	logInfo("bulkWrite integration test passed");
}

void main(string[] args)
{
	ushort port = args.length > 1
		? args[1].to!ushort
		: MongoClientSettings.defaultPort;
	runTest(port);
}
