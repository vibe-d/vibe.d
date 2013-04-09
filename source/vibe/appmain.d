/**
	Provides vibe based applications with a central program entry point.

	This module is included automatically through the import 'vibe.d'. It will provide a default
	application entry point which parses command line arguments, reads the global vibe configuration
	file, and starts the event loop.

	The application itself then just has to initialize itself from within a 'static this' module
	constructor and perform the appropriate calls to listen for connections or other operations.

	If you want to provide your own main() function, you have to import 'vibe.vibe' instead of
	'vibe.d'. Be sure to call start() at the end of your main function in this case. Also beware
	that any global configuration is not applied in this case and features such as priviledge
	lowering are not in place.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.appmain;

import vibe.core.args : finalizeCommandLineArgs;
import vibe.core.core : runEventLoop;
import vibe.core.log;

// only include main if VibeCustomMain is not set
version(VibeCustomMain) {} else:

/**
	The predefined vibe.d application entry point.

	This function will automatically be executed if you import the module vibe.d in your code. It
	will perform default command line parsing and starts the event loop.
*/
int main()
{
	version(unittest){
		logInfo("All unit tests were successful.");
		return 0;
	} else {
		finalizeCommandLineArgs();
		logInfo("Running event loop...");
		debug {
			return runEventLoop();
		} else {
			try {
				return runEventLoop();
			} catch( Throwable th ){
				logError("Unhandled exception in event loop: %s", th.toString());
				return 1;
			}
		}
	}
}
