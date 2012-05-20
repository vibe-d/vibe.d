/**
	Central logging facility for vibe.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.log;

import std.stdio;
import core.thread;

/// Specifies the log level for a particular log message.
enum LogLevel {
	Trace,
	Debug,
	Info,
	Warn,
	Error,
	Fatal
}

private LogLevel s_minLevel = LogLevel.Info;

/// Sets the minimum log level to be printed.
void setLogLevel(LogLevel level) nothrow
{
	s_minLevel = level;
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
	if( level < s_minLevel ) return;
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
		writef("[%08X:%08X %s] ", cast(void*)Thread.getThis(), cast(size_t)cast(void*)Fiber.getThis(), pref);
		writefln(fmt, args);
	} catch( Exception e ){}
}
