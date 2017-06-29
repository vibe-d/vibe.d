/**
	MongoDB operation flag definitions.

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.flags;

enum UpdateFlags {
	none         = 0,    /// Normal update of a single document.
	upsert       = 1<<0, /// Creates a document if none exists.
	multiUpdate  = 1<<1, /// Updates all matching documents.

	None = none, /// Deprecated compatibility alias
	Upsert = upsert, /// Deprecated compatibility alias
	MultiUpdate = multiUpdate /// Deprecated compatibility alias
}

enum IndexFlags {
	none = 0,
	unique = 1<<0,
	dropDuplicates = 1<<2,
	background = 1<<3,
	sparse = 1<<4,
	expireAfterSeconds = 1<<5,

	None = none, /// Deprecated compatibility alias, use `none` instead.
	Unique = unique, /// Deprecated compatibility alias, use `unique` instead.
	DropDuplicates = dropDuplicates, /// Deprecated compatibility alias, use `dropDuplicates` instead.
	Background = background, /// Deprecated compatibility alias, use `background` instead.
	Sparse = sparse, /// Deprecated compatibility alias, use `sparse` instead.
	ExpireAfterSeconds = expireAfterSeconds, /// Deprecated compatibility alias, use `expireAfterSeconds` instead.
}

enum InsertFlags {
	none             = 0,    /// Normal insert.
	continueOnError  = 1<<0, /// For multiple inserted documents, continues inserting further documents after a failure.

	None = none, /// Deprecated compatibility alias
	ContinueOnError = continueOnError /// Deprecated compatibility alias
}

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

enum DeleteFlags {
	none          = 0,
	singleRemove  = 1<<0,

	None = none, /// Deprecated compatibility alias
	SingleRemove = singleRemove /// Deprecated compatibility alias
}

enum ReplyFlags {
	none              = 0,
	cursorNotFound    = 1<<0,
	queryFailure      = 1<<1,
	shardConfigStale  = 1<<2,
	awaitCapable      = 1<<3,

	None = none, /// Deprecated compatibility alias
	CursorNotFound = cursorNotFound, /// Deprecated compatibility alias
	QueryFailure = queryFailure, /// Deprecated compatibility alias
	ShardConfigStale = shardConfigStale, /// Deprecated compatibility alias
	AwaitCapable = awaitCapable /// Deprecated compatibility alias
}
