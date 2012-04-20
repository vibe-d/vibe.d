/**
	Evented signal-slot mechanism

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.signal;

import vibe.core.core;

import intf.event2.event;
import intf.event2.util;

import core.thread;


class SignalException : Exception {
	this() { super("Signal emitted."); }
}

class Signal {
	private {
		event* m_event;
		bool[Fiber] m_listeners;
		int m_emitCount = 0;
	}

	this()
	{
		m_event = event_new(vibeGetEventLoop(), -1, EV_PERSIST, &onSignalTriggered, cast(void*)this);
		event_add(m_event, null);
	}

	~this()
	{
		event_free(m_event);
	}

	void emit()
	{
		event_active(m_event, 0, 0);
	}

	void wait()
	{
		assert(!isSelfRegistered());
		auto self = Fiber.getThis();
		registerSelf();
		auto start_count = m_emitCount;
		while( m_emitCount == start_count )
			vibeYieldForEvent();
		unregisterSelf();
	}

	void registerSelf()
	{
		m_listeners[Fiber.getThis()] = true;
	}

	void unregisterSelf()
	{
		auto self = Fiber.getThis();
		if( isSelfRegistered() )
			m_listeners.remove(self);
	}

	bool isSelfRegistered()
	{
		return (Fiber.getThis() in m_listeners) !is null;
	}

	@property int emitCount() const { return m_emitCount; }
}

private extern(C) void onSignalTriggered(evutil_socket_t, short events, void* userptr)
{
	auto sig = cast(Signal)userptr;

	sig.m_emitCount++;

	auto lst = sig.m_listeners.dup;
	
	foreach( l, _; lst )
		vibeResumeTask(l);
}
