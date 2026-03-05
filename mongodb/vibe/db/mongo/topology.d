/**
	MongoDB topology description and server selection.

	Implements server selection logic for replica sets based on the
	MongoDB Server Selection specification.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/server-selection/server-selection.md)

	Copyright: © 2026 GISCollective
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.db.mongo.topology;

import vibe.db.mongo.connection : ServerDescription;
import vibe.db.mongo.settings;
import vibe.core.log;

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
Nullable!MongoHost selectServer(ref const TopologyDescription topology, ReadPreference pref)
{
	final switch (pref)
	{
	case ReadPreference.primary:
		return topology.primaryHost;

	case ReadPreference.primaryPreferred:
		auto primary = topology.primaryHost;
		if (!primary.isNull)
			return primary;
		auto secondaries = topology.secondaryHosts;
		if (secondaries.length)
			return Nullable!MongoHost(secondaries[0]);
		return Nullable!MongoHost.init;

	case ReadPreference.secondary:
		auto secondaries = topology.secondaryHosts;
		if (secondaries.length)
			return Nullable!MongoHost(secondaries[0]);
		return Nullable!MongoHost.init;

	case ReadPreference.secondaryPreferred:
		auto secondaries = topology.secondaryHosts;
		if (secondaries.length)
			return Nullable!MongoHost(secondaries[0]);
		return topology.primaryHost;

	case ReadPreference.nearest:
		auto primary = topology.primaryHost;
		if (!primary.isNull)
			return primary;
		auto secondaries = topology.secondaryHosts;
		if (secondaries.length)
			return Nullable!MongoHost(secondaries[0]);
		return Nullable!MongoHost.init;
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

private import std.typecons : Nullable;

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

	topo.update(primary, primaryDesc);

	auto result = selectServer(topo, ReadPreference.nearest);
	assert(!result.isNull);
	assert(result.get == primary);
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
