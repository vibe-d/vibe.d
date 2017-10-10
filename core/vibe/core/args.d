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

import std.algorithm : any, filter, map, sort, startsWith;
import std.array : array, join, replicate, split;
import std.exception;
import std.file;
import std.getopt;
import std.path : buildPath;
import std.string : format, stripRight, wrap;

import core.runtime;


/**
	Finds and reads an option from the configuration file or command line.

	Command line options take precedence over configuration file entries.

	Params:
		names = Option names. Separate multiple name variants with "|",
			as for $(D std.getopt).
		pvalue = Pointer to store the value. Unchanged if value was not found.
		help_text = Text to be displayed when the application is run with
			--help.

	Returns:
		$(D true) if the value was found, $(D false) otherwise.

	See_Also: readRequiredOption
*/
bool readOption(T)(string names, T* pvalue, string help_text)
{
	// May happen due to http://d.puremagic.com/issues/show_bug.cgi?id=9881
	if (g_args is null) init();

	OptionInfo info;
	info.names = names.split("|").sort!((a, b) => a.length < b.length)().array();
	info.hasValue = !is(T == bool);
	info.helpText = help_text;
	assert(!g_options.any!(o => o.names == info.names)(), "readOption() may only be called once per option name.");
	g_options ~= info;

	immutable olen = g_args.length;
	getopt(g_args, getoptConfig, names, pvalue);
	if (g_args.length < olen) return true;

	if (g_haveConfig) {
		foreach (name; info.names)
			if (auto pv = name in g_config) {
				*pvalue = deserializeJson!T(*pv);
				return true;
			}
	}

	return false;
}


/**
	The same as readOption, but throws an exception if the given option is missing.

	See_Also: readOption
*/
T readRequiredOption(T)(string names, string help_text)
{
	string formattedNames() {
		return names.split("|").map!(s => s.length == 1 ? "-" ~ s : "--" ~ s).join("/");
	}
	T ret;
	enforce(readOption(names, &ret, help_text) || g_help,
		format("Missing mandatory option %s.", formattedNames()));
	return ret;
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

		string[] lopts; foreach(lo; longopts) lopts ~= optionString(lo);
		auto optstr = format(" %s %s", shortopt, lopts.join(", "));
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

	This function is called automatically from `vibe.appmain` and from
	`vibe.core.core.runApplication` to check for correct command line usage.
	It will print a help screen in case of unrecognized options.

	Params:
		args_out = Optional parameter for storing any arguments not handled
				   by any readOption call. If this is left to null, an error
				   will be triggered whenever unhandled arguments exist.

	Returns:
		If "--help" was passed, the function returns false. In all other
		cases either true is returned or an exception is thrown.
*/
bool finalizeCommandLineOptions(string[]* args_out = null)
{
	scope(exit) g_args = null;

	if (args_out) {
		*args_out = g_args;
	} else if (g_args.length > 1) {
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

/**
	This functions allows the usage of a custom command line argument parser
	with vibe.d.

	$(OL
		$(LI build executable with version(VibeDisableCommandLineParsing))
		$(LI parse main function arguments with a custom command line parser)
		$(LI pass vibe.d arguments to `setCommandLineArgs`)
		$(LI use vibe.d command line parsing utilities)
	)

	Params:
		args = The arguments that should be handled by vibe.d
*/
void setCommandLineArgs(string[] args)
{
	g_args = args;
}

///
unittest {
	import std.format : format;
	string[] args = ["--foo", "10"];
	setCommandLineArgs(args);
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

// this is invoked by the first readOption call (at least vibe.core will perform one)
private void init()
{
	import vibe.utils.string : stripUTF8Bom;

	version (VibeDisableCommandLineParsing) {}
	else g_args = Runtime.args.filter!(arg => !arg.startsWith("--DRT-")).array;

	if (!g_args.length) g_args = ["dummy"];

	// TODO: let different config files override individual fields
	auto searchpaths = getConfigPaths();
	foreach (spath; searchpaths) {
		auto cpath = buildPath(spath, configName);
		if (cpath.exists) {
			scope(failure) logError("Failed to parse config file %s.", cpath);
			auto text = stripUTF8Bom(cpath.readText());
			g_config = text.parseJson();
			g_haveConfig = true;
			break;
		}
	}

	if (!g_haveConfig)
		logDiagnostic("No config file found in %s", searchpaths);

	readOption("h|help", &g_help, "Prints this help screen.");
}

private enum configName = "vibe.conf";

private template ValueTuple(T...) { alias ValueTuple = T; }

private alias getoptConfig = ValueTuple!(std.getopt.config.passThrough, std.getopt.config.bundling);
