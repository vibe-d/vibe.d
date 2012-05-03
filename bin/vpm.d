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
import vibe.core.file;
import vibe.core.log;
import vibe.inet.url;
import vibe.vpm.vpm;
import vibe.vpm.registry;

void printHelp()
{
	// This help is actually a mixup of help for this application and the
	// supporting vibe script / .cmd file.
	logInfo("
Starts vibe.d for the application in the current working directory

Command line arguments:

vibe [OPT,...[,APP_OP]]

Where OPT is one of
	run: (default) makes sure everything is set up correctly and runs
		the application afterwards
	build: makes sure everything is set up, but does not run the application
	upgrade: performs a regular update and uninstalls and reinstalls all
		installed packages
		or
		upgrade:packageid to perform it only on one single package
		
	Advanced options:
		annotate: without actually updating, check for the status of the application
		keepDepsTxt: does not write out the deps.txt
		verbose: prints out lots of debug information

APP_OP will be passed on to the application to be run.");
}

// Applications needed arguments are
// 1: vibeDir
// 2: scriptDestination
// Therefore the real usage is:
// vpm.d vibeDir scriptDestination <everythingElseFromPrintHelp>
// 
// vibeDir: the installation folder of the vibe installation
// startupScriptFile: destination of the script, which can be used to run the app 
// 
// However, this should be taken care of the scripts.
int main(string[] args)
{	
	try {
		if(args.length < 2)
			throw new Exception("Too few parameters");
		
		enforce(isDir(args[1]));
		Path vibedDir = Path(args[1]);
		Path dstScript = Path(args[2]);
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
		logDebug("vpm initialized");
		
		vpm.update(parseOptions(vpmArgs));
		
		if(!canFind(vpmArgs, "keepDepsTxt"))
			vpm.createDepsTxt();

		// Spawn the application
		string appStartScript;
		if(!canFind(vpmArgs, "build")) 
		{
			string arguments;
			foreach(string a; appArgs)
				arguments ~= " " ~ a;
			
			// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d %1 %2 %3 %4 %5 %6"
			// or with "/" instead of "\"
			appStartScript = "rdmd --force " ~
				getDflags() ~ " " ~
				"-I" ~ (vibedDir ~ ".." ~ "source").toNativeString() ~ " " ~
				"-Jviews -Isource " ~
				(exists("deps.txt")? "@deps.txt " : " ") ~
				getLibs(vibedDir) ~ " " ~
				(Path("source") ~ "app.d").toNativeString() ~
				arguments;
		}
		else
		{
			appStartScript = ""; // empty script, application won't be run
		}
		
		// TODO: proper rights, make executable
		auto script = openFile(to!string(dstScript), FileMode.CreateTrunc);
		scope(exit) script.close();
		script.write(appStartScript);
		return 0;
	}
	catch(Throwable e) 
	{
		logError("Failed to perform properly: \n" ~ to!string(e) ~ "\n");
		printHelp();
		return -1;
	}
}

private int lastVpmArg(string[] args)
{
	// TODO
	return args.length;
}

private int parseOptions(string[] args)
{
	int options = 0;
	logInfo("parsing: %s", args);
	if(canFind(args, "upgrade"))
		options = options | UpdateOptions.Reinstall;
	if(canFind(args, "annotate"))
		options = options | UpdateOptions.JustAnnotate;
	logInfo("Options: %s", options);
	return options;
}

private string getDflags()
{
	auto globVibedDflags = environment.get("DFLAGS");
	if(globVibedDflags == null) 
		globVibedDflags = "-debug -g -w -property";
	return globVibedDflags;
}

private string getLibs(Path vibedDir) 
{
	version(Windows)
	{
		auto libDir = vibedDir ~ "..\\lib\\win-i386";
		return "ws2_32.lib " ~ 
			(libDir ~ "event2.lib").toNativeString() ~ " " ~
			(libDir ~ "eay.lib").toNativeString() ~ " " ~
			(libDir ~ "ssl.lib").toNativeString();
	}
	version(Posix)
	{
		return "-L-levent -L-levent_openssl -L-lssl -L-lcrypto";
	}
}