/**
	MongoDB topology description and server selection.

	Implements server selection logic for replica sets based on the
	MongoDB Server Selection specification.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/server-selection/server-selection.md)

	Copyright: © 2026 GISCollective
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.db.mongo.topology;

import vibe.db.mongo.connection : ServerDescription, TopologyVersion;
import vibe.data.bson : BsonObjectID;
import vibe.db.mongo.settings;
import vibe.core.log;

import std.random : uniform;
import std.typecons : Nullable;

@safe:

/**
 * Tracks the known state of all servers in a deployment.
 *
 * Updated after each successful handshake. Used by server selection
 * to pick an appropriate host for a given read preference.
 */
enum TopologyType
{
	unknown,
	single,
	replicaSetWithPrimary,
	replicaSetNoPrimary,
	sharded
}

struct TopologyDescription
{
	import vibe.data.bson : BsonObjectID;

	ServerRecord[] servers;
	string setName;
	TopologyType type = TopologyType.unknown;
	uint seedCount;
	Nullable!BsonObjectID maxElectionId;
	Nullable!int maxSetVersion;

	void update(MongoHost host, ServerDescription desc)
	{
		bool found = false;
		foreach (ref s; servers)
		{
			if (s.host == host)
			{
				if (isStaleUpdate(s.description, desc))
					return;

				s.description = desc;
				found = true;
				break;
			}
		}

		if (!found)
			servers ~= ServerRecord(host, desc);

		if (!setName.length && desc.setName.length)
			setName = desc.setName;

		if (desc.isPrimary)
		{
			if (handleNewPrimary(host, desc))
				pruneNonMembers(desc);
			else
				return;
		}

		auto serverType = desc.classifiedType();
		removeIncompatible(serverType);
		transitionType(serverType);
	}

	/**
	 * Handles a new primary: compares electionId/setVersion against the
	 * topology's max to detect stale primaries. Demotes the old primary
	 * if the new one is fresher, or demotes the new one if it's stale.
	 *
	 * Returns true if the new primary is accepted, false if it was stale.
	 */
	private bool handleNewPrimary(MongoHost host, ref const ServerDescription desc)
	{
		if (!desc.electionId.isNull && !maxElectionId.isNull)
		{
			bool newIsStale = false;

			if (!desc.setVersion.isNull && !maxSetVersion.isNull)
			{
				if (desc.setVersion.get < maxSetVersion.get)
					newIsStale = true;
				else if (desc.setVersion.get == maxSetVersion.get
					&& desc.electionId.get < maxElectionId.get)
					newIsStale = true;
			}
			else if (desc.electionId.get < maxElectionId.get)
			{
				newIsStale = true;
			}

			if (newIsStale)
			{
				foreach (ref s; servers)
				{
					if (s.host == host)
					{
						s.description = ServerDescription.init;
						break;
					}
				}
				transitionType(ServerDescription.ServerType.unknown);
				return false;
			}
		}

		// Demote old primary if different from the new one
		foreach (ref s; servers)
		{
			if (s.host != host && s.description.isPrimary)
				s.description = ServerDescription.init;
		}

		if (!desc.electionId.isNull)
			maxElectionId = desc.electionId;

		if (!desc.setVersion.isNull)
			maxSetVersion = desc.setVersion;

		return true;
	}

	private void pruneNonMembers(ref const ServerDescription primaryDesc)
	{
		auto memberHosts = collectMemberHosts(primaryDesc);

		if (!memberHosts.length)
			return;

		ServerRecord[] kept;
		foreach (ref s; servers)
		{
			if (hasHost(memberHosts, s.host))
				kept ~= s;
		}

		servers = kept;
	}

	private static MongoHost[] collectMemberHosts(ref const ServerDescription desc)
	{
		MongoHost[] result;

		foreach (h; desc.hosts)
		{
			auto parsed = parseHostPort(h);
			if (parsed != MongoHost.init)
				result ~= parsed;
		}

		foreach (h; desc.passives)
		{
			auto parsed = parseHostPort(h);
			if (parsed != MongoHost.init && !hasHost(result, parsed))
				result ~= parsed;
		}

		foreach (h; desc.arbiters)
		{
			auto parsed = parseHostPort(h);
			if (parsed != MongoHost.init && !hasHost(result, parsed))
				result ~= parsed;
		}

		return result;
	}

	private void removeIncompatible(ServerDescription.ServerType serverType)
	{
		if (type == TopologyType.single)
			return;

		bool isRS = type == TopologyType.replicaSetWithPrimary
			|| type == TopologyType.replicaSetNoPrimary;
		bool isSharded = type == TopologyType.sharded;

		if (isRS)
		{
			removeServersByType(ServerDescription.ServerType.mongos);
			removeServersByType(ServerDescription.ServerType.standalone);
			return;
		}

		if (isSharded)
		{
			ServerRecord[] kept;
			foreach (ref s; servers)
			{
				auto st = s.description.classifiedType();
				if (st == ServerDescription.ServerType.mongos || st == ServerDescription.ServerType.unknown)
					kept ~= s;
			}
			servers = kept;
		}
	}

	private void removeServersByType(ServerDescription.ServerType serverType)
	{
		ServerRecord[] kept;
		foreach (ref s; servers)
		{
			if (s.description.classifiedType() != serverType)
				kept ~= s;
		}
		servers = kept;
	}

	private void transitionType(ServerDescription.ServerType serverType)
	{
		if (type == TopologyType.single)
			return;

		final switch (serverType) with (ServerDescription.ServerType)
		{
		case standalone:
			if (type == TopologyType.unknown)
			{
				if (seedCount <= 1)
					type = TopologyType.single;
				else
					removeServersByType(ServerDescription.ServerType.standalone);
			}
			break;

		case mongos:
			if (type == TopologyType.unknown)
				type = TopologyType.sharded;
			break;

		case RSPrimary:
			type = TopologyType.replicaSetWithPrimary;
			break;

		case RSSecondary, RSArbiter, RSOther, RSGhost:
			if (type == TopologyType.unknown)
				type = TopologyType.replicaSetNoPrimary;
			break;

		case unknown, possiblePrimary:
			if (type == TopologyType.replicaSetWithPrimary)
			{
				if (findPrimaryIdx() == -1)
					type = TopologyType.replicaSetNoPrimary;
			}
			break;
		}
	}

	void markFailed(MongoHost host)
	{
		foreach (ref s; servers)
		{
			if (s.host == host)
			{
				s.description = ServerDescription.init;
				break;
			}
		}

		if (type == TopologyType.replicaSetWithPrimary && findPrimaryIdx() == -1)
			type = TopologyType.replicaSetNoPrimary;
	}

	MongoHost[] allKnownHosts() const
	{
		import std.algorithm : map, filter;
		import std.array : array;

		MongoHost[] result;

		foreach (ref s; servers)
		{
			foreach (hostStr; s.description.hosts)
			{
				auto h = parseHostPort(hostStr);
				if (h != MongoHost.init && !hasHost(result, h))
					result ~= h;
			}
			foreach (hostStr; s.description.passives)
			{
				auto h = parseHostPort(hostStr);
				if (h != MongoHost.init && !hasHost(result, h))
					result ~= h;
			}
		}

		return result;
	}

	Nullable!MongoHost randomMongosHost(long localThresholdMS = 15) const
	{
		double minRTT = double.max;
		foreach (ref s; servers)
		{
			if (s.description.classifiedType() != ServerDescription.ServerType.mongos)
				continue;

			if (s.description.roundTripTime < minRTT)
				minRTT = s.description.roundTripTime;
		}

		if (minRTT == double.max)
			return Nullable!MongoHost.init;

		double threshold = minRTT + localThresholdMS / 1_000.0;
		MongoHost[] eligible;
		foreach (ref s; servers)
		{
			if (s.description.classifiedType() != ServerDescription.ServerType.mongos)
				continue;

			if (s.description.roundTripTime <= threshold)
				eligible ~= s.host;
		}

		if (!eligible.length)
			return Nullable!MongoHost.init;

		return Nullable!MongoHost(eligible[uniform(0, eligible.length)]);
	}

	Nullable!MongoHost primaryHost() const
	{
		foreach (ref s; servers)
		{
			if (s.description.isPrimary)
				return Nullable!MongoHost(s.host);
		}
		return Nullable!MongoHost.init;
	}

	Nullable!MongoHost randomSecondaryHost(long maxStalenessSeconds = -1) const
	{
		auto hosts = secondaryHosts(maxStalenessSeconds);
		if (!hosts.length)
			return Nullable!MongoHost.init;

		return Nullable!MongoHost(hosts[uniform(0, hosts.length)]);
	}

	MongoHost[] secondaryHosts(long maxStalenessSeconds = -1) const
	{
		MongoHost[] result;
		foreach (ref s; servers)
		{
			if (!s.description.isSecondaryNode)
				continue;

			if (maxStalenessSeconds >= 0 && isStaleSecondary(s.description, maxStalenessSeconds))
				continue;

			result ~= s.host;
		}
		return result;
	}

	Nullable!MongoHost randomHostWithinLatencyWindow(long localThresholdMS, long maxStalenessSeconds = -1) const
	{
		double minRTT = double.max;
		foreach (ref s; servers)
		{
			if (!s.description.isPrimary && !s.description.isSecondaryNode)
				continue;

			if (s.description.isSecondaryNode && maxStalenessSeconds >= 0
				&& isStaleSecondary(s.description, maxStalenessSeconds))
				continue;

			if (s.description.roundTripTime < minRTT)
				minRTT = s.description.roundTripTime;
		}

		if (minRTT == double.max)
			return Nullable!MongoHost.init;

		double threshold = minRTT + localThresholdMS / 1_000.0;
		MongoHost[] eligible;
		foreach (ref s; servers)
		{
			if (!s.description.isPrimary && !s.description.isSecondaryNode)
				continue;

			if (s.description.isSecondaryNode && maxStalenessSeconds >= 0
				&& isStaleSecondary(s.description, maxStalenessSeconds))
				continue;

			if (s.description.roundTripTime <= threshold)
				eligible ~= s.host;
		}

		if (!eligible.length)
			return Nullable!MongoHost.init;

		import std.random : uniform;
		return Nullable!MongoHost(eligible[uniform(0, eligible.length)]);
	}

	private bool isStaleSecondary(ref const ServerDescription desc, long maxStalenessSeconds) const
	{
		if (desc.lastWrite.lastWriteDate.isNull)
			return false;

		auto primaryIdx = findPrimaryIdx();
		auto hasPrimaryWriteDate = primaryIdx != -1
			&& !servers[primaryIdx].description.lastWrite.lastWriteDate.isNull;

		auto stalenessUsecs = hasPrimaryWriteDate
			? stalenessWithPrimary(desc, servers[primaryIdx].description)
			: stalenessWithoutPrimary(desc);

		if (stalenessUsecs < 0)
			return false;

		return stalenessUsecs > maxStalenessSeconds * 1_000_000L;
	}

	private long stalenessWithPrimary(ref const ServerDescription sec, ref const ServerDescription pri) const
	{
		auto sLag = sec.lastUpdateTimeUsecs - sec.lastWrite.lastWriteDate.get.value * 1000;
		auto pLag = pri.lastUpdateTimeUsecs - pri.lastWrite.lastWriteDate.get.value * 1000;

		return sLag - pLag + HEARTBEAT_FREQUENCY_USECS;
	}

	private long stalenessWithoutPrimary(ref const ServerDescription desc) const
	{
		long maxWriteDate = long.min;
		foreach (ref s; servers)
		{
			if (!s.description.isSecondaryNode || s.description.lastWrite.lastWriteDate.isNull)
				continue;

			auto wd = s.description.lastWrite.lastWriteDate.get.value * 1000;
			if (wd > maxWriteDate)
				maxWriteDate = wd;
		}

		if (maxWriteDate == long.min)
			return -1;

		auto sWriteDate = desc.lastWrite.lastWriteDate.get.value * 1000;
		return maxWriteDate - sWriteDate + HEARTBEAT_FREQUENCY_USECS;
	}

	private long findPrimaryIdx() const
	{
		foreach (i, ref s; servers)
		{
			if (s.description.isPrimary)
				return cast(long) i;
		}
		return -1;
	}
}

struct ServerRecord
{
	MongoHost host;
	ServerDescription description;
}

/// Default heartbeat frequency (10 seconds) used for staleness calculation.
private enum long HEARTBEAT_FREQUENCY_USECS = 10_000_000;

/**
 * Selects a server from the topology based on the given read preference.
 *
 * Returns the host to connect to, or Nullable!MongoHost.init if no
 * suitable server is available.
 */
Nullable!MongoHost selectServer(ref const TopologyDescription topology, ReadPreference pref,
	long localThresholdMS = 15, long maxStalenessSeconds = -1)
{
	// Single topology: return the one server regardless of read preference
	if (topology.type == TopologyType.single && topology.servers.length > 0)
		return Nullable!MongoHost(topology.servers[0].host);

	// Sharded: return random mongos (read preference forwarded to mongos)
	if (topology.type == TopologyType.sharded)
		return topology.randomMongosHost(localThresholdMS);

	// Replica set or unknown: apply read preference logic
	final switch (pref)
	{
	case ReadPreference.primary:
		return topology.primaryHost;

	case ReadPreference.primaryPreferred:
		auto primary = topology.primaryHost;
		if (!primary.isNull)
			return primary;
		return topology.randomSecondaryHost(maxStalenessSeconds);

	case ReadPreference.secondary:
		return topology.randomSecondaryHost(maxStalenessSeconds);

	case ReadPreference.secondaryPreferred:
		auto secondary = topology.randomSecondaryHost(maxStalenessSeconds);
		if (!secondary.isNull)
			return secondary;
		return topology.primaryHost;

	case ReadPreference.nearest:
		return topology.randomHostWithinLatencyWindow(localThresholdMS, maxStalenessSeconds);
	}
}

private bool hasHost(const MongoHost[] hosts, MongoHost h) pure nothrow @nogc
{
	foreach (ref existing; hosts)
	{
		if (existing == h)
			return true;
	}
	return false;
}

/**
 * Returns true if `incoming` is stale relative to `existing`.
 *
 * Per the SDAM spec, a server description with the same processId but
 * a lower or equal counter is stale. A different processId means the
 * server restarted, so the update is always fresh.
 */
private bool isStaleUpdate(ref const ServerDescription existing, ref const ServerDescription incoming)
	pure nothrow @nogc
{
	if (existing.topologyVersion.isNull || incoming.topologyVersion.isNull)
		return false;

	auto oldTV = existing.topologyVersion.get;
	auto newTV = incoming.topologyVersion.get;

	if (oldTV.processId != newTV.processId)
		return false;

	return newTV.counter <= oldTV.counter;
}

/// selectServer returns primary for ReadPreference.primary
unittest
{
	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);
	auto sec = MongoHost("secondary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";

	topo.update(primary, primaryDesc);
	topo.update(sec, secDesc);

	auto result = selectServer(topo, ReadPreference.primary);
	assert(!result.isNull);
	assert(result.get == primary);
}

/// selectServer returns null for ReadPreference.primary when no primary
unittest
{
	TopologyDescription topo;
	auto sec = MongoHost("secondary", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";

	topo.update(sec, secDesc);

	auto result = selectServer(topo, ReadPreference.primary);
	assert(result.isNull);
}

/// selectServer returns secondary for ReadPreference.secondary
unittest
{
	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);
	auto sec = MongoHost("secondary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";

	topo.update(primary, primaryDesc);
	topo.update(sec, secDesc);

	auto result = selectServer(topo, ReadPreference.secondary);
	assert(!result.isNull);
	assert(result.get == sec);
}

/// selectServer returns null for ReadPreference.secondary when no secondaries in replica set
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto primary = MongoHost("primary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	topo.update(primary, primaryDesc);

	auto result = selectServer(topo, ReadPreference.secondary);
	assert(result.isNull);
}

/// single topology returns server regardless of read preference
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.single;
	auto host = MongoHost("standalone", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;

	topo.update(host, desc);
	assert(topo.type == TopologyType.single);

	auto result = selectServer(topo, ReadPreference.secondary);
	assert(!result.isNull);
	assert(result.get == host);
}

/// selectServer primaryPreferred falls back to secondary
unittest
{
	TopologyDescription topo;
	auto sec = MongoHost("secondary", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";

	topo.update(sec, secDesc);

	auto result = selectServer(topo, ReadPreference.primaryPreferred);
	assert(!result.isNull);
	assert(result.get == sec);
}

/// selectServer primaryPreferred prefers primary when available
unittest
{
	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);
	auto sec = MongoHost("secondary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";

	topo.update(primary, primaryDesc);
	topo.update(sec, secDesc);

	auto result = selectServer(topo, ReadPreference.primaryPreferred);
	assert(!result.isNull);
	assert(result.get == primary);
}

/// selectServer secondaryPreferred falls back to primary
unittest
{
	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	topo.update(primary, primaryDesc);

	auto result = selectServer(topo, ReadPreference.secondaryPreferred);
	assert(!result.isNull);
	assert(result.get == primary);
}

/// selectServer secondaryPreferred prefers secondary when available
unittest
{
	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);
	auto sec = MongoHost("secondary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";

	topo.update(primary, primaryDesc);
	topo.update(sec, secDesc);

	auto result = selectServer(topo, ReadPreference.secondaryPreferred);
	assert(!result.isNull);
	assert(result.get == sec);
}

/// selectServer nearest returns primary when only primary available
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto primary = MongoHost("primary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";
	primaryDesc.roundTripTime = 0.005;

	topo.update(primary, primaryDesc);

	auto result = selectServer(topo, ReadPreference.nearest);
	assert(!result.isNull);
	assert(result.get == primary);
}

/// selectServer nearest returns secondary when only secondaries available
unittest
{
	TopologyDescription topo;
	auto sec = MongoHost("secondary", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";
	secDesc.roundTripTime = 0.010;

	topo.update(sec, secDesc);

	auto result = selectServer(topo, ReadPreference.nearest);
	assert(!result.isNull);
	assert(result.get == sec);
}

/// selectServer nearest selects from all data-bearing members within latency window
unittest
{
	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);
	auto sec1 = MongoHost("secondary1", 27017);
	auto sec2 = MongoHost("secondary2", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";
	primaryDesc.roundTripTime = 0.005;

	ServerDescription sec1Desc;
	sec1Desc.secondary = true;
	sec1Desc.setName = "rs0";
	sec1Desc.roundTripTime = 0.010;

	ServerDescription sec2Desc;
	sec2Desc.secondary = true;
	sec2Desc.setName = "rs0";
	sec2Desc.roundTripTime = 0.012;

	topo.update(primary, primaryDesc);
	topo.update(sec1, sec1Desc);
	topo.update(sec2, sec2Desc);

	bool sawPrimary, sawSec1, sawSec2;
	foreach (_; 0 .. 200)
	{
		auto result = selectServer(topo, ReadPreference.nearest);
		assert(!result.isNull);
		if (result.get == primary) sawPrimary = true;
		if (result.get == sec1) sawSec1 = true;
		if (result.get == sec2) sawSec2 = true;
	}

	assert(sawPrimary);
	assert(sawSec1);
	assert(sawSec2);
}

/// selectServer nearest excludes servers outside latency window
unittest
{
	TopologyDescription topo;
	auto fast = MongoHost("fast", 27017);
	auto slow = MongoHost("slow", 27017);

	ServerDescription fastDesc;
	fastDesc.isWritablePrimary = true;
	fastDesc.setName = "rs0";
	fastDesc.roundTripTime = 0.005;

	ServerDescription slowDesc;
	slowDesc.secondary = true;
	slowDesc.setName = "rs0";
	slowDesc.roundTripTime = 0.500;

	topo.update(fast, fastDesc);
	topo.update(slow, slowDesc);

	foreach (_; 0 .. 100)
	{
		auto result = selectServer(topo, ReadPreference.nearest, 15);
		assert(!result.isNull);
		assert(result.get == fast);
	}
}

/// selectServer nearest with large localThresholdMS includes all servers
unittest
{
	TopologyDescription topo;
	auto fast = MongoHost("fast", 27017);
	auto slow = MongoHost("slow", 27017);

	ServerDescription fastDesc;
	fastDesc.isWritablePrimary = true;
	fastDesc.setName = "rs0";
	fastDesc.roundTripTime = 0.005;

	ServerDescription slowDesc;
	slowDesc.secondary = true;
	slowDesc.setName = "rs0";
	slowDesc.roundTripTime = 0.500;

	topo.update(fast, fastDesc);
	topo.update(slow, slowDesc);

	bool sawFast, sawSlow;
	foreach (_; 0 .. 200)
	{
		auto result = selectServer(topo, ReadPreference.nearest, 1000);
		assert(!result.isNull);
		if (result.get == fast) sawFast = true;
		if (result.get == slow) sawSlow = true;
	}

	assert(sawFast);
	assert(sawSlow);
}

/// selectServer returns null on empty topology
unittest
{
	TopologyDescription topo;

	assert(selectServer(topo, ReadPreference.primary).isNull);
	assert(selectServer(topo, ReadPreference.secondary).isNull);
	assert(selectServer(topo, ReadPreference.nearest).isNull);
	assert(selectServer(topo, ReadPreference.primaryPreferred).isNull);
	assert(selectServer(topo, ReadPreference.secondaryPreferred).isNull);
}

/// TopologyDescription.update updates existing server record
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("host1", 27017);

	ServerDescription desc1;
	desc1.secondary = true;
	desc1.setName = "rs0";

	topo.update(host, desc1);
	assert(topo.servers.length == 1);
	assert(topo.servers[0].description.isSecondaryNode);

	ServerDescription desc2;
	desc2.isWritablePrimary = true;
	desc2.setName = "rs0";

	topo.update(host, desc2);
	assert(topo.servers.length == 1);
	assert(topo.servers[0].description.isPrimary);
}

/// TopologyDescription.markFailed resets server description
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host = MongoHost("host1", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;
	desc.setName = "rs0";

	topo.update(host, desc);
	assert(topo.primaryHost.get == host);

	topo.markFailed(host);
	assert(topo.primaryHost.isNull);
}

/// TopologyDescription.setName is set from first server with setName
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host = MongoHost("host1", 27017);

	ServerDescription desc;
	desc.setName = "rs0";
	desc.isWritablePrimary = true;

	topo.update(host, desc);
	assert(topo.setName == "rs0");
}

/// TopologyDescription.allKnownHosts collects hosts from server descriptions
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host = MongoHost("host1", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;
	desc.setName = "rs0";
	desc.hosts = ["host1:27017", "host2:27017", "host3:27017"];

	topo.update(host, desc);

	auto known = topo.allKnownHosts();
	assert(known.length == 3);
}

/// update with higher topology version counter overwrites
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("host1", 27017);
	auto pid = BsonObjectID.fromHexString("aabbccddeeff00112233aabb");

	ServerDescription desc1;
	desc1.secondary = true;
	desc1.setName = "rs0";
	desc1.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 1));

	topo.update(host, desc1);
	assert(topo.servers[0].description.isSecondaryNode);

	ServerDescription desc2;
	desc2.isWritablePrimary = true;
	desc2.setName = "rs0";
	desc2.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 2));

	topo.update(host, desc2);
	assert(topo.servers[0].description.isPrimary);
}

/// update with lower topology version counter is rejected
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("host1", 27017);
	auto pid = BsonObjectID.fromHexString("aabbccddeeff00112233aabb");

	ServerDescription desc1;
	desc1.isWritablePrimary = true;
	desc1.setName = "rs0";
	desc1.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 5));

	topo.update(host, desc1);
	assert(topo.servers[0].description.isPrimary);

	ServerDescription desc2;
	desc2.secondary = true;
	desc2.setName = "rs0";
	desc2.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 3));

	topo.update(host, desc2);
	assert(topo.servers[0].description.isPrimary);
}

/// update with equal topology version counter is rejected
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("host1", 27017);
	auto pid = BsonObjectID.fromHexString("aabbccddeeff00112233aabb");

	ServerDescription desc1;
	desc1.isWritablePrimary = true;
	desc1.setName = "rs0";
	desc1.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 5));

	topo.update(host, desc1);

	ServerDescription desc2;
	desc2.secondary = true;
	desc2.setName = "rs0";
	desc2.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 5));

	topo.update(host, desc2);
	assert(topo.servers[0].description.isPrimary);
}

/// update with different processId always overwrites (server restarted)
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("host1", 27017);
	auto pid1 = BsonObjectID.fromHexString("aabbccddeeff00112233aabb");
	auto pid2 = BsonObjectID.fromHexString("112233aabbccddeeff001122");

	ServerDescription desc1;
	desc1.isWritablePrimary = true;
	desc1.setName = "rs0";
	desc1.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid1, 100));

	topo.update(host, desc1);
	assert(topo.servers[0].description.isPrimary);

	ServerDescription desc2;
	desc2.secondary = true;
	desc2.setName = "rs0";
	desc2.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid2, 1));

	topo.update(host, desc2);
	assert(topo.servers[0].description.isSecondaryNode);
}

/// update without topologyVersion always overwrites (pre-4.4 compat)
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("host1", 27017);

	ServerDescription desc1;
	desc1.isWritablePrimary = true;
	desc1.setName = "rs0";

	topo.update(host, desc1);
	assert(topo.servers[0].description.isPrimary);

	ServerDescription desc2;
	desc2.secondary = true;
	desc2.setName = "rs0";

	topo.update(host, desc2);
	assert(topo.servers[0].description.isSecondaryNode);
}

/// primary update removes server not in member list
unittest
{
	TopologyDescription topo;
	auto hostA = MongoHost("hostA", 27017);
	auto hostB = MongoHost("hostB", 27017);
	auto hostC = MongoHost("hostC", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";

	topo.update(hostA, secDesc);
	topo.update(hostB, secDesc);
	topo.update(hostC, secDesc);
	assert(topo.servers.length == 3);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";
	primaryDesc.hosts = ["hostA:27017", "hostB:27017"];

	topo.update(hostA, primaryDesc);
	assert(topo.servers.length == 2);
	assert(!topo.primaryHost.isNull);
	assert(topo.primaryHost.get == hostA);
}

/// primary update keeps all servers in member list
unittest
{
	TopologyDescription topo;
	auto hostA = MongoHost("hostA", 27017);
	auto hostB = MongoHost("hostB", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";
	topo.update(hostB, secDesc);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";
	primaryDesc.hosts = ["hostA:27017", "hostB:27017"];

	topo.update(hostA, primaryDesc);
	assert(topo.servers.length == 2);
}

/// secondary update does not remove any servers
unittest
{
	TopologyDescription topo;
	auto hostA = MongoHost("hostA", 27017);
	auto hostB = MongoHost("hostB", 27017);
	auto hostC = MongoHost("hostC", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";
	secDesc.hosts = ["hostA:27017", "hostB:27017"];

	topo.update(hostA, secDesc);
	topo.update(hostB, secDesc);
	topo.update(hostC, secDesc);
	assert(topo.servers.length == 3);
}

/// selectServer excludes stale secondary with maxStalenessSeconds
unittest
{
	import vibe.data.bson : BsonDate;

	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);
	auto freshSec = MongoHost("fresh", 27017);
	auto staleSec = MongoHost("stale", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";
	primaryDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(1_000_000)));
	primaryDesc.lastUpdateTimeUsecs = 1_000_000_000;

	ServerDescription freshDesc;
	freshDesc.secondary = true;
	freshDesc.setName = "rs0";
	freshDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(999_000)));
	freshDesc.lastUpdateTimeUsecs = 1_000_000_000;

	ServerDescription staleDesc;
	staleDesc.secondary = true;
	staleDesc.setName = "rs0";
	staleDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(900_000)));
	staleDesc.lastUpdateTimeUsecs = 1_000_000_000;

	topo.update(primary, primaryDesc);
	topo.update(freshSec, freshDesc);
	topo.update(staleSec, staleDesc);

	// maxStaleness=120s: staleSec has 100s lag, should be included
	auto result = selectServer(topo, ReadPreference.secondary, 15, 120);
	assert(!result.isNull);

	// maxStaleness=90s: staleSec has 100s lag, only freshSec eligible
	bool sawStale = false;
	foreach (_; 0 .. 100)
	{
		auto r = selectServer(topo, ReadPreference.secondary, 15, 90);
		assert(!r.isNull);
		if (r.get == staleSec) sawStale = true;
	}
	assert(!sawStale);
}

/// selectServer with maxStalenessSeconds=-1 disables staleness filtering
unittest
{
	import vibe.data.bson : BsonDate;

	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);
	auto staleSec = MongoHost("stale", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";
	primaryDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(1_000_000)));
	primaryDesc.lastUpdateTimeUsecs = 1_000_000_000;

	ServerDescription staleDesc;
	staleDesc.secondary = true;
	staleDesc.setName = "rs0";
	staleDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(1)));
	staleDesc.lastUpdateTimeUsecs = 1_000_000_000;

	topo.update(primary, primaryDesc);
	topo.update(staleSec, staleDesc);

	auto result = selectServer(topo, ReadPreference.secondary, 15, -1);
	assert(!result.isNull);
	assert(result.get == staleSec);
}

/// staleness calc without primary uses SMax fallback
unittest
{
	import vibe.data.bson : BsonDate;

	TopologyDescription topo;
	auto freshSec = MongoHost("fresh", 27017);
	auto staleSec = MongoHost("stale", 27017);

	ServerDescription freshDesc;
	freshDesc.secondary = true;
	freshDesc.setName = "rs0";
	freshDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(1_000_000)));
	freshDesc.lastUpdateTimeUsecs = 1_000_000_000;

	ServerDescription staleDesc;
	staleDesc.secondary = true;
	staleDesc.setName = "rs0";
	staleDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(900_000)));
	staleDesc.lastUpdateTimeUsecs = 1_000_000_000;

	topo.update(freshSec, freshDesc);
	topo.update(staleSec, staleDesc);

	// No primary. SMax.lastWriteDate - S.lastWriteDate = 100s + 10s heartbeat = 110s
	// maxStaleness=120s: both eligible
	auto result = selectServer(topo, ReadPreference.secondary, 15, 120);
	assert(!result.isNull);

	// maxStaleness=90s: staleSec has 110s staleness, excluded
	bool sawStale = false;
	foreach (_; 0 .. 100)
	{
		auto r = selectServer(topo, ReadPreference.secondary, 15, 90);
		assert(!r.isNull);
		if (r.get == staleSec) sawStale = true;
	}
	assert(!sawStale);
}

/// unknown transitions to replicaSetWithPrimary when primary discovered
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host = MongoHost("host1", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;
	desc.setName = "rs0";

	topo.update(host, desc);
	assert(topo.type == TopologyType.replicaSetWithPrimary);
}

/// replicaSetWithPrimary transitions to replicaSetNoPrimary when primary fails
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto primary = MongoHost("primary", 27017);
	auto sec = MongoHost("secondary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";

	topo.update(primary, primaryDesc);
	topo.update(sec, secDesc);
	assert(topo.type == TopologyType.replicaSetWithPrimary);

	topo.markFailed(primary);
	assert(topo.type == TopologyType.replicaSetNoPrimary);
}

/// sharded topology only keeps mongos servers
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.sharded;
	auto mongos = MongoHost("mongos", 27017);
	auto rs = MongoHost("rs", 27017);

	ServerDescription mongosDesc;
	mongosDesc.msg = "isdbgrid";

	ServerDescription rsDesc;
	rsDesc.isWritablePrimary = true;
	rsDesc.setName = "rs0";

	topo.update(mongos, mongosDesc);
	topo.update(rs, rsDesc);

	// RS server should be removed as incompatible with sharded topology
	assert(topo.servers.length == 1);
	assert(topo.servers[0].host == mongos);
}

/// server type classification from hello response fields
unittest
{
	ServerDescription primary;
	primary.isWritablePrimary = true;
	primary.setName = "rs0";
	assert(primary.classifiedType() == ServerDescription.ServerType.RSPrimary);

	ServerDescription secondary;
	secondary.secondary = true;
	secondary.setName = "rs0";
	assert(secondary.classifiedType() == ServerDescription.ServerType.RSSecondary);

	ServerDescription arbiter;
	arbiter.arbiterOnly = true;
	arbiter.setName = "rs0";
	assert(arbiter.classifiedType() == ServerDescription.ServerType.RSArbiter);

	ServerDescription mongos;
	mongos.msg = "isdbgrid";
	assert(mongos.classifiedType() == ServerDescription.ServerType.mongos);

	ServerDescription standalone;
	standalone.isWritablePrimary = true;
	assert(standalone.classifiedType() == ServerDescription.ServerType.standalone);

	ServerDescription unknown;
	assert(unknown.classifiedType() == ServerDescription.ServerType.unknown);
}

/// RSOther classification for setName member that is neither primary, secondary, nor arbiter
unittest
{
	ServerDescription desc;
	desc.setName = "rs0";
	assert(desc.classifiedType() == ServerDescription.ServerType.RSOther);
}

/// malformed response with both isWritablePrimary and secondary classifies as RSOther
unittest
{
	ServerDescription desc;
	desc.isWritablePrimary = true;
	desc.secondary = true;
	desc.setName = "rs0";
	assert(desc.classifiedType() == ServerDescription.ServerType.RSOther);
}

/// unknown transitions to sharded when mongos discovered
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("mongos1", 27017);

	ServerDescription desc;
	desc.msg = "isdbgrid";

	topo.update(host, desc);
	assert(topo.type == TopologyType.sharded);
}

/// unknown transitions to replicaSetNoPrimary when secondary discovered
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("sec1", 27017);

	ServerDescription desc;
	desc.secondary = true;
	desc.setName = "rs0";

	topo.update(host, desc);
	assert(topo.type == TopologyType.replicaSetNoPrimary);
}

/// replicaSetNoPrimary transitions to replicaSetWithPrimary when primary arrives
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto sec = MongoHost("sec", 27017);
	auto pri = MongoHost("pri", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";
	topo.update(sec, secDesc);
	assert(topo.type == TopologyType.replicaSetNoPrimary);

	ServerDescription priDesc;
	priDesc.isWritablePrimary = true;
	priDesc.setName = "rs0";
	topo.update(pri, priDesc);
	assert(topo.type == TopologyType.replicaSetWithPrimary);
}

/// sharded selectServer returns random mongos
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.sharded;
	auto m1 = MongoHost("mongos1", 27017);
	auto m2 = MongoHost("mongos2", 27017);

	ServerDescription desc;
	desc.msg = "isdbgrid";

	topo.update(m1, desc);
	topo.update(m2, desc);

	bool sawM1, sawM2;
	foreach (_; 0 .. 200)
	{
		auto r = selectServer(topo, ReadPreference.primary);
		assert(!r.isNull);
		if (r.get == m1) sawM1 = true;
		if (r.get == m2) sawM2 = true;
	}
	assert(sawM1);
	assert(sawM2);
}

/// sharded selectServer returns null when no mongos available
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.sharded;

	auto result = selectServer(topo, ReadPreference.primary);
	assert(result.isNull);
}

/// selectServer on empty single topology returns null
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.single;

	auto result = selectServer(topo, ReadPreference.primary);
	assert(result.isNull);
}

/// nearest read preference with staleness filtering excludes stale secondaries
unittest
{
	import vibe.data.bson : BsonDate;

	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto freshSec = MongoHost("fresh", 27017);
	auto staleSec = MongoHost("stale", 27017);

	ServerDescription freshDesc;
	freshDesc.secondary = true;
	freshDesc.setName = "rs0";
	freshDesc.roundTripTime = 0.005;
	freshDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(1_000_000)));
	freshDesc.lastUpdateTimeUsecs = 1_000_000_000;

	ServerDescription staleDesc;
	staleDesc.secondary = true;
	staleDesc.setName = "rs0";
	staleDesc.roundTripTime = 0.005;
	staleDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(900_000)));
	staleDesc.lastUpdateTimeUsecs = 1_000_000_000;

	topo.update(freshSec, freshDesc);
	topo.update(staleSec, staleDesc);

	// staleSec has 110s staleness, maxStaleness=90s should exclude it
	bool sawStale = false;
	foreach (_; 0 .. 100)
	{
		auto r = selectServer(topo, ReadPreference.nearest, 15, 90);
		assert(!r.isNull);
		if (r.get == staleSec) sawStale = true;
	}
	assert(!sawStale);
}

/// secondaryPreferred with all secondaries stale falls back to primary
unittest
{
	import vibe.data.bson : BsonDate;

	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto primary = MongoHost("primary", 27017);
	auto staleSec = MongoHost("stale", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";
	primaryDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(1_000_000)));
	primaryDesc.lastUpdateTimeUsecs = 1_000_000_000;

	ServerDescription staleDesc;
	staleDesc.secondary = true;
	staleDesc.setName = "rs0";
	staleDesc.lastWrite = ServerDescription.LastWrite(Nullable!BsonDate(BsonDate(800_000)));
	staleDesc.lastUpdateTimeUsecs = 1_000_000_000;

	topo.update(primary, primaryDesc);
	topo.update(staleSec, staleDesc);

	// staleSec has 200s + 10s staleness, maxStaleness=90 excludes it, falls back to primary
	auto result = selectServer(topo, ReadPreference.secondaryPreferred, 15, 90);
	assert(!result.isNull);
	assert(result.get == primary);
}

/// isStaleUpdate: incoming has topologyVersion but existing does not — accepts update
unittest
{
	auto pid = BsonObjectID.fromHexString("aabbccddeeff00112233aabb");

	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host = MongoHost("host1", 27017);

	ServerDescription desc1;
	desc1.isWritablePrimary = true;
	desc1.setName = "rs0";

	topo.update(host, desc1);
	assert(topo.servers[0].description.isPrimary);

	ServerDescription desc2;
	desc2.secondary = true;
	desc2.setName = "rs0";
	desc2.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 1));

	topo.update(host, desc2);
	assert(topo.servers[0].description.isSecondaryNode);
}

/// standalone in unknown multi-seed topology is removed, not promoted to single
unittest
{
	TopologyDescription topo;
	topo.seedCount = 2;
	auto standalone = MongoHost("standalone", 27017);
	auto other = MongoHost("other", 27017);

	ServerDescription standaloneDesc;
	standaloneDesc.isWritablePrimary = true;

	ServerDescription unknownDesc;

	topo.update(other, unknownDesc);
	topo.update(standalone, standaloneDesc);

	assert(topo.type == TopologyType.unknown);
	assert(topo.servers.length == 1);
	assert(topo.servers[0].host == other);
}

/// standalone in unknown single-seed topology transitions to single
unittest
{
	TopologyDescription topo;
	topo.seedCount = 1;
	auto host = MongoHost("standalone", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;

	topo.update(host, desc);
	assert(topo.type == TopologyType.single);
	assert(topo.servers.length == 1);
}

/// standalone in replica set topology is removed
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto sec = MongoHost("sec", 27017);
	auto standalone = MongoHost("standalone", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";
	topo.update(sec, secDesc);

	ServerDescription standaloneDesc;
	standaloneDesc.isWritablePrimary = true;
	topo.update(standalone, standaloneDesc);

	assert(topo.servers.length == 1);
	assert(topo.servers[0].host == sec);
}

/// mongos in replica set topology is removed
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto sec = MongoHost("sec", 27017);
	auto mongos = MongoHost("mongos", 27017);

	ServerDescription secDesc;
	secDesc.secondary = true;
	secDesc.setName = "rs0";
	topo.update(sec, secDesc);

	ServerDescription mongosDesc;
	mongosDesc.msg = "isdbgrid";
	topo.update(mongos, mongosDesc);

	assert(topo.servers.length == 1);
	assert(topo.servers[0].host == sec);
}

/// standalone in sharded topology is removed
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.sharded;
	auto mongos = MongoHost("mongos", 27017);
	auto standalone = MongoHost("standalone", 27017);

	ServerDescription mongosDesc;
	mongosDesc.msg = "isdbgrid";
	topo.update(mongos, mongosDesc);

	ServerDescription standaloneDesc;
	standaloneDesc.isWritablePrimary = true;
	topo.update(standalone, standaloneDesc);

	assert(topo.servers.length == 1);
	assert(topo.servers[0].host == mongos);
}

/// new primary demotes old primary (split-brain)
unittest
{
	import vibe.data.bson : BsonObjectID;

	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host1 = MongoHost("host1", 27017);
	auto host2 = MongoHost("host2", 27017);

	auto eid1 = BsonObjectID.fromHexString("aabbccddeeff00112233aa01");
	auto eid2 = BsonObjectID.fromHexString("aabbccddeeff00112233aa02");

	ServerDescription desc1;
	desc1.isWritablePrimary = true;
	desc1.setName = "rs0";
	desc1.setVersion = Nullable!int(1);
	desc1.electionId = Nullable!BsonObjectID(eid1);

	topo.update(host1, desc1);
	assert(topo.servers[0].description.isPrimary);

	ServerDescription desc2;
	desc2.isWritablePrimary = true;
	desc2.setName = "rs0";
	desc2.setVersion = Nullable!int(1);
	desc2.electionId = Nullable!BsonObjectID(eid2);

	topo.update(host2, desc2);

	bool host1Primary, host2Primary;
	foreach (ref s; topo.servers)
	{
		if (s.host == host1 && s.description.isPrimary) host1Primary = true;
		if (s.host == host2 && s.description.isPrimary) host2Primary = true;
	}
	assert(!host1Primary);
	assert(host2Primary);
}

/// stale primary with lower electionId is demoted to unknown
unittest
{
	import vibe.data.bson : BsonObjectID;

	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host1 = MongoHost("host1", 27017);
	auto host2 = MongoHost("host2", 27017);

	auto eid1 = BsonObjectID.fromHexString("aabbccddeeff00112233aa02");
	auto eid2 = BsonObjectID.fromHexString("aabbccddeeff00112233aa01");

	ServerDescription desc1;
	desc1.isWritablePrimary = true;
	desc1.setName = "rs0";
	desc1.setVersion = Nullable!int(1);
	desc1.electionId = Nullable!BsonObjectID(eid1);
	topo.update(host1, desc1);

	ServerDescription desc2;
	desc2.isWritablePrimary = true;
	desc2.setName = "rs0";
	desc2.setVersion = Nullable!int(1);
	desc2.electionId = Nullable!BsonObjectID(eid2);
	topo.update(host2, desc2);

	bool host1Primary, host2Primary;
	foreach (ref s; topo.servers)
	{
		if (s.host == host1 && s.description.isPrimary) host1Primary = true;
		if (s.host == host2 && s.description.isPrimary) host2Primary = true;
	}
	assert(host1Primary);
	assert(!host2Primary);
}

/// stale primary with lower setVersion is demoted
unittest
{
	import vibe.data.bson : BsonObjectID;

	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host1 = MongoHost("host1", 27017);
	auto host2 = MongoHost("host2", 27017);

	auto eid = BsonObjectID.fromHexString("aabbccddeeff00112233aa01");

	ServerDescription desc1;
	desc1.isWritablePrimary = true;
	desc1.setName = "rs0";
	desc1.setVersion = Nullable!int(2);
	desc1.electionId = Nullable!BsonObjectID(eid);
	topo.update(host1, desc1);

	ServerDescription desc2;
	desc2.isWritablePrimary = true;
	desc2.setName = "rs0";
	desc2.setVersion = Nullable!int(1);
	desc2.electionId = Nullable!BsonObjectID(eid);
	topo.update(host2, desc2);

	bool host1Primary, host2Primary;
	foreach (ref s; topo.servers)
	{
		if (s.host == host1 && s.description.isPrimary) host1Primary = true;
		if (s.host == host2 && s.description.isPrimary) host2Primary = true;
	}
	assert(host1Primary);
	assert(!host2Primary);
}

/// sharded selectServer applies latency window to mongos selection
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.sharded;
	auto fast = MongoHost("fast-mongos", 27017);
	auto slow = MongoHost("slow-mongos", 27017);

	ServerDescription fastDesc;
	fastDesc.msg = "isdbgrid";
	fastDesc.roundTripTime = 0.005;

	ServerDescription slowDesc;
	slowDesc.msg = "isdbgrid";
	slowDesc.roundTripTime = 0.500;

	topo.update(fast, fastDesc);
	topo.update(slow, slowDesc);

	foreach (_; 0 .. 100)
	{
		auto r = selectServer(topo, ReadPreference.primary, 15);
		assert(!r.isNull);
		assert(r.get == fast);
	}
}

/// sharded selectServer with large threshold includes all mongos
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.sharded;
	auto fast = MongoHost("fast-mongos", 27017);
	auto slow = MongoHost("slow-mongos", 27017);

	ServerDescription fastDesc;
	fastDesc.msg = "isdbgrid";
	fastDesc.roundTripTime = 0.005;

	ServerDescription slowDesc;
	slowDesc.msg = "isdbgrid";
	slowDesc.roundTripTime = 0.500;

	topo.update(fast, fastDesc);
	topo.update(slow, slowDesc);

	bool sawFast, sawSlow;
	foreach (_; 0 .. 200)
	{
		auto r = selectServer(topo, ReadPreference.primary, 1000);
		assert(!r.isNull);
		if (r.get == fast) sawFast = true;
		if (r.get == slow) sawSlow = true;
	}
	assert(sawFast);
	assert(sawSlow);
}
