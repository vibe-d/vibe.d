/**
	Utility functions for memory management

	Note that this module currently is a big sand box for testing allocation related stuff.
	Nothing here, including the interfaces, is final but rather a lot of experimentation.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
deprecated("Use the memutils package or stdx.allocator instead.")
module vibe.utils.memory;

public import vibe.internal.memory_legacy;
