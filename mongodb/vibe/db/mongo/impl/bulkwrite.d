/**
	MongoDB 8.0 server-level `bulkWrite` write models, command building, response
	parsing, and the client bulk-write exception. Extracted from impl.crud.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.bulkwrite;

import vibe.data.bson;                              // Bson, BsonObjectID, @embedNullable, @ignore, serializeToBson, deserializeBson
import std.typecons : Nullable;
import std.exception : enforce;
import vibe.db.mongo.connection : MongoException;   // base class of MongoClientBulkWriteException
import vibe.db.mongo.collection : WriteConcern;     // ClientBulkWriteOptions.writeConcern
import vibe.db.mongo.impl.crud;                     // BulkWriteError, InsertOneResult, UpdateResult, DeleteResult, WriteConcernOption

@safe:

/**
	Summary result of a server-level `MongoClient.bulkWrite`.

	Holds the aggregate counts reported by the server across every operation in
	the batch, plus `acknowledged` (whether the write concern was acknowledged).
	When verbose results were requested, it also carries the optional per-operation
	result maps (`insertResults`, `updateResults`, `deleteResults`) keyed by the
	operation's index in the batch; otherwise those maps stay empty.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/crud/bulk-write.md)
*/
struct ClientBulkWriteResult {
	bool acknowledged;
	long insertedCount;
	long matchedCount;
	long modifiedCount;
	long upsertedCount;
	long deletedCount;
	bool hasVerboseResults;            /// Whether per-operation verbose results are present.
	InsertOneResult[size_t] insertResults; /// Per-insert results keyed by op index; populated only when verbose results were requested.
	UpdateResult[size_t]    updateResults; /// Per-update results keyed by op index; populated only when verbose results were requested.
	DeleteResult[size_t]    deleteResults; /// Per-delete results keyed by op index; populated only when verbose results were requested.
}

/**
	Parses a server bulkWrite response document into a `ClientBulkWriteResult`.

	Reads the top-level `n*` counts and `ok` summary fields. Pure value-in,
	value-out function, so the cursor/IO handling stays at the call-site edge.

	Params:
		response = the server's bulkWrite reply document.
		models = the originating write models, used to classify per-operation
			verbose entries by type when mapping them by index.
		verbose = whether to populate the per-operation result maps. The maps are
			keyed by each operation's index in the batch; with `verbose` false they
			stay empty. See `collectVerboseResults` for the per-op classification.
*/
/// A server command response is acknowledged when its `ok` field is 1.0.
private bool isAcknowledged(Bson response) @safe {
	return response["ok"].get!double == 1.0;
}

ClientBulkWriteResult parseClientBulkWriteResult(Bson response, ClientBulkWriteModel[] models = null, bool verbose = false) @safe {
	ClientBulkWriteResult result;

	// An unacknowledged (w:0) write returns ok:1 but no result counts or cursor. Report
	// acknowledged=false with zero counts instead of throwing on the missing fields.
	if (response.tryIndex("nInserted").isNull) {
		result.acknowledged = false;
		return result;
	}

	result.acknowledged   = isAcknowledged(response);
	result.insertedCount  = response["nInserted"].to!long;
	result.matchedCount   = response["nMatched"].to!long;
	result.modifiedCount  = response["nModified"].to!long;
	result.upsertedCount  = response["nUpserted"].to!long;
	result.deletedCount   = response["nDeleted"].to!long;

	if (verbose)
		collectVerboseResults(response, models, result);

	auto writeErrors = collectClientBulkWriteErrors(response);
	auto writeConcernErrors = collectWriteConcernErrors(response);
	if (writeErrors.length > 0 || writeConcernErrors.length > 0) {
		auto ex = new MongoClientBulkWriteException(writeErrors, writeConcernErrors);
		ex.partialResult = result;
		throw ex;
	}

	return result;
}

/**
	Returns the entries of a server bulkWrite response's `cursor.firstBatch`,
	or `null` when no cursor or no firstBatch is present. Single source of truth
	for walking the per-operation result batch.
*/
private Bson[] firstBatchEntries(Bson response) @safe {
	auto cursor = response.tryIndex("cursor");
	if (cursor.isNull)
		return null;

	auto firstBatch = cursor.get.tryIndex("firstBatch");
	if (firstBatch.isNull)
		return null;

	return firstBatch.get.get!(Bson[]);
}

/**
	Scans a server bulkWrite response's `cursor.firstBatch` for per-operation
	successes and records them as verbose results on `result`, keyed by op index
	and classified by `models[idx].type`.

	Sets `hasVerboseResults` and populates the matching per-op result map for each
	successful entry. Returns early (leaving `result` untouched) when there is no
	cursor batch. Mirrors `collectClientBulkWriteErrors`'s flat, early-return shape.
*/
private void collectVerboseResults(Bson response, ClientBulkWriteModel[] models, ref ClientBulkWriteResult result) @safe {
	auto cursor = response.tryIndex("cursor");
	if (cursor.isNull)
		return;

	if (cursor.get.tryIndex("firstBatch").isNull)
		return;

	result.hasVerboseResults = true;

	foreach (entry; firstBatchEntries(response)) {
		if (entry["ok"].get!double != 1.0)
			continue;

		size_t idx = cast(size_t) entry["idx"].to!long;
		if (idx >= models.length)
			continue;

		final switch (models[idx].type) {
			case ClientBulkWriteType.deleteOne:
			case ClientBulkWriteType.deleteMany:
				result.deleteResults[idx] = DeleteResult(entry["n"].to!long);
				break;
			case ClientBulkWriteType.updateOne:
			case ClientBulkWriteType.updateMany:
			case ClientBulkWriteType.replaceOne:
				UpdateResult ur;
				ur.modifiedCount = entry["nModified"].to!long;
				auto upserted = entry.tryIndex("upserted");
				// An upsert is reported in `upserted`/nUpserted, not as a match: exclude it
				// from matchedCount (n - 1) and record its id (any BSON type).
				if (!upserted.isNull) {
					ur.matchedCount = entry["n"].to!long - 1;
					ur.upsertedIds = [upserted.get["_id"]];
				} else {
					ur.matchedCount = entry["n"].to!long;
				}
				result.updateResults[idx] = ur;
				break;
			case ClientBulkWriteType.insertOne:
				result.insertResults[idx] = InsertOneResult(models[idx].document["_id"]);
				break;
		}
	}
}

/**
	Scans a server bulkWrite response's `cursor.firstBatch` for per-operation
	failures, mapping each failed op index to its `BulkWriteError`.

	Returns an empty map when there is no cursor batch or every entry succeeded.
	Pure value-in, value-out so it stays free of cursor/IO handling.
*/
private BulkWriteError[size_t] collectClientBulkWriteErrors(Bson response) @safe {
	BulkWriteError[size_t] writeErrors;

	foreach (entry; firstBatchEntries(response)) {
		if (entry["ok"].get!double == 1.0)
			continue;

		size_t idx = cast(size_t) entry["idx"].to!long;
		BulkWriteError err;
		err.code = entry["code"].get!int;
		err.index = cast(int) idx;
		auto errmsg = entry.tryIndex("errmsg");
		if (!errmsg.isNull)
			err.message = errmsg.get.get!string;
		// Preserve errInfo (e.g. document-validation details) as BulkWriteError.details.
		auto errInfo = entry.tryIndex("errInfo");
		if (!errInfo.isNull)
			err.details = errInfo.get;
		writeErrors[idx] = err;
	}

	return writeErrors;
}

/**
	Scans a server bulkWrite response for a top-level `writeConcernError`,
	returning it as a single-element list or empty when absent.

	Mirrors `collectClientBulkWriteErrors`'s flat, early-return shape.
*/
private BulkWriteError[] collectWriteConcernErrors(Bson response) @safe {
	BulkWriteError[] errors;

	auto wce = response.tryIndex("writeConcernError");
	if (wce.isNull)
		return errors;

	errors ~= deserializeBson!BulkWriteError(wce.get);
	return errors;
}

/**
 * Thrown by `MongoClient.bulkWrite` when one or more individual operations of a
 * client-level bulk write fail, or when the server reports a write-concern error.
 *
 * `writeErrors` maps each failed operation index to its `BulkWriteError`.
 *
 * See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/crud/bulk-write.md)
 */
class MongoClientBulkWriteException : MongoException
{
@safe:
	BulkWriteError[size_t] writeErrors;
	/// Write-concern failures reported by the server even though the writes may have applied.
	BulkWriteError[] writeConcernErrors;
	/// Top-level summary counts for the writes that did apply before the error was raised.
	Nullable!ClientBulkWriteResult partialResult;

	this(BulkWriteError[size_t] writeErrors, BulkWriteError[] writeConcernErrors = null,
			string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		this.writeErrors = writeErrors;
		this.writeConcernErrors = writeConcernErrors;
		super(bulkWriteErrorMessage(writeErrors.length > 0, writeConcernErrors.length > 0), file, line, next);
	}
}

private string bulkWriteErrorMessage(bool hasWriteErrors, bool hasWriteConcernErrors) @safe pure nothrow
{
	if (hasWriteErrors && hasWriteConcernErrors)
		return "Client bulk write encountered write errors and write-concern errors";
	if (hasWriteConcernErrors)
		return "Client bulk write encountered write-concern errors";
	return "Client bulk write encountered write errors";
}

/**
	The kind of write a single $(D ClientBulkWriteModel) represents inside a
	server-level `bulkWrite` command.

	See_Also: $(LINK https://www.mongodb.com/docs/upcoming/reference/command/bulkwrite/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/master/source/crud/bulk-write.md)
*/
enum ClientBulkWriteType {
	insertOne, /// Insert a single document.
	updateOne, /// Update the first document matching the filter.
	updateMany, /// Update all documents matching the filter.
	replaceOne, /// Replace the first document matching the filter.
	deleteOne, /// Delete the first document matching the filter.
	deleteMany /// Delete all documents matching the filter.
}

/**
	A single write operation passed to the server-level `bulkWrite` command,
	carrying the target namespace, the operation $(D ClientBulkWriteType) and the
	operation document.

	Construct one via the write-model factories: $(D insertOne), $(D updateOne),
	$(D updateMany), $(D replaceOne), $(D deleteOne) and $(D deleteMany).

	Field-usage matrix (every field not listed for a type stays `Bson.init`):

	$(TABLE
		$(TR $(TH type) $(TH fields used))
		$(TR $(TD insertOne) $(TD `document`))
		$(TR $(TD updateOne) $(TD `filter`, `update`))
		$(TR $(TD updateMany) $(TD `filter`, `update`))
		$(TR $(TD replaceOne) $(TD `filter`, `document` (the replacement is stored in `document`)))
		$(TR $(TD deleteOne) $(TD `filter`))
		$(TR $(TD deleteMany) $(TD `filter`))
	)

	Asymmetry note: `replaceOne` reuses the `document` field for its replacement,
	while `updateOne`/`updateMany` carry their change in the separate `update`
	field. `buildClientBulkWriteOp`'s `final switch` relies on this exact mapping.

	See_Also: $(LINK https://www.mongodb.com/docs/upcoming/reference/command/bulkwrite/)

	Standards: $(LINK https://github.com/mongodb/specifications/blob/master/source/crud/bulk-write.md)
*/
struct ClientBulkWriteModel {
	/// Fully-qualified `database.collection` namespace the write targets.
	string ns;
	/// The kind of write this model represents.
	ClientBulkWriteType type;
	/// The operation document (e.g. the document to insert).
	Bson document;
	/// The match filter for update writes.
	Bson filter;
	/// The update document for update writes.
	Bson update;

	/// Builds an `insertOne` write targeting `ns` for the given `document`.
	static ClientBulkWriteModel insertOne(string ns, Bson document) @safe {
		ClientBulkWriteModel model;
		model.ns = ns;
		model.type = ClientBulkWriteType.insertOne;
		model.document = document;
		return model;
	}

	/// Builds an `updateOne` write targeting `ns` for the given `filter` and `update`.
	static ClientBulkWriteModel updateOne(string ns, Bson filter, Bson update) @safe {
		enforce(isUpdateDocument(update), "bulkWrite updateOne requires an update document with $-operators or an aggregation pipeline");
		ClientBulkWriteModel model;
		model.ns = ns;
		model.type = ClientBulkWriteType.updateOne;
		model.filter = filter;
		model.update = update;
		return model;
	}

	/// Builds an `updateMany` write targeting `ns` for the given `filter` and `update`.
	static ClientBulkWriteModel updateMany(string ns, Bson filter, Bson update) @safe {
		enforce(isUpdateDocument(update), "bulkWrite updateMany requires an update document with $-operators or an aggregation pipeline");
		ClientBulkWriteModel model;
		model.ns = ns;
		model.type = ClientBulkWriteType.updateMany;
		model.filter = filter;
		model.update = update;
		return model;
	}

	/// Builds a `deleteOne` write targeting `ns` for the given `filter`.
	static ClientBulkWriteModel deleteOne(string ns, Bson filter) @safe {
		ClientBulkWriteModel model;
		model.ns = ns;
		model.type = ClientBulkWriteType.deleteOne;
		model.filter = filter;
		return model;
	}

	/// Builds a `deleteMany` write targeting `ns` for the given `filter`.
	static ClientBulkWriteModel deleteMany(string ns, Bson filter) @safe {
		ClientBulkWriteModel model;
		model.ns = ns;
		model.type = ClientBulkWriteType.deleteMany;
		model.filter = filter;
		return model;
	}

	/// Builds a `replaceOne` write targeting `ns`, matching `filter` and storing `replacement` in `document`.
	static ClientBulkWriteModel replaceOne(string ns, Bson filter, Bson replacement) @safe {
		enforce(!isUpdateDocument(replacement), "bulkWrite replaceOne requires a replacement document without $-operators");
		ClientBulkWriteModel model;
		model.ns = ns;
		model.type = ClientBulkWriteType.replaceOne;
		model.filter = filter;
		model.document = replacement;
		return model;
	}
}

/**
	Generates the `_id`s for insert models once, up front, so the same id is the
	one sent on the wire and the one reported back in the verbose result.

	Returns a new array where every `insertOne` document lacking an `_id` gets a
	freshly generated `BsonObjectID`. Non-insert models and inserts that already
	carry an `_id` are passed through unchanged. The input `models` array is never
	mutated.
*/
ClientBulkWriteModel[] ensureInsertIds(ClientBulkWriteModel[] models) @safe {
	auto result = models.dup;
	foreach (ref model; result) {
		if (model.type != ClientBulkWriteType.insertOne)
			continue;
		if (!model.document.tryIndex("_id").isNull)
			continue;
		// Append _id to an ordered copy (Bson.emptyObject) rather than rebuilding through a
		// Bson[string] AA, which would silently reorder the user's fields.
		Bson doc = Bson.emptyObject;
		foreach (string key, value; model.document.byKeyValue)
			doc[key] = value;
		doc["_id"] = Bson(BsonObjectID.generate());
		model.document = doc;
	}
	return result;
}

/**
	Command-level options for `MongoClient.bulkWrite`.

	Supports `verboseResults`, `ordered`, `bypassDocumentValidation`, `let`,
	`comment`, and `writeConcern`. Every field is unset by default and emitted
	onto the command only when explicitly set. An unacknowledged write concern
	(`w: 0`) cannot be combined with `verboseResults`.

	The wire `errorsOnly` field is not stored here: it is derived as the
	negation of `verboseResults`, defaulting to `errorsOnly: true` when
	`verboseResults` is unset.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/crud/bulk-write.md)
*/
struct ClientBulkWriteOptions {

	/// Request detailed per-operation results. Unset by default; drives the
	/// wire `errorsOnly` field as its negation. `@ignore`d so it never serializes
	/// onto the command; it is read directly in code, not via serialization.
	@embedNullable @ignore Nullable!bool verboseResults;

	/// Whether operations run in order. Unset by default; emitted only when set.
	@embedNullable Nullable!bool ordered;

	/// Skip document validation rules. Unset by default; emitted only when set.
	@embedNullable Nullable!bool bypassDocumentValidation;

	/// Variables usable in operation expressions. Unset by default; emitted only when set.
	@embedNullable Nullable!Bson let;

	/// Free-form comment attached to the command. Unset by default; emitted only when set.
	@embedNullable Nullable!Bson comment;

	mixin WriteConcernOption;
}

/**
	Builds the body of the MongoDB 8.0 server-level `bulkWrite` admin command
	from client bulk write models. Emits one `ops` entry per model and one
	`nsInfo` entry per distinct namespace, and each op references its namespace
	by its position in `nsInfo`.

	Throws: Exception if `models` is empty; at least one write operation is required.

	See_Also: $(LINK https://www.mongodb.com/docs/upcoming/reference/command/bulkwrite/)
*/
Bson buildClientBulkWriteCommand(ClientBulkWriteModel[] models, ClientBulkWriteOptions options = ClientBulkWriteOptions.init) @safe {
	enforce(models.length > 0, "bulkWrite requires at least one write operation");

	bool wantsVerbose = !options.verboseResults.isNull && options.verboseResults.get;
	bool unacknowledged = !options.writeConcern.isNull
		&& !options.writeConcern.get.w.isNull
		&& options.writeConcern.get.w.get == Bson(0);
	enforce(!(wantsVerbose && unacknowledged),
		"Cannot request unacknowledged write concern and verbose results");

	Bson[] ops;
	Bson[] nsInfo;
	size_t[string] nsIndexByName;

	foreach (model; models) {
		size_t nsIndex = nsIndexByName.require(model.ns, {
			nsInfo ~= Bson(["ns": Bson(model.ns)]);
			return nsInfo.length - 1;
		}());
		ops ~= buildClientBulkWriteOp(model, nsIndex);
	}

	bool errorsOnly = options.verboseResults.isNull ? true : !options.verboseResults.get;

	Bson cmd = Bson.emptyObject; // empty object because order is important: bulkWrite must be the first field
	cmd["bulkWrite"] = Bson(1);
	cmd["ops"] = Bson(ops);
	cmd["nsInfo"] = Bson(nsInfo);
	cmd["errorsOnly"] = Bson(errorsOnly);

	// verboseResults is transformed into errorsOnly above; it carries @ignore so it
	// is never serialized and cannot reach the wire. Every other set option field
	// passes through verbatim via @embedNullable serialization.
	auto optionFields = serializeToBson(options);
	foreach (string key, value; optionFields.byKeyValue)
		cmd[key] = value;

	return cmd;
}

/**
	The MongoDB 8.0 server-level `bulkWrite` write-batch limits, as advertised by
	the server's `hello` reply. Until the driver captures these from the connection
	(`ServerDescription` does not yet deserialize them), `bulkWrite` falls back to
	these protocol defaults: a single command may carry at most `maxWriteBatchSize`
	operations and the encoded command may not exceed `maxMessageSizeBytes`.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/crud/bulk-write.md)
*/
enum int defaultMaxWriteBatchSize = 100_000;
/// ditto
enum int defaultMaxMessageSizeBytes = 48 * 1024 * 1024;

/**
	Partitions client bulk-write ops into batches that each respect the server's
	`maxWriteBatchSize` (op count) and `maxMessageSizeBytes` (encoded byte size)
	limits, so `bulkWrite` can split one logical write into several commands as the
	spec requires.

	`opSizes[i]` is the encoded BSON byte size of op `i`. Each returned `[start, end)`
	range covers a contiguous run of ops to send as one command; the ranges tile the
	whole input in order with no gaps or overlaps. An op larger than
	`maxMessageSizeBytes` on its own still occupies a batch by itself rather than
	being dropped or producing an empty batch. Returns an empty array for zero ops.

	Pure value-in, value-out so the IO/command-send stays at the call site.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/crud/bulk-write.md)
*/
size_t[2][] partitionBulkWriteOps(const(size_t)[] opSizes, int maxWriteBatchSize, int maxMessageSizeBytes) @safe pure {
	enforce(maxWriteBatchSize > 0, "maxWriteBatchSize must be positive");
	enforce(maxMessageSizeBytes > 0, "maxMessageSizeBytes must be positive");

	size_t[2][] batches;
	size_t start = 0;
	size_t bytesInBatch = 0;

	foreach (i, opSize; opSizes) {
		bool batchIsEmpty = i == start;
		bool exceedsCount = (i - start) >= cast(size_t) maxWriteBatchSize;
		bool exceedsBytes = bytesInBatch + opSize > cast(size_t) maxMessageSizeBytes;

		// Never emit an empty batch: an op that overflows on its own (e.g. larger than the
		// whole message limit) still opens a fresh batch only when the current one already
		// holds at least one op.
		if (!batchIsEmpty && (exceedsCount || exceedsBytes)) {
			batches ~= [start, i];
			start = i;
			bytesInBatch = 0;
		}

		bytesInBatch += opSize;
	}

	if (start < opSizes.length)
		batches ~= [start, opSizes.length];

	return batches;
}

// zero ops yields no batches
unittest {
	assert(partitionBulkWriteOps([], 100_000, 48 * 1024 * 1024) == []);
}

// a single op yields one batch covering it
unittest {
	assert(partitionBulkWriteOps([10UL], 100_000, 48 * 1024 * 1024) == [[0UL, 1UL]]);
}

// ops exactly at the count limit stay in one batch; one more op splits into two
unittest {
	// maxWriteBatchSize 2: two ops fit one batch, three ops split 2 + 1
	assert(partitionBulkWriteOps([1UL, 1UL], 2, 1_000) == [[0UL, 2UL]]);
	assert(partitionBulkWriteOps([1UL, 1UL, 1UL], 2, 1_000) == [[0UL, 2UL], [2UL, 3UL]]);
}

// the byte budget splits a batch before the count limit is reached
unittest {
	// maxMessageSizeBytes 100: 60 + 60 overflows, so each 60-byte op gets its own batch
	assert(partitionBulkWriteOps([60UL, 60UL], 100_000, 100) == [[0UL, 1UL], [1UL, 2UL]]);
	// 40 + 40 fits (80 <= 100), the third 40 overflows into a second batch
	assert(partitionBulkWriteOps([40UL, 40UL, 40UL], 100_000, 100) == [[0UL, 2UL], [2UL, 3UL]]);
}

// ops summing exactly to the byte limit stay together; exceeding by one byte splits
unittest {
	assert(partitionBulkWriteOps([50UL, 50UL], 100_000, 100) == [[0UL, 2UL]]);
	assert(partitionBulkWriteOps([50UL, 51UL], 100_000, 100) == [[0UL, 1UL], [1UL, 2UL]]);
}

// an op larger than the whole message limit still occupies a batch by itself, never an empty batch
unittest {
	auto batches = partitionBulkWriteOps([10UL, 500UL, 10UL], 100_000, 100);
	assert(batches == [[0UL, 1UL], [1UL, 2UL], [2UL, 3UL]],
		"an oversized op is isolated in its own batch and never produces an empty batch");
}

// the partition tiles the whole input in order with no gaps or overlaps
unittest {
	auto batches = partitionBulkWriteOps([30UL, 30UL, 30UL, 30UL, 30UL], 2, 1_000);
	assert(batches == [[0UL, 2UL], [2UL, 4UL], [4UL, 5UL]]);
	// contiguity: each batch starts where the previous ended, covering [0, 5)
	size_t cursor = 0;
	foreach (b; batches) {
		assert(b[0] == cursor);
		cursor = b[1];
	}
	assert(cursor == 5);
}

// rejects non-positive limits rather than looping forever on a zero budget
unittest {
	import std.exception : assertThrown;
	assertThrown(partitionBulkWriteOps([1UL], 0, 100));
	assertThrown(partitionBulkWriteOps([1UL], 100, 0));
}

/**
	Returns `true` when `update` is a valid update specification: an array is
	treated as an aggregation pipeline, and an object qualifies only when every
	top-level key starts with `$` (an update operator). Anything else, including
	a replacement-style object with plain field keys, returns `false`.
*/
private bool isUpdateDocument(Bson update) @safe {
	if (update.type == Bson.Type.array) return true;
	if (update.type != Bson.Type.object) return false;
	bool hasOperator = false;
	foreach (string key, value; update.byKeyValue) {
		if (key.length == 0 || key[0] != '$') return false;
		hasOperator = true;
	}
	return hasOperator; // an empty {} has no update operators and is not a valid update
}

/**
	Encodes a single client bulk write model into its wire `ops` entry,
	referencing the model's namespace by its index into `nsInfo`. Inserts
	emit `{insert, document}`, updates and replaces emit
	`{update, filter, updateMods, multi}`, and deletes emit
	`{delete, filter, multi}`. The `final switch` over $(D ClientBulkWriteType)
	is the authoritative list of handled types.

	See_Also: $(LINK https://www.mongodb.com/docs/upcoming/reference/command/bulkwrite/)
*/
private Bson buildClientBulkWriteOp(ClientBulkWriteModel model, size_t nsIndex) @safe {
	auto nsRef = Bson(cast(int) nsIndex);
	// empty object because order is important: the operation discriminator
	// (insert/update/delete) must be the first field so the server identifies the op type.
	Bson op = Bson.emptyObject;
	final switch (model.type) {
		case ClientBulkWriteType.insertOne:
			op["insert"] = nsRef;
			op["document"] = model.document;
			return op;
		case ClientBulkWriteType.updateOne:
			op["update"] = nsRef;
			op["filter"] = model.filter;
			op["updateMods"] = model.update;
			op["multi"] = Bson(false);
			return op;
		case ClientBulkWriteType.updateMany:
			op["update"] = nsRef;
			op["filter"] = model.filter;
			op["updateMods"] = model.update;
			op["multi"] = Bson(true);
			return op;
		case ClientBulkWriteType.deleteOne:
			op["delete"] = nsRef;
			op["filter"] = model.filter;
			op["multi"] = Bson(false);
			return op;
		case ClientBulkWriteType.deleteMany:
			op["delete"] = nsRef;
			op["filter"] = model.filter;
			op["multi"] = Bson(true);
			return op;
		case ClientBulkWriteType.replaceOne:
			op["update"] = nsRef;
			op["filter"] = model.filter;
			op["updateMods"] = model.document;
			op["multi"] = Bson(false);
			return op;
	}
}

unittest {
	auto pizza = Bson(["_id": Bson(4), "type": Bson("sausage")]);
	auto model = ClientBulkWriteModel.insertOne("test.pizzas", pizza);

	assert(model.ns == "test.pizzas");
	assert(model.type == ClientBulkWriteType.insertOne);
	assert(model.document == pizza);
}

// updateOne and updateMany carry ns, filter, update and the matching type
unittest {
	auto filter = Bson(["size": Bson("medium")]);
	auto update = Bson(["$set": Bson(["price": Bson(15)])]);

	auto one = ClientBulkWriteModel.updateOne("test.pizzas", filter, update);
	auto many = ClientBulkWriteModel.updateMany("test.pizzas", filter, update);

	assert(one.ns == "test.pizzas");
	assert(one.type == ClientBulkWriteType.updateOne);
	assert(one.filter == filter);
	assert(one.update == update);

	assert(many.type == ClientBulkWriteType.updateMany);
	assert(many.filter == filter);
	assert(many.update == update);
}

// updateOne rejects a non-$ update document (a replacement-style doc)
unittest {
	import std.exception : assertThrown;

	auto filter = Bson(["_id": Bson(4)]);
	auto badUpdate = Bson(["price": Bson(15)]);

	assertThrown(ClientBulkWriteModel.updateOne("test.pizzas", filter, badUpdate));
}

// updateOne rejects an empty update document (no update operators at all)
unittest {
	import std.exception : assertThrown;

	assertThrown(ClientBulkWriteModel.updateOne("test.pizzas", Bson(["_id": Bson(4)]), Bson.emptyObject),
		"an empty {} update has no operators and must be rejected");
}

// updateMany rejects a non-$ update document (a replacement-style doc)
unittest {
	import std.exception : assertThrown;

	auto filter = Bson(["_id": Bson(4)]);
	auto badUpdate = Bson(["price": Bson(15)]);

	assertThrown(ClientBulkWriteModel.updateMany("test.pizzas", filter, badUpdate));
}

// deleteOne and deleteMany carry ns, filter and the matching type
unittest {
	auto filter = Bson(["_id": Bson(2)]);

	auto one = ClientBulkWriteModel.deleteOne("test.pizzas", filter);
	auto many = ClientBulkWriteModel.deleteMany("test.pizzas", filter);

	assert(one.ns == "test.pizzas");
	assert(one.type == ClientBulkWriteType.deleteOne);
	assert(one.filter == filter);

	assert(many.type == ClientBulkWriteType.deleteMany);
	assert(many.filter == filter);
}

// replaceOne carries ns, filter and the replacement in the document field
unittest {
	auto filter = Bson(["_id": Bson(4)]);
	auto replacement = Bson(["_id": Bson(4), "type": Bson("vegan"), "price": Bson(20)]);

	auto model = ClientBulkWriteModel.replaceOne("test.pizzas", filter, replacement);

	assert(model.ns == "test.pizzas");
	assert(model.type == ClientBulkWriteType.replaceOne);
	assert(model.filter == filter);
	assert(model.document == replacement);
}

// replaceOne rejects a $-operator document (an update doc, not a replacement)
unittest {
	import std.exception : assertThrown;

	auto filter = Bson(["_id": Bson(4)]);
	auto badReplacement = Bson(["$set": Bson(["price": Bson(15)])]);

	assertThrown(ClientBulkWriteModel.replaceOne("test.pizzas", filter, badReplacement));
}

// builds a single-insert bulkWrite command referencing nsInfo[0]
unittest {
	auto pizza = Bson(["_id": Bson(4), "type": Bson("sausage")]);
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", pizza) ];

	auto cmd = buildClientBulkWriteCommand(models);

	assert(cmd["bulkWrite"].get!int == 1);

	string firstField;
	foreach (string key, value; cmd.byKeyValue) { firstField = key; break; }
	assert(firstField == "bulkWrite", "bulkWrite must be the first field so the server reads it as the command name");

	auto ops = cmd["ops"].get!(Bson[]);
	assert(ops.length == 1);
	assert(ops[0]["insert"].get!int == 0);
	assert(ops[0]["document"] == pizza);

	auto nsInfo = cmd["nsInfo"].get!(Bson[]);
	assert(nsInfo.length == 1);
	assert(nsInfo[0]["ns"].get!string == "test.pizzas");
}

// throws when the models array is empty
unittest {
	import std.exception : assertThrown;

	ClientBulkWriteModel[] models;

	assertThrown(buildClientBulkWriteCommand(models));
}

// emits errorsOnly:true when verboseResults is unset (default options)
unittest {
	auto pizza = Bson(["_id": Bson(4)]);
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", pizza) ];

	auto cmd = buildClientBulkWriteCommand(models, ClientBulkWriteOptions.init);

	assert(cmd["errorsOnly"].get!bool == true);
}

// emits errorsOnly:false when verboseResults is explicitly true
unittest {
	auto pizza = Bson(["_id": Bson(4)]);
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", pizza) ];

	ClientBulkWriteOptions options;
	options.verboseResults = true;

	auto cmd = buildClientBulkWriteCommand(models, options);
	assert(cmd["errorsOnly"].get!bool == false);
}

// throws when verboseResults is requested with an unacknowledged write concern
unittest {
	import std.exception : assertThrown;

	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", Bson(["_id": Bson(4)])) ];

	WriteConcern unacknowledged;
	unacknowledged.w = Bson(0);

	ClientBulkWriteOptions options;
	options.verboseResults = true;
	options.writeConcern = unacknowledged;

	assertThrown(buildClientBulkWriteCommand(models, options));
}

// allows verboseResults with an acknowledged write concern (the guard must not over-fire)
unittest {
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", Bson(["_id": Bson(4)])) ];

	WriteConcern acknowledged;
	acknowledged.w = Bson(1);

	ClientBulkWriteOptions options;
	options.verboseResults = true;
	options.writeConcern = acknowledged;

	auto cmd = buildClientBulkWriteCommand(models, options);
	assert(cmd["errorsOnly"].get!bool == false);
}

// serializes an acknowledged write concern onto the command verbatim
unittest {
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", Bson(["_id": Bson(4)])) ];

	WriteConcern majority;
	majority.w = Bson("majority");

	ClientBulkWriteOptions options;
	options.writeConcern = majority;

	auto cmd = buildClientBulkWriteCommand(models, options);
	assert(!cmd.tryIndex("writeConcern").isNull);
	assert(cmd["writeConcern"]["w"].get!string == "majority");
}

// emits ordered:false when ordered is explicitly false
unittest {
	auto pizza = Bson(["_id": Bson(4)]);
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", pizza) ];

	ClientBulkWriteOptions options;
	options.ordered = false;

	auto cmd = buildClientBulkWriteCommand(models, options);
	assert(cmd["ordered"].get!bool == false);
}

// emits bypassDocumentValidation, let and comment verbatim when set
unittest {
	auto pizza = Bson(["_id": Bson(4)]);
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", pizza) ];

	ClientBulkWriteOptions options;
	options.bypassDocumentValidation = true;
	options.let     = Bson(["rate": Bson(9)]);
	options.comment = Bson("trace-42");

	auto cmd = buildClientBulkWriteCommand(models, options);
	assert(cmd["bypassDocumentValidation"].get!bool == true);
	assert(cmd["let"] == Bson(["rate": Bson(9)]));
	assert(cmd["comment"] == Bson("trace-42"));
}

// reads top-level counts and the acknowledged flag from ok:1.0
unittest {
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(1L),
		"nMatched": Bson(1L),
		"nModified": Bson(1L),
		"nUpserted": Bson(0L),
		"nDeleted": Bson(1L),
	]);

	auto result = parseClientBulkWriteResult(response);

	assert(result.acknowledged == true);
	assert(result.insertedCount == 1);
	assert(result.matchedCount == 1);
	assert(result.modifiedCount == 1);
	assert(result.upsertedCount == 0);
	assert(result.deletedCount == 1);
}

// an unacknowledged (w:0) reply carries ok:1 but no counts: report acknowledged=false, not a crash
unittest {
	import std.exception : assertNotThrown;

	ClientBulkWriteResult result;
	assertNotThrown(result = parseClientBulkWriteResult(Bson(["ok": Bson(1.0)])),
		"a w:0 reply without result counts must not throw on the missing fields");

	assert(result.acknowledged == false, "a reply with no counts is unacknowledged");
	assert(result.insertedCount == 0);
	assert(result.deletedCount == 0);
}

// reads counts and verbose idx/n when the server returns them as int32 (MongoDB 8.0 wire form)
unittest {
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(0), "nMatched": Bson(1), "nModified": Bson(1),
		"nUpserted": Bson(0), "nDeleted": Bson(0),
		"cursor": Bson([
			"id": Bson(0L),
			"firstBatch": Bson([
				Bson(["ok": Bson(1.0), "idx": Bson(0), "n": Bson(1), "nModified": Bson(1)]),
			]),
		]),
	]);
	auto models = [ ClientBulkWriteModel.updateOne("test.pizzas",
		Bson(["size": Bson("medium")]), Bson(["$set": Bson(["price": Bson(15)])])) ];

	auto result = parseClientBulkWriteResult(response, models, true);

	assert(result.matchedCount == 1);
	assert(result.modifiedCount == 1);
	assert(result.updateResults[0] == UpdateResult(1, 1));
}

// leaves per-op result maps empty and hasVerboseResults false when verbose is false
unittest {
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(1L), "nMatched": Bson(0L), "nModified": Bson(0L),
		"nUpserted": Bson(0L), "nDeleted": Bson(0L),
	]);
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", Bson(["_id": Bson(4)])) ];

	auto result = parseClientBulkWriteResult(response, models, false);

	assert(result.hasVerboseResults == false);
	assert(result.insertResults.length == 0);
	assert(result.updateResults.length == 0);
	assert(result.deleteResults.length == 0);
	assert(result.insertedCount == 1);
}

// populates deleteResults[idx] and sets hasVerboseResults when verbose and a delete success entry is in cursor.firstBatch
unittest {
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(0L), "nMatched": Bson(0L), "nModified": Bson(0L),
		"nUpserted": Bson(0L), "nDeleted": Bson(2L),
		"cursor": Bson([
			"id": Bson(0L),
			"firstBatch": Bson([
				Bson(["ok": Bson(1.0), "idx": Bson(0L), "n": Bson(2L)]),
			]),
		]),
	]);
	auto models = [ ClientBulkWriteModel.deleteMany("test.pizzas", Bson(["price": Bson(1)])) ];

	auto result = parseClientBulkWriteResult(response, models, true);

	assert(result.hasVerboseResults == true);
	assert(0 in result.deleteResults);
	assert(result.deleteResults[0].deletedCount == 2);
}

// populates updateResults[idx] with matchedCount and modifiedCount when verbose and an update success entry is in cursor.firstBatch
unittest {
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(0L), "nMatched": Bson(1L), "nModified": Bson(1L),
		"nUpserted": Bson(0L), "nDeleted": Bson(0L),
		"cursor": Bson([
			"id": Bson(0L),
			"firstBatch": Bson([
				Bson(["ok": Bson(1.0), "idx": Bson(0L), "n": Bson(1L), "nModified": Bson(1L)]),
			]),
		]),
	]);
	auto models = [
		ClientBulkWriteModel.updateOne("test.pizzas", Bson(["size": Bson("medium")]), Bson(["$set": Bson(["price": Bson(15)])])),
	];

	auto result = parseClientBulkWriteResult(response, models, true);

	assert(result.hasVerboseResults == true);
	assert(0 in result.updateResults);
	assert(result.updateResults[0].matchedCount == 1);
	assert(result.updateResults[0].modifiedCount == 1);
}

// a verbose update result for an upsert records the upsertedId and excludes the upsert from matchedCount
unittest {
	auto upsertId = BsonObjectID.generate();
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(0L), "nMatched": Bson(0L), "nModified": Bson(0L),
		"nUpserted": Bson(1L), "nDeleted": Bson(0L),
		"cursor": Bson(["id": Bson(0L), "firstBatch": Bson([
			Bson(["ok": Bson(1.0), "idx": Bson(0L), "n": Bson(1L), "nModified": Bson(0L),
				"upserted": Bson(["_id": Bson(upsertId)])]),
		])]),
	]);
	auto models = [ ClientBulkWriteModel.updateOne("test.pizzas",
		Bson(["size": Bson("L")]), Bson(["$set": Bson(["price": Bson(9)])])) ];

	auto result = parseClientBulkWriteResult(response, models, true);

	assert(result.updateResults[0].matchedCount == 0, "an upsert is counted under nUpserted, not as a match (n - 1)");
	assert(result.updateResults[0].modifiedCount == 0);
	assert(result.updateResults[0].upsertedIds == [Bson(upsertId)], "the upserted id is recorded");
}

// populates insertResults[idx].insertedId from the model document _id when verbose and an insert success entry is in cursor.firstBatch
unittest {
	auto id = BsonObjectID.generate();
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(1L), "nMatched": Bson(0L), "nModified": Bson(0L),
		"nUpserted": Bson(0L), "nDeleted": Bson(0L),
		"cursor": Bson([
			"id": Bson(0L),
			"firstBatch": Bson([
				Bson(["ok": Bson(1.0), "idx": Bson(0L), "n": Bson(1L)]),
			]),
		]),
	]);
	auto models = [
		ClientBulkWriteModel.insertOne("test.pizzas", Bson(["_id": Bson(id), "type": Bson("sausage")])),
	];

	auto result = parseClientBulkWriteResult(response, models, true);

	assert(result.hasVerboseResults == true);
	assert(0 in result.insertResults);
	assert(result.insertResults[0].insertedId == Bson(id));
}

// reports a non-ObjectID insert _id (e.g. an int) verbatim instead of crashing
unittest {
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(1L), "nMatched": Bson(0L), "nModified": Bson(0L),
		"nUpserted": Bson(0L), "nDeleted": Bson(0L),
		"cursor": Bson(["id": Bson(0L), "firstBatch": Bson([
			Bson(["ok": Bson(1.0), "idx": Bson(0L), "n": Bson(1L)]),
		])]),
	]);
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", Bson(["_id": Bson(4), "type": Bson("sausage")])) ];

	auto result = parseClientBulkWriteResult(response, models, true);

	assert(result.insertResults[0].insertedId == Bson(4),
		"a non-ObjectID _id is reported verbatim, not coerced through BsonObjectID");
}

// routes a mixed insert+update+delete firstBatch to all three per-op maps by idx simultaneously
unittest {
	auto id = BsonObjectID.generate();
	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(1L), "nMatched": Bson(1L), "nModified": Bson(1L),
		"nUpserted": Bson(0L), "nDeleted": Bson(1L),
		"cursor": Bson([
			"id": Bson(0L),
			"firstBatch": Bson([
				Bson(["ok": Bson(1.0), "idx": Bson(0L), "n": Bson(1L)]),
				Bson(["ok": Bson(1.0), "idx": Bson(1L), "n": Bson(1L), "nModified": Bson(1L)]),
				Bson(["ok": Bson(1.0), "idx": Bson(2L), "n": Bson(1L)]),
			]),
		]),
	]);
	auto models = [
		ClientBulkWriteModel.insertOne("test.pizzas", Bson(["_id": Bson(id)])),
		ClientBulkWriteModel.updateOne("test.pizzaOrders", Bson(["size": Bson("medium")]), Bson(["$set": Bson(["price": Bson(15)])])),
		ClientBulkWriteModel.deleteOne("test.pizzaOrders", Bson(["price": Bson(1)])),
	];

	auto result = parseClientBulkWriteResult(response, models, true);

	assert(result.insertResults.length == 1);
	assert(result.updateResults.length == 1);
	assert(result.deleteResults.length == 1);
	assert(result.insertResults[0].insertedId == Bson(id));
	assert(result.updateResults[1].matchedCount == 1);
	assert(result.updateResults[1].modifiedCount == 1);
	assert(result.deleteResults[2].deletedCount == 1);
}

// throws MongoClientBulkWriteException mapping idx 1 to its per-op error when cursor.firstBatch has an ok:0 entry
unittest {
	import std.exception : collectException;

	auto response = Bson([
		"ok": Bson(1.0),
		"nErrors": Bson(1L),
		"nInserted": Bson(1L),
		"nMatched": Bson(0L),
		"nModified": Bson(0L),
		"nUpserted": Bson(0L),
		"nDeleted": Bson(0L),
		"cursor": Bson([
			"id": Bson(0L),
			"firstBatch": Bson([
				Bson([
					"ok": Bson(0.0),
					"idx": Bson(1L),
					"code": Bson(11000),
					"errmsg": Bson("E11000 duplicate key error"),
				]),
			]),
		]),
	]);

	auto ex = collectException!MongoClientBulkWriteException(parseClientBulkWriteResult(response));
	assert(ex !is null);
	assert(1 in ex.writeErrors);
	assert(ex.writeErrors[1].code == 11000);
}

// a per-op write error preserves errInfo as BulkWriteError.details (document-validation info)
unittest {
	import std.exception : collectException;

	auto response = Bson([
		"ok": Bson(1.0), "nErrors": Bson(1L),
		"nInserted": Bson(0L), "nMatched": Bson(0L), "nModified": Bson(0L),
		"nUpserted": Bson(0L), "nDeleted": Bson(0L),
		"cursor": Bson([
			"id": Bson(0L),
			"firstBatch": Bson([
				Bson([
					"ok": Bson(0.0), "idx": Bson(0L), "code": Bson(121),
					"errmsg": Bson("Document failed validation"),
					"errInfo": Bson(["failingDocumentId": Bson(4)]),
				]),
			]),
		]),
	]);

	auto ex = collectException!MongoClientBulkWriteException(parseClientBulkWriteResult(response));
	assert(ex !is null);
	assert(ex.writeErrors[0].details == Bson(["failingDocumentId": Bson(4)]),
		"errInfo (document-validation details) is preserved as BulkWriteError.details");
}

// partialResult carries the top-level counts when a per-op write error is thrown
unittest {
	import std.exception : collectException;

	auto response = Bson([
		"ok": Bson(1.0),
		"nErrors": Bson(1L),
		"nInserted": Bson(1L),
		"nMatched": Bson(0L),
		"nModified": Bson(0L),
		"nUpserted": Bson(0L),
		"nDeleted": Bson(0L),
		"cursor": Bson([
			"id": Bson(0L),
			"firstBatch": Bson([
				Bson([
					"ok": Bson(0.0),
					"idx": Bson(1L),
					"code": Bson(11000),
					"errmsg": Bson("E11000 duplicate key error"),
				]),
			]),
		]),
	]);

	auto ex = collectException!MongoClientBulkWriteException(parseClientBulkWriteResult(response));
	assert(ex !is null);
	assert(!ex.partialResult.isNull);
	assert(ex.partialResult.get.insertedCount == 1);
}

// throws MongoClientBulkWriteException exposing a top-level writeConcernError with no per-op errors
unittest {
	import std.exception : collectException;

	auto response = Bson([
		"ok": Bson(1.0),
		"nInserted": Bson(1L),
		"nMatched": Bson(0L),
		"nModified": Bson(0L),
		"nUpserted": Bson(0L),
		"nDeleted": Bson(0L),
		"writeConcernError": Bson([
			"code": Bson(100),
			"errmsg": Bson("waiting for replication timed out"),
		]),
	]);

	auto ex = collectException!MongoClientBulkWriteException(parseClientBulkWriteResult(response));
	assert(ex !is null);
	assert(ex.writeConcernErrors.length == 1);
	assert(ex.writeConcernErrors[0].code == 100);
}

// maps each insert op to the index of its namespace across two distinct namespaces
unittest {
	auto pizza = Bson(["_id": Bson(4)]);
	auto order = Bson(["_id": Bson(7)]);
	auto models = [
		ClientBulkWriteModel.insertOne("test.pizzas", pizza),
		ClientBulkWriteModel.insertOne("test.pizzaOrders", order),
	];

	auto cmd = buildClientBulkWriteCommand(models);

	auto nsInfo = cmd["nsInfo"].get!(Bson[]);
	assert(nsInfo.length == 2);
	assert(nsInfo[0]["ns"].get!string == "test.pizzas");
	assert(nsInfo[1]["ns"].get!string == "test.pizzaOrders");

	auto ops = cmd["ops"].get!(Bson[]);
	assert(ops.length == 2);
	assert(ops[0]["insert"].get!int == 0);
	assert(ops[0]["document"] == pizza);
	assert(ops[1]["insert"].get!int == 1);
	assert(ops[1]["document"] == order);
}

// collapses duplicate namespaces to one nsInfo entry both ops reference
unittest {
	auto a = Bson(["_id": Bson(1)]);
	auto b = Bson(["_id": Bson(2)]);
	auto models = [
		ClientBulkWriteModel.insertOne("test.pizzas", a),
		ClientBulkWriteModel.insertOne("test.pizzas", b),
	];

	auto cmd = buildClientBulkWriteCommand(models);

	auto nsInfo = cmd["nsInfo"].get!(Bson[]);
	assert(nsInfo.length == 1);
	assert(nsInfo[0]["ns"].get!string == "test.pizzas");

	auto ops = cmd["ops"].get!(Bson[]);
	assert(ops.length == 2);
	assert(ops[0]["insert"].get!int == 0);
	assert(ops[0]["document"] == a);
	assert(ops[1]["insert"].get!int == 0);
	assert(ops[1]["document"] == b);
}

// emits update ops with updateMods/filter and multi:false for updateOne, multi:true for updateMany
unittest {
	auto filter = Bson(["size": Bson("medium")]);
	auto mods = Bson(["$set": Bson(["price": Bson(15)])]);
	auto models = [
		ClientBulkWriteModel.updateOne("test.pizzas", filter, mods),
		ClientBulkWriteModel.updateMany("test.pizzas", filter, mods),
	];

	auto cmd = buildClientBulkWriteCommand(models);

	auto nsInfo = cmd["nsInfo"].get!(Bson[]);
	assert(nsInfo.length == 1);

	auto ops = cmd["ops"].get!(Bson[]);
	assert(ops.length == 2);

	string firstField;
	foreach (string key, value; ops[0].byKeyValue) { firstField = key; break; }
	assert(firstField == "update", "the operation discriminator must be the first field so the server identifies the op type");

	assert(ops[0]["update"].get!int == 0);
	assert(ops[0]["filter"] == filter);
	assert(ops[0]["updateMods"] == mods);
	assert(ops[0]["multi"].get!bool == false);
	assert(ops[1]["update"].get!int == 0);
	assert(ops[1]["multi"].get!bool == true);
}

unittest {
	auto filter = Bson(["_id": Bson(2)]);
	auto models = [
		ClientBulkWriteModel.deleteOne("test.pizzas", filter),
		ClientBulkWriteModel.deleteMany("test.pizzas", filter),
	];

	auto cmd = buildClientBulkWriteCommand(models);

	auto ops = cmd["ops"].get!(Bson[]);
	assert(ops.length == 2);
	assert(ops[0]["delete"].get!int == 0);
	assert(ops[0]["filter"] == filter);
	assert(ops[0]["multi"].get!bool == false);
	assert(ops[1]["delete"].get!int == 0);
	assert(ops[1]["multi"].get!bool == true);
}

// encodes replaceOne as an update op with the replacement in updateMods and multi:false
unittest {
	auto filter = Bson(["_id": Bson(4)]);
	auto replacement = Bson(["_id": Bson(4), "type": Bson("vegan"), "price": Bson(20)]);
	auto models = [
		ClientBulkWriteModel.replaceOne("test.pizzas", filter, replacement),
	];

	auto cmd = buildClientBulkWriteCommand(models);

	auto ops = cmd["ops"].get!(Bson[]);
	assert(ops.length == 1);
	assert(ops[0]["update"].get!int == 0);
	assert(ops[0]["filter"] == filter);
	assert(ops[0]["updateMods"] == replacement);
	assert(ops[0]["multi"].get!bool == false);
}

// ensureInsertIds adds a generated BsonObjectID _id to an insertOne document that lacks one
unittest {
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", Bson(["type": Bson("sausage")])) ];

	auto prepared = ensureInsertIds(models);

	assert(prepared.length == 1);
	auto idField = prepared[0].document.tryIndex("_id");
	assert(!idField.isNull);
	assert(idField.get.type == Bson.Type.objectID);
	assert(prepared[0].document["type"].get!string == "sausage");
}

// ensureInsertIds preserves the original field order and appends the generated _id last
unittest {
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas",
		Bson(["type": Bson("sausage"), "size": Bson("large"), "veg": Bson(false)])) ];

	auto prepared = ensureInsertIds(models);

	string[] keys;
	foreach (string key, value; prepared[0].document.byKeyValue)
		keys ~= key;
	assert(keys == ["type", "size", "veg", "_id"],
		"the user's field order is preserved and the generated _id is appended last");
}

// ensureInsertIds leaves an insertOne document that already has an _id unchanged
unittest {
	auto id = BsonObjectID.generate();
	auto models = [ ClientBulkWriteModel.insertOne("test.pizzas", Bson(["_id": Bson(id), "type": Bson("vegan")])) ];

	auto prepared = ensureInsertIds(models);

	assert(prepared[0].document["_id"].get!BsonObjectID == id);
}

// ensureInsertIds leaves a non-insert model's document untouched, injecting no _id
unittest {
	auto models = [ ClientBulkWriteModel.deleteOne("test.pizzas", Bson(["price": Bson(1)])) ];

	auto prepared = ensureInsertIds(models);

	assert(prepared[0].type == ClientBulkWriteType.deleteOne);
	// deleteOne never sets document, so it stays the undefined Bson.init; no _id was injected
	// (injection would turn it into a Bson object).
	assert(prepared[0].document.type == Bson.Type.undefined);
}
