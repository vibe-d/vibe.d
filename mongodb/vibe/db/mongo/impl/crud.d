/**
	MongoDB CRUD API definitions.

	Copyright: © 2022 Jan Jurzitza
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Jurzitza
*/
module vibe.db.mongo.impl.crud;

import core.time;

import vibe.db.mongo.connection : MongoException;
import vibe.db.mongo.collection;
import vibe.data.bson;

import std.typecons;

@safe:

deprecated("Use UpdateOptions instead")
enum UpdateFlags {
	none         = 0,    /// Normal update of a single document.
	upsert       = 1<<0, /// Creates a document if none exists.
	multiUpdate  = 1<<1, /// Updates all matching documents.

	None = none, /// Deprecated compatibility alias
	Upsert = upsert, /// Deprecated compatibility alias
	MultiUpdate = multiUpdate /// Deprecated compatibility alias
}

deprecated("Use InsertOneOptions or InsertManyOptions instead")
enum InsertFlags {
	none             = 0,    /// Normal insert.
	continueOnError  = 1<<0, /// For multiple inserted documents, continues inserting further documents after a failure.

	None = none, /// Deprecated compatibility alias
	ContinueOnError = continueOnError /// Deprecated compatibility alias
}

deprecated("Use FindOptions instead")
enum QueryFlags {
	none             = 0,    /// Normal query
	tailableCursor   = 1<<1, ///
	slaveOk          = 1<<2, ///
	oplogReplay      = 1<<3, ///
	noCursorTimeout  = 1<<4, ///
	awaitData        = 1<<5, ///
	exhaust          = 1<<6, ///
	partial          = 1<<7, ///

	None = none, /// Deprecated compatibility alias
	TailableCursor = tailableCursor, /// Deprecated compatibility alias
	SlaveOk = slaveOk, /// Deprecated compatibility alias
	OplogReplay = oplogReplay, /// Deprecated compatibility alias
	NoCursorTimeout = noCursorTimeout, /// Deprecated compatibility alias
	AwaitData = awaitData, /// Deprecated compatibility alias
	Exhaust = exhaust, /// Deprecated compatibility alias
	Partial = partial /// Deprecated compatibility alias
}

deprecated("Use DeleteOptions instead")
enum DeleteFlags {
	none          = 0,
	singleRemove  = 1<<0,

	None = none, /// Deprecated compatibility alias
	SingleRemove = singleRemove /// Deprecated compatibility alias
}

/**
	See_Also: $(LINK https://docs.mongodb.com/manual/reference/command/find/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#id16)
*/
struct FindOptions
{
	/**
		Enables writing to temporary files on the server. When set to true, the server
		can write temporary data to disk while executing the find operation.

		This option is only supported by servers >= 4.4.
	*/
	@embedNullable @errorBefore(WireVersion.v44)
	Nullable!bool allowDiskUse;

	/**
		Get partial results from a mongos if some shards are down (instead of throwing an error).
	*/
	@embedNullable
	Nullable!bool allowPartialResults;

	/**
		The number of documents to return per batch.
	*/
	@embedNullable
	Nullable!int batchSize;

	/**
		Determines whether to close the cursor after the first batch.

		Set automatically if limit < 0 || batchSize < 0.
	*/
	@embedNullable
	package Nullable!bool singleBatch;

	/**
		Collation allows users to specify language-specific rules for string
		comparison, such as rules for letter-case and accent marks.
	*/
	@embedNullable @errorBefore(WireVersion.v34)
	Nullable!Collation collation;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;

	/**
		Indicates the type of cursor to use. This value includes both
		the tailable and awaitData options.
	*/
	@ignore CursorType cursorType;

	/**
		The index to use. Specify either the index name as a string or the index
		key pattern.

		If specified, then the query system will only consider plans using the
		hinted index.
	*/
	@embedNullable
	Nullable!Bson hint;

	/**
		The maximum number of documents to return.

		A negative limit only returns a single batch of results.
	*/
	@embedNullable
	Nullable!long limit;

	/**
		The exclusive upper bound for a specific index.
	*/
	@embedNullable
	Nullable!Bson max;

	/**
		The maximum amount of time for the server to wait on new documents to
		satisfy a tailable cursor query. This only applies to a TAILABLE_AWAIT
		cursor. When the cursor is not a TAILABLE_AWAIT cursor, this option is
		ignored.

		Note: This option is specified as "maxTimeMS" in the getMore command and
		not provided as part of the initial find command.
	*/
	@embedNullable @since(WireVersion.v32)
	Nullable!long maxAwaitTimeMS;

	/// ditto
	void maxAwaitTime(Duration d)
	@safe {
		maxAwaitTimeMS = cast(long)d.total!"msecs";
	}

	/**
		Maximum number of documents or index keys to scan when executing the query.
	*/
	@embedNullable @deprecatedSince(WireVersion.v40)
	Nullable!long maxScan;

	/**
		The maximum amount of time to allow the query to run.
	*/
	@embedNullable
	Nullable!long maxTimeMS;

	/// ditto
	void maxTime(Duration d)
	@safe {
		maxTimeMS = cast(long)d.total!"msecs";
	}

	/**
		The exclusive lower bound for a specific index.
	*/
	@embedNullable
	Nullable!Bson min;

	/**
		The server normally times out idle cursors after an inactivity period
		(10 minutes) to prevent excess memory use. Set this option to prevent
		that.
	*/
	@embedNullable
	Nullable!bool noCursorTimeout;

	/**
		Enables optimization when querying the oplog for a range of ts values.

		Note: this option is intended for internal replication use only.
	*/
	@embedNullable @deprecatedSince(WireVersion.v44)
	Nullable!bool oplogReplay;

	/**
		Limits the fields to return for all matching documents.
	*/
	@embedNullable
	Nullable!Bson projection;

	/**
		If true, returns only the index keys in the resulting documents.
	*/
	@embedNullable
	Nullable!bool returnKey;

	/**
		Determines whether to return the record identifier for each document. If
		true, adds a field $recordId to the returned documents.
	*/
	@embedNullable
	Nullable!bool showRecordId;

	/**
		The number of documents to skip before returning.
	*/
	@embedNullable
	Nullable!long skip;

	/**
		Prevents the cursor from returning a document more than once because of
		an intervening write operation.
	*/
	@embedNullable @deprecatedSince(WireVersion.v40)
	Nullable!bool snapshot;

	/**
		The order in which to return matching documents.
	*/
	@embedNullable
	Nullable!Bson sort;

	/**
		If true, when an insert fails, return without performing the remaining
		writes. If false, when a write fails, continue with the remaining writes,
		if any.

		Defaults to true.
	*/
	@embedNullable
	Nullable!bool ordered;

	/**
		Specifies the read concern. Only compatible with a write stage. (e.g.
		`$out`, `$merge`)

		Aggregate commands do not support the $(D ReadConcern.Level.linearizable)
		level.

		Standards: $(LINK https://github.com/mongodb/specifications/blob/7745234f93039a83ae42589a6c0cdbefcffa32fa/source/read-write-concern/read-write-concern.rst)
	*/
	@embedNullable Nullable!ReadConcern readConcern;
}

///
enum CursorType
{
	/**
		The default value. A vast majority of cursors will be of this type.
	*/
	nonTailable,
	/**
		Tailable means the cursor is not closed when the last data is retrieved.
		Rather, the cursor marks the final object’s position. You can resume
		using the cursor later, from where it was located, if more data were
		received. Like any “latent cursor”, the cursor may become invalid at
		some point (CursorNotFound) – for example if the final object it
		references were deleted.
	*/
	tailable,
	/**
		Combines the tailable option with awaitData, as defined below.

		Use with TailableCursor. If we are at the end of the data, block for a
		while rather than returning no data. After a timeout period, we do
		return as normal. The default is true.
	*/
	tailableAwait,
}

/**
	See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/command/distinct/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#id16)
*/
struct DistinctOptions
{
	/**
		Collation allows users to specify language-specific rules for string
		comparison, such as rules for letter-case and accent marks.
	*/
	@embedNullable @errorBefore(WireVersion.v34)
	Nullable!Collation collation;

	/**
		The maximum amount of time to allow the query to run.
	*/
	@embedNullable
	Nullable!long maxTimeMS;

	/// ditto
	void maxTime(Duration d)
	@safe {
		maxTimeMS = cast(long)d.total!"msecs";
	}

	/**
		Specifies the read concern. Only compatible with a write stage. (e.g.
		`$out`, `$merge`)

		Aggregate commands do not support the $(D ReadConcern.Level.linearizable)
		level.

		Standards: $(LINK https://github.com/mongodb/specifications/blob/7745234f93039a83ae42589a6c0cdbefcffa32fa/source/read-write-concern/read-write-concern.rst)
	*/
	@embedNullable Nullable!ReadConcern readConcern;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;
}

/**
	See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/command/count/)
		  and $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.countDocuments/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#id16)
*/
struct CountOptions
{
	/**
		Collation allows users to specify language-specific rules for string
		comparison, such as rules for letter-case and accent marks.
	*/
	@embedNullable @errorBefore(WireVersion.v34)
	Nullable!Collation collation;

	/**
		The index to use. Specify either the index name as a string or the index
		key pattern.

		If specified, then the query system will only consider plans using the
		hinted index.
	*/
	@embedNullable
	Nullable!Bson hint;

	/**
		The maximum number of documents to return.

		A negative limit only returns a single batch of results.
	*/
	@embedNullable
	Nullable!long limit;

	/**
		The maximum amount of time to allow the query to run.
	*/
	@embedNullable
	Nullable!long maxTimeMS;

	/// ditto
	void maxTime(Duration d)
	@safe {
		maxTimeMS = cast(long)d.total!"msecs";
	}

	/**
		The number of documents to skip before returning.
	*/
	@embedNullable
	Nullable!long skip;

	/**
		Specifies the read concern. Only compatible with a write stage. (e.g.
		`$out`, `$merge`)

		Aggregate commands do not support the $(D ReadConcern.Level.linearizable)
		level.

		Standards: $(LINK https://github.com/mongodb/specifications/blob/7745234f93039a83ae42589a6c0cdbefcffa32fa/source/read-write-concern/read-write-concern.rst)
	*/
	@embedNullable Nullable!ReadConcern readConcern;
}

/**
	See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/db.collection.estimatedDocumentCount/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#id16)
*/
struct EstimatedDocumentCountOptions
{
	/**
		The maximum amount of time to allow the query to run.
	*/
	@embedNullable
	Nullable!long maxTimeMS;

	/// ditto
	void maxTime(Duration d)
	@safe {
		maxTimeMS = cast(long)d.total!"msecs";
	}
}

/**
	Represents available options for an aggregate call

	See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/command/aggregate/#dbcmd.aggregate)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#id16)
*/
struct AggregateOptions
{
	// undocumented because this field isn't a spec field because it is
	// out-of-scope for a driver
	@embedNullable Nullable!bool explain;

	/**
		Enables writing to temporary files. When set to true, aggregation
		operations can write data to the _tmp subdirectory in the dbPath
		directory.
	*/
	@embedNullable
	Nullable!bool allowDiskUse;

	// non-optional since 3.6
	// get/set by `batchSize`, undocumented in favor of that field
	CursorInitArguments cursor;

	/// Specifies the initial batch size for the cursor.
	ref inout(Nullable!int) batchSize()
	return @property inout @safe pure nothrow @nogc @ignore {
		return cursor.batchSize;
	}

	/**
		If true, allows the write to opt-out of document level validation.
		This only applies when the $out or $merge stage is specified.
	*/
	@embedNullable @since(WireVersion.v32)
	Nullable!bool bypassDocumentValidation;

	/**
		Collation allows users to specify language-specific rules for string
		comparison, such as rules for letter-case and accent marks.
	*/
	@embedNullable @errorBefore(WireVersion.v34)
	Nullable!Collation collation;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;

	/**
		The maximum amount of time for the server to wait on new documents to
		satisfy a tailable cursor query. This only applies to a TAILABLE_AWAIT
		cursor. When the cursor is not a TAILABLE_AWAIT cursor, this option is
		ignored.

		Note: This option is specified as "maxTimeMS" in the getMore command and
		not provided as part of the initial find command.
	*/
	@embedNullable @since(WireVersion.v32)
	Nullable!long maxAwaitTimeMS;

	/// ditto
	void maxAwaitTime(Duration d)
	@safe {
		maxAwaitTimeMS = cast(long)d.total!"msecs";
	}

	/**
		Specifies a time limit in milliseconds for processing operations on a
		cursor. If you do not specify a value for maxTimeMS, operations will not
		time out.
	*/
	@embedNullable
	Nullable!long maxTimeMS;

	/// ditto
	void maxTime(Duration d)
	@safe {
		maxTimeMS = cast(long)d.total!"msecs";
	}

	/**
		The index to use for the aggregation. The index is on the initial
		collection / view against which the aggregation is run.

		The hint does not apply to $lookup and $graphLookup stages.

		Specify the index either by the index name as a string or the index key
		pattern. If specified, then the query system will only consider plans
		using the hinted index.
	*/
	@embedNullable
	Nullable!Bson hint;

	/**
		Map of parameter names and values. Values must be constant or closed
		expressions that do not reference document fields. Parameters can then
		be accessed as variables in an aggregate expression context
		(e.g. `"$$var"`).

		This option is only supported by servers >= 5.0. Older servers >= 2.6 (and possibly earlier) will report an error for using this option.
	*/
	@embedNullable
	Nullable!Bson let;

	/**
		Specifies the read concern. Only compatible with a write stage. (e.g.
		`$out`, `$merge`)

		Aggregate commands do not support the $(D ReadConcern.Level.linearizable)
		level.

		Standards: $(LINK https://github.com/mongodb/specifications/blob/7745234f93039a83ae42589a6c0cdbefcffa32fa/source/read-write-concern/read-write-concern.rst)
	*/
	@embedNullable Nullable!ReadConcern readConcern;
}

/**
	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#insert-update-replace-delete-and-bulk-writes)
*/
struct BulkWriteOptions {

	/**
		If true, when a write fails, return without performing the remaining
		writes. If false, when a write fails, continue with the remaining writes,
		if any.

		Defaults to true.
	*/
	@embedNullable
	Nullable!bool ordered;

	/**
		If true, allows the write to opt-out of document level validation.

		For servers < 3.2, this option is ignored and not sent as document
		validation is not available.

		For unacknowledged writes using OP_INSERT, OP_UPDATE, or OP_DELETE, the
		driver MUST raise an error if the caller explicitly provides a value.
	*/
	@embedNullable
	Nullable!bool bypassDocumentValidation;

	/**
		A document that expresses the
		$(LINK2 https://www.mongodb.com/docs/manual/reference/write-concern/,write concern)
		of the insert command. Omit to use the default write concern.
	*/
	@embedNullable
	Nullable!WriteConcern writeConcern;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;
}

/**
	See_Also: $(LINK https://docs.mongodb.com/manual/reference/command/insert/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#insert-update-replace-delete-and-bulk-writes)
*/
struct InsertOneOptions {
	/**
		If true, allows the write to opt-out of document level validation.

		For servers < 3.2, this option is ignored and not sent as document
		validation is not available.
	*/
	@embedNullable
	Nullable!bool bypassDocumentValidation;

	/**
		A document that expresses the
		$(LINK2 https://www.mongodb.com/docs/manual/reference/write-concern/,write concern)
		of the insert command. Omit to use the default write concern.
	*/
	@embedNullable
	Nullable!WriteConcern writeConcern;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;
}

/**
	See_Also: $(LINK https://docs.mongodb.com/manual/reference/command/insert/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#insert-update-replace-delete-and-bulk-writes)
*/
struct InsertManyOptions {
	/**
		If true, allows the write to opt-out of document level validation.

		For servers < 3.2, this option is ignored and not sent as document
		validation is not available.
	*/
	@embedNullable
	Nullable!bool bypassDocumentValidation;

	/**
		If true, when an insert fails, return without performing the remaining
		writes. If false, when a write fails, continue with the remaining writes,
		if any.

		Defaults to true.
	*/
	@embedNullable
	Nullable!bool ordered;

	/**
		A document that expresses the
		$(LINK2 https://www.mongodb.com/docs/manual/reference/write-concern/,write concern)
		of the insert command. Omit to use the default write concern.
	*/
	@embedNullable
	Nullable!WriteConcern writeConcern;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;
}

/**
	See_Also: $(LINK https://docs.mongodb.com/manual/reference/command/update/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#insert-update-replace-delete-and-bulk-writes)
*/
struct UpdateOptions {
	/**
		A set of filters specifying to which array elements an update should
		apply.
	*/
	@embedNullable @errorBefore(WireVersion.v36)
	Nullable!(Bson[]) arrayFilters;

	/**
		If true, allows the write to opt-out of document level validation.

		For servers < 3.2, this option is ignored and not sent as document
		validation is not available.
	*/
	@embedNullable @since(WireVersion.v32)
	Nullable!bool bypassDocumentValidation;

	/**
		Collation allows users to specify language-specific rules for string
		comparison, such as rules for letter-case and accent marks.
	*/
	@embedNullable @errorBefore(WireVersion.v34)
	Nullable!Collation collation;

	/**
		The index to use. Specify either the index name as a string or the index
		key pattern.

		If specified, then the query system will only consider plans using the
		hinted index.
	*/
	@embedNullable
	Nullable!Bson hint;

	/**
		When true, creates a new document if no document matches the query.
	*/
	@embedNullable
	Nullable!bool upsert;

	/**
		A document that expresses the
		$(LINK2 https://www.mongodb.com/docs/manual/reference/write-concern/,write concern)
		of the insert command. Omit to use the default write concern.
	*/
	@embedNullable
	Nullable!WriteConcern writeConcern;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;
}

/**
	See_Also: $(LINK https://docs.mongodb.com/manual/reference/command/update/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#insert-update-replace-delete-and-bulk-writes)
*/
struct ReplaceOptions {
	/**
		If true, allows the write to opt-out of document level validation.

		For servers < 3.2, this option is ignored and not sent as document
		validation is not available.
	*/
	@embedNullable
	Nullable!bool bypassDocumentValidation;

	/**
		Collation allows users to specify language-specific rules for string
		comparison, such as rules for letter-case and accent marks.
	*/
	@embedNullable @errorBefore(WireVersion.v34)
	Nullable!Collation collation;

	/**
		The index to use. Specify either the index name as a string or the index
		key pattern.

		If specified, then the query system will only consider plans using the
		hinted index.
	*/
	@embedNullable
	Nullable!Bson hint;

	/**
		When true, creates a new document if no document matches the query.
	*/
	@embedNullable
	Nullable!bool upsert;

	/**
		A document that expresses the
		$(LINK2 https://www.mongodb.com/docs/manual/reference/write-concern/,write concern)
		of the insert command. Omit to use the default write concern.
	*/
	@embedNullable
	Nullable!WriteConcern writeConcern;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;
}

/**
	See_Also: $(LINK https://docs.mongodb.com/manual/reference/command/delete/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/525dae0aa8791e782ad9dd93e507b60c55a737bb/source/crud/crud.rst#insert-update-replace-delete-and-bulk-writes)
*/
struct DeleteOptions {
	/**
		Collation allows users to specify language-specific rules for string
		comparison, such as rules for letter-case and accent marks.
	*/
	@embedNullable @errorBefore(WireVersion.v34)
	Nullable!Collation collation;

	/**
		The index to use. Specify either the index name as a string or the index
		key pattern.

		If specified, then the query system will only consider plans using the
		hinted index.
	*/
	@embedNullable
	Nullable!Bson hint;

	/**
		A document that expresses the
		$(LINK2 https://www.mongodb.com/docs/manual/reference/write-concern/,write concern)
		of the insert command. Omit to use the default write concern.
	*/
	@embedNullable
	Nullable!WriteConcern writeConcern;

	/**
		Users can specify an arbitrary string to help trace the operation
		through the database profiler, currentOp, and logs.
	*/
	@embedNullable
	Nullable!string comment;

	/**
		Map of parameter names and values. Values must be constant or closed
		expressions that do not reference document fields. Parameters can then
		be accessed as variables in an aggregate expression context
		(e.g. `"$$var"`).

		This option is only supported by servers >= 5.0. Older servers >= 2.6 (and possibly earlier) will report an error for using this option.
	*/
	@embedNullable
	Nullable!Bson let;
}

struct InsertOneResult {
	/**
		The identifier that was automatically generated, if not set.
	*/
	BsonObjectID insertedId;
}

struct InsertManyResult {
	/**
		The identifiers that were automatically generated, if not set.
	*/
	BsonObjectID[size_t] insertedIds;
	/**
		The number of documents that were inserted.
	*/
	long insertedCount;
}

struct DeleteResult {
	/**
		The number of documents that were deleted.
	*/
	long deletedCount;
}

struct UpdateResult {
	/**
		The number of documents that matched the filter.
	*/
	long matchedCount;

	/**
		The number of documents that were modified.
	*/
	long modifiedCount;

	/**
		The identifier of the inserted document if an upsert took place. Can be
		none if no upserts took place, can be multiple if using the updateImpl
		helper.
	*/
	BsonObjectID[] upsertedIds;
}

/**
	Describes a failed write command result for a single document.

	See_Also: $(LINK https://www.mongodb.com/docs/manual/reference/method/WriteResult/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/0b6b96b758259edc91c2fc475bcf08eea54e08e2/source/crud/crud.rst#L1745)
*/
struct BulkWriteError
{
	/**
	 * An integer value identifying the write error.
	 */
	int code;
	/**
	 * A document providing more information about the write error (e.g. details
	 * pertaining to document validation).
	 */
	@optional @name("errInfo") Bson details;
	/**
	 * A description of the error.
	 */
	@optional @name("errmsg") string message;
	/**
	 * The index of the request that errored.
	 */
	@optional int index;
}

/**
 * Exception for partially or fully failed writes from `insert`, `update` or
 * `delete`.
 */
class MongoBulkWriteException : MongoException
{
@safe:
	BulkWriteError[] errors;

	this(BulkWriteError[] errors, string file = __FILE__,
			size_t line = __LINE__, Throwable next = null)
	{
		import std.algorithm : map;
		import std.string : join;

		super("Failed to write all documents:\n"
			~ errors.map!(e => "- " ~ e.message).join("\n"), file, line, next);

		this.errors = errors;
	}
}

/**
 * Handles the raw DB response from `insert`, `update` or `delete` operations.
 *
 * If the `countField` template argument is set, that field is set on `result`
 * to `dbResult["n"]`, if it exists.
 */
package(vibe.db.mongo) void handleWriteResult(string countField = null, T)(
	Bson dbResult, ref T result, string file = __FILE__, size_t line = __LINE__)
{
	auto dbObject = dbResult.get!(Bson[string]);
	static if (countField != null)
	{
		if (auto n = "n" in dbObject)
			__traits(getMember, result, countField) = n.to!long;
	}

	if (auto writeErrors = "writeErrors" in dbObject)
	{
		if (writeErrors.type == Bson.Type.array)
		{
			auto errors = deserializeBson!(BulkWriteError[])(*writeErrors);
			if (errors.length > 0)
				throw new MongoBulkWriteException(errors, file, line);
		}
	}
}
