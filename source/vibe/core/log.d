/**
	Central logging facility for vibe.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.log;

import vibe.core.concurrency;
import vibe.core.sync;

import std.array;
import std.datetime;
import std.format;
import std.stdio;
import core.thread;

/// Sets the minimum log level to be printed.
void setLogLevel(LogLevel level) nothrow
{
	ss_minLevel = level;
}

/// Disables output of thread/task ids with each log message
void setPlainLogging(bool enable)
{
	ss_stdoutLogger.lock().format = enable ? FileLogger.Format.plain : FileLogger.Format.thread;
}

/// Sets a log file for disk logging
void setLogFile(string filename, LogLevel min_level = LogLevel.error)
{
	auto logger = new shared(FileLogger)(filename);
	logger.lock().minLevel = min_level;
	ss_loggers ~= logger;
}

void registerLogger(shared(Logger) logger)
{
	ss_loggers ~= logger;
}

/**
	Logs a message.

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string

	Examples:
	---
	logInfo("Hello, World!");
	logWarn("This may not be %s.", "good");
	log!(LogLevel.info)("This is a %s.", "test");
	---
*/
void log(LogLevel level, /*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args)
nothrow {
	if (level < ss_minLevel || ss_loggers.empty) return;
	try {
		auto app = appender!string();
		formattedWrite(app, fmt, args);
		rawLog(/*mod, func,*/ file, line, level, app.data);
	} catch(Exception) assert(false);
}
/// ditto
void logVerbose4(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.verbose4/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logVerbose3(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.verbose3/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logVerbose2(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.verbose2/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logVerbose1(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.verbose1/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logTrace(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.trace/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logDebug(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.debug_/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logInfo(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.info/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logWarn(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.warn/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logError(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.error/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logCritical(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, T...)(string fmt, auto ref T args) nothrow { log!(LogLevel.critical/*, mod, func*/, file, line)(fmt, args); }


void rawLog(/*string mod, string func,*/ string file, int line, LogLevel level, string text)
nothrow {
	static uint makeid(void* ptr) { return (cast(ulong)ptr & 0xFFFFFFFF) ^ (cast(ulong)ptr >> 32); }

	LogMessage msg;
	try {
		msg.time = Clock.currTime(UTC());
		//msg.mod = mod;
		//msg.func = func;
		msg.file = file;
		msg.line = line;
		msg.level = level;
		msg.thread = Thread.getThis();
		msg.threadID = makeid(cast(void*)msg.thread);
		msg.fiber = Fiber.getThis();
		msg.fiberID = makeid(cast(void*)msg.fiber);
		msg.text = text;

		foreach (l; ss_loggers) l.lock().log(msg);
	} catch(Exception) assert(false);
}

/// Specifies the log level for a particular log message.
enum LogLevel {
	verbose4,
	verbose3,
	verbose2,
	verbose1,
	trace = verbose2,
	debug_ = verbose1,
	info,
	warn,
	error,
	fatal,
	none,

	/// deprecated
	Trace = trace,
	/// deprecated
	Debug = debug_,
	/// deprecated
	Info = info,
	/// deprecated
	Warn = warn,
	/// deprecated
	Error = error,
	/// deprecated
	Fatal = fatal,
	/// deprecated
	None = none
}

struct LogMessage {
	string mod;
	string func;
	string file;
	int line;
	LogLevel level;
	Thread thread;
	uint threadID;
	Fiber fiber;
	uint fiberID;
	SysTime time;
	string text;
}

class Logger {
	abstract void log(in ref LogMessage message);
}

class FileLogger : Logger {
	enum Format {
		plain,
		thread,
		threadTime
	}

	private {
		File m_infoFile;
		File m_diagFile;
	}

	Format format = Format.thread;
	LogLevel minLevel = LogLevel.min;

	this(File info_file, File diag_file)
	{
		m_infoFile = info_file;
		m_diagFile = diag_file;
	}

	this(string filename)
	{
		m_infoFile = File(filename, "ab");
		m_diagFile = m_infoFile;
	}

	override void log(in ref LogMessage msg)
	{
		if (msg.level < this.minLevel) return;

		string pref;
		File file;
		final switch (msg.level) {
			case LogLevel.verbose4: pref = "v4"; file = m_diagFile; break;
			case LogLevel.verbose3: pref = "v3"; file = m_diagFile; break;
			case LogLevel.trace: pref = "trc"; file = m_diagFile; break;
			case LogLevel.debug_: pref = "dbg"; file = m_diagFile; break;
			case LogLevel.info: pref = "INF"; file = m_infoFile; break;
			case LogLevel.warn: pref = "WRN"; file = m_diagFile; break;
			case LogLevel.error: pref = "ERR"; file = m_diagFile; break;
			case LogLevel.fatal: pref = "FATAL"; file = m_diagFile; break;
			case LogLevel.none: assert(false);
		}

		final switch (this.format) {
			case Format.plain: file.write(msg.text); break;
			case Format.thread: file.writefln("[%08X:%08X %s] %s", msg.threadID, msg.fiberID, pref, msg.text); break;
			case Format.threadTime:
				auto tm = msg.time;
				file.writefln("[%08X:%08X %d.%02d.%02d %02d:%02d:%02d.%03d %s] %s",
					msg.threadID, msg.fiberID,
					tm.year, tm.month, tm.day, tm.hour, tm.minute, tm.second, tm.fracSec.msecs,
					pref, msg.text);
				break;
		}
		file.flush();
	}
}


private {
	shared LogLevel ss_minLevel = LogLevel.info;
	shared Logger[] ss_loggers;
	shared(FileLogger) ss_stdoutLogger;
	shared(FileLogger) ss_fileLogger;
}

shared static this()
{
	ss_stdoutLogger = new shared(FileLogger)(stdout, stderr);
	ss_loggers ~= ss_stdoutLogger;
}