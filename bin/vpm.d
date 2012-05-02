/**
	A package manager.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
import std.file;
import std.algorithm;

import vibe.vibe;
import vibe.core.log;
import vibe.inet.url;
import vibe.vpm.vpm;
import vibe.vpm.registry;

/// Starts the VPM and updates the application in the current working directory
/// and writes the deps.txt afterwards, so that the application can start proper.
///
/// Command line arguments:
///
/// - reinstall: performs a regular update and uninstalls and reinstalls any
/// installed packages
/// - keepDepsTxt: does not write out the deps.txt
int main(string[] args)
{
	setLogLevel(LogLevel.Info);

	auto appPath = getcwd();
	logInfo("Updating application in '%s'", appPath);
	
	Url url = Url.parse("http://registry.vibed.org/");
	logDebug("Using registry url '%s'", url);
	
	Vpm vpm = new Vpm(Path(appPath), new RegistryPS(url));
	logDebug("Initialized");
	
	int options = 0;
	if(canFind(args, "reinstall"))
		options = options | UpdateOptions.Reinstall;
		
	vpm.update(options);
	
	if(!canFind(args, "keepDepsTxt"))
		vpm.createDepsTxt();

	return 0;
}

