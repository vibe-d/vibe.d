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

import std.typecons : Nullable;

@safe:

/**
 * Tracks the known state of all servers in a deployment.
 *
 * Updated after each successful handshake. Used by server selection
 * to pick an appropriate host for a given read preference.
 */
struct TopologyDescription
{
	ServerRecord[] servers;
	string setName;

	void update(MongoHost host, ServerDescription desc)
	{
		foreach (ref s; servers)
		{
			if (s.host == host)
			{
				if (isStaleUpdate(s.description, desc))
					return;

				s.description = desc;
				return;
			}
		}
		servers ~= ServerRecord(host, desc);

		if (!setName.length && desc.setName.length)
			setName = desc.setName;
	}

	void markFailed(MongoHost host)
	{
		foreach (ref s; servers)
		{
			if (s.host == host)
			{
				s.description = ServerDescription.init;
				return;
			}
		}
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

	Nullable!MongoHost primaryHost() const
	{
		foreach (ref s; servers)
		{
			if (s.description.isPrimary)
				return Nullable!MongoHost(s.host);
		}
		return Nullable!MongoHost.init;
	}

	MongoHost[] secondaryHosts() const
	{
		MongoHost[] result;
		foreach (ref s; servers)
		{
			if (s.description.isSecondaryNode)
				result ~= s.host;
		}
		return result;
	}

	Nullable!MongoHost randomSecondaryHost() const
	{
		auto hosts = secondaryHosts;
		if (!hosts.length)
			return Nullable!MongoHost.init;
		import std.random : uniform;
		return Nullable!MongoHost(hosts[uniform(0, hosts.length)]);
	}

	Nullable!MongoHost randomHostWithinLatencyWindow(long localThresholdMS) const
	{
		double minRTT = double.max;
		foreach (ref s; servers)
		{
			if (!s.description.isPrimary && !s.description.isSecondaryNode)
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

			if (s.description.roundTripTime <= threshold)
				eligible ~= s.host;
		}

		if (!eligible.length)
			return Nullable!MongoHost.init;

		import std.random : uniform;
		return Nullable!MongoHost(eligible[uniform(0, eligible.length)]);
	}
}

struct ServerRecord
{
	MongoHost host;
	ServerDescription description;
}

/**
 * Selects a server from the topology based on the given read preference.
 *
 * Returns the host to connect to, or Nullable!MongoHost.init if no
 * suitable server is available.
 */
Nullable!MongoHost selectServer(ref const TopologyDescription topology, ReadPreference pref, long localThresholdMS = 15)
{
	final switch (pref)
	{
	case ReadPreference.primary:
		return topology.primaryHost;

	case ReadPreference.primaryPreferred:
		auto primary = topology.primaryHost;
		if (!primary.isNull)
			return primary;
		return topology.randomSecondaryHost;

	case ReadPreference.secondary:
		return topology.randomSecondaryHost;

	case ReadPreference.secondaryPreferred:
		auto secondary = topology.randomSecondaryHost;
		if (!secondary.isNull)
			return secondary;
		return topology.primaryHost;

	case ReadPreference.nearest:
		return topology.randomHostWithinLatencyWindow(localThresholdMS);
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

/// selectServer returns null for ReadPreference.secondary when no secondaries
unittest
{
	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;

	topo.update(primary, primaryDesc);

	auto result = selectServer(topo, ReadPreference.secondary);
	assert(result.isNull);
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
	auto primary = MongoHost("primary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
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
	auto host = MongoHost("host1", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;

	topo.update(host, desc);
	assert(topo.primaryHost.get == host);

	topo.markFailed(host);
	assert(topo.primaryHost.isNull);
}

/// TopologyDescription.setName is set from first server with setName
unittest
{
	TopologyDescription topo;
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
	auto host = MongoHost("host1", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;
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
