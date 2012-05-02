/**
	The entry point to vibe.d

	Copyright: © 2012 Matthias Dondorff
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Matthias Dondorff
*/
	
import std.algorithm;
import std.exception;
import std.file;
import std.process;

import vibe.vibe;
import vibe.core.log;
import vibe.inet.url;
import vibe.vpm.vpm;
import vibe.vpm.registry;

/// Starts the vpm and updates the application in the current working directory
/// and writes the deps.txt afterwards, so that the application can start proper.
///
/// Command line arguments:
///
/// vpm vibeDir [OPT,...[,APP_OP]]
///
/// vibeDir: the installation folder of the vibe installation
/// 
/// Where OPT is one of
/// run: (default) makes sure everything is set up correctly and runs
///		the application afterwards
/// build: makes sure everything is set up, but does not run the application
/// reinstall: performs a regular update and uninstalls and reinstalls any
/// 	installed packages
/// keepDepsTxt: does not write out the deps.txt
/// verbose: prints out lots of debug information
///
/// APP_OP will be passed on to the application to be run (not implemented)
int main(string[] args)
{	
	enforce(args.length > 1);
	enforce(isDir(args[1]));
	Path vibedDir = Path(args[1]);
	int vpmArg = lastVpmArg(args);
	string[] vpmArgs = args[2..vpmArg];
	string[] appArgs;
	if(vpmArg < args.length)
		appArgs = args[vpmArg+1..$];

	if(canFind(vpmArgs, "verbose"))
		setLogLevel(LogLevel.Debug);
	else
		setLogLevel(LogLevel.Info);

	auto appPath = getcwd();
	logInfo("Updating application in '%s'", appPath);
	
	Url url = Url.parse("http://registry.vibed.org/");
	logDebug("Using vpm registry url '%s'", url);
	
	Vpm vpm = new Vpm(Path(appPath), new RegistryPS(url));
	logDebug("Initialized");
	
	vpm.update(parseOptions(vpmArgs));
	
	if(!canFind(vpmArgs, "keepDepsTxt"))
		vpm.createDepsTxt();

	// Spawn the application
	if(!canFind(vpmArgs, "build")) 
	{
		string[] rdmdFlags;
		
		build "--force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d %1 %2 %3 %4 %5 %6"
		rdmdFlags ~= "--force";
		rdmdFlags ~= getDflags();
		rdmdFlags ~= "-I" ~ to!string(vibedDir ~ ".." ~ "source");
		rdmdFlags ~= "-Jviews";
		rdmdFlags ~= "-Isource";
		if(exists("deps.txt"))
			rdmdFlags ~= "@deps.txt";
		rdmdFlags ~= getLibs(vibedDir);
		rdmdFlags ~= to!string(Path("source")~"app.d");
		rdmdFlags ~= appArgs;
		logInfo("Flags for rdmd: %s", to!string(rdmdFlags));
		return spawnvp(std.c.process._P_NOWAIT, "rdmd", rdmdFlags);
	}
	else
		return 0;
}

private int lastVpmArg(string[] args)
{
	// TODO
	return args.length;
}

private int parseOptions(string[] args)
{
	int options = 0;
	if(canFind(args, "reinstall"))
		options = options | UpdateOptions.Reinstall;
	if(canFind(args, "annotate"))
		options = options | UpdateOptions.JustAnnotate;
	return options;
}

private string[] getDflags()
{
	auto globVibedDflags = environment.get("DFLAGS");
	if(globVibedDflags == null) 
		globVibedDflags = "-debug -g -w -property";
	auto r = splitter(globVibedDflags);
	string[] dflags;
	foreach(string f; r)
		dflags ~= f;
	return dflags;
}

private string[] getLibs(Path vibedDir) 
{
	string[] libs;
	version(Windows)
	{
		auto libDir = vibedDir ~ "..\\lib\\win-i386";
		libs ~= "ws2_32.lib";
		libs ~= to!string(libDir ~ "event2.lib");
		libs ~= to!string(libDir ~ "eay.lib");
		libs ~= to!string(libDir ~ "ssl.lib");
	}
	else
	{
		libs ~= "-L-levent";
		libs ~= "-L-levent_openssl";
		libs ~= "-L-lssl";
		libs ~= "-L-lcrypto";
	}
	return libs;
}