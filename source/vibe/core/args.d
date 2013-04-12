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

import std.algorithm : any, array, map, sort;
import std.array : join, replicate, split;
import std.exception;
import std.file;
import std.getopt;
import std.path : buildPath;
import std.string : format, stripRight, wrap;

import core.runtime;


/**
	Deprecated. Removes any recognized arguments from args leaving any unrecognized options.

	Note that vibe.d parses all options on start up and calling this function is not necessary.
	It is recommended to use 
	Currently does nothing - Vibe will parse arguments
	automatically on startup. Call $(D finalizeCommandLineArgs) from your
	$(D main()) if you use a custom one, to check for unrecognized options.
*/
deprecated void processCommandLineArgs(ref string[] args)
{
	args = g_args.dup;
}


/**
	Finds and reads an option from the configuration file or command line.
	
	Command line options take precedence over configuration file entries.

	Params:
		names = Option names. Separate multiple name variants with "|",
				as for $(D std.getopt).
		pvalue = Pointer to store the value. Unchanged if value was not found.

	Returns:
		$(D true) if the value was found, $(D false) otherwise.
*/
bool getOption(T)(string names, T* pvalue, string help_text)
{
	// May happen due to http://d.puremagic.com/issues/show_bug.cgi?id=9881
	if (!g_args) init();

	OptionInfo info;
	info.names = names.split("|").sort!((a, b) => a.length < b.length)().array();
	info.hasValue = !is(T == bool);
	info.helpText = help_text;
	assert(!g_options.any!(o => o.names == info.names)(), "getOption() may only be called once per option name.");
	g_options ~= info;

	getopt(g_args, getoptConfig, names, pvalue);

	if (g_haveConfig) {
		foreach (name; info.names)
			if (auto pv = name in g_config) {
				*pvalue = pv.get!T;
				return true;
			}
	}

	return false;
}


/**
	Prints a help screen consisting of all options encountered in getOption calls.
*/
void printCommandLineHelp()
{
	enum dcolumn = 20;
	enum ncolumns = 80;

	logInfo("Usage: %s <options>\n", g_args[0]);
	foreach (opt; g_options) {
		string shortopt;
		string[] longopts;
		if (opt.names[0].length == 1 && !opt.hasValue) {
			shortopt = "-"~opt.names[0];
			longopts = opt.names[1 .. $];
		} else {
			shortopt = "  ";
			longopts = opt.names;
		}

		string optionString(string name)
		{
			if (name.length == 1) return "-"~name~(opt.hasValue ? " <value>" : "");
			else return "--"~name~(opt.hasValue ? "=<value>" : "");
		}

		auto optstr = format(" %s %s", shortopt, longopts.map!optionString().join(", "));
		if (optstr.length < dcolumn) optstr ~= replicate(" ", dcolumn - optstr.length);

		auto indent = replicate(" ", dcolumn+1);
		auto desc = wrap(opt.helpText, ncolumns - dcolumn - 2, optstr.length > dcolumn ? indent : "", indent).stripRight();

		if (optstr.length > dcolumn)
			logInfo("%s\n%s", optstr, desc);
		else logInfo("%s %s", optstr, desc);
	}
}


/**
	Checks for unrecognized command line options and display a help screen.

	This function is called automatically from vibe.appmain to check for
	correct command line usage. It will print a help screen in case of
	unrecognized options.

	Returns:
		If "--help" was passed, the function returns false. In all other
		cases either true is returned or an exception is thrown.
*/
bool finalizeCommandLineOptions()
{
	if (g_args.length > 1) {
		logError("Unrecognized command line option: %s\n", g_args[1]);
		printCommandLineHelp();
		throw new Exception("Unrecognized command line option.");
	}

	if (g_help) {
		printCommandLineHelp();
		return false;
	}

	return true;
}


private struct OptionInfo {
	string[] names;
	bool hasValue;
	string helpText;
}

private {
	__gshared string[] g_args;
	__gshared bool g_haveConfig;
	__gshared Json g_config;
	__gshared OptionInfo[] g_options;
	__gshared bool g_help;
}

private string[] getConfigPaths()
{
	string[] result = [""];
	import std.process : environment;
	version (Windows)
		result ~= environment.get("USERPROFILE");
	else
		result ~= [environment.get("HOME"), "/etc/vibe/"];
	return result;
}

// this is invoked by the first getOption call (at least vibe.core will porform one)
private void init()
{
	g_args = Runtime.args.dup;

	// TODO: let different config files override induvidual fields
	auto searchpaths = getConfigPaths();
	foreach (spath; searchpaths) {
		auto cpath = buildPath(spath, configName);
		if (cpath.exists) {
			scope(failure) logError("Failed to parse config file %s.", cpath);
			auto text = cpath.readText();
			g_config = text.parseJson();
			g_haveConfig = true;
			break;
		}
	}

	if (!g_haveConfig)
		logDiagnostic("No config file found in %s", searchpaths);

	getOption("h|help", &g_help, "Prints this help screen.");
}

private enum configName = "vibe.conf";

private template ValueTuple(T...) { alias T ValueTuple; }

private alias getoptConfig = ValueTuple!(std.getopt.config.passThrough, std.getopt.config.bundling);
