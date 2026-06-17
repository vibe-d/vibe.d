/**
	DNS Seedlist Discovery (mongodb+srv) helpers.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.impl.srv;

import vibe.db.mongo.settings : MongoClientSettings, MongoHost, isValidLoadBalancedConfig;

@safe:

/// Builds the SRV record name (`_mongodb._tcp.<host>`) for a host.
string srvQueryName(string host) @safe
{
	return "_mongodb._tcp." ~ host;
}

/// srvQueryName builds the _mongodb._tcp SRV record name for a host
unittest
{
	assert(srvQueryName("test.mongodb.net") == "_mongodb._tcp.test.mongodb.net",
		"the SRV query name is _mongodb._tcp.<host>");
}

/// Whether an SRV-resolved `target` shares the `queryHost`'s parent domain (the
/// query host with its first DNS label removed). Per the seedlist spec, returned
/// hosts must match on a label boundary, case-insensitively.
bool srvTargetInParentDomain(string queryHost, string target) @safe
{
	import std.string : indexOf;
	import std.uni : toLower;
	import std.algorithm : endsWith;

	auto dot = queryHost.indexOf('.');
	if (dot < 0)
		return false;

	auto parentDomain = queryHost[dot + 1 .. $].toLower;
	auto loweredTarget = target.toLower;
	return loweredTarget == parentDomain || loweredTarget.endsWith("." ~ parentDomain);
}

/// srvTargetInParentDomain accepts a target sharing the query host's parent domain
unittest
{
	assert(srvTargetInParentDomain("test.mongodb.net", "cluster0.mongodb.net"),
		"a target in the parent domain (mongodb.net) is accepted");
}

/// srvTargetInParentDomain rejects out-of-domain and boundary-trick targets
unittest
{
	assert(!srvTargetInParentDomain("test.mongodb.net", "evil.com"),
		"a target in a foreign domain is rejected");
	assert(!srvTargetInParentDomain("test.mongodb.net", "evilmongodb.net"),
		"a suffix that is not on a label boundary is rejected");
}

/// Parses a MongoDB SRV TXT record's `key=value&key=value` options string into a map.
string[string] parseSrvTxtOptions(string txt) @safe
{
	import std.algorithm : splitter, canFind;
	import std.array : join;
	import std.string : indexOf;
	import std.exception : enforce;

	static immutable string[] allowed = ["replicaSet", "authSource", "loadBalanced"];

	string[string] opts;
	foreach (pair; txt.splitter('&'))
	{
		auto eq = pair.indexOf('=');
		if (eq < 0)
			continue;
		auto key = pair[0 .. eq];
		enforce(allowed.canFind(key),
			"mongodb+srv TXT record option '" ~ key ~ "' is not permitted (allowed: " ~ allowed.join(", ") ~ ")");
		opts[key] = pair[eq + 1 .. $];
	}
	return opts;
}

/// parseSrvTxtOptions parses the allowlisted TXT record options
unittest
{
	auto opts = parseSrvTxtOptions("replicaSet=rs0&authSource=admin");
	assert(opts["replicaSet"] == "rs0", "replicaSet is parsed from the TXT record");
	assert(opts["authSource"] == "admin", "authSource is parsed from the TXT record");
}

/// parseSrvTxtOptions rejects a TXT option outside the allowlist
unittest
{
	import std.exception : assertThrown;
	assertThrown(parseSrvTxtOptions("tls=true"),
		"a non-allowlisted TXT option (tls) must be rejected");
}

/** A resolver seam: plain delegates that turn DNS names into SRV hosts and TXT
	records.

	Keeping DNS I/O behind delegates lets `applySrvSeedlist` stay pure and testable
	without touching the network.

	Params:
		srv = resolves an SRV query name (`_mongodb._tcp.<host>`) to its hosts.
		txt = resolves a host's TXT record to its raw chunks.
*/
struct SrvResolver
{
	MongoHost[] delegate(string srvName) @safe srv;
	string[] delegate(string host) @safe txt;
}

/// Copies a TXT option into a settings field, but only when the field is still
/// empty, so a value carried by the connection URI always wins.
private void applyTxtOption(ref string field, string key, in string[string] opts) @safe
{
	auto value = key in opts;
	if (value && field.length == 0)
		field = *value;
}

/** Replaces the seed host in `cfg` with the hosts resolved from its SRV record
	and applies the options carried by the matching TXT record.

	The seed host's SRV record is resolved and every returned target is validated
	to share the seed host's parent domain before it is trusted. The TXT record's
	`replicaSet` and `authSource` options are then applied with URI precedence:
	each is honoured only when the corresponding `cfg` field was not already set.

	Params:
		cfg = the settings whose single seed host is expanded into the seedlist.
		resolver = the DNS seam used to look up the SRV and TXT records.

	Throws: when no SRV records are found or a target escapes the parent domain.
*/
void applySrvSeedlist(MongoClientSettings cfg, scope SrvResolver resolver) @safe
{
	import std.exception : enforce;

	auto queryHost = cfg.hosts[0].name;

	auto resolvedHosts = resolver.srv(srvQueryName(queryHost));
	enforce(resolvedHosts.length > 0, "no SRV records found for " ~ queryHost);
	foreach (host; resolvedHosts)
		enforce(srvTargetInParentDomain(queryHost, host.name),
			"SRV target '" ~ host.name ~ "' is not in the domain of '" ~ queryHost ~ "'");
	cfg.hosts = resolvedHosts;

	auto txtChunks = resolver.txt(queryHost);
	if (txtChunks.length == 0)
		return;

	// The seedlist spec permits at most one TXT record; multiple records (each a separate
	// resource record) must be rejected rather than concatenated into a bogus option string.
	enforce(txtChunks.length == 1,
		"more than one TXT record found for " ~ queryHost ~ " (mongodb+srv permits at most one)");

	auto opts = parseSrvTxtOptions(txtChunks[0]);
	applyTxtOption(cfg.replicaSet, "replicaSet", opts);
	applyTxtOption(cfg.authSource, "authSource", opts);

	// The URI takes precedence over the TXT record: only adopt the TXT loadBalanced when
	// the connection string did not specify it.
	auto loadBalanced = "loadBalanced" in opts;
	if (loadBalanced && !cfg.loadBalancedSpecified)
		cfg.loadBalanced = *loadBalanced == "true";

	// loadBalanced requires a single host and no replicaSet; re-validate now that SRV has
	// expanded the seed into the resolved hosts (parseMongoDBUrl validated only the seed).
	enforce(isValidLoadBalancedConfig(cfg),
		"loadBalanced=true is invalid after SRV resolution (it requires a single host and no replicaSet)");
}

/// applySrvSeedlist replaces the seed host with the resolved SRV hosts
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017), MongoHost("b.mongodb.net", 27017)],
		(string h) => string[].init);

	applySrvSeedlist(cfg, resolver);

	assert(cfg.hosts == [MongoHost("a.mongodb.net", 27017), MongoHost("b.mongodb.net", 27017)],
		"the seed host is replaced by the two resolved SRV hosts");
}

/// applySrvSeedlist rejects an SRV target outside the query host's domain
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;
	import std.exception : assertThrown;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	auto resolver = SrvResolver(
		(string n) => [MongoHost("evil.com", 27017)],
		(string h) => string[].init);

	assertThrown(applySrvSeedlist(cfg, resolver));
}

/// applySrvSeedlist rejects an empty SRV result
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;
	import std.exception : assertThrown;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	auto resolver = SrvResolver(
		(string n) => MongoHost[].init,
		(string h) => string[].init);

	assertThrown(applySrvSeedlist(cfg, resolver));
}

/// applySrvSeedlist rejects a non-allowlisted TXT option
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;
	import std.exception : assertThrown;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017)],
		(string h) => ["tls=true"]);

	assertThrown(applySrvSeedlist(cfg, resolver));
}

/// applySrvSeedlist applies the TXT replicaSet option when the URI did not set one
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017)],
		(string h) => ["replicaSet=rs0"]);

	applySrvSeedlist(cfg, resolver);

	assert(cfg.replicaSet == "rs0",
		"the TXT replicaSet option is copied into cfg.replicaSet");
}

/// applySrvSeedlist rejects more than one TXT record instead of concatenating them
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;
	import std.exception : assertThrown;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	// Two separate TXT records on the seed host: the seedlist spec requires an error,
	// not a silent join into "replicaSet=rs0authSource=admin".
	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017)],
		(string h) => ["replicaSet=rs0", "authSource=admin"]);

	assertThrown(applySrvSeedlist(cfg, resolver),
		"more than one TXT record is rejected");
}

/// applySrvSeedlist keeps a URI-set replicaSet over the TXT option
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];
	cfg.replicaSet = "fromUri";

	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017)],
		(string h) => ["replicaSet=rs0"]);

	applySrvSeedlist(cfg, resolver);

	assert(cfg.replicaSet == "fromUri",
		"a replicaSet already set from the URI is not overwritten by the TXT option");
}

/// applySrvSeedlist rejects TXT loadBalanced=true when SRV resolves to multiple hosts
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;
	import std.exception : assertThrown;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	// loadBalanced=true requires a single host, but SRV resolved to two — this must error
	// instead of silently treating hosts[0] as the load balancer.
	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017), MongoHost("b.mongodb.net", 27017)],
		(string h) => ["loadBalanced=true"]);

	assertThrown(applySrvSeedlist(cfg, resolver),
		"TXT loadBalanced=true with multiple resolved hosts is rejected");
}

/// applySrvSeedlist keeps a URI-set loadBalanced=false over the TXT loadBalanced=true
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];
	cfg.loadBalanced = false;
	cfg.loadBalancedSpecified = true; // the URI explicitly set loadBalanced=false

	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017)],
		(string h) => ["loadBalanced=true"]);

	applySrvSeedlist(cfg, resolver);

	assert(!cfg.loadBalanced,
		"an explicit URI loadBalanced=false is not overridden by the TXT loadBalanced=true");
}

/// applySrvSeedlist applies the TXT authSource option when the URI did not set one
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017)],
		(string h) => ["authSource=admin"]);

	applySrvSeedlist(cfg, resolver);

	assert(cfg.authSource == "admin",
		"the TXT authSource option is copied into cfg.authSource");
}

/// applySrvSeedlist applies the TXT loadBalanced option
unittest
{
	import vibe.db.mongo.settings : MongoClientSettings, MongoHost;

	auto cfg = new MongoClientSettings();
	cfg.srv = true;
	cfg.hosts = [MongoHost("test.mongodb.net", 27017)];

	auto resolver = SrvResolver(
		(string n) => [MongoHost("a.mongodb.net", 27017)],
		(string h) => ["loadBalanced=true"]);

	applySrvSeedlist(cfg, resolver);

	assert(cfg.loadBalanced,
		"the TXT loadBalanced option is copied into cfg.loadBalanced");
}
