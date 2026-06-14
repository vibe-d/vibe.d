/**
	MongoDB topology description and server selection.

	Implements server selection logic for replica sets based on the
	MongoDB Server Selection specification.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/server-selection/server-selection.md)

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.topology;

import vibe.db.mongo.connection : ServerDescription, TopologyVersion;
import vibe.data.bson : BsonObjectID;
import vibe.db.mongo.settings;
import vibe.core.log;

import std.random : uniform;
import std.range : chain;
import std.typecons : Nullable;
import core.time : Duration;

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
	sharded,
	loadBalanced
}

bool supportsRetryableWrites(TopologyType type)
{
	return type != TopologyType.single;
}

struct TopologyDescription
{
	import vibe.data.bson : BsonObjectID;

	ServerRecord[] servers;
	string setName;
	TopologyType type = TopologyType.unknown;
	uint seedCount;
	/// Configured heartbeat interval, fed into the maxStaleness formula. Defaults to the
	/// spec default (10s) so an unseeded topology matches the historical hardcoded value.
	long heartbeatFrequencyMS = 10_000;
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

		auto serverType = desc.classifiedType();

		// SDAM: in a Sharded topology a server reporting as anything other than a mongos
		// is simply removed — it must not adopt its setName, prune the mongos list via the
		// primary path, or flip the topology type to replicaSetWithPrimary.
		if (type == TopologyType.sharded
			&& serverType != ServerDescription.ServerType.mongos
			&& serverType != ServerDescription.ServerType.unknown)
		{
			removeHost(host);
			return;
		}

		// SDAM: a server reporting a different replica-set name belongs to another set;
		// remove it before it can demote the real primary or contribute foreign members.
		if (setName.length && desc.setName.length && desc.setName != setName)
		{
			removeHost(host);
			return;
		}

		if (!setName.length && desc.setName.length)
			setName = desc.setName;

		if (desc.isPrimary)
		{
			if (handleNewPrimary(host, desc))
				pruneNonMembers(desc);
			else
				return;
		}

		removeIncompatible(serverType);
		transitionType(serverType);
	}

	private void removeHost(MongoHost host)
	{
		ServerRecord[] kept;
		foreach (ref s; servers)
			if (s.host != host)
				kept ~= s;
		servers = kept;
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
		if (isStalePrimary(desc.electionId, desc.setVersion, maxElectionId, maxSetVersion))
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

		import std.algorithm : canFind;

		ServerRecord[] kept;
		foreach (ref s; servers)
		{
			if (memberHosts.canFind(s.host))
				kept ~= s;
		}

		servers = kept;
	}

	private static MongoHost[] collectMemberHosts(ref const ServerDescription desc)
	{
		import std.algorithm : canFind;

		MongoHost[] result;

		foreach (h; chain(desc.hosts, desc.passives, desc.arbiters))
		{
			auto parsed = parseHostPort(h);
			if (parsed != MongoHost.init && !result.canFind(parsed))
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
		// single and loadBalanced are fixed by configuration; they bypass SDAM transitions.
		if (type == TopologyType.single || type == TopologyType.loadBalanced)
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
		import std.algorithm : canFind;

		MongoHost[] result;

		void addHost(MongoHost h)
		{
			if (h != MongoHost.init && !result.canFind(h))
				result ~= h;
		}

		foreach (ref s; servers)
		{
			addHost(s.host);
			foreach (hostStr; chain(s.description.hosts, s.description.passives, s.description.arbiters))
				addHost(parseHostPort(hostStr));
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

	Nullable!MongoHost randomSecondaryHost(long maxStalenessSeconds = -1, string[string][] tagSets = null) const
	{
		auto hosts = secondaryHosts(maxStalenessSeconds, tagSets);
		if (!hosts.length)
			return Nullable!MongoHost.init;

		return Nullable!MongoHost(hosts[uniform(0, hosts.length)]);
	}

	MongoHost[] secondaryHosts(long maxStalenessSeconds = -1, string[string][] tagSets = null) const
	{
		import std.algorithm : map;
		import std.array : array;

		size_t[] eligible;
		foreach (i, ref s; servers)
		{
			if (!s.description.isSecondaryNode)
				continue;

			if (maxStalenessSeconds >= 0 && isStaleSecondary(s.description, maxStalenessSeconds))
				continue;

			eligible ~= i;
		}

		return selectIndicesByTagSets(eligible, tagSets).map!(i => servers[i].host).array.dup;
	}

	private size_t[] selectIndicesByTagSets(size_t[] indices, string[string][] tagSets) const
	{
		import std.algorithm : filter;
		import std.array : array;

		if (!tagSets.length)
			return indices;

		foreach (tagSet; tagSets)
		{
			auto matched = indices
				.filter!(i => serverMatchesTagSet(servers[i].description.tags, tagSet))
				.array;
			if (matched.length)
				return matched;
		}

		return null;
	}

	Nullable!MongoHost randomHostWithinLatencyWindow(long localThresholdMS,
		long maxStalenessSeconds = -1, string[string][] tagSets = null) const
	{
		size_t[] eligible;
		foreach (i, ref s; servers)
		{
			if (!s.description.isPrimary && !s.description.isSecondaryNode)
				continue;

			if (s.description.isSecondaryNode && maxStalenessSeconds >= 0
				&& isStaleSecondary(s.description, maxStalenessSeconds))
				continue;

			eligible ~= i;
		}

		eligible = selectIndicesByTagSets(eligible, tagSets);
		if (!eligible.length)
			return Nullable!MongoHost.init;

		double minRTT = double.max;
		foreach (i; eligible)
			if (servers[i].description.roundTripTime < minRTT)
				minRTT = servers[i].description.roundTripTime;

		double threshold = minRTT + localThresholdMS / 1_000.0;
		MongoHost[] withinWindow;
		foreach (i; eligible)
			if (servers[i].description.roundTripTime <= threshold)
				withinWindow ~= servers[i].host;

		import std.random : uniform;
		return Nullable!MongoHost(withinWindow[uniform(0, withinWindow.length)]);
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

		return sLag - pLag + heartbeatFrequencyMS * 1000;
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
		return maxWriteDate - sWriteDate + heartbeatFrequencyMS * 1000;
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

/// SDAM stale-primary test: a reported primary is stale when its (electionId, setVersion)
/// tuple is strictly less than the topology's max watermark, comparing electionId FIRST
/// (it advances on every election; setVersion can regress across terms). A null component
/// sorts below any present one, so a primary omitting electionId loses to one that has it.
/// With no watermark yet (both max values null) nothing is stale.
bool isStalePrimary(Nullable!BsonObjectID electionId, Nullable!int setVersion,
	Nullable!BsonObjectID maxElectionId, Nullable!int maxSetVersion) @safe
{
	if (maxElectionId.isNull && maxSetVersion.isNull)
		return false;

	auto byElection = compareNullable(electionId, maxElectionId);
	if (byElection != 0)
		return byElection < 0;

	return compareNullable(setVersion, maxSetVersion) < 0;
}

/// Three-way compare of two Nullables, treating null as smaller than any present value.
private int compareNullable(T)(Nullable!T a, Nullable!T b) @safe
{
	if (a.isNull)
		return b.isNull ? 0 : -1;
	if (b.isNull)
		return 1;
	if (a.get < b.get)
		return -1;
	if (b.get < a.get)
		return 1;
	return 0;
}

/// isStalePrimary compares electionId first, then setVersion, with null sorting lowest
unittest
{
	import vibe.data.bson : BsonObjectID;

	auto eidLow  = Nullable!BsonObjectID(BsonObjectID.fromHexString("aabbccddeeff00112233aa01"));
	auto eidHigh = Nullable!BsonObjectID(BsonObjectID.fromHexString("aabbccddeeff00112233aa02"));
	auto noEid = Nullable!BsonObjectID.init;
	auto v1 = Nullable!int(1);
	auto v2 = Nullable!int(2);
	auto noV = Nullable!int.init;

	assert(!isStalePrimary(eidLow, v1, noEid, noV), "the first primary (no watermark yet) is accepted");

	// electionId decides before setVersion: a higher setVersion does not rescue a lower electionId.
	assert(isStalePrimary(eidLow, v2, eidHigh, v1), "a lower electionId is stale even with a higher setVersion");
	assert(!isStalePrimary(eidHigh, v1, eidLow, v2), "a higher electionId wins even with a lower setVersion");

	// Equal electionId: setVersion breaks the tie.
	assert(isStalePrimary(eidHigh, v1, eidHigh, v2), "equal electionId, lower setVersion is stale");
	assert(!isStalePrimary(eidHigh, v2, eidHigh, v1), "equal electionId, higher setVersion wins");

	// A primary omitting electionId loses to an established electionId watermark.
	assert(isStalePrimary(noEid, v2, eidHigh, v1), "a missing electionId sorts below a present one");
}

/// Builds the fixed topology for load-balancer mode: a single load-balancer host,
/// no discovery or monitoring (the load balancer fronts the real backends).
TopologyDescription loadBalancedTopology(MongoHost host)
{
	TopologyDescription topo;
	topo.type = TopologyType.loadBalanced;
	topo.servers = [ServerRecord(host, ServerDescription.init)];
	topo.seedCount = 1;
	return topo;
}

/// Returns a new topology with `desc` applied for `host`, leaving `current` unchanged.
TopologyDescription applyDescription(TopologyDescription current, MongoHost host, ServerDescription desc)
{
	current.servers = current.servers.dup;
	current.update(host, desc);
	return current;
}

/// Returns a new topology with `host` marked failed, leaving `current` unchanged.
TopologyDescription applyFailed(TopologyDescription current, MongoHost host)
{
	current.servers = current.servers.dup;
	current.markFailed(host);
	return current;
}

/// Holds the current topology behind an atomically-swapped pointer for lock-free reads.
struct AtomicTopology
{
	private shared(TopologyDescription)* m_current;

	/// Atomically replace the current snapshot with a heap copy of `topology`.
	void publish(TopologyDescription topology) @trusted
	{
		import core.atomic : atomicStore;

		auto snapshot = new TopologyDescription;
		*snapshot = topology;
		atomicStore(m_current, cast(shared(TopologyDescription)*) snapshot);
	}

	/// Return a value copy of the current snapshot, or the default if none.
	TopologyDescription load() @trusted const
	{
		import core.atomic : atomicLoad;

		auto p = atomicLoad(m_current);
		if (p is null)
			return TopologyDescription.init;
		return *(cast(TopologyDescription*) p);
	}
}

/// applyDescription returns a new topology and leaves the input snapshot unchanged
unittest
{
	TopologyDescription before;
	auto host = MongoHost("primary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	auto after = applyDescription(before, host, primaryDesc);

	assert(!after.primaryHost.isNull && after.primaryHost.get == host,
		"the result reflects the applied primary");
	assert(before.servers.length == 0 && before.primaryHost.isNull,
		"the input snapshot is not mutated");
}

/// applyFailed clears the failed host in the result without mutating the input
unittest
{
	auto host = MongoHost("primary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	TopologyDescription before = applyDescription(TopologyDescription.init, host, primaryDesc);

	auto after = applyFailed(before, host);

	assert(after.primaryHost.isNull, "the result no longer has the failed primary");
	assert(!before.primaryHost.isNull && before.primaryHost.get == host,
		"the input snapshot still has the primary");
}

/// AtomicTopology.load returns the default topology before anything is published
unittest
{
	AtomicTopology holder;
	assert(holder.load().servers.length == 0);
}

/// AtomicTopology round-trips the most recently published snapshot
unittest
{
	AtomicTopology holder;
	auto host = MongoHost("primary", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";

	holder.publish(applyDescription(TopologyDescription.init, host, primaryDesc));

	auto loaded = holder.load();
	assert(!loaded.primaryHost.isNull && loaded.primaryHost.get == host);
}

/**
 * Selects a server from the topology based on the given read preference.
 *
 * Returns the host to connect to, or Nullable!MongoHost.init if no
 * suitable server is available.
 */
Nullable!MongoHost selectServer(ref const TopologyDescription topology, ReadPreference pref,
	long localThresholdMS = 15, long maxStalenessSeconds = -1, string[string][] tagSets = null)
{
	// Single and load-balanced topologies are fixed to one host, returned regardless of
	// read preference (the load balancer fronts the backends; pinning is per cursor via serviceId).
	if ((topology.type == TopologyType.single || topology.type == TopologyType.loadBalanced)
		&& topology.servers.length > 0)
		return Nullable!MongoHost(topology.servers[0].host);

	// For sharded topologies return a random mongos (read preference forwarded to mongos)
	if (topology.type == TopologyType.sharded)
		return topology.randomMongosHost(localThresholdMS);

	// For replica set or unknown topologies apply read preference logic
	final switch (pref)
	{
	case ReadPreference.primary:
		return topology.primaryHost;

	case ReadPreference.primaryPreferred:
		auto primary = topology.primaryHost;
		if (!primary.isNull)
			return primary;
		return topology.randomSecondaryHost(maxStalenessSeconds, tagSets);

	case ReadPreference.secondary:
		return topology.randomSecondaryHost(maxStalenessSeconds, tagSets);

	case ReadPreference.secondaryPreferred:
		auto secondary = topology.randomSecondaryHost(maxStalenessSeconds, tagSets);
		if (!secondary.isNull)
			return secondary;
		return topology.primaryHost;

	case ReadPreference.nearest:
		return topology.randomHostWithinLatencyWindow(localThresholdMS, maxStalenessSeconds, tagSets);
	}
}

/**
 * Returns the server that writes must be sent to, regardless of the configured
 * read preference. Resolves the primary for a replica set, the single server for
 * a standalone deployment, and a mongos for a sharded cluster. Null if no write
 * target is currently available (e.g. a replica set with no elected primary).
 */
Nullable!MongoHost writeTarget(ref const TopologyDescription topology, long localThresholdMS = 15)
{
	return selectServer(topology, ReadPreference.primary, localThresholdMS);
}

/// Picks the primary when `toPrimary`, else the read-preference target; null if none.
Nullable!MongoHost selectTarget(ref const TopologyDescription topology, bool toPrimary,
	ReadPreference pref, long localThresholdMS = 15, long maxStalenessSeconds = -1,
	string[string][] tagSets = null)
{
	return toPrimary
		? writeTarget(topology, localThresholdMS)
		: selectServer(topology, pref, localThresholdMS, maxStalenessSeconds, tagSets);
}

/// writeTarget returns the primary even when a secondary is available
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetWithPrimary;

	auto primary = MongoHost("primary", 27017);
	ServerDescription pdesc;
	pdesc.isWritablePrimary = true;
	pdesc.setName = "rs0";
	topo.update(primary, pdesc);

	auto secondary = MongoHost("secondary", 27017);
	ServerDescription sdesc;
	sdesc.secondary = true;
	sdesc.setName = "rs0";
	topo.update(secondary, sdesc);

	auto target = writeTarget(topo);
	assert(!target.isNull);
	assert(target.get == primary);
}

/// writeTarget returns the only server for a standalone topology
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("standalone", 27017);
	ServerDescription desc;
	desc.isWritablePrimary = true;
	topo.update(host, desc);
	topo.type = TopologyType.single;

	auto target = writeTarget(topo);
	assert(!target.isNull);
	assert(target.get == host);
}

/// selectServer returns the load-balancer host regardless of read preference
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("loadbalancer", 27017);
	ServerDescription desc;
	topo.update(host, desc);
	topo.type = TopologyType.loadBalanced;

	auto target = selectServer(topo, ReadPreference.secondary);
	assert(!target.isNull);
	assert(target.get == host);
}

/// loadBalancedTopology builds a loadBalanced topology with the configured host selectable
unittest
{
	auto host = MongoHost("loadbalancer", 27017);
	auto topo = loadBalancedTopology(host);

	assert(topo.type == TopologyType.loadBalanced);

	auto target = selectServer(topo, ReadPreference.primary);
	assert(!target.isNull);
	assert(target.get == host);
}

/// writeTarget returns null when the replica set has no primary
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;

	auto secondary = MongoHost("secondary", 27017);
	ServerDescription desc;
	desc.secondary = true;
	desc.setName = "rs0";
	topo.update(secondary, desc);

	auto target = writeTarget(topo);
	assert(target.isNull);
}

/// selectTarget routes writes to the primary and reads by read preference
unittest
{
	TopologyDescription topo;
	auto primary = MongoHost("primary", 27017);
	auto secondary = MongoHost("secondary", 27017);

	ServerDescription pdesc;
	pdesc.isWritablePrimary = true;
	pdesc.setName = "rs0";
	topo.update(primary, pdesc);

	ServerDescription sdesc;
	sdesc.secondary = true;
	sdesc.setName = "rs0";
	topo.update(secondary, sdesc);

	auto write = selectTarget(topo, true, ReadPreference.secondary);
	assert(!write.isNull && write.get == primary, "writes go to the primary, ignoring read preference");

	auto read = selectTarget(topo, false, ReadPreference.secondary);
	assert(!read.isNull && read.get == secondary, "reads honor the read preference");
}

/**
 * Returns true if `incoming` is stale relative to `existing`.
 *
 * Monitor checks are sequential per host, so only a STRICTLY-LOWER counter
 * (an out-of-order delivery) is stale and dropped. An equal counter is a
 * steady-state heartbeat that must refresh the description's volatile
 * metadata (roundTripTime/lastWrite/lastUpdateTimeUsecs), so it is NOT stale.
 * A different processId means the server restarted, so the update is fresh.
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

	return newTV.counter < oldTV.counter;
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

/// selectServer primaryPreferred honors tagSets when falling back to a secondary
unittest
{
	TopologyDescription topo;
	auto east = MongoHost("east-sec", 27017);
	auto west = MongoHost("west-sec", 27017);

	ServerDescription eastDesc;
	eastDesc.secondary = true;
	eastDesc.setName = "rs0";
	eastDesc.tags = ["dc": "east"];

	ServerDescription westDesc;
	westDesc.secondary = true;
	westDesc.setName = "rs0";
	westDesc.tags = ["dc": "west"];

	topo.update(east, eastDesc);
	topo.update(west, westDesc);

	string[string][] tagSets = [["dc": "east"]];

	// With no primary, primaryPreferred must still respect the tag set and never pick west.
	foreach (_; 0 .. 100)
	{
		auto result = selectServer(topo, ReadPreference.primaryPreferred, 15, -1, tagSets);
		assert(!result.isNull, "a tag-matching secondary is selected");
		assert(result.get == east, "primaryPreferred must not select a tag-excluded secondary");
	}
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

/// allKnownHosts includes arbiters so they are monitored as replica-set members
unittest
{
	import std.algorithm : canFind;

	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto primary = MongoHost("primary", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;
	desc.setName = "rs0";
	desc.hosts = ["primary:27017", "sec:27017"];
	desc.arbiters = ["arb:27017"];

	topo.update(primary, desc);

	assert(topo.allKnownHosts().canFind(MongoHost("arb", 27017)),
		"an arbiter advertised in the member list must be monitored");
}

/// allKnownHosts includes a server's own host even when its description carries no member list (standalone/sharded)
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("standalone", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;

	topo.update(host, desc);

	assert(topo.allKnownHosts() == [host],
		"allKnownHosts must include the server's own host even without a description hosts array");
}

/// a markFailed-cleared server's host stays in allKnownHosts so monitoring can recover after a full outage
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("host1", 27017);

	ServerDescription desc;
	desc.isWritablePrimary = true;
	desc.setName = "rs0";
	desc.hosts = ["host1:27017"];
	topo.update(host, desc);

	topo.markFailed(host); // simulate an outage: the server's description is cleared

	assert(topo.allKnownHosts() == [host],
		"a failed server's host stays known so reconcileWith does not stop its monitor (monitoring can recover)");
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

/// update with equal topology version counter is accepted (heartbeats refresh the description)
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
	assert(topo.servers[0].description.isSecondaryNode);
}

/// update with an equal topology version counter still refreshes volatile metadata (roundTripTime)
unittest
{
	TopologyDescription topo;
	auto host = MongoHost("host1", 27017);
	auto pid = BsonObjectID.fromHexString("aabbccddeeff00112233aabb");

	ServerDescription first;
	first.isWritablePrimary = true;
	first.setName = "rs0";
	first.roundTripTime = 10;
	first.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 5));
	topo.update(host, first);

	ServerDescription heartbeat;
	heartbeat.isWritablePrimary = true;
	heartbeat.setName = "rs0";
	heartbeat.roundTripTime = 25;
	heartbeat.topologyVersion = Nullable!TopologyVersion(TopologyVersion(pid, 5));
	topo.update(host, heartbeat);

	assert(topo.servers[0].description.roundTripTime == 25,
		"an equal-counter heartbeat must refresh roundTripTime, not freeze it at the first-probe value");
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

/// loadBalanced topology stays loadBalanced when an RSPrimary description arrives
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.loadBalanced;
	auto host = MongoHost("lb-backend", 27017);

	ServerDescription primaryDesc;
	primaryDesc.isWritablePrimary = true;
	primaryDesc.setName = "rs0";
	assert(primaryDesc.classifiedType() == ServerDescription.ServerType.RSPrimary);

	topo.update(host, primaryDesc);
	assert(topo.type == TopologyType.loadBalanced,
		"a load-balanced topology must not transition based on SDAM");
}

/// loadBalanced topology stays loadBalanced for mongos, standalone and RSSecondary descriptions
unittest
{
	auto host = MongoHost("lb-backend", 27017);

	ServerDescription mongosDesc;
	mongosDesc.msg = "isdbgrid";
	assert(mongosDesc.classifiedType() == ServerDescription.ServerType.mongos);

	ServerDescription standaloneDesc;
	standaloneDesc.isWritablePrimary = true;
	assert(standaloneDesc.classifiedType() == ServerDescription.ServerType.standalone);

	ServerDescription secondaryDesc;
	secondaryDesc.secondary = true;
	secondaryDesc.setName = "rs0";
	assert(secondaryDesc.classifiedType() == ServerDescription.ServerType.RSSecondary);

	foreach (desc; [mongosDesc, standaloneDesc, secondaryDesc])
	{
		TopologyDescription topo;
		topo.type = TopologyType.loadBalanced;

		topo.update(host, desc);
		assert(topo.type == TopologyType.loadBalanced,
			"a load-balanced topology must not transition based on SDAM");
	}
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

/// a rogue RSPrimary in a sharded topology is removed without wiping the mongos list or flipping the type
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.sharded;
	auto mongos = MongoHost("mongos", 27017);
	auto rogue = MongoHost("rogue", 27017);

	ServerDescription mongosDesc;
	mongosDesc.msg = "isdbgrid";
	topo.update(mongos, mongosDesc);

	// A host thought to be a mongos now reports as an RS primary advertising its own
	// replica-set members (which do NOT include the mongos). The primary-handling block
	// would prune the mongos to those members, then flip the topology type.
	ServerDescription rogueDesc;
	rogueDesc.isWritablePrimary = true;
	rogueDesc.setName = "rs0";
	rogueDesc.hosts = ["rogue:27017", "other:27017"];
	topo.update(rogue, rogueDesc);

	assert(topo.type == TopologyType.sharded, "a non-mongos must not flip a sharded topology's type");
	assert(topo.servers.length == 1, "the rogue RS server is removed and the mongos retained");
	assert(topo.servers[0].host == mongos, "the mongos survives the rogue primary");
}

/// an RS server whose setName differs from the topology's is rejected, not allowed to demote the primary
unittest
{
	TopologyDescription topo;
	topo.type = TopologyType.replicaSetWithPrimary;
	topo.setName = "rs0";
	auto good = MongoHost("good", 27017);
	auto wrong = MongoHost("wrong", 27017);

	ServerDescription goodPrimary;
	goodPrimary.isWritablePrimary = true;
	goodPrimary.setName = "rs0";
	topo.update(good, goodPrimary);

	// A host re-provisioned into a DIFFERENT replica set now reports setName "other".
	ServerDescription wrongPrimary;
	wrongPrimary.isWritablePrimary = true;
	wrongPrimary.setName = "other";
	topo.update(wrong, wrongPrimary);

	assert(topo.servers.length == 1, "the wrong-set server is rejected");
	assert(topo.servers[0].host == good, "only the matching-set host remains");
	assert(topo.findPrimaryIdx() != -1 && topo.servers[topo.findPrimaryIdx()].host == good,
		"the wrong-set primary did not take over the topology");
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

/// isStaleUpdate accepts the update when incoming has topologyVersion but existing does not
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

/// a primary with a higher setVersion but lower electionId is stale (electionId is compared first)
unittest
{
	import vibe.data.bson : BsonObjectID;

	TopologyDescription topo;
	topo.type = TopologyType.replicaSetNoPrimary;
	auto host1 = MongoHost("host1", 27017);
	auto host2 = MongoHost("host2", 27017);

	auto eidHigh = BsonObjectID.fromHexString("aabbccddeeff00112233aa02");
	auto eidLow  = BsonObjectID.fromHexString("aabbccddeeff00112233aa01");

	// Real current primary: highest electionId, a modest setVersion.
	ServerDescription current;
	current.isWritablePrimary = true;
	current.setName = "rs0";
	current.setVersion = Nullable!int(1);
	current.electionId = Nullable!BsonObjectID(eidHigh);
	topo.update(host1, current);

	// Stale primary from a previous term: it bumped its setVersion but has a LOWER electionId.
	ServerDescription stale;
	stale.isWritablePrimary = true;
	stale.setName = "rs0";
	stale.setVersion = Nullable!int(2);
	stale.electionId = Nullable!BsonObjectID(eidLow);
	topo.update(host2, stale);

	bool host1Primary, host2Primary;
	foreach (ref s; topo.servers)
	{
		if (s.host == host1 && s.description.isPrimary) host1Primary = true;
		if (s.host == host2 && s.description.isPrimary) host2Primary = true;
	}
	assert(host1Primary, "the real primary (higher electionId) keeps the role");
	assert(!host2Primary, "the stale primary (higher setVersion, lower electionId) is rejected");
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

/// returns true when every required tag is present in the server's tags
bool serverMatchesTagSet(const(string[string]) serverTags, string[string] required) @safe
{
	foreach (key, value; required)
		if (serverTags.get(key, null) != value)
			return false;
	return true;
}

/// serverMatchesTagSet returns true when the server carries every required tag pair
unittest
{
	string[string] serverTags = ["dc": "east"];
	string[string] required = ["dc": "east"];

	assert(serverMatchesTagSet(serverTags, required) == true,
		"server tagged dc:east must satisfy required tag set dc:east");
}

/// serverMatchesTagSet returns false when a required tag value differs
unittest
{
	assert(serverMatchesTagSet(["dc": "west"], ["dc": "east"]) == false,
		"server in dc:west must not satisfy required tag set dc:east");
}

/// serverMatchesTagSet returns true for the empty (catch-all) tag set
unittest
{
	assert(serverMatchesTagSet(["dc": "east"], null) == true,
		"an empty required tag set matches any server");
}

version (unittest)
{
	/// Builds a replica set with a primary plus dc:east and dc:west secondaries,
	/// returning the topology and the two tagged secondary host handles.
	private struct TaggedSecondaries
	{
		TopologyDescription topo;
		MongoHost secEast;
		MongoHost secWest;
	}

	private TaggedSecondaries buildTaggedSecondaries()
	{
		TopologyDescription topo;
		topo.type = TopologyType.replicaSetWithPrimary;

		auto primary = MongoHost("primary", 27017);
		ServerDescription primaryDesc;
		primaryDesc.isWritablePrimary = true;
		primaryDesc.setName = "rs0";
		topo.update(primary, primaryDesc);

		auto secEast = MongoHost("sec-east", 27017);
		ServerDescription eastDesc;
		eastDesc.secondary = true;
		eastDesc.setName = "rs0";
		eastDesc.tags = ["dc": "east"];
		topo.update(secEast, eastDesc);

		auto secWest = MongoHost("sec-west", 27017);
		ServerDescription westDesc;
		westDesc.secondary = true;
		westDesc.setName = "rs0";
		westDesc.tags = ["dc": "west"];
		topo.update(secWest, westDesc);

		return TaggedSecondaries(topo, secEast, secWest);
	}
}

/// secondaryHosts with a single tag set returns only the matching secondary
unittest
{
	auto rs = buildTaggedSecondaries();

	auto hosts = rs.topo.secondaryHosts(-1, [["dc": "east"]]);
	assert(hosts == [rs.secEast], "tag set dc:east must select only the matching secondary");
}

/// secondaryHosts falls through to the second tag set when the first matches nothing
unittest
{
	auto rs = buildTaggedSecondaries();

	auto hosts = rs.topo.secondaryHosts(-1, [["dc": "nowhere"], ["dc": "east"]]);
	assert(hosts == [rs.secEast], "must fall through to the second tag set when the first matches nothing");
}

/// secondaryHosts stops at the first matching tag set and ignores later ones
unittest
{
	auto rs = buildTaggedSecondaries();

	auto hosts = rs.topo.secondaryHosts(-1, [["dc": "east"], ["dc": "west"]]);
	assert(hosts == [rs.secEast],
		"first matching tag set wins; later sets must not add hosts");

	auto none = rs.topo.secondaryHosts(-1, [["dc": "nowhere"]]);
	assert(none.length == 0, "no tag set matching any secondary yields no hosts");
}

/// selectServer secondary with tag set dc:east returns only the matching secondary
unittest
{
	auto rs = buildTaggedSecondaries();

	auto chosen = selectServer(rs.topo, ReadPreference.secondary, 15, -1, [["dc": "east"]]);
	assert(!chosen.isNull, "tag set dc:east must select a secondary");
	assert(chosen.get == rs.secEast, "tag set dc:east must select only the matching secondary");
}

/// selectServer secondaryPreferred with a non-matching tag set falls back to the primary
unittest
{
	auto rs = buildTaggedSecondaries();

	auto chosen = selectServer(rs.topo, ReadPreference.secondaryPreferred, 15, -1, [["dc": "nowhere"]]);
	assert(!chosen.isNull, "secondaryPreferred must fall back to a server when no secondary matches");
	assert(chosen.get == rs.topo.primaryHost.get, "secondaryPreferred with non-matching tags must fall back to the primary");
}

/// selectServer nearest with a tag set matching no member returns null
unittest
{
	auto rs = buildTaggedSecondaries();

	auto chosen = selectServer(rs.topo, ReadPreference.nearest, 15, -1, [["dc": "nowhere"]]);
	assert(chosen.isNull, "nearest with a tag set matching no member must select no server");
}

/// selectTarget forwards a secondary read tag set dc:east to selectServer and returns the matching secondary
unittest
{
	auto rs = buildTaggedSecondaries();

	auto chosen = selectTarget(rs.topo, false, ReadPreference.secondary, 15, -1, [["dc": "east"]]);
	assert(!chosen.isNull, "selectTarget with tag set dc:east must select a secondary");
	assert(chosen.get == rs.secEast, "selectTarget must forward the tag set so only sec-east is chosen");
}

/// tag sets never exclude the primary: primary reads and writes ignore them
unittest
{
	auto rs = buildTaggedSecondaries();
	auto primary = rs.topo.primaryHost.get;

	auto read = selectServer(rs.topo, ReadPreference.primary, 15, -1, [["dc": "nowhere"]]);
	assert(!read.isNull && read.get == primary,
		"primary read preference must ignore tag sets and still pick the primary");

	auto write = selectTarget(rs.topo, true, ReadPreference.primary, 15, -1, [["dc": "nowhere"]]);
	assert(!write.isNull && write.get == primary,
		"writes must ignore tag sets and still target the primary");
}

/// supportsRetryableWrites returns false for a standalone (single) topology
unittest
{
	assert(supportsRetryableWrites(TopologyType.single) == false,
		"standalone mongod rejects lsid/txnNumber, so retryable writes are unsupported on TopologyType.single");
}

/// supportsRetryableWrites returns true for a load-balanced topology
unittest
{
	assert(supportsRetryableWrites(TopologyType.loadBalanced),
		"a load-balanced deployment fronts a mongos, which supports retryable writes");
}

/// The topology-wide logical session timeout: the MIN advertised logicalSessionTimeoutMinutes
/// across data-bearing servers, or null when it cannot be determined.
Nullable!Duration logicalSessionTimeout(const ServerDescription[] servers) @safe
{
	import core.time : minutes;
	Nullable!int min;
	foreach (s; servers)
	{
		if (!s.isDataBearing)
			continue;
		if (s.logicalSessionTimeoutMinutes.isNull)
			return Nullable!Duration.init;
		if (min.isNull || s.logicalSessionTimeoutMinutes.get < min.get)
			min = s.logicalSessionTimeoutMinutes.get;
	}
	return min.isNull ? Nullable!Duration.init : Nullable!Duration(min.get.minutes);
}

/// logicalSessionTimeout returns 30.minutes for a single server advertising 30
unittest
{
	import core.time : minutes;

	ServerDescription primary;
	primary.isWritablePrimary = true;
	primary.logicalSessionTimeoutMinutes = 30;

	auto timeout = logicalSessionTimeout([primary]);

	assert(!timeout.isNull && timeout.get == 30.minutes,
		"single server advertises a 30 minute session timeout");
}

/// logicalSessionTimeout returns the minimum advertised timeout across servers
unittest
{
	import core.time : minutes;

	ServerDescription primary;
	primary.isWritablePrimary = true;
	primary.logicalSessionTimeoutMinutes = 30;

	ServerDescription secondary;
	secondary.secondary = true;
	secondary.logicalSessionTimeoutMinutes = 10;

	auto timeout = logicalSessionTimeout([primary, secondary]);

	assert(!timeout.isNull && timeout.get == 10.minutes,
		"the topology timeout is the minimum advertised across servers");
}

/// logicalSessionTimeout returns null when a data-bearing server advertises no timeout
unittest
{
	ServerDescription primary;
	primary.isWritablePrimary = true;
	primary.logicalSessionTimeoutMinutes = 30;

	ServerDescription secondary;
	secondary.secondary = true;

	auto timeout = logicalSessionTimeout([primary, secondary]);

	assert(timeout.isNull,
		"a data-bearing server that does not advertise a session timeout disables sessions topology-wide");
}

/// logicalSessionTimeout excludes arbiters from the minimum computation
unittest
{
	import core.time : minutes;

	ServerDescription primary;
	primary.isWritablePrimary = true;
	primary.logicalSessionTimeoutMinutes = 30;

	ServerDescription arbiter;
	arbiter.arbiterOnly = true;
	arbiter.logicalSessionTimeoutMinutes = 10;

	auto timeout = logicalSessionTimeout([primary, arbiter]);

	assert(!timeout.isNull && timeout.get == 30.minutes,
		"arbiters are excluded from the session timeout computation");
}
