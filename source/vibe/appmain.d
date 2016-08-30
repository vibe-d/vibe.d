/**
	Provides vibe based applications with a central program entry point.

	This module is included automatically through the import 'vibe.d'. It will provide a default
	application entry point which parses command line arguments, reads the global vibe configuration
	file, and starts the event loop.

	The application itself then just has to initialize itself from within a 'static this' module
	constructor and perform the appropriate calls to listen for connections or other operations.

	If you want to provide your own main function, you have to import vibe.vibe instead of
	vibe.d and define a -version=VibeCustomMain. Be sure to call vibe.core.core.runEventLoop
	at the end of your main function in this case. Also beware that you have to make appropriate
	calls to vibe.core.args.finalizeCommandLineOptions and vibe.core.core.lowerPrivileges to get the
	same behavior.

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.appmain;

version (VibeDefaultMain):

version (VibeCustomMain) {
	static assert(false, "Both, VibeCustomMain and VibeDefaultMain are defined. "
		~ "Either define only VibeDefaultMain, or nothing at all (VibeCustomMain "
		~ "has no effect since 0.7.26).");
}

/**
	The predefined vibe.d application entry point.

	This function will automatically be executed if you import the module vibe.d in your code. It
	will perform default command line parsing and starts the event loop.
*/
int main()
{
	import vibe.core.core : runApplication;

	version (unittest) {
		return 0;
	} else {
		return runApplication();
	}
}
