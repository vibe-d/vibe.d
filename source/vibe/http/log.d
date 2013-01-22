/**
	A HTTP 1.1/1.0 server implementation.

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Jan Krüger
*/
module vibe.http.log;

import vibe.core.file;
import vibe.core.log;
import vibe.http.server;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;


class HttpConsoleLogger : HttpLogger {
	this(HttpServerSettings settings, string format)
	{
		super(settings, format);
	}

	protected override void writeLine(string ln)
	{
		logInfo("%s", ln);
	}
}

class HttpFileLogger : HttpLogger {
	private {
		FileStream m_stream;
	}

	this(HttpServerSettings settings, string format, string filename)
	{
		m_stream = openFile(filename, FileMode.Append);
		super(settings, format);
	}

	override void close()
	{
		m_stream.close();
		m_stream = null;
	}

	protected override void writeLine(string ln)
	{
		assert(m_stream);
		m_stream.write(ln, false);
		m_stream.write("\n");
	}
}

class HttpLogger {
	private {
		string m_format;
		HttpServerSettings m_settings;
	}

	this(HttpServerSettings settings, string format)
	{
		m_format = format;
		m_settings = settings;
	}

	void close() {}

	void log(HttpServerRequest req, HttpServerResponse res)
	{
		auto ln = formatApacheLog(m_format, req, res, m_settings);
		writeLine(ln);
	}

	protected abstract void writeLine(string ln);
}

string formatApacheLog(string format, HttpServerRequest req, HttpServerResponse res, HttpServerSettings settings)
{
	enum State {Init, Directive, Status, Key, Command}

	State state = State.Init;
	bool conditional = false;
	bool negate = false;
	bool match = false;
	string statusStr;
	string key = "";
	auto ln = appender!string();
	ln.reserve(500);
	while( format.length > 0 ) {
		final switch(state) {
			case State.Init:
				auto idx = format.countUntil('%');
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
				auto idx = format.countUntil('}');
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
						ln.put( res.bytesWritten == 0 ? "-" : to!string(res.bytesWritten) );
						break;
					case 'C': //Cookie content {cookie}
						enforce(key, "cookie name missing");
						if( auto pv = key in req.cookies ) ln.put(*pv);
						else ln.put("-");
						break;
					case 'D': //The time taken to serve the request
						auto d = res.timeFinalized - req.timeCreated;
						ln.put(to!string(d.total!"msecs"()));
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
						enforce(key, "header name missing");
						if( auto pv = key in req.headers ) ln.put(*pv);
						else ln.put("-");
						break;
					case 'm': //Request method
						ln.put(httpMethodString(req.method));
						break;
					case 'o': //Response header {header}						
						enforce(key, "header name missing");
						if( auto pv = key in res.headers ) ln.put(*pv);
						else ln.put("-");
						break;
					case 'p': //port
						ln.put(to!string(settings.port));
						break;
					//case 'P': //Process ID
					case 'q': //query string (with prepending '?')
						ln.put("?" ~ req.queryString);
						break;
					case 'r': //First line of Request
						ln.put(httpMethodString(req.method) ~ " " ~ req.requestUrl ~ " " ~ getHttpVersionString(req.httpVersion));
						break;
					case 's': //Status
						ln.put(to!string(res.statusCode));
						break;
					case 't': //Time the request was received {format}
						ln.put(req.timeCreated.toSimpleString());
						break;
					case 'T': //Time taken to server the request in seconds
						auto d = res.timeFinalized - req.timeCreated;
						ln.put(to!string(d.total!"seconds"));
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
	return ln.data;
}
