/**
	Parsing of command line arguments.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.args;

import vibe.core.log;
import vibe.data.json;
import vibe.http.server;

import std.getopt;
import std.exception;
import std.file;


version(Posix)
{
	import core.sys.posix.unistd;

	private enum configPath = "/etc/vibe/vibe.conf";

	private bool setUID(int uid, int gid)
	{
		if( geteuid() == 0 && (uid >= 0 || gid >= 0) ){
			logInfo("Vibe was run as root, lowering priviledges to uid=%d, gid=%d...", uid, gid);
			if( gid >= 0 && setegid(gid) != 0 ) return false;
			//if( initgroups(const char *user, gid_t group);
			if( uid >= 0 && seteuid(uid) != 0 ) return false;
		}
		return true;
	}

} else version(Windows){
	private enum configPath = "vibe.conf";

	private bool setUID(int uid, int gid)
	{
		assert(uid < 0 && gid < 0, "UID/GID not supported on Windows.");
		if( uid >= 0 || gid >= 0 )
			return false;
		return true;
	}
}


/**
	Processes the command line arguments passed to the application.

	Any argument that matches a vibe supported command switch is removed from the 'args' array.
*/
void processCommandLineArgs(ref string[] args)
{
	int uid = -1;
	int gid = -1;
	bool verbose = false;
	string disthost;
	ushort distport = 11000;

	if( exists(configPath) ){
		try {
			auto config = readText(configPath);
			auto cnf = parseJson(config);
			if( auto pv = "uid" in cnf ) uid = cast(int)*pv;
			if( auto pv = "gid" in cnf ) gid = cast(int)*pv;
		} catch(Exception e){
			logWarn("Failed to parse config file %s: %s", configPath, e.msg);
		}
	} else {
		logDebug("No config file found at %s", configPath);
	}

	getopt(args,
		"uid", &uid,
		"gid", &gid,
		"verbose|v", &verbose,
		"disthost|d", &disthost,
		"disport", &distport
		);

	if( verbose ) setLogLevel(LogLevel.Trace);

	setVibeDistHost(disthost, distport);
	startListening();

	enforce(setUID(uid, gid), "Error lowering privileges!");
}
