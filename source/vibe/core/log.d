/**
	Central logging facility for vibe.

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.log;

import vibe.core.args;
import vibe.core.concurrency;
import vibe.core.sync;

import std.algorithm;
import std.array;
import std.datetime;
import std.format;
import std.stdio;
import core.atomic;
import core.thread;

import std.traits : isSomeString;

/**
	Sets the minimum log level to be printed using the default console logger.

	This level applies to the default stdout/stderr logger only.
*/
void setLogLevel(LogLevel level)
nothrow @safe {
	assert(ss_stdoutLogger !is null, "Console logging disabled due to missing console.");
	ss_stdoutLogger.lock().minLevel = level;
}


/**
	Deprecated. Enables/disables output of thread/task ids with each log message.

	By default, only the log message is displayed (enable=true).

	Please use setLogFormat with FileLogger.Format.plain or FileLogger.Format.thread instead.
*/
deprecated("Use setLogFormat instead.")
void setPlainLogging(bool enable)
nothrow @safe {
	assert(ss_stdoutLogger !is null, "Console logging disabled du to missing console.");
	ss_stdoutLogger.lock().format = enable ? FileLogger.Format.plain : FileLogger.Format.thread;
}

/**
	Sets the log format used for the default console logger.

	This level applies to the default stdout/stderr logger only.
*/
void setLogFormat(FileLogger.Format fmt)
nothrow @safe {
	assert(ss_stdoutLogger !is null, "Console logging disabled du to missing console.");
	ss_stdoutLogger.lock().format = fmt;
}


/**
	Sets a log file for disk file logging.

	Multiple calls to this function will register multiple log
	files for output.
*/
void setLogFile(string filename, LogLevel min_level = LogLevel.error)
{
	auto logger = cast(shared)new FileLogger(filename);
	{
		auto l = logger.lock();
		l.minLevel = min_level;
		l.format = FileLogger.Format.threadTime;
	}
	registerLogger(logger);
}


/**
	Registers a new logger instance.

	The specified Logger will receive all log messages in its Logger.log
	method after it has been registered.

	Examples:
	---
	auto logger = cast(shared)new HTMLLogger("log.html");
	logger.lock().format = FileLogger.Format.threadTime;
	registerLogger(logger);
	---

	See_Also: deregisterLogger
*/
void registerLogger(shared(Logger) logger)
nothrow {
	ss_loggers ~= logger;
}


/**
	Deregisters an active logger instance.

	See_Also: registerLogger
*/
void deregisterLogger(shared(Logger) logger)
nothrow {
	for (size_t i = 0; i < ss_loggers.length; ) {
		if (ss_loggers[i] !is logger) i++;
		else ss_loggers = ss_loggers[0 .. i] ~ ss_loggers[i+1 .. $];
	}
}


/**
	Logs a message.

	Params:
		level = The log level for the logged message
		fmt = See http://dlang.org/phobos/std_format.html#format-string
		args = Any input values needed for formatting
*/
void log(LogLevel level, /*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args)
	nothrow @safe if (isSomeString!S)
{
	static assert(level != LogLevel.none);
	try {
		foreach (l; getLoggers())
			if (l.minLevel <= level) { // WARNING: TYPE SYSTEM HOLE: accessing field of shared class!
				auto app = appender!string();
				() @trusted { formattedWrite(app, fmt, args); }(); // not @safe as of 2.065
				rawLog(/*mod, func,*/ file, line, level, app.data);
				break;
			}
	} catch(Exception e) debug assert(false, e.msg);
}
/// ditto
void logTrace(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow @safe { log!(LogLevel.trace/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logDebugV(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow @safe { log!(LogLevel.debugV/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logDebug(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow @safe { log!(LogLevel.debug_/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logDiagnostic(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow @safe { log!(LogLevel.diagnostic/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logInfo(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow @safe { log!(LogLevel.info/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logWarn(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow @safe { log!(LogLevel.warn/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logError(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow @safe { log!(LogLevel.error/*, mod, func*/, file, line)(fmt, args); }
/// ditto
void logCritical(/*string mod = __MODULE__, string func = __FUNCTION__,*/ string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow @safe { log!(LogLevel.critical/*, mod, func*/, file, line)(fmt, args); }
/// ditto 
void logFatal(string file = __FILE__, int line = __LINE__, S, T...)(S fmt, lazy T args) nothrow { log!(LogLevel.fatal, file, line)(fmt, args); }

///
@safe unittest {
	logInfo("Hello, World!");
	logWarn("This may not be %s.", "good");
	log!(LogLevel.info)("This is a %s.", "test");
}

/// Specifies the log level for a particular log message.
enum LogLevel {
	trace,      /// Developer information for locating events when no useful stack traces are available
	debugV,     /// Developer information useful for algorithm debugging - for verbose output
	debug_,     /// Developer information useful for algorithm debugging
	diagnostic, /// Extended user information (e.g. for more detailed error information)
	info,       /// Informational message for normal user education
	warn,       /// Unexpected condition that count indicate an error but has no direct consequences
	error,      /// Normal error that is handled gracefully
	critical,   /// Error that severely influences the execution of the application
	fatal,      /// Error that forces the application to terminate
	none,       /// Special value used to indicate no logging when set as the minimum log level

	verbose1 = diagnostic, /// Alias for diagnostic messages
	verbose2 = debug_,     /// Alias for debug messages
	verbose3 = debugV,     /// Alias for verbose debug messages
	verbose4 = trace,      /// Alias for trace messages
}

/// Represents a single logged line
struct LogLine {
	string mod;
	string func;
	string file;
	int line;
	LogLevel level;
	Thread thread;
	string threadName;
	uint threadID;
	Fiber fiber;
	uint fiberID;
	SysTime time;
	string text;
}

/// Abstract base class for all loggers
class Logger {
	LogLevel minLevel = LogLevel.min;

	final bool acceptsLevel(LogLevel value) nothrow pure @safe { return value >= this.minLevel; }

	abstract void log(ref LogLine message) @safe;
}


/**
	Plain-text based logger for logging to regular files or stdout/stderr
*/
final class FileLogger : Logger {
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

	override void log(ref LogLine msg)
		@trusted // FILE isn't @safe (as of DMD 2.065)
	{
		string pref;
		File file;
		final switch (msg.level) {
			case LogLevel.trace: pref = "trc"; file = m_diagFile; break;
			case LogLevel.debugV: pref = "dbv"; file = m_diagFile; break;
			case LogLevel.debug_: pref = "dbg"; file = m_diagFile; break;
			case LogLevel.diagnostic: pref = "dia"; file = m_diagFile; break;
			case LogLevel.info: pref = "INF"; file = m_infoFile; break;
			case LogLevel.warn: pref = "WRN"; file = m_diagFile; break;
			case LogLevel.error: pref = "ERR"; file = m_diagFile; break;
			case LogLevel.critical: pref = "CRITICAL"; file = m_diagFile; break;
			case LogLevel.fatal: pref = "FATAL"; file = m_diagFile; break;
			case LogLevel.none: assert(false);
		}

		auto fmt = this.format;
		// force informational output to be in plain form
		if (file !is m_diagFile) fmt = Format.plain;

		final switch (fmt) {
			case Format.plain: file.writeln(msg.text); break;
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

import vibe.textfilter.html; // http://d.puremagic.com/issues/show_bug.cgi?id=7016

/**	
	Logger implementation for logging to an HTML file with dynamic filtering support.
*/
final class HTMLLogger : Logger {
	private {
		File m_logFile;
	}

	this(string filename = "log.html")
	{
		m_logFile = File(filename, "wt");
		writeHeader();
	}

	~this()
	{
		//version(FinalizerDebug) writeln("HtmlLogWritet.~this");
		writeFooter();
		m_logFile.close();
		//version(FinalizerDebug) writeln("HtmlLogWritet.~this out");
	}

	@property void minLogLevel(LogLevel value) pure nothrow @safe { this.minLevel = value; }

	override void log(ref LogLine msg)
		@trusted // FILE isn't @safe (as of DMD 2.065)
	{
		if( !m_logFile.isOpen ) return;

		final switch (msg.level) {
			case LogLevel.none: assert(false);
			case LogLevel.trace: m_logFile.write(`<div class="trace">`); break;
			case LogLevel.debugV: m_logFile.write(`<div class="debugv">`); break;
			case LogLevel.debug_: m_logFile.write(`<div class="debug">`); break;
			case LogLevel.diagnostic: m_logFile.write(`<div class="diagnostic">`); break;
			case LogLevel.info: m_logFile.write(`<div class="info">`); break;
			case LogLevel.warn: m_logFile.write(`<div class="warn">`); break;
			case LogLevel.error: m_logFile.write(`<div class="error">`); break;
			case LogLevel.critical: m_logFile.write(`<div class="critical">`); break;
			case LogLevel.fatal: m_logFile.write(`<div class="fatal">`); break;
		}
		m_logFile.writef(`<div class="timeStamp">%s</div>`, msg.time.toISOExtString());
		if (msg.thread)
			m_logFile.writef(`<div class="threadName">%s</div>`, msg.thread.name);
		m_logFile.write(`<div class="message">`);
		{
			auto dst = m_logFile.lockingTextWriter();
			auto txt = msg.text;
			while (!txt.empty && (txt.front == ' ' || txt.front == '\t')) {
				foreach (i; 0 .. txt.front == ' ' ? 1 : 4)
					dst.put("&nbsp;");
				txt.popFront();
			}
			filterHTMLEscape(dst, txt);
		}
		m_logFile.write(`</div>`);
		m_logFile.writeln(`</div>`);
		m_logFile.flush();
	}

	private void writeHeader(){
		if( !m_logFile.isOpen ) return;

		m_logFile.writeln(
`<html>
<head>
	<title>HTML Log</title>
	<style content="text/css">
		.trace { position: relative; color: #E0E0E0; font-size: 9pt; }
		.debugv { position: relative; color: #E0E0E0; font-size: 9pt; }
		.debug { position: relative; color: #808080; }
		.diagnostic { position: relative; color: #808080; }
		.info { position: relative; color: black; }
		.warn { position: relative; color: #E08000; }
		.error { position: relative; color: red; }
		.critical { position: relative; color: red; background-color: black; }
		.fatal { position: relative; color: red; background-color: black; }

		.log { margin-left: 10pt; }
		.code {
			font-family: "Courier New";
			background-color: #F0F0F0;
			border: 1px solid gray;
			margin-bottom: 10pt;
			margin-left: 30pt;
			margin-right: 10pt;
			padding-left: 0pt;
		}

		div.timeStamp {
			position: absolute;
			width: 150pt;
		}
		div.threadName {
			position: absolute;
			top: 0pt;
			left: 150pt;
			width: 100pt;
		}
		div.message {
			position: relative;
			top: 0pt;
			left: 250pt;
		}
		body {
			font-family: Tahoma, Arial, sans-serif;
			font-size: 10pt;
		}
	</style>
	<script language="JavaScript">
		function enableStyle(i){
			var style = document.styleSheets[0].cssRules[i].style;
			style.display = "block";
		}

		function disableStyle(i){
			var style = document.styleSheets[0].cssRules[i].style;
			style.display = "none";
		}

		function updateLevels(){
			var sel = document.getElementById("Level");
			var level = sel.value;
			for( i = 0; i < level; i++ ) disableStyle(i);
			for( i = level; i < 5; i++ ) enableStyle(i);
		}
	</script>
</head>
<body style="padding: 0px; margin: 0px;" onLoad="updateLevels(); updateCode();">
	<div style="position: fixed; z-index: 100; padding: 4pt; width:100%; background-color: lightgray; border-bottom: 1px solid black;">
		<form style="margin: 0px;">
			Minimum Log Level:
			<select id="Level" onChange="updateLevels()">
				<option value="0">Trace</option>
				<option value="1">Verbose</option>
				<option value="2">Debug</option>
				<option value="3">Diagnostic</option>
				<option value="4">Info</option>
				<option value="5">Warn</option>
				<option value="6">Error</option>
				<option value="7">Critical</option>
				<option value="8">Fatal</option>
			</select>
		</form>
	</div>
	<div style="height: 30pt;"></div>
	<div class="log">`);
		m_logFile.flush();
	}

	private void writeFooter(){
		if( !m_logFile.isOpen ) return;

		m_logFile.writeln(
`	</div>
</body>
</html>`);
		m_logFile.flush();
	}
}

import std.conv;
/**
	A logger that logs in syslog format according to RFC 5424.

	Messages can be logged to files (via file streams) or over the network (via
	TCP or SSL streams).

	Standards: Conforms to RFC 5424.
*/
final class SyslogLogger : Logger {
	import vibe.core.stream;
	private {
		string m_hostName;
		string m_appName;
		OutputStream m_ostream;
		Facility m_facility;
	}

	/// Facilities
	enum Facility {
		kern,        /// kernel messages
		user,        /// user-level messages
		mail,        /// mail system
		daemon,      /// system daemons
		auth,        /// security/authorization messages
		syslog,      /// messages generated internally by syslogd
		lpr,         /// line printer subsystem
		news,        /// network news subsystem
		uucp,        /// UUCP subsystem
		clockDaemon, /// clock daemon
		authpriv,    /// security/authorization messages
		ftp,         /// FTP daemon
		ntp,         /// NTP subsystem
		logAudit,    /// log audit
		logAlert,    /// log alert
		cron,        /// clock daemon
		local0,      /// local use 0
		local1,      /// local use 1
		local2,      /// local use 2
		local3,      /// local use 3
		local4,      /// local use 4
		local5,      /// local use 5
		local6,      /// local use 6
		local7,      /// local use 7
	}

	/// Severities
	private enum Severity {
		emergency,   /// system is unusable
		alert,       /// action must be taken immediately
		critical,    /// critical conditions
		error,       /// error conditions
		warning,     /// warning conditions
		notice,      /// normal but significant condition
		info,        /// informational messages
		debug_,      /// debug-level messages
	}

	/// syslog message format (version 1)
	/// see section 6 in RFC 5424
	private enum SYSLOG_MESSAGE_FORMAT_VERSION1 = "<%.3s>1 %s %.255s %.48s %.128s %.32s %s %s";
	///
	private enum NILVALUE = "-";
	///
	private enum BOM = x"EFBBBF";

	/**
		Construct a SyslogLogger.

		The log messages are sent to the given OutputStream stream using the given
		Facility facility.Optionally the appName and hostName can be set. The
		appName defaults to null. The hostName defaults to hostName().

		Note that the passed stream's write function must not use logging with
		a level for that this Logger's acceptsLevel returns true. Because this
		Logger uses the stream's write function when it logs and would hence
		log forevermore.
	*/
	this(OutputStream stream, Facility facility, string appName = null, string hostName = hostName())
	{
		m_hostName = hostName ? hostName : NILVALUE;
		m_appName = appName ? appName : NILVALUE;
		m_ostream = stream;
		m_facility = facility;
		this.minLevel = LogLevel.debug_;
	}

	/**
		Logs the given LogLine msg.

		It uses the msg's time, level, and text field.
	*/
	override void log(ref LogLine msg)
	@trusted { // OutputStream isn't @safe
		auto tm = msg.time;
		import core.time;
		// at most 6 digits for fractional seconds according to RFC
		tm.fracSec = FracSec.from!"usecs"(tm.fracSec.usecs);
		auto timestamp = tm.toISOExtString();

		Severity syslogSeverity;
		// map LogLevel to syslog's severity
		final switch(msg.level) {
			case LogLevel.none: assert(false);
			case LogLevel.trace: return;
			case LogLevel.debugV: return;
			case LogLevel.debug_: syslogSeverity = Severity.debug_; break;
			case LogLevel.diagnostic: syslogSeverity = Severity.info; break;
			case LogLevel.info: syslogSeverity = Severity.notice; break;
			case LogLevel.warn: syslogSeverity = Severity.warning; break;
			case LogLevel.error: syslogSeverity = Severity.error; break;
			case LogLevel.critical: syslogSeverity = Severity.critical; break;
			case LogLevel.fatal: syslogSeverity = Severity.alert; break;
		}

		assert(msg.level >= LogLevel.debug_);
		auto priVal = (m_facility * 8 + syslogSeverity).to!string();

		alias procId = NILVALUE;
		alias msgId = NILVALUE;
		alias structuredData = NILVALUE;

		auto text = msg.text;
		import std.string : format;
		m_ostream.write(SYSLOG_MESSAGE_FORMAT_VERSION1.format(
		              priVal, timestamp, m_hostName, BOM ~ m_appName, procId, msgId, structuredData, BOM ~ text) ~ "\n");
		m_ostream.flush();
	}

	unittest
	{
		import vibe.core.file;
		auto fstream = createTempFile();
		auto logger = new SyslogLogger(fstream, Facility.local1, "appname", null);
		LogLine msg;
		import std.datetime;
		import core.thread;
		msg.time = SysTime(DateTime(0, 1, 1, 0, 0, 0), FracSec.from!"usecs"(1));
		msg.text = "αβγ";

		msg.level = LogLevel.debug_;
		logger.log(msg);
		msg.level = LogLevel.diagnostic;
		logger.log(msg);
		msg.level = LogLevel.info;
		logger.log(msg);
		msg.level = LogLevel.warn;
		logger.log(msg);
		msg.level = LogLevel.error;
		logger.log(msg);
		msg.level = LogLevel.critical;
		logger.log(msg);
		msg.level = LogLevel.fatal;
		logger.log(msg);
		fstream.close();

		import std.file;
		import std.string;
		auto lines = splitLines(readText(fstream.path().toNativeString()), KeepTerminator.yes);
		assert(lines.length == 7);
		assert(lines[0] == "<143>1 0000-01-01T00:00:00.000001 - " ~ BOM ~ "appname - - - " ~ BOM ~ "αβγ\n");
		assert(lines[1] == "<142>1 0000-01-01T00:00:00.000001 - " ~ BOM ~ "appname - - - " ~ BOM ~ "αβγ\n");
		assert(lines[2] == "<141>1 0000-01-01T00:00:00.000001 - " ~ BOM ~ "appname - - - " ~ BOM ~ "αβγ\n");
		assert(lines[3] == "<140>1 0000-01-01T00:00:00.000001 - " ~ BOM ~ "appname - - - " ~ BOM ~ "αβγ\n");
		assert(lines[4] == "<139>1 0000-01-01T00:00:00.000001 - " ~ BOM ~ "appname - - - " ~ BOM ~ "αβγ\n");
		assert(lines[5] == "<138>1 0000-01-01T00:00:00.000001 - " ~ BOM ~ "appname - - - " ~ BOM ~ "αβγ\n");
		assert(lines[6] == "<137>1 0000-01-01T00:00:00.000001 - " ~ BOM ~ "appname - - - " ~ BOM ~ "αβγ\n");
	}
}

/// Returns: this host's host name.
///
/// If the host name cannot be determined the function returns null.
private string hostName()
{
	string hostName;

	version (Posix) {
		import core.sys.posix.sys.utsname;
		utsname name;
		if (uname(&name)) return hostName;
		hostName = name.nodename.to!string();

		import std.socket;
		auto ih = new InternetHost;
		if (!ih.getHostByName(hostName)) return hostName;
		hostName = ih.name;
	}
	// TODO: determine proper host name on windows

	return hostName;
}

private {
	__gshared shared(Logger)[] ss_loggers;
	shared(FileLogger) ss_stdoutLogger;
}

private shared(Logger)[] getLoggers() nothrow @trusted { return ss_loggers; }

private void rawLog(/*string mod, string func,*/ string file, int line, LogLevel level, string text)
nothrow @safe {
	static uint makeid(T)(T ptr) @trusted { return (cast(ulong)cast(void*)ptr & 0xFFFFFFFF) ^ (cast(ulong)cast(void*)ptr >> 32); }

	LogLine msg;
	try {
		() @trusted { msg.time = Clock.currTime(UTC()); }(); // not @safe as of 2.065
		//msg.mod = mod;
		//msg.func = func;
		msg.file = file;
		msg.line = line;
		msg.level = level;
		msg.thread = () @trusted { return Thread.getThis(); }(); // not @safe as of 2.065
		msg.threadID = makeid(msg.thread);
		msg.fiber = () @trusted { return Fiber.getThis(); }(); // not @safe as of 2.065
		msg.fiberID = makeid(msg.fiber);

		() @trusted { // splitter not @safe as of 2.065
			foreach (ln; text.splitter("\n")) {
				msg.text = ln;
				foreach (l; getLoggers()) {
					auto ll = l.lock();
					if (ll.acceptsLevel(msg.level))
						ll.log(msg);
				}
			}
		}();
	} catch (Exception e) {
		try {
			() @trusted { writefln("Error during logging: %s", e.toString()); }(); // not @safe as of 2.065
		} catch(Exception) {}
		assert(false, "Exception during logging: "~e.msg);
	}
}

package void initializeLogModule()
{
	version (Windows) {
		version (VibeWinrtDriver) enum disable_stdout = true;
		else {
			enum disable_stdout = false;
			if (!GetStdHandle(STD_OUTPUT_HANDLE) || !GetStdHandle(STD_ERROR_HANDLE)) return;
		}
	} else enum disable_stdout = false;

	static if (!disable_stdout) {
		ss_stdoutLogger = cast(shared)new FileLogger(stdout, stderr);
		{
			auto l = ss_stdoutLogger.lock();
			l.minLevel = LogLevel.info;
			l.format = FileLogger.Format.plain;
		}
		registerLogger(ss_stdoutLogger);

		bool[4] verbose;
		getOption("verbose|v"  , &verbose[0], "Enables diagnostic messages (verbosity level 1).");
		getOption("vverbose|vv", &verbose[1], "Enables debugging output (verbosity level 2).");
		getOption("vvv"        , &verbose[2], "Enables high frequency debugging output (verbosity level 3).");
		getOption("vvvv"       , &verbose[3], "Enables high frequency trace output (verbosity level 4).");

		foreach_reverse (i, v; verbose)
			if (v) {
				setLogFormat(FileLogger.Format.thread);
				setLogLevel(cast(LogLevel)(LogLevel.diagnostic - i));
				break;
			}
	}
}

version (Windows) {
	import core.sys.windows.windows;
	enum STD_OUTPUT_HANDLE = cast(DWORD)-11;
	enum STD_ERROR_HANDLE = cast(DWORD)-12;
	extern(System) HANDLE GetStdHandle(DWORD nStdHandle);
}
