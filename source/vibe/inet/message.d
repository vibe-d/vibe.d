/**
	Internet message handling according to RFC822/RFC5322

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.inet.message;

import vibe.core.log;
import vibe.http.common : StrMapCI;
import vibe.core.stream;
import vibe.stream.operations;
import vibe.utils.array;
import vibe.utils.memory;
import vibe.utils.string;

import std.conv;
import std.datetime;
import std.exception;
import std.range;
import std.string;


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
	if( idx > 0 ) str = str[idx .. $].stripLeft();

	str = str.stripLeft();
	auto day = parse!int(str);
	str = str.stripLeft();
	int month = -1;
	foreach( i, ms; monthStrings )
		if( str.startsWith(ms) ){
			month = cast(int)i+1;
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
	Behaves like string[string] but case does not matter for the key and the insertion order is not changed.

	This kind of map is used for MIME headers (e.g. for HTTP), where the case of the key strings
	does not matter.

	Note that despite case not being relevant for matching keyse, iterating over the map will yield
	the original case of the key that was put in.
*/
struct InetHeaderMap {
	private {
		static struct Field { uint keyCheckSum; string key; string value; }
		Field[64] m_fields;
		size_t m_fieldCount = 0;
		Field[] m_extendedFields;
		static char[256] s_keyBuffer;
	}
	
	@property size_t length() const { return m_fieldCount + m_extendedFields.length; }

	void remove(string key){
		auto keysum = computeCheckSumI(key);
		auto idx = getIndex(m_fields[0 .. m_fieldCount], key, keysum);
		if( idx >= 0 ){
			removeFromArrayIdx(m_fields[0 .. m_fieldCount], idx);
			m_fieldCount--;
		} else {
			idx = getIndex(m_extendedFields, key, keysum);
			enforce(idx >= 0);
			removeFromArrayIdx(m_extendedFields, idx);
		}
	}

	string get(string key, string def_val = null)
	const {
		if( auto pv = key in this ) return *pv;
		return def_val;
	}

	string opIndex(string key)
	const {
		auto pitm = key in this;
		enforce(pitm !is null, "Accessing non-existent key '"~key~"'.");
		return *pitm;
	}
	
	string opIndexAssign(string val, string key)
	{
		auto pitm = key in this;
		if( pitm ) *pitm = val;
		else if( m_fieldCount < m_fields.length ) m_fields[m_fieldCount++] = Field(computeCheckSumI(key), key, val);
		else m_extendedFields ~= Field(computeCheckSumI(key), key, val);
		return val;
	}

	inout(string)* opBinaryRight(string op)(string key) inout if(op == "in") {
		uint keysum = computeCheckSumI(key);
		auto idx = getIndex(m_fields[0 .. m_fieldCount], key, keysum);
		if( idx >= 0 ) return &m_fields[idx].value;
		idx = getIndex(m_extendedFields, key, keysum);
		if( idx >= 0 ) return &m_extendedFields[idx].value;
		return null;
	}

	bool opBinaryRight(string op)(string key) inout if(op == "!in") {
		return !(key in this);
	}

	int opApply(int delegate(ref string key, ref string val) del)
	{
		foreach( ref kv; m_fields[0 .. m_fieldCount] ){
			string kcopy = kv.key;
			if( auto ret = del(kcopy, kv.value) )
				return ret;
		}
		foreach( ref kv; m_extendedFields ){
			string kcopy = kv.key;
			if( auto ret = del(kcopy, kv.value) )
				return ret;
		}
		return 0;
	}

	int opApply(int delegate(ref string val) del)
	{
		foreach( ref kv; m_fields[0 .. m_fieldCount] ){
			if( auto ret = del(kv.value) )
				return ret;
		}
		foreach( ref kv; m_extendedFields ){
			if( auto ret = del(kv.value) )
				return ret;
		}
		return 0;
	}

	@property StrMapCI dup()
	const {
		StrMapCI ret;
		ret.m_fields[0 .. m_fieldCount] = m_fields[0 .. m_fieldCount];
		ret.m_fieldCount = m_fieldCount;
		ret.m_extendedFields = m_extendedFields.dup;
		return ret;
	}

	private ptrdiff_t getIndex(in Field[] map, string key, uint keysum)
	const {
		foreach( i, ref const(Field) entry; map ){
			if( entry.keyCheckSum != keysum ) continue;
			if( icmp2(entry.key, key) == 0 )
				return i;
		}
		return -1;
	}
	
	// very simple check sum function with a good chance to match
	// strings with different case equal
	private static uint computeCheckSumI(string s)
	{
		import std.uni;
		uint csum = 0;
		foreach( i; 0 .. s.length )
			csum += 357*(s[i]&0x1101_1111);
		return csum;
	}
}


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
