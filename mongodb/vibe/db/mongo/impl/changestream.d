/**
	MongoDB change stream spec helpers.

	A change stream is an aggregation pipeline whose first stage is `$changeStream`.
	This module builds that pipeline from typed options, extracts resume tokens from
	change events, recognises resumable server errors, and exposes `ChangeStream`,
	an input range that transparently re-opens its cursor from the last seen token
	when the server reports a resumable error.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.changestream;

import vibe.data.bson;
import vibe.db.mongo.connection : MongoException;
import vibe.db.mongo.cursor : MongoCursor;
import std.typecons : Nullable;

@safe:

/// Controls which version of a document is returned for update events.
enum ChangeStreamFullDocument {
	/// Omit the `fullDocument` field (server default).
	default_,
	/// Look up and return the current majority-committed document.
	updateLookup,
	/// Return the post-image when available.
	whenAvailable,
	/// Require the post-image, erroring when unavailable.
	required,
}

/// Options controlling how a change stream is opened.
struct ChangeStreamOptions {
	/// Which document version to return for update events.
	ChangeStreamFullDocument fullDocument;
	/// Resume token to restart the stream after a previously seen event.
	Nullable!Bson resumeAfter;
	/// Resume token to restart the stream after the named event, excluding it.
	Nullable!Bson startAfter;
	/// Watch every collection in every database of the cluster (whole-cluster stream).
	bool allChangesForCluster;
}

/** Builds the `$changeStream` aggregation stage from the given options.

	Each option is only emitted when it deviates from the server default, so
	`ChangeStreamOptions.init` yields an empty `$changeStream` stage.

	Params:
		options = the typed options to encode into the stage.

	Returns: the BSON object `{ "$changeStream": { ... } }`.
*/
Bson changeStreamStage(ChangeStreamOptions options)
{
	auto inner = Bson.emptyObject;

	const fullDocumentName = mongoName(options.fullDocument);
	if (fullDocumentName !is null)
		inner["fullDocument"] = Bson(fullDocumentName);

	setIfPresent(inner, "resumeAfter", options.resumeAfter);
	setIfPresent(inner, "startAfter", options.startAfter);

	if (options.allChangesForCluster)
		inner["allChangesForCluster"] = Bson(true);

	return Bson(["$changeStream": inner]);
}

/// changeStreamStage with default options yields an empty $changeStream stage
unittest
{
	assert(changeStreamStage(ChangeStreamOptions.init) == Bson(["$changeStream": Bson.emptyObject]));
}

/// changeStreamStage includes fullDocument when set to updateLookup
unittest
{
	ChangeStreamOptions options;
	options.fullDocument = ChangeStreamFullDocument.updateLookup;
	assert(changeStreamStage(options) == Bson(["$changeStream": Bson(["fullDocument": Bson("updateLookup")])]));
}

/// changeStreamStage includes the resumeAfter token when set
unittest
{
	import std.typecons : nullable;
	auto token = Bson(["_data": Bson("abc")]);
	ChangeStreamOptions options;
	options.resumeAfter = token.nullable;
	assert(changeStreamStage(options) == Bson(["$changeStream": Bson(["resumeAfter": token])]));
}

/// changeStreamStage includes the startAfter token when set
unittest
{
	import std.typecons : nullable;
	auto token = Bson(["_data": Bson("xyz")]);
	ChangeStreamOptions options;
	options.startAfter = token.nullable;
	assert(changeStreamStage(options) == Bson(["$changeStream": Bson(["startAfter": token])]));
}

/// changeStreamStage includes allChangesForCluster when set
unittest
{
	ChangeStreamOptions options;
	options.allChangesForCluster = true;
	assert(changeStreamStage(options) == Bson(["$changeStream": Bson(["allChangesForCluster": Bson(true)])]));
}

/** Builds the full aggregation pipeline for a change stream.

	The `$changeStream` stage built from `options` is prepended in front of the
	caller-supplied stages.

	Params:
		options = the typed options for the leading `$changeStream` stage.
		userPipeline = the caller's downstream aggregation stages.

	Returns: the change-stream stage followed by `userPipeline`.
*/
Bson[] buildChangeStreamPipeline(ChangeStreamOptions options, Bson[] userPipeline)
{
	return changeStreamStage(options) ~ userPipeline;
}

/// buildChangeStreamPipeline prepends the changeStream stage before the user pipeline
unittest
{
	auto userStage = Bson(["$match": Bson(["operationType": Bson("insert")])]);
	auto pipeline = buildChangeStreamPipeline(ChangeStreamOptions.init, [userStage]);
	assert(pipeline.length == 2);
	assert(pipeline[0] == Bson(["$changeStream": Bson.emptyObject]));
	assert(pipeline[1] == userStage);
}

/** Extracts the resume token (`_id`) from a change stream event document.

	Params:
		event = a change event document as returned by the server.

	Returns: the event's `_id`, or null when the event carries no `_id`.
*/
Nullable!Bson resumeToken(Bson event)
{
	import std.typecons : nullable;
	auto id = event["_id"];
	if (id.isNull)
		return Nullable!Bson.init;
	return id.nullable;
}

/// resumeToken returns the change event's _id
unittest
{
	import std.typecons : nullable;
	auto event = Bson([
		"_id": Bson(["_data": Bson("826...")]),
		"operationType": Bson("insert")
	]);
	assert(resumeToken(event) == Bson(["_data": Bson("826...")]).nullable);
}

/// resumeToken returns null when the event has no _id
unittest
{
	auto event = Bson(["operationType": Bson("insert")]);
	assert(resumeToken(event).isNull);
}

/** Whether a server error is a resumable change-stream error.

	Such errors carry the `ResumableChangeStreamError` label, meaning the stream
	may safely re-open from the last seen resume token instead of failing.

	Params:
		e = the server error to classify.

	Returns: true when the error carries the resumable label.
*/
bool isResumableChangeStreamError(MongoException e)
{
	return e.hasErrorLabel("ResumableChangeStreamError");
}

/// isResumableChangeStreamError is true when the resumable label is present
unittest
{
	import vibe.db.mongo.connection : MongoException;
	auto resumableError = new MongoException("getMore failed");
	resumableError.errorLabels = ["ResumableChangeStreamError"];
	assert(isResumableChangeStreamError(resumableError));
}

/// isResumableChangeStreamError is false without the resumable label
unittest
{
	import vibe.db.mongo.connection : MongoException;
	auto other = new MongoException("network blip");
	other.errorLabels = ["TransientTransactionError"];
	assert(!isResumableChangeStreamError(other));

	auto bare = new MongoException("no labels");
	assert(!isResumableChangeStreamError(bare));
}

/** Derives the change-stream options for a resume attempt.

	Once a resume token is known, resumption uses `resumeAfter` with that token and
	drops `startAfter`. With no cached token the options are returned unchanged, so
	the original `startAfter`/`resumeAfter` intent is preserved.

	Params:
		original = the options the stream was originally opened with.
		cachedToken = the last seen resume token, or null if none yet.

	Returns: the options to re-open the stream with.
*/
ChangeStreamOptions optionsForResume(ChangeStreamOptions original, Nullable!Bson cachedToken)
{
	auto resumed = original;
	if (!cachedToken.isNull) {
		resumed.resumeAfter = cachedToken;
		resumed.startAfter = Nullable!Bson.init;
	}
	return resumed;
}

/// optionsForResume switches to resumeAfter with the cached token
unittest
{
	import std.typecons : nullable;
	ChangeStreamOptions original;
	original.startAfter = Bson(["_data": Bson("orig")]).nullable;
	auto token = Bson(["_data": Bson("cached")]);
	auto resumed = optionsForResume(original, token.nullable);
	assert(resumed.resumeAfter == token.nullable);
	assert(resumed.startAfter.isNull);
}

/** An auto-resuming input range over a MongoDB change stream.

	It iterates change events like a normal cursor, but caches the latest resume
	token and transparently re-opens the underlying cursor (via the supplied opener)
	when the server reports a resumable error, so iteration survives transient
	failures and elections.
*/
struct ChangeStream(DocType = Bson) {
	private {
		MongoCursor!DocType delegate(ChangeStreamOptions) @safe m_open;
		ChangeStreamOptions m_options;
		MongoCursor!DocType m_cursor;
		Nullable!Bson m_resumeToken;
		bool m_started;
	}

	/** Constructs a change stream from an opener delegate.

		Params:
			open = runs the `$changeStream` aggregation for the given options and
				returns its cursor; called again to resume after a resumable error.
			options = the options the stream is first opened with.
	*/
	this(MongoCursor!DocType delegate(ChangeStreamOptions) @safe open, ChangeStreamOptions options)
	{
		m_open = open;
		m_options = options;
	}

	/** The most recent resume token observed.

		Usable to resume later via `ChangeStreamOptions.resumeAfter`. Null until the
		first event is consumed.
	*/
	@property Nullable!Bson resumeToken() { return m_resumeToken; }

	/** Range primitive: whether no further change events are currently available.

		On a resumable server error the stream re-opens from the cached token and
		retries before reporting emptiness.

		$(B Tailable semantics — important): a change stream is a tailable cursor, so
		`empty` reflects only whether an event is available $(I right now). On an idle but
		live stream the underlying getMore returns an empty batch and `empty` is `true`,
		even though more events may still arrive — so `empty` is $(B non-monotonic): it can
		return `true` now and `false` later. A plain `foreach (event; stream) {}` therefore
		stops at the first idle moment rather than blocking for the next event.

		To follow a live stream, re-poll in a loop, e.g.
		`while (true) { if (!stream.empty) { use(stream.front); stream.popFront(); } }`.
		(A blocking `tryNext`/awaitData primitive is not yet provided.)
	*/
	@property bool empty()
	{
		ensureStarted();
		try
			return m_cursor.empty;
		catch (MongoException e) {
			if (!isResumableChangeStreamError(e))
				throw e;
			m_cursor = m_open(optionsForResume(m_options, m_resumeToken));
			return m_cursor.empty;
		}
	}

	/// Range primitive returning the current change event.
	@property DocType front() { ensureStarted(); return m_cursor.front; }

	/// Range primitive that advances to the next change event, caching the consumed
	/// event's resume token first.
	void popFront()
	{
		ensureStarted();
		cacheResumeToken();
		m_cursor.popFront();
	}

	private void ensureStarted()
	{
		if (m_started) return;
		m_cursor = m_open(m_options);
		m_started = true;
	}

	private void cacheResumeToken()
	{
		static if (is(DocType == Bson))
			auto eventBson = m_cursor.front;
		else
			auto eventBson = () @safe { return serializeToBson(m_cursor.front); }();
		auto token = .resumeToken(eventBson);
		if (!token.isNull)
			m_resumeToken = token;
	}
}

/// The MongoDB wire name for a fullDocument mode, or null for the server default.
private string mongoName(ChangeStreamFullDocument fullDocument)
{
	final switch (fullDocument) {
		case ChangeStreamFullDocument.default_: return null;
		case ChangeStreamFullDocument.updateLookup: return "updateLookup";
		case ChangeStreamFullDocument.whenAvailable: return "whenAvailable";
		case ChangeStreamFullDocument.required: return "required";
	}
}

/// Sets `obj[key]` to the token's value, but only when the token is present.
private void setIfPresent(ref Bson obj, string key, Nullable!Bson value)
{
	if (!value.isNull)
		obj[key] = value.get;
}
