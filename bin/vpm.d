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
	help: you watch this currently
	run: (default) makes sure everything is set up correctly and runs
		the application afterwards
	build: makes sure everything is set up, but does not run the application
	upgrade: performs a regular update and uninstalls and reinstalls all
		installed packages
		or
		upgrade:packageId[,packageId] to perform it only on one single package
		(not yet implemented)
	install: installs a specified package
		install:packageId[,packageId]
		
	Advanced options:
		-annotate: without actually updating, check for the status of the application
		-verbose: prints out lots of debug information
		-vverbose: even more debug output

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
		if(args.length < 3)
			throw new Exception("Too few parameters");
		
		enforce(isDir(args[1]));
		Path vibedDir = Path(args[1]);
		Path dstScript = Path(args[2]);
		string[] vpmArgs = args[3..$];
		auto vpmArg = lastVpmArg(vpmArgs);
		string[] appArgs;
		if(vpmArg < vpmArgs.length)
			appArgs = vpmArgs[vpmArg..$];
		vpmArgs = vpmArgs[0..vpmArg];
	
		string appStartScript;
		if(canFind(vpmArgs, "help")) {
			printHelp();
			appStartScript = ""; // make sure the script is empty, so that the app is not run
		}
		else {
			if(canFind(vpmArgs, "-verbose"))
				setLogLevel(LogLevel.Debug);
			if(canFind(vpmArgs, "-vverbose"))
				setLogLevel(LogLevel.Trace);

			auto appPath = getcwd();
			logInfo("Updating application in '%s'", appPath);
			
			Url url = Url.parse("http://registry.vibed.org/");
			logDebug("Using vpm registry url '%s'", url);
			
			Vpm vpm = new Vpm(Path(appPath), new RegistryPS(url));
			logDebug("vpm initialized");
			
			vpm.update(parseOptions(vpmArgs));
			
			string binName = (Path(".") ~ "app").toNativeString();
			version(Windows) { binName ~= ".exe"; }

			// Create start script, which will be used by the calling bash/cmd script.			
			// build "rdmd --force %DFLAGS% -I%~dp0..\source -Jviews -Isource @deps.txt %LIBS% source\app.d" ~ application arguments
			// or with "/" instead of "\"
			string[] flags = ["--force"];
			if( canFind(vpmArgs, "build") ){
				flags ~= "--build-only";
				flags ~= "-of"~binName;
			}
			flags ~= "-g";
			flags ~= "-I" ~ (vibedDir ~ ".." ~ "source").toNativeString();
			flags ~= "-Isource";
			flags ~= "-Jviews";
			flags ~= vpm.dflags;
			flags ~= getLibs(vibedDir);
			flags ~= getPackagesAsVersion(vpm);
			flags ~= (Path("source") ~ "app.d").toNativeString();
			flags ~= appArgs;

			appStartScript = "rdmd " ~ getDflags() ~ " " ~ join(flags, " ");
		}

		auto script = openFile(to!string(dstScript), FileMode.CreateTrunc);
		scope(exit) script.close();
		script.write(appStartScript);
		
		return 0;
	}
	catch(Throwable e) 
	{
		logError("Failed to perform properly: \n" ~ to!string(e) ~ "\nShowing the help, just in case ...");
		printHelp();
		return -1;
	}
}

private size_t lastVpmArg(string[] args)
{
	string[] vpmArgs = 
	[
		"help",
		"upgrade",
		"install",
		"run",
		"build",
		"-annotate",
		"-keepDepsTxt",
		"-verbose"
		"-vverbose"
	];
	foreach(k,s; args) 
		if( false == reduce!((bool a, string b) => a || s.startsWith(b))(false, vpmArgs) )
			return k;
	return args.length;
}

private int parseOptions(string[] args)
{
	int options = 0;
	if(canFind(args, "upgrade"))
		options = options | UpdateOptions.Reinstall;
	if(canFind(args, "-annotate"))
		options = options | UpdateOptions.JustAnnotate;
	return options;
}

private string getDflags()
{
	auto globVibedDflags = environment.get("DFLAGS");
	if(globVibedDflags == null) 
		globVibedDflags = "-debug -g -w -property";
	return globVibedDflags;
}

private string[] getLibs(Path vibedDir) 
{
	version(Windows)
	{
		auto libDir = vibedDir ~ "..\\lib\\win-i386";
		return ["ws2_32.lib", 
			(libDir ~ "event2.lib").toNativeString(),
			(libDir ~ "eay.lib").toNativeString(),
			(libDir ~ "ssl.lib").toNativeString()];
	}
	version(Posix)
	{
		return split(environment.get("LIBS", "-L-levent_openssl -L-levent"));
	}
}

private string stripDlangSpecialChars(string s) {
	char[] ret = s.dup;
	for(int i=0; i<ret.length; ++i)
		if(!isAlpha(ret[i])) 
			ret[i] = '_';
	return to!string(ret);
}

private string[] getPackagesAsVersion(const Vpm vpm) 
{
	string[] ret;
	string[string] pkgs = vpm.installedPackages();
	foreach(id, vers; pkgs) 
		ret ~= "-version=VPM_package_" ~ stripDlangSpecialChars(id);
	return ret;
}
