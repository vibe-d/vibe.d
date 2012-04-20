/**
	A package manager.

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
import std.array;
import std.file;
import std.exception;
import std.algorithm;
import std.zip;
import std.typecons;

import vibe.d;

import vibe.core.log;
import vibe.core.file;
import vibe.data.json;
import vibe.inet.url;

import vibe.vpm.vpm;
import vibe.vpm.registry;

import vibe.http.fileserver;
import vibe.http.router;
import vibe.inet.url;

static this() {
	setLogLevel(LogLevel.Info);
	
	auto appPath = getcwd();
	logInfo("Updating for '%s'", appPath);
	
	Url url = Url.parse("http://127.0.0.1:8080/registry/");
	logDebug("Using registry url '%s'", url);
	
	Vpm vpm = new Vpm(Path(appPath), new RegistryPS(url));
	logDebug("Initialized");
	// if(exists("C:\\dev\\vpm\\playground\\modules\\CowboysFromHell"))
		// vpm.uninstall("CowboysFromHell");
	vpm.update(true);
	vpm.createDepsTxt();


	// TODO: way to quit vibe needed
	throw new Exception("quit vibe");
}

