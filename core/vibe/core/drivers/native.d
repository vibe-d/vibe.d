/**
	Defines a type alias to the statically selected event driver.

	Copyright: © 2014 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.native;

version (VibeLibeventDriver) {
	import vibe.core.drivers.libevent2;
	alias NativeEventDriver = Libevent2Driver;
} else version (VibeLibasyncDriver) {
	import vibe.core.drivers.libasync;
	alias NativeEventDriver = LibasyncDriver;
} else version (VibeWin32Driver) {
	import vibe.core.drivers.win32;
	alias NativeEventDriver = Win32EventDriver;
} else static assert(false, "No event driver has been selected. Please specify a -version=Vibe*Driver for the desired driver.");
