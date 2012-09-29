/**
	Mime header parsing according to RFC5322

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.rfc5322;

import vibe.core.log;
import vibe.http.common : StrMapCI;
import vibe.stream.stream;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string;

import std.conv;
import std.datetime;
import std.exception;
import std.string;


alias StrMapCI InetHeaderMap;

/**
	Parses an internet header according to RFC5322 (with RFC822 compatibility).
*/
void parseRfc5322Header(InputStream input, ref InetHeaderMap dst, size_t max_line_length = 1000, Allocator alloc = defaultAllocator())
{
	string hdr, hdrvalue;

	void addPreviousHeader(){
		if( !hdr.length ) return;
		if( auto pv = hdr in dst ) {
			*pv ~= "," ~ hdrvalue; // RFC822 legacy support
		} else {
			dst[hdr] = hdrvalue;
		}
	}

	string ln;
	while( (ln = cast(string)input.readLine(max_line_length, "\r\n", alloc)).length > 0 ){
		logTrace("hdr: %s", ln);
		if( ln[0] != ' ' && ln[0] != '\t' ){
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

void writeRFC822DateString(R)(ref R dst, SysTime time)
{
	assert(time.timezone == UTC());

	static immutable dayStrings = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
	dst.put(dayStrings[time.dayOfWeek]);
	dst.put(", ");
	writeDecimal2(dst, time.day);
	dst.put(' ');
	dst.put(monthStrings[time.month-1]);
	dst.put(' ');
	writeDecimal(dst, time.year);
}

void writeRFC822TimeString(R)(ref R dst, SysTime time)
{
	assert(time.timezone == UTC());
	writeDecimal2(dst, time.hour);
	dst.put(':');
	writeDecimal2(dst, time.minute);
	dst.put(':');
	writeDecimal2(dst, time.second);
	dst.put(" GMT");
}

void writeRFC822DateTimeString(R)(ref R dst, SysTime time)
{
	writeRFC822DateString(dst, time);
	dst.put(' ');
	writeRFC822TimeString(dst, time);
}

string toRFC822TimeString(SysTime time)
{
	auto ret = new FixedAppender!(string, 12);
	writeRFC822TimeString(ret, time);
	return ret.data;
}

string toRFC822DateString(SysTime time)
{
	auto ret = new FixedAppender!(string, 16);
	writeRFC822DateString(ret, time);
	return ret.data;
}

string toRFC822DateTimeString(SysTime time)
{
	auto ret = new FixedAppender!(string, 29);
	writeRFC822DateTimeString(ret, time);
	return ret.data;
}

SysTime parseRFC822DateTimeString(string str)
{
	auto idx = str.indexOf(',');
	if( idx > 0 ) str = str[idx .. $].stripLeft();

	str = str.stripLeft();
	auto day = parse!int(str);
	str = str.stripLeft();
	int month = -1;
	foreach( i, ms; monthStrings )
		if( str.startsWith(ms) ){
			month = i+1;
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
	else return SysTime(dt, new SimpleTimeZone((tzoffset / 100) * 60 + tzoffset % 100));
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
