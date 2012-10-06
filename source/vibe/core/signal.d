/**
	Evented signal-slot mechanism

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.signal;

public import vibe.core.driver;


/** Creates a new signal that can be shared between fibers.
*/
Signal createSignal()
{
	return getEventDriver().createSignal();
}

/** A cross-fiber signal

	Note: the ownership can be shared between multiple fibers.
*/
interface Signal : EventedObject {
	/// A counter that is increased with every emit() call
	@property int emitCount() const;

	/// Emits the signal, waking up all owners of the signal.
	void emit();

	/// Acquires ownership and waits until the signal is emitted.
	void wait();

	/// Acquires ownership and waits until the signal is emitted if no emit has happened since the given reference emit count.
	void wait(int reference_emit_count);
}

class SignalException : Exception {
	this() { super("Signal emitted."); }
}

