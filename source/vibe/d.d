/**
	Provides the vibe.d API and a default main() function for the application.

	Applications that import 'vibe.d' will have most of the vibe API available and will be provided
	with an implicit application entry point (main). The resulting application parses command line
	parameters and reads the global vibe.d configuration (/etc/vibe/vibe.conf).

	Initialization is done in module constructors (static this), which run just before the event
	loop is started by the application entry point.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.d;

public import vibe.vibe;
