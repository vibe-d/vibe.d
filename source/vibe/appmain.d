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

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.appmain;

import vibe.core.args : finalizeCommandLineOptions;
import vibe.core.core : runEventLoop, lowerPrivileges;
import vibe.core.log;
import std.encoding : sanitize;

// only include main if VibeCustomMain is not set
version (VibeCustomMain) {}
else:

version (VibeDefaultMain) {}
else { pragma(msg, "Warning: -version=VibeDefaultMain will be required in the future to use vibe.d's default main(). Please update your build scripts."); }

/**
	The predefined vibe.d application entry point.

	This function will automatically be executed if you import the module vibe.d in your code. It
	will perform default command line parsing and starts the event loop.
*/
int main()
{
	version (unittest) {
		logInfo("All unit tests were successful.");
		return 0;
	} else {
		try if (!finalizeCommandLineOptions()) return 0;
		catch (Exception e) {
			logDiagnostic("Error processing command line: %s", e.msg);
			return 1;
		}

		lowerPrivileges();
		
		logDiagnostic("Running event loop...");
		int status;
		version (VibeDebugCatchAll) {
			try {
				status = runEventLoop();
			} catch( Throwable th ){
				logError("Unhandled exception in event loop: %s", th.msg);
				logDiagnostic("Full exception: %s", th.toString().sanitize());
				return 1;
			}
		} else {
			status = runEventLoop();
		}
		logDiagnostic("Event loop exited with status %d.", status);
		return status;
	}
}
