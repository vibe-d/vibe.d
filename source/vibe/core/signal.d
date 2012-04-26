/**
	Evented signal-slot mechanism

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.signal;

public import vibe.core.driver;

import vibe.core.core;

import core.thread;


class SignalException : Exception {
	this() { super("Signal emitted."); }
}

