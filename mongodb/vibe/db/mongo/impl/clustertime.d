/**
	Cluster time gossip: track and compare the `$clusterTime` documents
	exchanged on command replies for causal consistency.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.clustertime;

import vibe.data.bson;

@safe:

/// laterClusterTime returns the document whose clusterTime timestamp is higher
unittest
{
    auto earlier = Bson(["clusterTime": Bson(BsonTimestamp(0x0000000100000005L)), "signature": Bson.emptyObject]);
    auto later   = Bson(["clusterTime": Bson(BsonTimestamp(0x0000000200000001L)), "signature": Bson.emptyObject]);

    assert(laterClusterTime(earlier, later) == later,
        "the higher clusterTime timestamp is returned");
    assert(laterClusterTime(later, earlier) == later,
        "order-independent: the later clusterTime wins regardless of argument order");
}

/// laterClusterTime treats a null / missing clusterTime as the oldest, never throwing
unittest
{
    auto valid = Bson(["clusterTime": Bson(BsonTimestamp(0x0000000100000005L)), "signature": Bson.emptyObject]);

    assert(laterClusterTime(Bson(null), valid) == valid,
        "a null/absent cluster time loses to a real one");
    assert(laterClusterTime(valid, Bson(null)) == valid,
        "order-independent: the real cluster time wins over null");
    assert(laterClusterTime(Bson(null), Bson(null)).type == Bson.Type.null_,
        "two nulls yield null (nothing tracked yet)");
}

/// gossipClusterTime attaches $clusterTime when one is tracked, and is a no-op when none is
unittest
{
    auto ct = Bson(["clusterTime": Bson(BsonTimestamp(0x0000000100000005L)), "signature": Bson.emptyObject]);

    auto cmd = Bson.emptyObject;
    cmd["ping"] = Bson(1);

    auto decorated = gossipClusterTime(cmd, ct);
    assert(decorated["$clusterTime"] == ct, "the tracked $clusterTime is attached to the command");
    assert(decorated["ping"] == Bson(1), "the original command fields are preserved");
    assert(cmd["$clusterTime"].type == Bson.Type.null_, "the caller's command is not mutated");

    // no cluster time tracked yet -> command unchanged, no $clusterTime added
    auto untouched = gossipClusterTime(cmd, Bson(null));
    assert(untouched["$clusterTime"].type == Bson.Type.null_, "a null cluster time adds nothing");
}

/// Returns the `$clusterTime` document whose `clusterTime` Timestamp is later (higher).
/// Per the sessions spec the driver tracks the maximum observed cluster time.
Bson laterClusterTime(Bson a, Bson b) @safe
{
	return clusterTimeValue(b) > clusterTimeValue(a) ? b : a;
}

/// Returns `command` with the gossiped `$clusterTime` attached; a null/non-object
/// clusterTime (nothing tracked yet) is a no-op and the command is returned as-is.
Bson gossipClusterTime(Bson command, Bson clusterTime) @safe
{
	if (clusterTime.type != Bson.Type.object)
		return command;

	Bson result = Bson.emptyObject;
	foreach (string key, value; command.byKeyValue)
		result[key] = value;
	result["$clusterTime"] = clusterTime;
	return result;
}

/// Decodes the unsigned 64-bit value of a `$clusterTime` doc's `clusterTime` Timestamp.
/// BSON timestamps are 8 little-endian bytes with the seconds in the high half, so the
/// raw u64 compares temporally. Compared as UNSIGNED so a post-2038 seconds value (high
/// bit set) doesn't flip the comparison.
private ulong clusterTimeValue(Bson clusterTimeDoc) @safe
{
	import std.bitmanip : littleEndianToNative;
	if (clusterTimeDoc.type != Bson.Type.object)
		return 0;
	auto ts = clusterTimeDoc["clusterTime"];
	if (ts.type != Bson.Type.timestamp)
		return 0;
	ubyte[8] bytes = ts.data[0 .. 8];
	return littleEndianToNative!ulong(bytes);
}
