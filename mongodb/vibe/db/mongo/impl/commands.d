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

import std.algorithm : min, skipOver, among;
import std.meta : AliasSeq;
import std.range : chain;
import std.string : indexOf;

import vibe.data.bson;
import vibe.db.mongo.impl.crud : FindOptions, CursorType, CountOptions, AggregateOptions;
import vibe.db.mongo.settings : ReadPreference, readPreferenceBson;

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

/// A completed cursor-producing command together with its batching parameters.
struct CursorCommand
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
CursorCommand buildFindCommand(Bson command, FindOptions options, ReadPreference pref = ReadPreference.primary, string[string][] tagSets = null)
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

	if (pref != ReadPreference.primary)
		command["$readPreference"] = readPreferenceBson(pref, tagSets);

	return CursorCommand(
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

	// a non-primary read preference is injected as $readPreference
	auto secondaryRead = buildFindCommand(base(), FindOptions.init, ReadPreference.secondary);
	assert(secondaryRead.command["$readPreference"]["mode"].get!string == "secondary");

	// primary (the default) is omitted from the wire
	auto primaryRead = buildFindCommand(base(), FindOptions.init, ReadPreference.primary);
	assert(primaryRead.command["$readPreference"].isNull);
	auto defaultedRead = buildFindCommand(base(), FindOptions.init);
	assert(defaultedRead.command["$readPreference"].isNull);

	// the configured readPreferenceTags are emitted alongside the mode (host selection
	// uses them, so the $readPreference sent to mongos must carry them too)
	string[string][] tags = [["dc": "east"]];
	auto taggedRead = buildFindCommand(base(), FindOptions.init, ReadPreference.secondary, tags);
	assert(taggedRead.command["$readPreference"] == readPreferenceBson(ReadPreference.secondary, tags),
		"the cursor $readPreference carries the configured readPreferenceTags");
}

/** Assembles a `delete` command from serialized queries and options.

	The `limit`, `collation` and `hint` options belong inside each delete
	statement rather than at the command level, so they are partitioned out.
*/
Bson buildDeleteCommand(string collection, Bson[] queries, Bson optionsBson, scope int[] limits)
{
	alias FieldsMovedIntoChildren = AliasSeq!("limit", "collation", "hint");

	Bson cmd = Bson.emptyObject;
	cmd["delete"] = Bson(collection);
	foreach (string k, v; optionsBson.byKeyValue)
		if (!k.among!FieldsMovedIntoChildren)
			cmd[k] = v;

	Bson[] deletesBson = new Bson[queries.length];
	foreach (i, q; queries)
	{
		auto deleteBson = Bson.emptyObject;
		deleteBson["q"] = q;
		foreach (string k, v; optionsBson.byKeyValue)
			if (k.among!FieldsMovedIntoChildren)
				deleteBson[k] = v;
		deleteBson["limit"] = Bson(i < limits.length ? limits[i] : 0);
		deletesBson[i] = deleteBson;
	}
	cmd["deletes"] = Bson(deletesBson);

	return cmd;
}

unittest {
	auto query = Bson(["x": Bson(1)]);
	auto cmd = buildDeleteCommand("coll", [query], Bson.emptyObject, [1]);
	assert(cmd["delete"].get!string == "coll");
	assert(cmd["deletes"].get!(Bson[]).length == 1);
	assert(cmd["deletes"][0]["q"] == query);
	assert(cmd["deletes"][0]["limit"].get!int == 1);

	// missing limit defaults to 0
	auto noLimit = buildDeleteCommand("coll", [query], Bson.emptyObject, null);
	assert(noLimit["deletes"][0]["limit"].get!int == 0);

	// limit/collation/hint move into each statement, other options stay top level
	auto options = Bson(["ordered": Bson(true), "limit": Bson(5), "hint": Bson("idx")]);
	auto partitioned = buildDeleteCommand("coll", [query], options, null);
	assert(partitioned["ordered"].get!bool == true);
	assert(partitioned["limit"].isNull);
	assert(partitioned["deletes"][0]["hint"].get!string == "idx");
}

/** Assembles an `update` command from serialized queries, documents,
	per-update options and command options.

	The `arrayFilters`, `collation`, `hint` and `upsert` options belong inside
	each update statement rather than at the command level.
*/
Bson buildUpdateCommand(string collection, Bson[] queries, Bson[] documents, Bson[] perUpdateOptions, Bson optionsBson)
{
	alias FieldsMovedIntoChildren = AliasSeq!("arrayFilters", "collation", "hint", "upsert");

	Bson cmd = Bson.emptyObject;
	cmd["update"] = Bson(collection);
	foreach (string k, v; optionsBson.byKeyValue)
		if (!k.among!FieldsMovedIntoChildren)
			cmd[k] = v;

	Bson[] updatesBson = new Bson[queries.length];
	foreach (i, q; queries)
	{
		auto updateBson = Bson.emptyObject;
		updateBson["q"] = q;
		updateBson["u"] = documents[i];
		foreach (string k, v; optionsBson.byKeyValue)
			if (k.among!FieldsMovedIntoChildren)
				updateBson[k] = v;
		foreach (string k, v; perUpdateOptions[i].byKeyValue)
			updateBson[k] = v;
		updatesBson[i] = updateBson;
	}
	cmd["updates"] = Bson(updatesBson);

	return cmd;
}

unittest {
	auto query = Bson(["x": Bson(1)]);
	auto doc = Bson(["$set": Bson(["y": Bson(2)])]);
	auto perUpdate = Bson(["multi": Bson(true)]);
	auto options = Bson(["ordered": Bson(true), "upsert": Bson(true)]);

	auto cmd = buildUpdateCommand("coll", [query], [doc], [perUpdate], options);
	assert(cmd["update"].get!string == "coll");
	assert(cmd["ordered"].get!bool == true);
	assert(cmd["upsert"].isNull);

	auto stmt = cmd["updates"][0];
	assert(stmt["q"] == query);
	assert(stmt["u"] == doc);
	assert(stmt["upsert"].get!bool == true);
	assert(stmt["multi"].get!bool == true);
}

/** Builds the aggregation pipeline used by `countDocuments`.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#count-api-details)
*/
Bson[] buildCountPipeline(Bson filter, CountOptions options)
{
	Bson[] pipeline = [Bson(["$match": filter])];

	if (!options.skip.isNull)
		pipeline ~= Bson(["$skip": Bson(options.skip.get)]);

	if (!options.limit.isNull)
		pipeline ~= Bson(["$limit": Bson(options.limit.get)]);

	pipeline ~= Bson(["$group": Bson([
		"_id": Bson(1),
		"n": Bson(["$sum": Bson(1)])
	])]);

	return pipeline;
}

unittest {
	auto filter = Bson(["x": Bson(1)]);

	auto minimal = buildCountPipeline(filter, CountOptions.init);
	assert(minimal.length == 2);
	assert(minimal[0]["$match"] == filter);
	assert(minimal[1]["$group"]["n"]["$sum"].get!int == 1);

	CountOptions skipLimit;
	skipLimit.skip = 5;
	skipLimit.limit = 10;
	auto full = buildCountPipeline(filter, skipLimit);
	assert(full.length == 4);
	assert(full[1]["$skip"].get!long == 5);
	assert(full[2]["$limit"].get!long == 10);
}

/** Assembles an `aggregate` command and its cursor batching parameters.

	When `explain` is set, the spec recommends omitting the `cursor` field.
*/
CursorCommand buildAggregateCommand(string collection, string database, Bson pipeline, AggregateOptions options, ReadPreference pref = ReadPreference.primary, string[string][] tagSets = null)
{
	Bson cmd = Bson.emptyObject;
	cmd["aggregate"] = Bson(collection);
	cmd["$db"] = Bson(database);
	cmd["pipeline"] = pipeline;
	foreach (string k, v; serializeToBson(options).byKeyValue)
	{
		if (!options.explain.isNull && options.explain.get && k == "cursor")
			continue;
		cmd[k] = v;
	}

	if (pref != ReadPreference.primary)
		cmd["$readPreference"] = readPreferenceBson(pref, tagSets);

	return CursorCommand(cmd,
		!options.batchSize.isNull ? options.batchSize.get : 0,
		!options.maxAwaitTimeMS.isNull ? options.maxAwaitTimeMS.get.msecs
			: !options.maxTimeMS.isNull ? options.maxTimeMS.get.msecs
			: Duration.max);
}

unittest {
	auto pipeline = Bson([Bson(["$match": Bson.emptyObject])]);

	auto plain = buildAggregateCommand("coll", "db", pipeline, AggregateOptions.init);
	assert(plain.command["aggregate"].get!string == "coll");
	assert(plain.command["$db"].get!string == "db");
	assert(plain.command["pipeline"] == pipeline);
	assert(plain.batchSize == 0);
	assert(plain.getMoreMaxTime == Duration.max);

	AggregateOptions timed;
	timed.maxTimeMS = 1200;
	auto timedResult = buildAggregateCommand("coll", "db", pipeline, timed);
	assert(timedResult.getMoreMaxTime == 1200.msecs);

	// maxAwaitTimeMS takes precedence over maxTimeMS for getMore
	AggregateOptions awaiting;
	awaiting.maxAwaitTimeMS = 900;
	awaiting.maxTimeMS = 1200;
	auto awaitingResult = buildAggregateCommand("coll", "db", pipeline, awaiting);
	assert(awaitingResult.getMoreMaxTime == 900.msecs);

	// the cursor field is normally present, but omitted when explain is set
	assert(!plain.command["cursor"].isNull);
	AggregateOptions explained;
	explained.explain = true;
	auto explainedResult = buildAggregateCommand("coll", "db", pipeline, explained);
	assert(explainedResult.command["cursor"].isNull);

	// a non-primary read preference is injected as $readPreference
	auto secondaryRead = buildAggregateCommand("coll", "db", pipeline, AggregateOptions.init, ReadPreference.secondary);
	assert(secondaryRead.command["$readPreference"]["mode"].get!string == "secondary");

	// primary (the default) is omitted from the wire
	auto primaryRead = buildAggregateCommand("coll", "db", pipeline, AggregateOptions.init, ReadPreference.primary);
	assert(primaryRead.command["$readPreference"].isNull);
	auto defaultedRead = buildAggregateCommand("coll", "db", pipeline, AggregateOptions.init);
	assert(defaultedRead.command["$readPreference"].isNull);

	// the configured readPreferenceTags reach the aggregate $readPreference too
	string[string][] tags = [["dc": "east"]];
	auto taggedRead = buildAggregateCommand("coll", "db", pipeline, AggregateOptions.init, ReadPreference.secondary, tags);
	assert(taggedRead.command["$readPreference"] == readPreferenceBson(ReadPreference.secondary, tags),
		"the aggregate $readPreference carries the configured readPreferenceTags");
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
