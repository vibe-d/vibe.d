/**
	Deprecated; SHA-1 hashing functions.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.crypto.sha1;
pragma(msg, "Module vibe.crypto.sha1 is deprecated, please import std.digest.sha instead.");

import std.digest.sha;

deprecated("Please use std.digest.sha.sha1Of instead.")
alias sha1 = sha1Of;
