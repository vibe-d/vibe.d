/**
	A package manager.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
import std.file;

import vibe.d;
import vibe.core.log;
import vibe.inet.url;
import vibe.vpm.vpm;
import vibe.vpm.registry;

/// Starts the VPM and updates the application in the current working directory
/// and writes the deps.txt afterwards, so that the application can start proper.
static this() {
	setLogLevel(LogLevel.Info);

	auto appPath = getcwd();
	logInfo("Updating application in '%s'", appPath);
	
	Url url = Url.parse("http://registry.vibed.org/");
	//Url url = Url.parse("http://127.0.0.1:8005/");
	logDebug("Using registry url '%s'", url);
	
	Vpm vpm = new Vpm(Path(appPath), new RegistryPS(url));
	logDebug("Initialized");
	
	vpm.update();
	vpm.createDepsTxt();
	//vpm.createZip("testApp.zip");


	// TODO: way to quit vibe needed
	throw new Exception("quit vibe");
}

