/**
	Deprecated; Contains the SSLContext class used for SSL based network connections.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.crypto.ssl;

pragma(msg, "Module vibe.crypto.ssl is deprecated, please import vibe.stream.ssl instead.");

public import vibe.stream.ssl;
