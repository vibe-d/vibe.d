/**
	A HTTP 1.1/1.0 server implementation.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.log;

import vibe.core.file;
import vibe.core.log;
import vibe.core.sync : InterruptibleTaskMutex, performLocked;
import vibe.http.server;
import vibe.utils.array : FixedAppender;

import std.array;
import std.conv;
import std.exception;
import std.string;


class HTTPLogger {
	@safe:

	private {
		string m_format;
		const(HTTPServerSettings) m_settings;
		InterruptibleTaskMutex m_mutex;
		Appender!(char[]) m_lineAppender;
	}

	this(in HTTPServerSettings settings, string format)
	{
		m_format = format;
		m_settings = settings;
		m_mutex = new InterruptibleTaskMutex;
		m_lineAppender.reserve(2048);
	}

	void close() {}

	final void log(scope HTTPServerRequest req, scope HTTPServerResponse res)
	{
		m_mutex.performLocked!(() @safe {
			m_lineAppender.clear();
			formatApacheLog(m_lineAppender, m_format, req, res, m_settings);
			writeLine(m_lineAppender.data);
		});
	}

	protected abstract void writeLine(const(char)[] ln);
}


final class HTTPConsoleLogger : HTTPLogger {
@safe:

	this(HTTPServerSettings settings, string format)
	{
		super(settings, format);
	}

	protected override void writeLine(const(char)[] ln)
	{
		logInfo("%s", ln);
	}
}


final class HTTPFileLogger : HTTPLogger {
@safe:

	private {
		FileStream m_stream;
	}

	this(HTTPServerSettings settings, string format, string filename)
	{
		m_stream = openFile(filename, FileMode.append);
		super(settings, format);
	}

	override void close()
	{
		m_stream.close();
		m_stream = FileStream.init;
	}

	protected override void writeLine(const(char)[] ln)
	{
		assert(!!m_stream);
		m_stream.write(ln);
		m_stream.write("\n");
		m_stream.flush();
	}
}

void formatApacheLog(R)(ref R ln, string format, scope HTTPServerRequest req, scope HTTPServerResponse res, in HTTPServerSettings settings)
@safe {
	import std.format : formattedWrite;
	enum State {Init, Directive, Status, Key, Command}

	State state = State.Init;
	bool conditional = false;
	bool negate = false;
	bool match = false;
	string statusStr;
	string key = "";
	while( format.length > 0 ) {
		final switch(state) {
			case State.Init:
				auto idx = format.indexOf('%');
				if( idx < 0 ) {
					ln.put( format );
					format = "";
				} else {
					ln.put( format[0 .. idx] );
					format = format[idx+1 .. $];

					state = State.Directive;
				}
				break;
			case State.Directive:
				if( format[0] == '!' ) {
					conditional = true;
					negate = true;
					format = format[1 .. $];
					state = State.Status;
				} else if( format[0] == '%' ) {
					ln.put("%");
					format = format[1 .. $];
					state = State.Init;
				} else if( format[0] == '{' ) {
					format = format[1 .. $];
					state = State.Key;
				} else if( format[0] >= '0' && format[0] <= '9' ) {
					conditional = true;
					state = State.Status;
				} else {
					state = State.Command;
				}
				break;
			case State.Status:
				if( format[0] >= '0' && format[0] <= '9' ) {
					statusStr ~= format[0];
					format = format[1 .. $];
				} else if( format[0] == ',' ) {
					statusStr = "";
					format = format[1 .. $];
				} else if( format[0] == '{' ) {
					format = format[1 .. $];
					state = State.Key;
				} else {
					state = State.Command;
				}
				if (statusStr.length == 3 && !match) {
					auto status = parse!int(statusStr);
					match = status == res.statusCode;
				}
				break;
			case State.Key:
				auto idx = format.indexOf('}');
				enforce(idx > -1, "Missing '}'");
				key = format[0 .. idx];
				format = format[idx+1 .. $];
				state = State.Command;
				break;
			case State.Command:
				if( conditional && negate == match ) {
					ln.put('-');
					format = format[1 .. $];
					state = State.Init;
					break;
				}
				switch(format[0]) {
					case 'a': //Remote IP-address
						ln.put(req.peer);
						break;
					//TODO case 'A': //Local IP-address
					//case 'B': //Size of Response in bytes, excluding headers
					case 'b': //same as 'B' but a '-' is written if no bytes where sent
						if (!res.bytesWritten) ln.put('-');
						else formattedWrite(() @trusted { return &ln; } (), "%s", res.bytesWritten);
						break;
					case 'C': //Cookie content {cookie}
						import std.algorithm : joiner;
						enforce(key != "", "cookie name missing");
						auto values = req.cookies.getAll(key);
						if (values.length) ln.formattedWrite("%s", values.joiner(";"));
						else ln.put("-");
						break;
					case 'D': //The time taken to serve the request
						auto d = res.timeFinalized - req.timeCreated;
						formattedWrite(() @trusted { return &ln; } (), "%s", d.total!"msecs"());
						break;
					//case 'e': //Environment variable {variable}
					//case 'f': //Filename
					case 'h': //Remote host
						ln.put(req.peer);
						break;
					case 'H': //The request protocol
						ln.put("HTTP");
						break;
					case 'i': //Request header {header}
						enforce(key != "", "header name missing");
						if (auto pv = key in req.headers) ln.put(*pv);
						else ln.put("-");
						break;
					case 'm': //Request method
						ln.put(httpMethodString(req.method));
						break;
					case 'o': //Response header {header}
						enforce(key != "", "header name missing");
						if( auto pv = key in res.headers ) ln.put(*pv);
						else ln.put("-");
						break;
					case 'p': //port
						formattedWrite(() @trusted { return &ln; } (), "%s", settings.port);
						break;
					//case 'P': //Process ID
					case 'q': //query string (with prepending '?')
						ln.put("?");
						ln.put(req.queryString);
						break;
					case 'r': //First line of Request
						ln.put(httpMethodString(req.method));
						ln.put(' ');
						ln.put(req.requestURL);
						ln.put(' ');
						ln.put(getHTTPVersionString(req.httpVersion));
						break;
					case 's': //Status
						formattedWrite(() @trusted { return &ln; } (), "%s", res.statusCode);
						break;
					case 't': //Time the request was received {format}
						ln.put(req.timeCreated.toSimpleString());
						break;
					case 'T': //Time taken to server the request in seconds
						auto d = res.timeFinalized - req.timeCreated;
						formattedWrite(() @trusted { return &ln; } (), "%s", d.total!"seconds");
						break;
					case 'u': //Remote user
						ln.put(req.username.length ? req.username : "-");
						break;
					case 'U': //The URL path without query string
						ln.put(req.path);
						break;
					case 'v': //Server name
						ln.put(req.host.length ? req.host : "-");
						break;
					default:
						throw new Exception("Unknown directive '" ~ format[0] ~ "' in log format string");
				}
				state = State.Init;
				format = format[1 .. $];
				break;
		}
	}
}
