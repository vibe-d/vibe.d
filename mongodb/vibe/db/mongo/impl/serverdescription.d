/**
	MongoDB server description and topology state: the per-server `hello`/`isMaster`
	response model, its classification helpers, and replica-set matching.

	Pure data + classification logic; the live probing that fills these in
	(`probeServer`) stays in connection.d because it drives a MongoConnection.

	Copyright: © 2020-2022 Jan Jurzitza
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Jurzitza
*/
module vibe.db.mongo.impl.serverdescription;

import std.typecons : Nullable;

import vibe.data.bson;
import vibe.db.mongo.impl.wireversion : WireVersion;

struct TopologyVersion
{
@optional:
	BsonObjectID processId;
	long counter = -1;
}

struct ServerDescription
{
	enum ServerType
	{
		unknown,
		standalone,
		mongos,
		possiblePrimary,
		RSPrimary,
		RSSecondary,
		RSArbiter,
		RSOther,
		RSGhost
	}

	static struct LastWrite
	{
	@optional:
		Nullable!BsonDate lastWriteDate;
	}

@optional:
	string address;
	string error;
	float roundTripTime = 0;
	LastWrite lastWrite;
	Nullable!BsonObjectID opTime;
	ServerType type = ServerType.unknown;
	int minWireVersion, maxWireVersion;
	string me;
	string[] hosts, passives, arbiters;
	string[string] tags;
	string setName;
	Nullable!int setVersion;
	Nullable!BsonObjectID electionId;
	string primary;
	Nullable!TopologyVersion topologyVersion;

	/// Deprecated since MongoDB 5.0: the `isMaster` command was replaced by `hello`.
	/// The `secondary` field itself is still present in the `hello` response.
	bool secondary;

	/// Deprecated since MongoDB 5.0: renamed to `isWritablePrimary` in the `hello` command response.
	/// True if the instance is a primary, mongos, or standalone mongod.
	bool ismaster;

	bool isWritablePrimary;
	bool arbiterOnly;
	string msg;
	Nullable!int logicalSessionTimeoutMinutes;
	string[] compression;

	/// Set by the driver after probing, not deserialized from the server response.
	long lastUpdateTimeUsecs;

	bool satisfiesVersion(WireVersion wireVersion) @safe const @nogc pure nothrow
	{
		return maxWireVersion >= wireVersion;
	}

	bool isPrimary() @safe const @nogc pure nothrow
	{
		return (ismaster || isWritablePrimary) && !secondary;
	}

	bool isSecondaryNode() @safe const @nogc pure nothrow
	{
		return secondary && !ismaster && !isWritablePrimary;
	}

	bool isReplicaSetMember() @safe const @nogc pure nothrow
	{
		return setName.length > 0;
	}

	ServerType classifiedType() @safe const @nogc pure nothrow
	{
		if (msg == "isdbgrid")
			return ServerType.mongos;

		if (setName.length)
		{
			if (isPrimary)
				return ServerType.RSPrimary;

			if (isSecondaryNode)
				return ServerType.RSSecondary;

			if (arbiterOnly)
				return ServerType.RSArbiter;

			return ServerType.RSOther;
		}

		if (isPrimary)
			return ServerType.standalone;

		return ServerType.unknown;
	}
}

/// satisfiesVersion returns true for versions up to maxWireVersion v36
@safe unittest
{
	ServerDescription desc;
	desc.maxWireVersion = WireVersion.v36;
	assert(desc.satisfiesVersion(WireVersion.old));
	assert(desc.satisfiesVersion(WireVersion.v26));
	assert(desc.satisfiesVersion(WireVersion.v30));
	assert(desc.satisfiesVersion(WireVersion.v34));
	assert(desc.satisfiesVersion(WireVersion.v36));
	assert(!desc.satisfiesVersion(WireVersion.v40));
	assert(!desc.satisfiesVersion(WireVersion.v44));
	assert(!desc.satisfiesVersion(WireVersion.v60));
}

/// satisfiesVersion with maxWireVersion old only satisfies old
@safe unittest
{
	ServerDescription oldServer;
	oldServer.maxWireVersion = WireVersion.old;
	assert(oldServer.satisfiesVersion(WireVersion.old));
	assert(!oldServer.satisfiesVersion(WireVersion.v26));
	assert(!oldServer.satisfiesVersion(WireVersion.v30));
}

/// satisfiesVersion with maxWireVersion v80 satisfies all versions
@safe unittest
{
	ServerDescription latestServer;
	latestServer.maxWireVersion = WireVersion.v80;
	assert(latestServer.satisfiesVersion(WireVersion.old));
	assert(latestServer.satisfiesVersion(WireVersion.v36));
	assert(latestServer.satisfiesVersion(WireVersion.v44));
	assert(latestServer.satisfiesVersion(WireVersion.v60));
	assert(latestServer.satisfiesVersion(WireVersion.v70));
	assert(latestServer.satisfiesVersion(WireVersion.v80));
}

/// Default-initialized ServerDescription has maxWireVersion 0 and unknown type
@safe unittest
{
	ServerDescription def;
	assert(def.maxWireVersion == 0);
	assert(def.type == ServerDescription.ServerType.unknown);
	assert(def.satisfiesVersion(WireVersion.old));
	assert(!def.satisfiesVersion(WireVersion.v26));
}

/// isPrimary returns true when ismaster=true and secondary=false
@safe unittest
{
	ServerDescription desc;
	desc.ismaster = true;
	desc.secondary = false;
	assert(desc.isPrimary);
}

/// isPrimary returns false when both ismaster=true and secondary=true
@safe unittest
{
	ServerDescription desc;
	desc.ismaster = true;
	desc.secondary = true;
	assert(!desc.isPrimary);
}

/// isPrimary returns false when ismaster=false
@safe unittest
{
	ServerDescription desc;
	desc.ismaster = false;
	desc.secondary = false;
	assert(!desc.isPrimary);
}

/// isPrimary returns true when isWritablePrimary=true (hello response)
@safe unittest
{
	ServerDescription desc;
	desc.isWritablePrimary = true;
	desc.secondary = false;
	assert(desc.isPrimary);
}

/// isPrimary returns false when isWritablePrimary=true but secondary=true
@safe unittest
{
	ServerDescription desc;
	desc.isWritablePrimary = true;
	desc.secondary = true;
	assert(!desc.isPrimary);
}

/// isSecondaryNode returns true when secondary=true and ismaster=false
@safe unittest
{
	ServerDescription desc;
	desc.secondary = true;
	desc.ismaster = false;
	assert(desc.isSecondaryNode);
}

/// isSecondaryNode returns false when ismaster=true
@safe unittest
{
	ServerDescription desc;
	desc.secondary = true;
	desc.ismaster = true;
	assert(!desc.isSecondaryNode);
}

/// isSecondaryNode returns false when isWritablePrimary=true
@safe unittest
{
	ServerDescription desc;
	desc.secondary = true;
	desc.isWritablePrimary = true;
	assert(!desc.isSecondaryNode);
}

/// isSecondaryNode returns false when secondary=false
@safe unittest
{
	ServerDescription desc;
	desc.secondary = false;
	desc.ismaster = false;
	assert(!desc.isSecondaryNode);
}

/// isReplicaSetMember returns true when setName is non-empty
@safe unittest
{
	ServerDescription desc;
	desc.setName = "rs0";
	assert(desc.isReplicaSetMember);
}

/// isReplicaSetMember returns false when setName is empty
@safe unittest
{
	ServerDescription desc;
	assert(!desc.isReplicaSetMember);
}

/// Default ServerDescription is not primary, not secondary, not RS member
@safe unittest
{
	ServerDescription desc;
	assert(!desc.isPrimary);
	assert(!desc.isSecondaryNode);
	assert(!desc.isReplicaSetMember);
}

/// classifiedType returns mongos when msg is isdbgrid
@safe unittest
{
	ServerDescription desc;
	desc.msg = "isdbgrid";
	assert(desc.classifiedType == ServerDescription.ServerType.mongos);
}

/// classifiedType returns RSPrimary for a primary with a set name
@safe unittest
{
	ServerDescription desc;
	desc.setName = "rs0";
	desc.ismaster = true;
	assert(desc.classifiedType == ServerDescription.ServerType.RSPrimary);
}

/// classifiedType returns RSSecondary for a secondary with a set name
@safe unittest
{
	ServerDescription desc;
	desc.setName = "rs0";
	desc.secondary = true;
	assert(desc.classifiedType == ServerDescription.ServerType.RSSecondary);
}

/// classifiedType returns RSArbiter for an arbiter with a set name
@safe unittest
{
	ServerDescription desc;
	desc.setName = "rs0";
	desc.arbiterOnly = true;
	assert(desc.classifiedType == ServerDescription.ServerType.RSArbiter);
}

/// classifiedType returns RSOther for a set member that is neither primary, secondary nor arbiter
@safe unittest
{
	ServerDescription desc;
	desc.setName = "rs0";
	assert(desc.classifiedType == ServerDescription.ServerType.RSOther);
}

/// classifiedType returns standalone for a primary without a set name
@safe unittest
{
	ServerDescription desc;
	desc.ismaster = true;
	assert(desc.classifiedType == ServerDescription.ServerType.standalone);
}

/// classifiedType returns unknown for a default description
@safe unittest
{
	ServerDescription desc;
	assert(desc.classifiedType == ServerDescription.ServerType.unknown);
}

/**
 * Checks whether the server's replica set name matches the expected one.
 * Returns true if no replica set is configured (empty string) or if
 * the names match.
 */
package(vibe.db.mongo) bool matchesReplicaSet(string expectedSet, ref const ServerDescription desc)
@safe @nogc pure nothrow
{
	if (!expectedSet.length)
		return true;
	return desc.setName == expectedSet;
}

/// matchesReplicaSet returns true when no replica set is configured
@safe @nogc pure nothrow unittest
{
	ServerDescription desc;
	desc.setName = "rs0";
	assert(matchesReplicaSet("", desc));
}

/// matchesReplicaSet returns true when replica set names match
@safe @nogc pure nothrow unittest
{
	ServerDescription desc;
	desc.setName = "rs0";
	assert(matchesReplicaSet("rs0", desc));
}

/// matchesReplicaSet returns false when replica set names differ
@safe @nogc pure nothrow unittest
{
	ServerDescription desc;
	desc.setName = "rs1";
	assert(!matchesReplicaSet("rs0", desc));
}

/// matchesReplicaSet returns false when server has no setName but one is expected
@safe @nogc pure nothrow unittest
{
	ServerDescription desc;
	assert(!matchesReplicaSet("rs0", desc));
}

/// matchesReplicaSet returns true when both are empty
@safe @nogc pure nothrow unittest
{
	ServerDescription desc;
	assert(matchesReplicaSet("", desc));
}
