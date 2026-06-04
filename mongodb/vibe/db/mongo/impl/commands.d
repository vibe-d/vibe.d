/**
	Pure helpers extracted from the connection-bound MongoDB driver code.

	These functions take plain data in and return plain data out, so they can be
	unit-tested without a live MongoDB connection. They are kept in a dedicated
	module to make the divergence from upstream vibe-d easy to review.

	Copyright: © 2012-2016 Sönke Ludwig, © 2020-2022 Jan Jurzitza
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Jurzitza
*/
module vibe.db.mongo.impl.commands;

@safe:

import core.time;

import std.algorithm : min, skipOver;
import std.range : chain;
import std.string : indexOf;

import vibe.data.bson;
import vibe.db.mongo.impl.crud : FindOptions, CursorType;

/// A "database.collection" namespace split into its two parts.
struct Namespace
{
	string database;
	string collection;
}

/** Splits a qualified "database.collection" path at the first dot.

	The caller is responsible for validating that a dot is present.
*/
Namespace splitNamespace(string fullPath)
{
	auto dotidx = fullPath.indexOf('.');
	return Namespace(fullPath[0 .. dotidx], fullPath[dotidx + 1 .. $]);
}

unittest {
	assert(splitNamespace("db.coll") == Namespace("db", "coll"));
	assert(splitNamespace("db.a.b") == Namespace("db", "a.b"));
}

/** Removes a leading "database." prefix from a qualified namespace.

	Mongo reports the qualified collection name in cursor replies, but requesting
	more data needs the database and collection names separately.
*/
string collectionFromNamespace(string ns, string database)
{
	ns.skipOver(database.chain("."));
	return ns;
}

unittest {
	assert(collectionFromNamespace("db.coll", "db") == "coll");
	assert(collectionFromNamespace("other.coll", "db") == "other.coll");
	assert(collectionFromNamespace("db.a.b", "db") == "a.b");
}

/// The completed find command together with the cursor batching parameters.
struct FindCommandResult
{
	Bson command;
	int batchSize;
	Duration getMoreMaxTime;
}

/** Normalizes `FindOptions` into the wire-level find command.

	Handles the OP_QUERY-to-find limit/batchSize mapping, tailable/awaitData
	flags and the maxTimeMS semantics, then serializes the remaining options into
	the command document.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/find_getmore_killcursors_commands.rst)
*/
FindCommandResult buildFindCommand(Bson command, FindOptions options)
{
	bool singleBatch;
	if (!options.limit.isNull && options.limit.get < 0)
	{
		singleBatch = true;
		options.limit = -options.limit.get;
		options.batchSize = cast(int)options.limit.get;
	}
	if (!options.batchSize.isNull && options.batchSize.get < 0)
	{
		singleBatch = true;
		options.batchSize = -options.batchSize.get;
	}
	if (singleBatch)
		command["singleBatch"] = Bson(true);

	bool allowMaxTime = true;
	if (options.cursorType == CursorType.tailable
		|| options.cursorType == CursorType.tailableAwait)
		command["tailable"] = Bson(true);
	else
	{
		options.maxAwaitTimeMS.nullify();
		allowMaxTime = false;
	}

	if (options.cursorType == CursorType.tailableAwait)
		command["awaitData"] = Bson(true);
	else
	{
		options.maxAwaitTimeMS.nullify();
		allowMaxTime = false;
	}

	auto optionsBson = serializeToBson(options);
	foreach (string key, value; optionsBson.byKeyValue)
		command[key] = value;

	return FindCommandResult(
		command,
		options.batchSize.isNull ? 0 : options.batchSize.get,
		!options.maxAwaitTimeMS.isNull ? options.maxAwaitTimeMS.get.msecs
			: allowMaxTime && !options.maxTimeMS.isNull ? options.maxTimeMS.get.msecs
			: Duration.max);
}

unittest {
	Bson base()
	{
		Bson command = Bson.emptyObject;
		command["find"] = Bson("coll");
		command["$db"] = Bson("db");
		return command;
	}

	auto plain = buildFindCommand(base(), FindOptions.init);
	assert(plain.command["singleBatch"].isNull);
	assert(plain.command["tailable"].isNull);
	assert(plain.batchSize == 0);
	assert(plain.getMoreMaxTime == Duration.max);

	FindOptions negativeLimit;
	negativeLimit.limit = -5;
	auto negative = buildFindCommand(base(), negativeLimit);
	assert(negative.command["singleBatch"].get!bool == true);
	assert(negative.batchSize == 5);

	FindOptions negativeBatch;
	negativeBatch.batchSize = -7;
	auto batch = buildFindCommand(base(), negativeBatch);
	assert(batch.command["singleBatch"].get!bool == true);
	assert(batch.batchSize == 7);

	FindOptions tailable;
	tailable.cursorType = CursorType.tailable;
	auto tail = buildFindCommand(base(), tailable);
	assert(tail.command["tailable"].get!bool == true);
	assert(tail.command["awaitData"].isNull);

	FindOptions awaiting;
	awaiting.cursorType = CursorType.tailableAwait;
	auto await = buildFindCommand(base(), awaiting);
	assert(await.command["tailable"].get!bool == true);
	assert(await.command["awaitData"].get!bool == true);

	// A non-tailable cursor disables maxTime for getMore, so maxTimeMS is ignored here.
	FindOptions plainTimed;
	plainTimed.maxTimeMS = 1500;
	auto plainTimedResult = buildFindCommand(base(), plainTimed);
	assert(plainTimedResult.getMoreMaxTime == Duration.max);

	// A tailableAwait cursor keeps maxTime, so maxTimeMS feeds getMore.
	FindOptions timed;
	timed.cursorType = CursorType.tailableAwait;
	timed.maxTimeMS = 1500;
	auto timedResult = buildFindCommand(base(), timed);
	assert(timedResult.getMoreMaxTime == 1500.msecs);

	// maxAwaitTimeMS takes precedence over maxTimeMS for getMore.
	FindOptions awaitTimed;
	awaitTimed.cursorType = CursorType.tailableAwait;
	awaitTimed.maxAwaitTimeMS = 800;
	auto awaitTimedResult = buildFindCommand(base(), awaitTimed);
	assert(awaitTimedResult.getMoreMaxTime == 800.msecs);
}

/// The reduced limit/batch state for a legacy cursor.
struct LimitReduction
{
	int nret;
	long limit;
}

/** Folds a new `limit(count)` call into the existing cursor limit state.

	A non-positive count is a no-op; otherwise the lowest positive limit wins and
	the per-batch count is capped at 1024.
*/
LimitReduction reduceLimit(int nret, long limit, long count)
{
	if (count > 0)
	{
		if (nret == 0 || nret > count)
			nret = cast(int)min(count, 1024);

		if (limit == 0 || limit > count)
			limit = count;
	}

	return LimitReduction(nret, limit);
}

unittest {
	assert(reduceLimit(0, 0, 0) == LimitReduction(0, 0));
	assert(reduceLimit(0, 0, 10) == LimitReduction(10, 10));
	assert(reduceLimit(10, 10, 20) == LimitReduction(10, 10));
	assert(reduceLimit(10, 10, 5) == LimitReduction(5, 5));
	assert(reduceLimit(0, 0, 5000) == LimitReduction(1024, 5000));
}
