/**
	Per-server SDAM health monitoring.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.monitor;

import vibe.db.mongo.connection : ServerDescription;
import vibe.db.mongo.settings : MongoHost, hostKey;

import vibe.core.core : runTask, sleep;
import vibe.core.task : Task;
import vibe.core.log : logError;
import vibe.core.sync : LocalManualEvent, createManualEvent;

import core.time : MonoTime, Duration, seconds, msecs;
import std.typecons : Nullable;

alias ServerProber = ServerDescription delegate(MongoHost) @safe;
alias MonitorResult = void delegate(MongoHost host, Nullable!ServerDescription desc, Duration rtt) @safe;

/// Monitors a single server, probing it on demand and reporting the result.
final class ServerMonitor {
	private {
		MongoHost m_host;
		ServerProber m_probe;
		MonitorResult m_onResult;
		Duration m_heartbeat;
		Duration m_minHeartbeat;
		bool m_running;
		Task m_loop;
		LocalManualEvent m_wake;
		MonoTime m_lastCheck;
	}

	this(MongoHost host, ServerProber probe, MonitorResult onResult, Duration heartbeat, Duration minHeartbeat) @safe
	{
		m_host = host;
		m_probe = probe;
		m_onResult = onResult;
		m_heartbeat = heartbeat;
		m_minHeartbeat = minHeartbeat;
		m_wake = createManualEvent();
	}

	/// Probes the host once and reports the resulting description via the callback.
	void checkOnce() @safe
	{
		auto started = MonoTime.currTime;
		Nullable!ServerDescription result;
		try
			result = Nullable!ServerDescription(m_probe(m_host));
		catch (Exception)
			result = Nullable!ServerDescription.init;

		m_onResult(m_host, result, MonoTime.currTime - started);
	}

	/// Starts the background heartbeat loop that probes the host periodically.
	void start() @trusted
	{
		m_running = true;
		m_loop = runTask(&supervise);
	}

	/// Restarts `runLoop` after a crash, waiting one heartbeat between attempts.
	private void supervise() nothrow
	{
		while (m_running)
		{
			if (runLoop())
				break;
			if (!m_running)
				break;
			try
				sleep(m_heartbeat);
			catch (Exception) {}
		}
	}

	/// Stops the background heartbeat loop.
	void stop() @safe
	{
		m_running = false;
	}

	/// Requests an immediate check, throttled by minHeartbeat.
	void requestCheck() @safe
	{
		if (shouldCheckNow(m_lastCheck, MonoTime.currTime, m_minHeartbeat))
			m_wake.emit();
	}

	/// Runs the heartbeat loop until `stop()`; returns false if an exception escaped.
	private bool runLoop() nothrow
	{
		try
		{
			while (m_running)
			{
				auto ec = m_wake.emitCount;
				checkOnce();
				m_lastCheck = MonoTime.currTime;
				m_wake.wait(m_heartbeat, ec);
			}
			return true;
		}
		catch (Exception e)
		{
			logError("MongoDB ServerMonitor heartbeat loop failed for %s: %s", m_host, e.msg);
			return false;
		}
	}
}

/// Owns the live per-host monitors, starting and stopping them as the topology changes.
final class MonitorRegistry {
	private {
		ServerProber m_prober;
		MonitorResult m_onResult;
		Duration m_heartbeat;
		Duration m_minHeartbeat;
		ServerMonitor[string] m_monitors;
		MongoHost[string] m_hosts;
	}

	this(ServerProber prober, MonitorResult onResult, Duration heartbeat, Duration minHeartbeat) @safe
	{
		m_prober = prober;
		m_onResult = onResult;
		m_heartbeat = heartbeat;
		m_minHeartbeat = minHeartbeat;
	}

	/// Number of monitors currently running.
	size_t length() const @safe
	{
		return m_monitors.length;
	}

	/// Whether a monitor is running for `host`.
	bool isMonitoring(MongoHost host) const @safe
	{
		return (hostKey(host) in m_monitors) !is null;
	}

	/// The hosts currently being monitored.
	MongoHost[] hosts() @safe
	{
		return m_hosts.values;
	}

	/// Starts a monitor for `host` unless one is already running.
	void ensure(MongoHost host) @safe
	{
		auto key = hostKey(host);
		if (key in m_monitors)
			return;

		auto monitor = new ServerMonitor(host, m_prober, m_onResult, m_heartbeat, m_minHeartbeat);
		m_monitors[key] = monitor;
		m_hosts[key] = host;
		monitor.start();
	}

	/// Stops and forgets the monitor for `host`.
	void remove(MongoHost host) @safe
	{
		auto key = hostKey(host);
		if (key !in m_monitors)
			return;

		m_monitors[key].stop();
		m_monitors.remove(key);
		m_hosts.remove(key);
	}

	/// Starts monitors for new hosts and stops monitors for removed ones.
	void reconcileWith(MongoHost[] desired) @safe
	{
		auto plan = reconcileMonitors(m_hosts.values, desired);
		foreach (host; plan.toStart)
			ensure(host);
		foreach (host; plan.toStop)
			remove(host);
	}

	/// Asks every monitor to run a check now.
	void requestAllChecks() @safe
	{
		foreach (monitor; m_monitors.byValue)
			monitor.requestCheck();
	}

	/// Asks the monitor for `host`, if any, to run a check now.
	void requestCheck(MongoHost host) @safe
	{
		if (auto monitor = hostKey(host) in m_monitors)
			monitor.requestCheck();
	}

	/// Stops and forgets every monitor.
	void stopAll() @safe
	{
		foreach (monitor; m_monitors.byValue)
			monitor.stop();
		m_monitors.clear();
		m_hosts.clear();
	}
}

/// Returns true once at least `minInterval` has elapsed since the last check.
bool shouldCheckNow(MonoTime last, MonoTime now, Duration minInterval) @safe pure nothrow @nogc
{
	return now - last >= minInterval;
}

/// Whether a server error code is in the SDAM "not master or recovering" set.
bool isStaleTopologyError(int code) @safe pure nothrow @nogc
{
	switch (code)
	{
		case 10107: // NotWritablePrimary
		case 13435: // NotPrimaryNoSecondaryOk
		case 13436: // NotPrimaryOrSecondary
		case 11600: // InterruptedAtShutdown
		case 11602: // InterruptedDueToReplStateChange
		case 189:   // PrimarySteppedDown
		case 91:    // ShutdownInProgress
			return true;
		default:
			return false;
	}
}

/// The per-host monitors to start and stop after a topology change.
struct MonitorReconcile
{
	MongoHost[] toStart;
	MongoHost[] toStop;
}

/// Set-diffs monitored hosts against desired hosts into hosts to start and to stop.
MonitorReconcile reconcileMonitors(MongoHost[] current, MongoHost[] desired) @safe pure nothrow
{
	import std.algorithm : canFind, filter;
	import std.array : array;

	MonitorReconcile result;
	result.toStart = desired.filter!(h => !current.canFind(h)).array;
	result.toStop = current.filter!(h => !desired.canFind(h)).array;
	return result;
}

/// reconcileMonitors starts new hosts and stops removed ones
unittest
{
	import vibe.db.mongo.settings : MongoHost;

	auto a = MongoHost("a", 27017);
	auto b = MongoHost("b", 27017);
	auto c = MongoHost("c", 27017);

	auto r = reconcileMonitors([a, b], [b, c]);

	assert(r.toStart == [c], "starts monitors for newly-discovered hosts");
	assert(r.toStop == [a], "stops monitors for removed hosts");
}

/// isStaleTopologyError flags the not-master / recovering server error codes
unittest
{
	assert(isStaleTopologyError(10107), "NotWritablePrimary");
	assert(isStaleTopologyError(13435), "NotPrimaryNoSecondaryOk");
	assert(isStaleTopologyError(11602), "InterruptedDueToReplStateChange");
	assert(isStaleTopologyError(189), "PrimarySteppedDown");
	assert(isStaleTopologyError(91), "ShutdownInProgress");

	assert(!isStaleTopologyError(11000), "duplicate key is not a topology error");
	assert(!isStaleTopologyError(0), "no error code");
}

/// shouldCheckNow allows a check once the minHeartbeatFrequencyMS floor has elapsed
unittest
{
	auto now = MonoTime.currTime;
	auto minInterval = 500.msecs;

	auto elapsed = now - 600.msecs;
	auto tooSoon = now - 400.msecs;

	assert(shouldCheckNow(elapsed, now, minInterval),
		"a check is allowed once the floor has elapsed");
	assert(!shouldCheckNow(tooSoon, now, minInterval),
		"a check is blocked before the floor has elapsed");
}

/// checkOnce probes the host and reports the probed description via the callback
unittest
{
	import vibe.db.mongo.connection : ServerDescription;
	import vibe.db.mongo.settings : MongoHost;

	auto host = MongoHost("primary", 27017);

	ServerDescription prober(MongoHost h) @safe
	{
		ServerDescription desc;
		desc.isWritablePrimary = true;
		desc.setName = "rs0";
		return desc;
	}

	MongoHost reportedHost;
	Nullable!ServerDescription reportedDesc;
	void onResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe
	{
		reportedHost = h;
		reportedDesc = desc;
	}

	auto monitor = new ServerMonitor(host, &prober, &onResult, 10.seconds, 500.msecs);
	monitor.checkOnce();

	assert(!reportedDesc.isNull, "a successful probe reports a non-null description");
	assert(reportedDesc.get.isWritablePrimary, "the reported description is the probed primary");
	assert(reportedHost == host, "the reported host is the monitored host");
}

/// checkOnce reports a null description when the prober throws
unittest
{
	import vibe.db.mongo.connection : ServerDescription;
	import vibe.db.mongo.settings : MongoHost;

	auto host = MongoHost("primary", 27017);

	ServerDescription prober(MongoHost h) @safe
	{
		throw new Exception("connection refused");
	}

	bool wasCalled;
	Nullable!ServerDescription reportedDesc;
	void onResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe
	{
		wasCalled = true;
		reportedDesc = desc;
	}

	auto monitor = new ServerMonitor(host, &prober, &onResult, 10.seconds, 500.msecs);
	monitor.checkOnce();

	assert(wasCalled, "a failed probe still reports a result");
	assert(reportedDesc.isNull, "a failed probe reports a null description");
}

/// start() runs periodic checks until stop()
unittest
{
	import vibe.core.core : sleep;
	import core.time : msecs;
	import vibe.db.mongo.connection : ServerDescription;
	import vibe.db.mongo.settings : MongoHost;

	auto host = MongoHost("primary", 27017);

	ServerDescription prober(MongoHost h) @safe
	{
		ServerDescription desc;
		desc.isWritablePrimary = true;
		desc.setName = "rs0";
		return desc;
	}

	int checks;
	void onResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe
	{
		checks++;
	}

	auto monitor = new ServerMonitor(host, &prober, &onResult, 20.msecs, 1.msecs);

	monitor.start();
	sleep(100.msecs);
	assert(checks >= 2, "the loop performs periodic checks while running");

	monitor.stop();
	sleep(60.msecs);
	auto afterStop = checks;
	sleep(60.msecs);
	assert(checks == afterStop, "no checks happen after stop()");
}

/// runLoop returns false when the loop body throws
unittest
{
	import vibe.db.mongo.connection : ServerDescription;
	import vibe.db.mongo.settings : MongoHost;

	auto host = MongoHost("primary", 27017);
	ServerDescription prober(MongoHost h) @safe { ServerDescription d; d.isWritablePrimary = true; return d; }
	void onResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe { throw new Exception("boom"); }

	auto monitor = new ServerMonitor(host, &prober, &onResult, 20.msecs, 1.msecs);
	monitor.m_running = true;

	auto ok = monitor.runLoop();

	assert(!ok, "runLoop returns false when the loop throws");
}

/// start() restarts the heartbeat loop after a failure
unittest
{
	import vibe.core.core : sleep;
	import core.time : msecs;
	import vibe.db.mongo.connection : ServerDescription;
	import vibe.db.mongo.settings : MongoHost;

	auto host = MongoHost("primary", 27017);
	ServerDescription prober(MongoHost h) @safe { ServerDescription d; d.isWritablePrimary = true; d.setName = "rs0"; return d; }

	bool thrownOnce;
	int goodChecks;
	void onResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe
	{
		if (!thrownOnce) { thrownOnce = true; throw new Exception("first check crashes the loop"); }
		goodChecks++;
	}

	auto monitor = new ServerMonitor(host, &prober, &onResult, 20.msecs, 1.msecs);
	monitor.start();
	sleep(150.msecs);
	monitor.stop();

	assert(goodChecks >= 1, "the monitor restarted its loop after the failure");
}

/// requestCheck triggers a check before the heartbeat interval elapses
unittest
{
	import vibe.core.core : sleep;
	import core.time : msecs, seconds;
	import vibe.db.mongo.connection : ServerDescription;
	import vibe.db.mongo.settings : MongoHost;

	auto host = MongoHost("primary", 27017);
	ServerDescription prober(MongoHost h) @safe { ServerDescription d; d.isWritablePrimary = true; d.setName = "rs0"; return d; }

	int checks;
	void onResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe { checks++; }

	auto monitor = new ServerMonitor(host, &prober, &onResult, 10.seconds, 1.msecs);

	monitor.start();
	sleep(40.msecs);
	auto before = checks;
	monitor.requestCheck();
	sleep(40.msecs);
	monitor.stop();

	assert(checks > before, "requestCheck causes an immediate re-check instead of waiting the full heartbeat");
}

version (unittest)
{
	private ServerDescription stubProbe(MongoHost h) @safe
	{
		ServerDescription desc;
		desc.isWritablePrimary = true;
		desc.setName = "rs0";
		return desc;
	}

	private void ignoreResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe {}

	private MonitorRegistry idleRegistry()
	{
		import std.functional : toDelegate;
		return new MonitorRegistry(toDelegate(&stubProbe), toDelegate(&ignoreResult), 1.seconds, 1.msecs);
	}
}

/// ensure starts a monitor and is idempotent for the same host
unittest
{
	auto registry = idleRegistry();
	auto host = MongoHost("a", 27017);

	registry.ensure(host);
	registry.ensure(host);

	assert(registry.length == 1, "ensure starts exactly one monitor per host");
	assert(registry.isMonitoring(host), "the host is reported as monitored");

	registry.stopAll();
}

/// remove stops the monitor and forgets the host
unittest
{
	auto registry = idleRegistry();
	auto host = MongoHost("a", 27017);

	registry.ensure(host);
	registry.remove(host);

	assert(registry.length == 0, "remove drops the monitor");
	assert(!registry.isMonitoring(host), "the removed host is no longer monitored");
}

/// remove of an unmonitored host is a no-op
unittest
{
	auto registry = idleRegistry();

	registry.remove(MongoHost("missing", 27017));

	assert(registry.length == 0, "removing an unknown host changes nothing");
}

/// reconcileWith starts newly-discovered hosts and stops removed ones
unittest
{
	auto registry = idleRegistry();
	auto a = MongoHost("a", 27017);
	auto b = MongoHost("b", 27017);
	auto c = MongoHost("c", 27017);

	registry.reconcileWith([a, b]);
	assert(registry.length == 2, "the first reconcile starts a monitor per host");

	registry.reconcileWith([b, c]);

	assert(registry.length == 2, "the set size matches the new topology");
	assert(registry.isMonitoring(b), "a host present in both reconciles keeps its monitor");
	assert(registry.isMonitoring(c), "a newly-discovered host gets a monitor");
	assert(!registry.isMonitoring(a), "a removed host loses its monitor");

	registry.stopAll();
}

/// stopAll stops and forgets every monitor
unittest
{
	auto registry = idleRegistry();

	registry.ensure(MongoHost("a", 27017));
	registry.ensure(MongoHost("b", 27017));
	registry.stopAll();

	assert(registry.length == 0, "stopAll empties the registry");
}

/// requestCheck for an unmonitored host is a no-op
unittest
{
	auto registry = idleRegistry();

	registry.requestCheck(MongoHost("missing", 27017));

	assert(registry.length == 0, "requesting a check for an unknown host changes nothing");
}

/// requestAllChecks triggers an immediate re-check on every monitor
unittest
{
	import vibe.core.core : sleep;
	import core.time : msecs, hours;
	import std.functional : toDelegate;

	int checks;
	void countResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe { checks++; }

	auto registry = new MonitorRegistry(toDelegate(&stubProbe), &countResult, 1.hours, 1.msecs);

	registry.ensure(MongoHost("a", 27017));
	registry.ensure(MongoHost("b", 27017));
	sleep(40.msecs);
	auto before = checks;

	registry.requestAllChecks();
	sleep(40.msecs);
	registry.stopAll();

	assert(checks > before, "requestAllChecks re-checks each monitor instead of waiting the full heartbeat");
}
