/**
	MongoDB operation flag definitions.

	Copyright: © 2012-2016 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.db.mongo.flags;

deprecated public import vibe.db.mongo.impl.index : IndexFlags;
deprecated public import vibe.db.mongo.impl.crud : UpdateFlags, InsertFlags, QueryFlags, DeleteFlags;

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
