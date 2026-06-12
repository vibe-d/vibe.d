/**
	Per-server SDAM health monitoring.

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.monitor;

import vibe.db.mongo.impl.serverdescription : ServerDescription;
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

	/// Requests a check. Always wakes the loop; the loop honors the minHeartbeat
	/// floor so a request inside the cooldown runs at lastCheck + minHeartbeat
	/// rather than being dropped until the next full heartbeat.
	void requestCheck() @safe
	{
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

				// A request that woke us inside the cooldown is honored at the floor,
				// not the full heartbeat: wait out the rest of minHeartbeat first.
				auto now = MonoTime.currTime;
				if (m_running && !shouldCheckNow(m_lastCheck, now, m_minHeartbeat))
					sleep(m_minHeartbeat - (now - m_lastCheck));
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
		m_monitors = null;
		m_hosts = null;
	}
}

/// Returns true once at least `minInterval` has elapsed since the last check.
bool shouldCheckNow(MonoTime last, MonoTime now, Duration minInterval) @safe pure nothrow @nogc
{
	return now - last >= minInterval;
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

/// MongoDB server error codes the driver classifies for retry decisions.
enum MongoServerErrorCode : int
{
	none = 0,
	hostUnreachable = 6,
	hostNotFound = 7,
	networkTimeout = 89,
	shutdownInProgress = 91,
	primarySteppedDown = 189,
	exceededTimeLimit = 262,
	socketException = 9001,
	duplicateKey = 11000,
	notWritablePrimary = 10107,
	interruptedAtShutdown = 11600,
	interruptedDueToReplStateChange = 11602,
	notPrimaryNoSecondaryOk = 13435,
	notPrimaryOrSecondary = 13436,
}

/// Whether a server error code is in the SDAM "not master or recovering" set.
bool isStaleTopologyError(MongoServerErrorCode code) @safe pure nothrow @nogc
{
	switch (code)
	{
		case MongoServerErrorCode.notWritablePrimary:
		case MongoServerErrorCode.notPrimaryNoSecondaryOk:
		case MongoServerErrorCode.notPrimaryOrSecondary:
		case MongoServerErrorCode.interruptedAtShutdown:
		case MongoServerErrorCode.interruptedDueToReplStateChange:
		case MongoServerErrorCode.primarySteppedDown:
		case MongoServerErrorCode.shutdownInProgress:
			return true;
		default:
			return false;
	}
}

/// isStaleTopologyError flags the not-master / recovering server error codes
unittest
{
	assert(isStaleTopologyError(MongoServerErrorCode.notWritablePrimary), "NotWritablePrimary");
	assert(isStaleTopologyError(MongoServerErrorCode.notPrimaryNoSecondaryOk), "NotPrimaryNoSecondaryOk");
	assert(isStaleTopologyError(MongoServerErrorCode.interruptedDueToReplStateChange), "InterruptedDueToReplStateChange");
	assert(isStaleTopologyError(MongoServerErrorCode.primarySteppedDown), "PrimarySteppedDown");
	assert(isStaleTopologyError(MongoServerErrorCode.shutdownInProgress), "ShutdownInProgress");
	assert(isStaleTopologyError(MongoServerErrorCode.notPrimaryOrSecondary), "NotPrimaryOrSecondary");
	assert(isStaleTopologyError(MongoServerErrorCode.interruptedAtShutdown), "InterruptedAtShutdown");

	assert(!isStaleTopologyError(MongoServerErrorCode.duplicateKey), "duplicate key is not a topology error");
	assert(!isStaleTopologyError(MongoServerErrorCode.none), "no error code");
}

/// Whether a server error code marks a write safe to retry once (MongoDB 3.6+
/// retryable writes). Covers the election/topology set plus the network-error codes.
bool isRetryableWriteError(MongoServerErrorCode code) @safe pure nothrow @nogc
{
	if (isStaleTopologyError(code))
		return true;

	switch (code)
	{
		case MongoServerErrorCode.hostUnreachable:
		case MongoServerErrorCode.hostNotFound:
		case MongoServerErrorCode.networkTimeout:
		case MongoServerErrorCode.socketException:
		case MongoServerErrorCode.exceededTimeLimit:
			return true;
		default:
			return false;
	}
}

/// isRetryableWriteError flags network errors beyond the election set
unittest
{
	assert(isRetryableWriteError(MongoServerErrorCode.networkTimeout), "NetworkTimeout is a retryable write error");
}

/// isRetryableWriteError flags SocketException as a network error
unittest
{
	assert(isRetryableWriteError(MongoServerErrorCode.socketException) == true, "SocketException is a retryable write error");
}

/// isRetryableWriteError flags election codes from the stale-topology set
unittest
{
	assert(isRetryableWriteError(MongoServerErrorCode.notWritablePrimary) == true, "an election code is also a retryable write error");
}

/// isRetryableWriteError rejects non-retryable error codes
unittest
{
	assert(!isRetryableWriteError(MongoServerErrorCode.duplicateKey), "a duplicate-key error is not a retryable write error");
	assert(!isRetryableWriteError(MongoServerErrorCode.none), "no error code is not a retryable write error");
}

/// isRetryableWriteError rejects an unknown server error code
unittest
{
	assert(!isRetryableWriteError(cast(MongoServerErrorCode) 99999),
		"an unknown server error code is not a retryable write error");
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

/// Whether a stale-topology error is retryable: only for idempotent ops or ops with session support.
bool shouldRetryAfterStepDown(MongoServerErrorCode code, bool idempotent, bool sessionSupport) @safe pure nothrow @nogc
{
	return isStaleTopologyError(code) && (idempotent || sessionSupport);
}

/// shouldRetryAfterStepDown retries idempotent or session-supported ops on a stale-topology error
unittest
{
	assert(shouldRetryAfterStepDown(MongoServerErrorCode.notWritablePrimary, true, false), "idempotent NotWritablePrimary is retryable");
	assert(shouldRetryAfterStepDown(MongoServerErrorCode.notWritablePrimary, false, true), "session-supported NotWritablePrimary is retryable");
}

/// Whether a failed write may be retried once: a retryable-write error on a
/// session-supported write (the transaction number lets the server deduplicate).
bool shouldRetryWrite(MongoServerErrorCode code, bool sessionSupport) @safe pure nothrow @nogc
{
	return isRetryableWriteError(code) && sessionSupport;
}

/// shouldRetryWrite retries a network error on a session-supported write
unittest
{
	assert(shouldRetryWrite(MongoServerErrorCode.networkTimeout, true) == true, "a network error on a session-supported write is retryable");
}

/// shouldRetryWrite does not retry without session support
unittest
{
	assert(shouldRetryWrite(MongoServerErrorCode.networkTimeout, false) == false, "a write without session support is not retried (the server cannot deduplicate)");
}

/// checkOnce probes the host and reports the probed description via the callback
unittest
{
	import vibe.db.mongo.impl.serverdescription : ServerDescription;
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
	import vibe.db.mongo.impl.serverdescription : ServerDescription;
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
	import vibe.db.mongo.impl.serverdescription : ServerDescription;
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
	import vibe.db.mongo.impl.serverdescription : ServerDescription;
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
	import vibe.db.mongo.impl.serverdescription : ServerDescription;
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
	import vibe.db.mongo.impl.serverdescription : ServerDescription;
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

/// requestCheck during the minHeartbeat cooldown still schedules a check at the floor, not after the full heartbeat
unittest
{
	import vibe.core.core : sleep;
	import core.time : msecs, seconds;
	import vibe.db.mongo.impl.serverdescription : ServerDescription;
	import vibe.db.mongo.settings : MongoHost;

	auto host = MongoHost("primary", 27017);
	ServerDescription prober(MongoHost h) @safe { ServerDescription d; d.isWritablePrimary = true; d.setName = "rs0"; return d; }

	int checks;
	void onResult(MongoHost h, Nullable!ServerDescription desc, Duration rtt) @safe { checks++; }

	auto monitor = new ServerMonitor(host, &prober, &onResult, 10.seconds, 50.msecs);

	monitor.start();
	sleep(20.msecs);
	auto before = checks;
	monitor.requestCheck();
	sleep(250.msecs);
	monitor.stop();

	assert(checks > before, "a check requested during the minHeartbeat cooldown still runs at the floor, not after the full heartbeat");
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

/// an inert registry (constructed but never reconciled, as in load-balanced mode) answers every query safely
unittest
{
	auto registry = idleRegistry(); // never ensure/reconcileWith -> empty, exactly the LB-mode state

	assert(registry.length == 0, "an inert registry has no monitors");
	registry.requestCheck(MongoHost("anyhost", 27017)); // unknown host -> must be a no-op, not a crash
	registry.requestAllChecks();                        // no monitors -> no-op
	registry.stopAll();                                 // no monitors -> no-op
	assert(registry.length == 0, "still no monitors after the no-op calls");
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
