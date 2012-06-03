/**
	Evented signal-slot mechanism

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.signal;

public import vibe.core.driver;

import vibe.core.core;


class SignalException : Exception {
	this() { super("Signal emitted."); }
}


/** Creates a new signal that can be shared between fibers.
*/
Signal createSignal()
{
	return getEventDriver().createSignal();
}