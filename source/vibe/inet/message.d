/**
	Internet message handling according to RFC822/RFC5322

	Copyright: © 2012-2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.message;

import vibe.core.log;
import vibe.core.stream;
import vibe.stream.operations;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string;
import vibe.utils.dictionarylist;

import std.conv;
import std.datetime;
import std.exception;
import std.range;
import std.string;


/**
	Parses an internet header according to RFC5322 (with RFC822 compatibility).

	Params:
		input = Input stream from which the header is parsed
		dst = Destination map to write into
		max_line_length = The maximum allowed length of a single line
		alloc = Custom allocator to use for allocating strings
		rfc822_compatible = Flag indicating that duplicate fields should be merged using a comma
*/
void parseRFC5322Header(InputStream input, ref InetHeaderMap dst, size_t max_line_length = 1000, Allocator alloc = defaultAllocator(), bool rfc822_compatible = true)
{
	string hdr, hdrvalue;

	void addPreviousHeader() {
		if (!hdr.length) return;
		if (rfc822_compatible) {
			if (auto pv = hdr in dst) {
				*pv ~= "," ~ hdrvalue; // RFC822 legacy support
			} else {
				dst[hdr] = hdrvalue;
			}
		} else dst.addField(hdr, hdrvalue);
	}

	string ln;
	while ((ln = cast(string)input.readLine(max_line_length, "\r\n", alloc)).length > 0) {
		if (ln[0] != ' ' && ln[0] != '\t') {
			addPreviousHeader();

			auto colonpos = ln.indexOf(':');
			enforce(colonpos > 0 && colonpos < ln.length-1, "Header is missing ':'.");
			hdr = ln[0..colonpos].stripA();
			hdrvalue = ln[colonpos+1..$].stripA();
		} else {
			hdrvalue ~= " " ~ ln.stripA();
		}
	}
	addPreviousHeader();
}


private immutable monthStrings = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/**
	Writes an RFC-822/5322 date string to the given output range.
*/
void writeRFC822DateString(R)(ref R dst, SysTime time)
{
	static immutable dayStrings = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
	dst.put(dayStrings[time.dayOfWeek]);
	dst.put(", ");
	writeDecimal2(dst, time.day);
	dst.put(' ');
	dst.put(monthStrings[time.month-1]);
	dst.put(' ');
	writeDecimal(dst, time.year);
}

/**
	Writes an RFC-822 time string to the given output range.
*/
void writeRFC822TimeString(R)(ref R dst, SysTime time)
{
	writeDecimal2(dst, time.hour);
	dst.put(':');
	writeDecimal2(dst, time.minute);
	dst.put(':');
	writeDecimal2(dst, time.second);
	if( time.timezone == UTC() ) dst.put(" GMT");
	else {
		auto now = Clock.currStdTime();
		auto offset = cast(int)((time.timezone.utcToTZ(now) - now) / 600_000_000);
		dst.put(' ');
		dst.put(offset >= 0 ? '+' : '-');
		if( offset < 0 ) offset = -offset;
		writeDecimal2(dst, offset / 60);
		writeDecimal2(dst, offset % 60);
	}
}

/**
	Writes an RFC-822 date+time string to the given output range.
*/
void writeRFC822DateTimeString(R)(ref R dst, SysTime time)
{
	writeRFC822DateString(dst, time);
	dst.put(' ');
	writeRFC822TimeString(dst, time);
}

/**
	Returns the RFC-822 time string representation of the given time.
*/
string toRFC822TimeString(SysTime time)
{
	auto ret = new FixedAppender!(string, 14);
	writeRFC822TimeString(ret, time);
	return ret.data;
}

/**
	Returns the RFC-822/5322 date string representation of the given time.
*/
string toRFC822DateString(SysTime time)
{
	auto ret = new FixedAppender!(string, 16);
	writeRFC822DateString(ret, time);
	return ret.data;
}

/**
	Returns the RFC-822 date+time string representation of the given time.
*/
string toRFC822DateTimeString(SysTime time)
{
	auto ret = new FixedAppender!(string, 31);
	writeRFC822DateTimeString(ret, time);
	return ret.data;
}

/**
	Parses a date+time string according to RFC-822/5322.
*/
SysTime parseRFC822DateTimeString(string str)
{
	auto idx = str.indexOf(',');
	if( idx != -1 ) str = str[idx+1 .. $].stripLeft();

	str = str.stripLeft();
	auto day = parse!int(str);
	str = str.stripLeft();
	int month = -1;
	foreach( i, ms; monthStrings )
		if( str.startsWith(ms) ){
			month = cast(int)i+1;
			str = str[ms.length .. $];
			break;
		}
	enforce(month > 0);
	str = str.stripLeft();
	auto year = str.parse!int();
	str = str.stripLeft();

	int hour, minute, second, tzoffset = 0;
	hour = str.parse!int();
	enforce(str.startsWith(':'));
	str = str[1 .. $];
	minute = str.parse!int();
	enforce(str.startsWith(':'));
	str = str[1 .. $];
	second = str.parse!int();
	str = str.stripLeft();
	enforce(str.length > 0);
	if( str != "GMT" ){
		if( str.startsWith('+') ) str = str[1 .. $];
		tzoffset = str.parse!int();
	}

	auto dt = DateTime(year, month, day, hour, minute, second);
	if( tzoffset == 0 ) return SysTime(dt, UTC());
	else return SysTime(dt, new immutable SimpleTimeZone((tzoffset / 100) * 60 + tzoffset % 100));
}

unittest {
	import std.typecons;

	auto times = [
		tuple("Wed, 02 Oct 2002 08:00:00 GMT", SysTime(DateTime(2002, 10, 02, 8, 0, 0), UTC())),
		tuple("Wed, 02 Oct 2002 08:00:00 +0200", SysTime(DateTime(2002, 10, 02, 8, 0, 0), new immutable SimpleTimeZone(120))),
		tuple("Wed, 02 Oct 2002 08:00:00 -0130", SysTime(DateTime(2002, 10, 02, 8, 0, 0), new immutable SimpleTimeZone(-90)))
	];
	foreach (t; times) {
		auto st = parseRFC822DateTimeString(t[0]);
		auto ts = toRFC822DateTimeString(t[1]);
		assert(st == t[1], "Parse error: "~t[0]);
		assert(parseRFC822DateTimeString(ts) == t[1], "Stringify error: "~ts);
	}
}


/**
	Decodes a string in encoded-word form.

	See_Also: $(LINK http://tools.ietf.org/html/rfc2047#section-2)
*/
string decodeEncodedWords()(string encoded)
{
	import std.array;
	auto dst = appender!string();
	decodeEncodedWords(dst, encoded);
	return dst.data;
}
/// ditto
void decodeEncodedWords(R)(ref R dst, string encoded)
{
	import std.base64;
	import std.encoding;

	while(!encoded.empty){
		auto idx = encoded.indexOf("=?");
		if( idx >= 0 ){
			auto end = encoded.indexOf("?=");
			enforce(end > idx);
			dst.put(encoded[0 .. idx]);
			auto code = encoded[idx+2 .. end];
			encoded = encoded[end+2 .. $];

			idx = code.indexOf('?');
			auto cs = code[0 .. idx];
			auto enc = code[idx+1];
			auto data = code[idx+3 .. $];
			ubyte[] textenc;
			switch(enc){
				default: textenc = cast(ubyte[])data; break;
				case 'B': textenc = Base64.decode(data); break;
				case 'Q': textenc = QuotedPrintable.decode(data, true); break;
			}

			switch(cs){
				default: dst.put(sanitizeUTF8(textenc)); break;
				case "UTF-8": dst.put(cast(string)textenc); break;
				case "ISO-8859-15": // hack...
				case "ISO-8859-1":
					string tmp;
					transcode(cast(Latin1String)textenc, tmp);
					dst.put(tmp);
					break;
			}
		} else {
			dst.put(encoded);
			break;
		}
	}
}


/**
	Decodes a From/To header value as it appears in emails.
*/
void decodeEmailAddressHeader(string header, out string name, out string address)
{
	import std.utf;

	scope(failure) logDebug("emailbase %s", header);
	header = decodeEncodedWords(header);
	scope(failure) logDebug("emaildec %s", header);

	if( header[$-1] == '>' ){
		auto sidx = header.lastIndexOf('<');
		enforce(sidx >= 0);
		address = header[sidx+1 .. $-1];
		header = header[0 .. sidx].strip();

		if( header[0] == '"' ){
			name = header[1 .. $-1];
		} else {
			name = header.strip();
		}
	} else {
		name = header;
		address = header;
	}
	validate(name);
}


/**
	Decodes a message body according to the specified content transfer
	encoding ("Content-Transfer-Encoding" header).

	The result is returned as a UTF-8 string.
*/
string decodeMessage(in ubyte[] message_body, string content_transfer_encoding)
{
	import std.algorithm;
	import std.base64;

	const(ubyte)[] msg = message_body;
	switch (content_transfer_encoding) {
		default: break;
		case "quoted-printable": msg = QuotedPrintable.decode(cast(string)msg); break;
		case "base64":
			try msg = Base64.decode(msg);
			catch(Exception e){
				auto dst = appender!(ubyte[])();
				try {
					auto dec = Base64.decoder(filter!(ch => ch != '\r' && ch != '\n')(msg));
					while( !dec.empty ){
						dst.put(dec.front);
						dec.popFront();
					}
				} catch(Exception e){
					dst.put(cast(ubyte[])"\r\n-------\r\nDECODING ERROR: ");
					dst.put(cast(ubyte[])e.toString());
				}
				msg = dst.data();
			}
			break;
	}
	// TODO: do character encoding etc.
	return sanitizeUTF8(msg);
}


/**
	Behaves similar to string[string] but case does not matter for the key, the insertion order is not
	changed and multiple values per key are supported.

	This kind of map is used for MIME headers (e.g. for HTTP), where the case of the key strings
	does not matter. Note that the map can contain fields with the same key multiple times if
	addField is used for insertion. Insertion order is preserved.

	Note that despite case not being relevant for matching keyse, iterating over the map will yield
	the original case of the key that was put in.
*/
alias InetHeaderMap = DictionaryList!(string, false);



/**
	Performs quoted-printable decoding.
*/
struct QuotedPrintable {
	static ubyte[] decode(in char[] input, bool in_header = false)
	{
		auto ret = appender!(ubyte[])();
		for( size_t i = 0; i < input.length; i++ ){
			if( input[i] == '=' ){
				auto code = input[i+1 .. i+3];
				i += 2;
				if( code != cast(ubyte[])"\r\n" )
					ret.put(code.parse!ubyte(16));
			} else if( in_header && input[i] == '_') ret.put(' ');
			else ret.put(input[i]);
		}
		return ret.data();
	}
}



private void writeDecimal2(R)(ref R dst, uint n)
{
	auto d1 = n % 10;
	auto d2 = (n / 10) % 10;
	dst.put(cast(char)(d2 + '0'));
	dst.put(cast(char)(d1 + '0'));
}

private void writeDecimal(R)(ref R dst, uint n)
{
	if( n == 0 ){
		dst.put('0');
		return;
	}

	// determine all digits
	uint[10] digits;
	int i = 0;
	while( n > 0 ){
		digits[i++] = n % 10;
		n /= 10;
	}

	// write out the digits in reverse order
	while( i > 0 ) dst.put(cast(char)(digits[--i] + '0'));
}
