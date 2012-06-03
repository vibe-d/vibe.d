/**
	Central logging facility for vibe.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.log;

import vibe.core.file;

import std.array;
import std.format;
import std.stdio;
import core.thread;

private {
	shared LogLevel s_minLevel = LogLevel.Info;
	shared LogLevel s_logFileLevel;
	FileStream s_logFile;
}

/// Sets the minimum log level to be printed.
void setLogLevel(LogLevel level) nothrow
{
	s_minLevel = level;
}

/// Sets a log file for disk logging
void setLogFile(string filename, LogLevel min_level = LogLevel.Error)
{
	s_logFile = openFile(filename, FileMode.Append);
	s_logFileLevel = min_level;
}

/**
	Logs a message.

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
*/
void logTrace(T...)(string fmt, T args) nothrow { log(LogLevel.Trace, fmt, args); }
/// ditto
void logDebug(T...)(string fmt, T args) nothrow { log(LogLevel.Debug, fmt, args); }
/// ditto
void logInfo(T...)(string fmt, T args) nothrow { log(LogLevel.Info, fmt, args); }
/// ditto
void logWarn(T...)(string fmt, T args) nothrow { log(LogLevel.Warn, fmt, args); }
/// ditto
void logError(T...)(string fmt, T args) nothrow { log(LogLevel.Error, fmt, args); }

/// ditto
void log(T...)(LogLevel level, string fmt, T args)
nothrow {
	if( level < s_minLevel && (level < s_logFileLevel || !s_logFile) ) return;
	string pref;
	final switch( level ){
		case LogLevel.Trace: pref = "trc"; break;
		case LogLevel.Debug: pref = "dbg"; break;
		case LogLevel.Info: pref = "INF"; break;
		case LogLevel.Warn: pref = "WRN"; break;
		case LogLevel.Error: pref = "ERR"; break;
		case LogLevel.Fatal: pref = "FATAL"; break;
	}

	try {
		auto txt = appender!string();
		formattedWrite(txt, "[%08X:%08X %s] ", cast(void*)Thread.getThis(), cast(size_t)cast(void*)Fiber.getThis(), pref);
		formattedWrite(txt, fmt, args);

		if( level >= s_minLevel ){
			writeln(txt.data());
			stdout.flush();
		}

		if( level >= s_logFileLevel && s_logFile ){
			s_logFile.write(txt.data(), false);
			s_logFile.write("\n");
		}
	} catch( Exception e ){
		// this is bad but what can we do..
	}
}

/// Specifies the log level for a particular log message.
enum LogLevel {
	Trace,
	Debug,
	Info,
	Warn,
	Error,
	Fatal
}

