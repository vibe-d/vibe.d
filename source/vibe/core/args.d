/**
	Parses and allows querying the command line arguments and configuration
	file.

	The optional configuration file (vibe.conf) is a JSON file, containing an
	object with the keys corresponding to option names, and values corresponding
	to their values. It is searched for in the local directory, user's home
	directory, or /etc/vibe/ (POSIX only), whichever is found first.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Vladimir Panteleev
*/
module vibe.core.args;

import vibe.core.log;
import vibe.data.json;

import std.exception;
import std.file;
import std.getopt;
import std.path;
import std.string;

import core.runtime;

/// Deprecated. Currently does nothing - Vibe will parse arguments
/// automatically on startup. Call $(D finalizeCommandLineArgs) from your
/// $(D main()) if you use a custom one, to check for unrecognized options.
deprecated void processCommandLineArgs(ref string[] args)
{
	finalizeCommandLineArgs();
}

/**
	Finds and reads an option from the configuration file or command line.
	Command line options take precedence.

	Params:
		names = Option names. Separate multiple name variants with $(D |),
				as with $(D std.getopt).
		pvalue = Pointer to store the value. Unchanged if value was not found.

	Returns:
		$(D true) if the value was found, $(D false) otherwise.
*/
bool getOption(T)(string names, T* pvalue)
{
	if (!args) // May happen due to http://d.puremagic.com/issues/show_bug.cgi?id=9881
		init();

	auto oldLength = args.length;
	getopt(args, getoptConfig, names, pvalue);
	if (oldLength != args.length) // getopt found it
	{
		static void removeArg(string names)
		{
			T v;
			getopt(args, getoptConfig, names, &v);
		}
		argRemovers[names] = &removeArg;
		return true;
	}

	if (haveConfig)
		foreach (name; names.split("|"))
			if (auto pv = name in config)
			{
				*pvalue = pv.get!T;
				return true;
			}

	return false;
}

/// Checks for unrecognized options.
/// Called automatically from $(D vibe.appmain).
void finalizeCommandLineArgs()
{
	foreach (names, fn; argRemovers)
		fn(names);
	enforce(args.length<=1, "Unrecognized command-line parameter: " ~ args[1]);
}

private:

enum configName = "vibe.conf";

string[] getConfigPaths()
{
	string[] result = [""];
	import std.process : environment;
	version (Windows)
		result ~= environment.get("USERPROFILE");
	else
		result ~= [environment.get("HOME"), "/etc/vibe/"];
	return result;
}

shared static this()
{
	if (!args)
		init();
}

void init()
{
	args = Runtime.args;

	auto searchPaths = getConfigPaths();
	foreach (searchPath; searchPaths)
	{
		auto configPath = buildPath(searchPath, configName);
		if (configPath.exists)
		{
			scope(failure) logError("Failed to parse config file %s:", configPath);
			auto configText = configPath.readText();
			config = configText.parseJson();
			haveConfig = true;
		}
	}

	if (!haveConfig)
		logDebug("No config file found in %s", searchPaths);
}

template ValueTuple(T...) { alias T ValueTuple; }
alias getoptConfig = ValueTuple!(
	std.getopt.config.passThrough,
	std.getopt.config.bundling,
);

__gshared:

string[] args;
bool haveConfig;
Json config;
void function(string)[string] argRemovers;
