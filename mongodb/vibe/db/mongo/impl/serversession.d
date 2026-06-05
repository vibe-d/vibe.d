/**
	Logical session id generation for retryable writes.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.serversession;

import vibe.data.bson;

@safe:

/// Builds a fresh logical session id document `{ id: <UUID binary subtype 0x04, 16 bytes> }`.
Bson logicalSessionId()
{
	import std.uuid : randomUUID;
	auto bytes = randomUUID().data;
	return Bson(["id": Bson(BsonBinData(BsonBinData.Type.uuid, bytes.idup))]);
}

/// Tracks per-session state such as the monotonic transaction number.
struct ServerSession
{
	private long m_txnNumber;
	private Bson m_lsid;

	/// Returns the next monotonic transaction number, starting at 1.
	long nextTransactionNumber() @safe { return ++m_txnNumber; }

	/// Builds a session carrying its own fresh logical session id.
	static ServerSession create() @safe { ServerSession s; s.m_lsid = logicalSessionId(); return s; }

	/// The logical session id document for this session.
	Bson lsid() @safe const { return m_lsid; }
}

/// A fresh logical session id is `{ id: <UUID binary subtype 0x04, 16 bytes> }`.
unittest
{
	auto lsid = logicalSessionId();

	assert(lsid["id"].type == Bson.Type.binData,
		"the lsid id field must be binary data");
	assert(lsid["id"].get!BsonBinData.type == BsonBinData.Type.uuid,
		"the lsid id field must use UUID binary subtype 0x04");
	assert(lsid["id"].get!BsonBinData.rawData.length == 16,
		"the lsid UUID must be 16 bytes");
}

/// Each fresh logical session id is unique.
unittest
{
	auto a = logicalSessionId();
	auto b = logicalSessionId();

	auto ra = a["id"].get!BsonBinData.rawData;
	auto rb = b["id"].get!BsonBinData.rawData;

	assert(ra != rb, "each logical session id must be unique");
}

/// The first transaction number on a fresh session is 1.
unittest
{
	ServerSession session;

	assert(session.nextTransactionNumber() == 1,
		"the first transaction number must be 1");
}

/// A session built via `create` carries its own logical session id.
unittest
{
	auto session = ServerSession.create();

	assert(session.lsid["id"].type == Bson.Type.binData,
		"server session carries a logical session id");
}
