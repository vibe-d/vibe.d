/**
	Efficient timer management routines for large number of timers.

	Copyright: © 2014 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.timerqueue;

import vibe.utils.hashmap;

import std.datetime;


struct TimerQueue(DATA, long TIMER_RESOLUTION = 10_000) {
	static struct TimerInfo {
		long timeout; // standard time
		long repeatDuration; // hnsecs
		bool pending;
		DATA data;
	}

	private {
		size_t m_timerIDCounter = 1;
		HashMap!(size_t, TimerInfo) m_timers;

		static if (__VERSION__ >= 2065) {
			import std.container : Array, BinaryHeap;
			BinaryHeap!(Array!TimeoutEntry, "a.timeout > b.timeout") m_timeoutHeap;
		} else {
			// Workaround for ICE/Linker errors
			import std.container : DList;
			DList!TimeoutEntry m_timeoutHeap;
		}
	}

	size_t create(DATA data)
	{
		while (!m_timerIDCounter || m_timerIDCounter in m_timers) m_timerIDCounter++;
		m_timers[m_timerIDCounter] = TimerInfo(0, 0, false, data);
		return m_timerIDCounter++;
	}

	void destroy(size_t timer)
	{
		m_timers.remove(timer);
	}

	void schedule(size_t timer_id, Duration timeout_duration, bool periodic)
	{
		auto timeout = Clock.currStdTime() + timeout_duration.total!"hnsecs";
		auto pt = timer_id in m_timers;
		assert(pt !is null, "Accessing non-existent timer ID.");
		pt.timeout = timeout;
		pt.repeatDuration = periodic ? timeout_duration.total!"hnsecs" : 0;
		pt.pending = true;
		//logDebugV("rearming timer %s in %s s", timer_id, dur.total!"usecs" * 1e-6);
		scheduleTimer(timeout, timer_id);
	}

	void unschedule(size_t timer_id)
	{
		//logTrace("Stopping timer %s", timer_id);
		auto pt = timer_id in m_timers;
		pt.pending = false;
	}

	ref inout(DATA) getUserData(size_t timer_id) inout { return m_timers[timer_id].data; }

	bool isPending(size_t timer_id) const { return m_timers[timer_id].pending; }

	bool isPeriodic(size_t timer_id) const { return m_timers[timer_id].repeatDuration > 0; }

	SysTime getFirstTimeout()
	{
		if (m_timeoutHeap.empty) return SysTime.max;
		else return SysTime(m_timeoutHeap.front.timeout, UTC());
	}

	void consumeTimeouts(SysTime now, scope void delegate(size_t timer, bool periodic, ref DATA data) del)
	{
		//if (m_timeoutHeap.empty) logTrace("no timers scheduled");
		//else logTrace("first timeout: %s", (m_timeoutHeap.front.timeout - now) * 1e-7);

		while (!m_timeoutHeap.empty && (m_timeoutHeap.front.timeout - now.stdTime) / TIMER_RESOLUTION <= 0) {
			auto tm = m_timeoutHeap.front;
			m_timeoutHeap.removeFront();

			auto pt = tm.id in m_timers;
			if (!pt || !pt.pending || pt.timeout != tm.timeout) continue;
	
			if (pt.repeatDuration > 0) {
				pt.timeout += pt.repeatDuration;
				scheduleTimer(pt.timeout, tm.id);
			} else pt.pending = false;

			//logTrace("Timer %s fired (%s/%s)", tm.id, owner != Task.init, callback !is null);

			del(tm.id, pt.repeatDuration > 0, pt.data);
		}
	}

	private void scheduleTimer(long timeout, size_t id)
	{
		//logTrace("Schedule timer %s", id);
		auto entry = TimeoutEntry(timeout, id);
		static if (__VERSION__ >= 2065) {
			m_timeoutHeap.insert(entry);
		} else {
			auto existing = m_timeoutHeap[];
			while (!existing.empty && existing.front.timeout < entry.timeout)
				existing.popFront();
			m_timeoutHeap.insertBefore(existing, entry);
		}
		//logDebugV("first timer %s in %s s", id, (timeout - now) * 1e-7);
	}
}

private struct TimeoutEntry {
	long timeout;
	size_t id;
}
