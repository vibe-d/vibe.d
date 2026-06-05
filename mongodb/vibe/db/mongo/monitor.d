/**
	Per-server SDAM health monitoring.

	Implements the heartbeat throttling and server health checks defined by the
	MongoDB Server Discovery and Monitoring specification.

	See_Also: $(LINK https://github.com/mongodb/specifications/blob/master/source/server-discovery-and-monitoring/server-discovery-and-monitoring.md)

	Copyright: © 2026 Szabo Bogdan
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Szabo Bogdan
*/
module vibe.db.mongo.monitor;

import vibe.db.mongo.connection : ServerDescription;
import vibe.db.mongo.settings : MongoHost;

import vibe.core.core : runTask, sleep;
import vibe.core.task : Task;
import vibe.core.log : logError;

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
	}

	this(MongoHost host, ServerProber probe, MonitorResult onResult, Duration heartbeat, Duration minHeartbeat) @safe
	{
		m_host = host;
		m_probe = probe;
		m_onResult = onResult;
		m_heartbeat = heartbeat;
		m_minHeartbeat = minHeartbeat;
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

	/**
	 * Supervises `runLoop`, restarting it after a logged failure.
	 *
	 * Stops when `runLoop` exits cleanly (returns `true`) or when `stop()` was
	 * requested. After a crash, waits one `m_heartbeat` before restarting so a
	 * persistently failing server is retried at the regular heartbeat cadence
	 * rather than in a tight spin loop.
	 */
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

	/**
	 * Runs the heartbeat loop until `stop()` is requested.
	 *
	 * Returns: `true` when the loop exits cleanly because `m_running` became
	 *   false; `false` when an exception escaped the loop body, in which case
	 *   the failure is logged before returning.
	 */
	private bool runLoop() nothrow
	{
		try
		{
			while (m_running)
			{
				checkOnce();
				sleep(m_heartbeat);
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
