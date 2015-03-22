module vibe.http.cookiejar;

import vibe.core.log;
import vibe.http.common;
import vibe.utils.memory;
import vibe.utils.array;
import vibe.utils.dictionarylist : icmp2;
import vibe.core.file;
import vibe.inet.message;
import vibe.stream.memory;
import vibe.stream.wrapper;
import vibe.stream.operations;
import std.file : getcwd;
import vibe.core.sync;
import std.algorithm;
import std.datetime;
import std.typecons;
import std.conv : parse, to;
import std.exception;

interface CookieJar : CookieStore
{
	/// Get all valid cookies corresponding to the specified criteria
	/// Note: '*' is used as a wildcard strictly when used alone
	CookiePair[] find(string domain = "*", string name = "*", string path = "/", bool secure = false, bool http_only = false);

	/// Removes all valid cookies corresponding to the specified search criteria
	/// Note: '*' is used as a wildcard strictly when used alone
	void remove(string domain = "*", string name = "*", string path = "/", bool secure = false, bool http_only = false);

	/// Add a custom cookie, replaces the old one if it collides
	void setCookie(string name, Cookie cookie);

	/// Removes all session cookies (that were set without 'expires')
	void clearSession();

	/// Removes all invalid cookies (that are now expired)
	void cleanup();
}

struct CookiePair
{
	string name;
	Cookie value;
}

class FileCookieJar : CookieJar
{
private:
	Path m_filePath;
	RecursiveTaskMutex m_writeLock;
public:
	@property const(Path) path() const { return m_filePath; }

	void get(string host, string path, bool secure, void delegate(string) send_to) const
	{
		logTrace("Get cookies (concat) for host: %s path: %s secure: %s", host, path, secure);
		import std.array : Appender;
		StrictCookieSearch search = StrictCookieSearch("*", host, path, secure);
		Appender!string app;
		app.reserve(128);
		bool flag;

		auto ret = readCookies( (CookiePair cookie) {
				if (search.match(cookie)) {
					logDebug("Search matched cookie: %s", cookie.name);
					if (flag) {
						app ~= "; ";
					}
					else flag = true;
					app ~= cookie.name;
					app ~= '=';
					app ~= cookie.value.value;
				}
				return false;
			});
		assert(ret.length == 0);
		// the data will be copied upon being received through the callback
		send_to(app.data);

	}

	void get(string host, string path, bool secure, void delegate(string[]) send_to) const
	{
		logTrace("Get cookies for host: %s path: %s secure: %s", host, path, secure);
		import std.array : Appender;
		StrictCookieSearch search = StrictCookieSearch("*", host, path, secure);
		Appender!(string[]) app;
		scope(exit) {
			foreach (ref string kv; app.data)
			{
				freeArray(manualAllocator(), kv);
			}
		}

		auto ret = readCookies( (CookiePair cookie) {
				if (search.match(cookie)) {
					logDebug("Search matched cookie: %s", cookie.name);
					char[] kv = allocArray!char(manualAllocator(), cookie.name.length + 1 + cookie.value.value.length);
					kv[0 .. cookie.name.length] = cookie.name[];
					kv[cookie.name.length] = '=';
					kv[cookie.name.length + 1 .. $] = cookie.value.value[];
					app ~= cast(string) kv;
				}
				return false;
			});
		assert(ret.length == 0);

		send_to(app.data);
	}
	
	/// Sets the cookies using the provided Set-Cookie: header value entry
	void set(string host, string set_cookie)
	{
		m_writeLock.lock();
		scope(exit) m_writeLock.unlock();
		auto cookie_local = FreeListObjectAlloc!Cookie.alloc();
		scope(exit) FreeListObjectAlloc!Cookie.free(cookie_local);
		parseSetCookieString(set_cookie, cookie_local, (CookiePair cookie) {
				if (cookie.value.domain is null || cookie.value.domain == "")
					cookie.value.domain = host;
				setCookie(cookie.name, cookie.value);
			});
	}

	this(Path path)
	{
		m_writeLock = new RecursiveTaskMutex();
		m_filePath = path;
		if (!existsFile(m_filePath))
		{ // touch
			import std.stdio;
			auto file = File(m_filePath.toNativeString(), "w+");
		}
		logDebug("Using cookie jar on file: ", m_filePath.toNativeString());
	}

	this(string path)
	{
		if (!path.canFind('/') || path.startsWith("./"))
			path = getcwd() ~ "/" ~ path;

		this(Path(path));
	}

	CookiePair[] find(string domain = "*", string name = "*", string path = "/", bool secure = false, bool http_only = false)
	{
		StrictCookieSearch search = StrictCookieSearch(name, domain, path, secure, http_only);
		return readCookies(&search.match);
	}

	void setCookie(string name, Cookie cookie)
	{
		m_writeLock.lock();
		scope(exit) m_writeLock.unlock();
		StrictCookieSearch search = StrictCookieSearch(name, cookie.domain, cookie.path, cookie.secure, cookie.httpOnly);
		removeCookies(&search.match);
		if (cookie.maxAge) {
			cookie.expires = (Clock.currTime(UTC()) + dur!"seconds"(cookie.maxAge)).toRFC822DateTimeString();
		}
		else if (!cookie.maxAge && (!cookie.expires || cookie.expires == ""))
		{
			cookie.expires = "Thu, 01 Jan 1970 00:00:00 GMT";
		}

		{
			FileStream stream = openFile(m_filePath, FileMode.append);
			auto range = StreamOutputRange(stream);
			cookie.writeString(&range, name, false);
			range.put('\n');
		}
	}

	void remove(string domain = "*", string name = "*", string path = "/", bool secure = false, bool http_only = false)
	{
		m_writeLock.lock();
		scope(exit) m_writeLock.unlock();
		StrictCookieSearch search = StrictCookieSearch(name, domain, path, secure, http_only);
		return removeCookies(&search.match);
	}

	void clearSession()
	{
		m_writeLock.lock();
		scope(exit) m_writeLock.unlock();
		removeCookies( (CookiePair cookie) { return cookie.value.expires == "Thu, 01 Jan 1970 00:00:00 GMT"; } );
	}

	void cleanup()
	{
		m_writeLock.lock();
		scope(exit) m_writeLock.unlock();
		StrictCookieSearch search;
		search.expires = Clock.currTime(UTC()).toRFC822DateTimeString(); // find cookies with expiration before now, excluding session cookies
		removeCookies( &search.match );
	}

	// read cookies from the file, allocating on the GC only for the selection
	CookiePair[] readCookies(bool delegate(CookiePair) predicate) const {
		import std.array : Appender;
		Appender!(CookiePair[]) cookies;
		ubyte[2048] buffer = void;
		ubyte[] contents = buffer[0 .. buffer.length];
		auto carry_over = AllocAppender!(ubyte[])(manualAllocator());
		scope(exit) carry_over.reset(AppenderResetMode.freeData);
		PoolAllocator pool = FreeListObjectAlloc!PoolAllocator.alloc(4096, manualAllocator());
		scope(exit) FreeListObjectAlloc!PoolAllocator.free(pool);
		
		while (contents.length == 2048)
		{
			scope(exit) pool.reset();
			contents = readFile(m_filePath, buffer);
			InputStream stream;
			scope(exit) if (stream) FreeListObjectAlloc!MemoryStream.free(cast(MemoryStream)stream);
			if (carry_over.data.length > 0) {
				carry_over.put(contents);
				stream = cast(InputStream)FreeListObjectAlloc!MemoryStream.alloc(carry_over.data);
				carry_over.reset(AppenderResetMode.reuseData);
			}
			else
				stream = cast(InputStream)FreeListObjectAlloc!MemoryStream.alloc(contents);
			size_t total_read;

			// loop for each cookie (line) found until the end of the buffer
			while(total_read < contents.length) {
				if (stream.peek().countUntil('\n') == -1)
				{
					carry_over.put(contents[total_read .. $]);
					break;
				}
				string cookie_str;
				try 
					cookie_str = cast(string) stream.readLine(4096, "\n", pool);
				catch(Exception e) {
					carry_over.put(contents[total_read .. $]);
					break;
				}
				total_read += cookie_str.length;
				
				auto getVal = (CookiePair cookiepair) {
					if (predicate(cookiepair)) {
						// copy the cookie_str on the GC and parse again
						Cookie cookie2 = new Cookie;
						// use the specified allocator for the payload
						char[] cookie_str_alloc = cast(char[])cookie_str.dup;
						auto app = (CookiePair gcpair) {
							// append the result to the `cookies`
							cookies ~= gcpair;
						};
						parseSetCookieString(cast(string)cookie_str_alloc, cookie2, app);
					}
				};
				
				{
					Cookie cookie = FreeListObjectAlloc!Cookie.alloc();
					scope(exit) FreeListObjectAlloc!Cookie.free(cookie);
					parseSetCookieString(cookie_str, cookie, getVal);
				}
			}
		}
		
		return cookies.data;
	}

	// removes cookies by skipping those that test true for specified predicate
	void removeCookies(bool delegate(CookiePair) predicate) {

		m_writeLock.lock();
		scope(exit) m_writeLock.unlock();

		ubyte[2048] buffer = void;
		ubyte[] contents = buffer[0 .. buffer.length];
		auto carry_over = AllocAppender!(ubyte[])(manualAllocator());
		scope(exit) 
			carry_over.reset(AppenderResetMode.freeData);
		PoolAllocator pool = FreeListObjectAlloc!PoolAllocator.alloc(4096, manualAllocator());
		scope(exit) FreeListObjectAlloc!PoolAllocator.free(pool);

		FileStream new_file = createTempFile();
		AllocAppender!(ubyte[]) new_file_data = AllocAppender!(ubyte[])(manualAllocator());
		scope(exit) new_file_data.reset(AppenderResetMode.freeData);

		while (contents.length == 2048)
		{
			scope(exit) pool.reset();
			contents = readFile(m_filePath, buffer);
		
			InputStream stream;
			scope(exit) if (stream) FreeListObjectAlloc!MemoryStream.free(cast(MemoryStream)stream);
			if (carry_over.data.length > 0) {
				carry_over.put(contents);
				stream = FreeListObjectAlloc!MemoryStream.alloc(carry_over.data); // todo: Avoid this GC allocation
				carry_over.reset(AppenderResetMode.reuseData);
			}
			else
				stream = FreeListObjectAlloc!MemoryStream.alloc(contents);
			size_t total_read;

			// loop for each cookie (line) found until the end of the buffer
			while(total_read < contents.length) {
				if (stream.peek().countUntil('\n') == -1)
				{
					carry_over.put(contents[total_read .. $]);
					break;
				}
				string cookie_str;
				try
					cookie_str = cast(string) stream.readLine(4096, "\n", pool);
				catch(Exception e) {
					carry_over.put(contents[total_read .. $]);
					break;
				}
				total_read += cookie_str.length;
				auto getVal = (CookiePair cookiepair) {
					if (!predicate(cookiepair)) {
						new_file_data.put(cast(ubyte[])cookie_str);
						new_file_data.put('\n');
						if (new_file_data.data.length >= 256) {
							new_file.write(cast(ubyte[]) new_file_data.data);
							new_file.flush();
							new_file_data.reset(AppenderResetMode.reuseData);
						}
					}
				};
				
				{
					Cookie cookie = FreeListObjectAlloc!Cookie.alloc();
					scope(exit) FreeListObjectAlloc!Cookie.free(cookie);
					parseSetCookieString(cookie_str, cookie, getVal);
				}
			}
		}
		new_file.write(cast(ubyte[]) new_file_data.data);
		new_file.finalize();
		removeFile(m_filePath);
		moveFile(new_file.path, m_filePath);
	}

}

struct StrictCookieSearch
{
	enum epoch = "Thu, 01 Jan 1970 00:00:00 GMT";
	string name = "*";
	string domain = "*";
	string path = "/";
	bool secure = true; 
	bool httpOnly = false;
	// by default, only session/current cookies are returned
	// to get expired cookies, set this to the cutoff date after which they are expired
	string expires = epoch;

	bool match(CookiePair cookie) {
		if (name != "*") {
			if (cookie.name != name) {
				logTrace("Cookie name match failed: %s != %s", name, cookie.name);
				return false;
			}
		}
		if (domain != "*") {
			enforce(cookie.value.domain.length > 0, "Empty domain found in cookies file while searching through it");
			if (!cookie.value.domain.isCNameOf(domain))
			{
				logTrace("Domain predicate failed: %s != %s", domain, cookie.value.domain);
				return false;
			}
		}
		if (path != "/") {
			if (!path.startsWith(cookie.value.path)) {
				logTrace("Path match failed: %s != %s", path, cookie.value.path); 
				return false;
			}
		}
		if (!secure) {
			if (cookie.value.secure) {
				logTrace("Cookie secure check failed: %s != %s", secure, cookie.value.secure);
				return false;
			}
		}
		if (httpOnly) {
			if (!cookie.value.httpOnly) {
				logTrace("Cookie httpOnly check failed: %s != %s", httpOnly, cookie.value.httpOnly);
				return false;
			}
		}

		if (expires == epoch) {
			// give me valid cookies, both session and according to current time
			if (cookie.value.expires !is null && 
				cookie.value.expires != epoch && 
				cookie.value.expires != "" && 
				cookie.value.expires.parseCookieDate() < Clock.currTime(UTC()))
			{
				logTrace("Cookie date check failed: %s != %s", expires, cookie.value.expires);
				logTrace("Cookie date check parse values: %s != %s", expires.parseCookieDate().toString(), cookie.value.expires.parseCookieDate().toString());
				return false;
			}
		}
		else if (expires != "") {
			// give me expired cookies according to expires
			if (expires.parseCookieDate() < cookie.value.expires.parseCookieDate() || cookie.value.expires == epoch)
			{
				logTrace("Cookie date check failed: %s != %s", expires, cookie.value.expires);
				logTrace("Cookie date check parse values: %s != %s", expires.parseCookieDate().toString(), cookie.value.expires.parseCookieDate().toString());
				return false; // it's valid
			}
		}
		else if (expires == "")
		{
			// give me only session cookies
			if (cookie.value.expires != epoch)
				return false;
		}
		// else don't filter expires
		logDebug("Cookie success for name: %s", name);
		return true;
	}
}

bool isCNameOf(string canonical_name, string host) {
	// lowercase...
	bool dot_domain = canonical_name[0] == '.' && canonical_name.length > 1 && (host.length >= canonical_name.length && icmp2(host[$-canonical_name.length .. $], canonical_name) == 0 || icmp2(canonical_name[1 .. $], host) == 0);
	bool raw_domain = canonical_name[0] != '.' && icmp2(host, canonical_name) == 0;
	bool www_of_domain = host.length >= 4 && host[0 .. 4] == "www." && canonical_name[0] != '.' && icmp2(host[4 .. $], canonical_name[0 .. $]) == 0;
	bool domain_of_www = canonical_name.length >= 4 && canonical_name[0 .. 4] == "www." && icmp2(canonical_name[4 .. $], host[0 .. $]) == 0;

	return dot_domain || raw_domain || www_of_domain || domain_of_www;
}

unittest {
	// www.example.com in .example.com ?
	assert(".example.com".isCNameOf("www.example.com"));
	// example.com in .example.com ?
	assert(".example.com".isCNameOf("example.com"));
	// www.example.com in example.com ?
	assert("example.com".isCNameOf("www.example.com"));
	// anotherexample.com !in example.com ?
	assert(!"example.com".isCNameOf("anotherexample.com"));
	// example.com in www.example.com ?
	assert("www.example.com".isCNameOf("example.com"));
	// www2.example.com !in www.example.com ?
	assert(!"www.example.com".isCNameOf("www2.example.com"));
	// .com !in www.example.com ?
	assert(!"www.example.com".isCNameOf(".com"));
}


void parseSetCookieString(string set_cookie_str, ref Cookie cookie, void delegate(CookiePair) sink) {
	string name;
	size_t i;
	foreach (string part; set_cookie_str.splitter!"a is ';'"())
	{
		scope(exit) i++;
		if (part.length <= 1)
			continue;
		if (i > 0 && part[0] == ' ')
			part = part[1 .. $]; // remove whitespace
		int idx = cast(int)part.countUntil!"a is '='"();
		if (i == 0) {
			auto pair = parseNameValue(part, idx);
			name = pair[0];
			cookie.value = pair[1];
			continue;
		}
		
		parseAttributeValue(part, idx, cookie);
	}
	
	sink(CookiePair(name, cookie));
}

Tuple!(string, string) parseNameValue(string part, int idx) {
	string name;
	string value;
	if (idx == -1)
		return Tuple!(string, string).init;
	name = part[0 .. idx];
	if (idx == part.length)
		return Tuple!(string, string)(name, null);
	value = part[idx+1 .. $];
	return Tuple!(string, string)(name, value);
}

void parseAttributeValue(string part, int idx, ref Cookie cookie) {
	switch (idx) {
		case -1:
			// Secure
			// HttpOnly
			if (part.length == 6) {
				// Secure
				if (icmp2(part, "Secure") != 0) { logError("Cookie Secure parse failed, got %s", part); break; }
				cookie.secure = true;
			}
			else {
				// HttpOnly
				if (icmp2(part, "HttpOnly") != 0) { logError("Cookie HttpOnly parse failed, got %s", part); break; }
				cookie.httpOnly = true;
			}
			break;
		case 4: 
			// Path
			if (icmp2(part[0 .. 4], "Path") != 0 && part.length < 6) { logError("Cookie Path parse failed, got %s", part); break; }
			cookie.path = part[5 .. $];
			break;
		case 6:
			if (icmp2(part[0 .. 6], "Domain") != 0 || part.length < 8) { logError("Cookie Domain parse failed, got %s", part); break; }
			cookie.domain = part[7 .. $];
			// Domain
			break;
		case 7:
			// Max-Age
			// Expires
			if (icmp2(part[0 .. 7], "Max-Age") == 0) {
				if (part.length < 9) { logError("Cookie Max-Age parse failed, got %s", part); break; }
				string chunk = part[8 .. $];
				cookie.maxAge = chunk.parse!long;
			}
			else {
				// Expires
				if (icmp2(part[0 .. 7], "Expires") != 0 || part.length < 9) { logError("Cookie Expires parse failed, got %s", part); break; }
				cookie.expires = part[8 .. $];
			}
			break;
		default:
			logError("Cookie parse failed, got %s", part);
			break;
	}
}


/* RFC 6265 cookie dates
	cookie-date     = *delimiter date-token-list *delimiter
	date-token-list = date-token *( 1*delimiter date-token )
		date-token      = 1*non-delimiter
		
		delimiter       = %x09 / %x20-2F / %x3B-40 / %x5B-60 / %x7B-7E
		non-delimiter   = %x00-08 / %x0A-1F / DIGIT / ":" / ALPHA / %x7F-FF
		non-digit       = %x00-2F / %x3A-FF
		
		day-of-month    = 1*2DIGIT ( non-digit *OCTET )
		month           = ( "jan" / "feb" / "mar" / "apr" /
			"may" / "jun" / "jul" / "aug" /
			"sep" / "oct" / "nov" / "dec" ) *OCTET
		year            = 2*4DIGIT ( non-digit *OCTET )
		time            = hms-time ( non-digit *OCTET )
		hms-time        = time-field ":" time-field ":" time-field
		time-field      = 1*2DIGIT
*/

import std.ascii : isDigit, isWhite, isAlpha;

SysTime parseCookieDate(string date_str)
{
	Date date;
	TimeOfDay time;

	// temp vars
	int[3] unordered_date = [-1, -1, -1];
	int year = -1;
	int month = -1;
	int day = -1;
	int seconds_offset = -1; // from zone
	
	size_t pos;
	while(date_str.length > 0) {
		scope(exit) pos++;
		bool is_digit = date_str[0].isDigit();
		bool is_alpha = !is_digit && date_str[0].isAlpha();
		if (date_str[0].isWhite()) {
			date_str = date_str[1 .. $];
			continue;
		}
		// Year
		if (is_digit && year == -1 && date_str.length > 3 && date_str[1].isDigit() && date_str[2].isDigit() && date_str[3].isDigit()) 
		{
			year = date_str[0 .. 4].to!int;
			date_str = date_str[4 .. $];
			continue;
		}

		// Month
		if (is_alpha && (month == 0 || month == -1) && date_str.length >= 3) {
			month = cast(int) months.countUntil!((a, b) { return memieq(a.ptr, b.ptr, a.length); })(date_str[0 .. 3]) + 1;
			if (month > 0) {
				date_str = date_str[3 .. $];
				continue;
			}
		}

		// Time Zone
		if (!is_digit && seconds_offset == -1 && date_str.length >= 3) 
		{
			int idx = cast(int) zones.countUntil!((a, b) { return memieq(a.ptr, b.ptr, a.length); })(date_str[0 .. 3]);
			if (idx != -1) {
				int sign = (pos > 0 && (date_str.ptr - 1)[0] == '-') ? -1 : 1;
				seconds_offset = sign * zones_offsets[idx] * 60 * 60;
				date_str = date_str[3 .. $];
				continue;
			}
		}

		// another try on zones
		if (!is_digit && (seconds_offset == -1 || seconds_offset == 0) && (date_str[0] == '+' || date_str[0] == '-')
			&& (pos == 0 || *(date_str.ptr - 1) == ' ' || *(date_str.ptr - 1) == '\t' || *(date_str.ptr - 1) == ','
				|| (pos >= 3 && (downcase(*(date_str.ptr - 3)) == 'g') && (downcase(*(date_str.ptr - 2)) == 'm') 
					&& (downcase(*(date_str.ptr - 1)) == 't'))))
		{
			int end = 1;
			while (end < 5 && date_str.length > end && date_str[end].isDigit())
				++end;
			int minutes = 0;
			int hours = 0;
			switch (end - 1)
			{
				case 4:
					minutes = date_str[3 .. 5].to!int;
					goto case 2;
				case 2:
					hours = date_str[1 .. 3].to!int;
					break;
				case 1:
					hours = date_str[1 .. 2].to!int;
					break;
				default:
					date_str = date_str[end .. $];
					continue;
			}
			if (end != 1) {
				int sign = date_str[0] == '-' ? -1 : 1;
				seconds_offset = sign * ((minutes * 60) + (hours * 60 * 60));
				date_str = date_str[end .. $];
				continue;
			}
		}
		
		// TimeOfDay
		if (is_digit && time is TimeOfDay.init
			&& ((date_str.length >= 3 && date_str[2] == ':') || (date_str.length >= 2 && date_str[1] == ':'))) 
		{
			import std.regex;

			// hour:minute:second.ms pm
			auto time_regex = regex(`(\d{1,2}):(\d{1,2})(:(\d{1,2})|)(\.(\d{1,3})|)((\s{0,}(am|pm))|)`);
			auto captured = date_str.matchFirst(time_regex);
			if (!captured.empty) {
				time = TimeOfDay(captured[1].to!int, captured[2].to!int, captured[4].to!int);
				if (time.hour < 12 && captured[9].length > 0)
					if (captured[9] == "pm")
						time.hour = time.hour + 12;
				date_str = date_str[captured[0].length .. $];
				continue;
			}
		}
		
		// Probably a day, but keep the value around and resolve possible date misordering later
		if (is_digit) 
		{
			int length = 1;
			if (date_str.length > 1 && date_str[1].isDigit())
				++length;
			int x = date_str[0 .. length].to!int;
			if (year == -1 && (x > 31 || x == 0))
				// not a day or month
				year = x;
			else {
				if (unordered_date[0] == -1) 
					unordered_date[0] = x;
				else if (unordered_date[1] == -1)
					unordered_date[1] = x;
				else if (unordered_date[2] == -1)
					unordered_date[2] = x;
			}
			date_str = date_str[length .. $];
			continue;
		}

		date_str = date_str[1 .. $];
	}

	// Resolve date misordering
	resolveComplexDate(unordered_date, year, month, day);

	// We should have it now...

	enforce(year != -1 && month != -1 && day != -1, "Parser failure, got: " ~ year.to!string ~ "-" ~ month.to!string ~ "-" ~ day.to!string);

	int to4DigitYear(int yr) {
		if (yr < 70)
			yr += 2000;
		else if (yr < 100)
			yr += 1900;
		return yr;
	}
	// 29 feb is still unhandled until here
	if (valid!"days"(to4DigitYear(year), month, day))
		date = Date(to4DigitYear(year), month, day);
	else date = Date(to4DigitYear(day), month, year);	

	DateTime date_time = DateTime(date, time);
	// convert to UTC
	if (seconds_offset != -1)
		date_time += dur!"seconds"(seconds_offset);

	return SysTime(date_time, UTC());
}

private:

string[] months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// common time zones. We use GMT-XX notation usually though
string[] zones = [	   "PST", "PDT", "MST", "MDT", "CST", "CDT", "EST", "EDT", "AST", "NST", "GMT", "UTC", "BST", "MET", "EET", "JST"];
int[] zones_offsets = [-8,	  -7,	 -7,	-6,	   -6,	  -6,	 -5,	-5,    -4,	  -4,	  0,	 0,	    1,	   1, 	  2, 	 9];

char downcase(char c) {
	return cast(char)('A' <= c && c <= 'Z' ? (c - 'A' + 'a') : c);
}

bool memieq(const void *a, const void *b, size_t n) {
	size_t i;
	const ubyte* aa = cast(const ubyte*) a;
	const ubyte* bb =  cast(const ubyte*) b;
	
	for (i = 0; i < n; ++i) {
		if (downcase(aa[i]) != downcase(bb[i])) {
			//logDebug("%s != %s", cast(string)aa[0 .. n], cast(string)bb[0 .. n]);
			return false;
		}
	}
	return true;
}


private void resolveComplexDate(int[3] date_vals, ref int year, ref int month, ref int day)
{
	enum {
		MaybeDay = 1,
		MaybeMonth = 2,
		MaybeYear = 4
	}
	int[3] date_keys;

	int must_find = 3;

	// Figure out what is still missing
	for (int i = 0; i < must_find; ++i) {
		// This field could be anything (without checking further)
		if (date_vals[i] == -1) {
			date_keys[i] = MaybeDay | MaybeYear | MaybeMonth;
			must_find = i;
			continue;
		}

		// If we had all values correctly, this is the day.
		if (date_vals[i] >= 1)
			date_keys[i] = MaybeDay;
			
		// Or it could be a month, maybe
		if (month == -1 && date_vals[i] >= 1 && date_vals[i] <= 12)
			date_keys[i] |= MaybeMonth;

		// or a year...
		if (year == -1)
			date_keys[i] |= MaybeYear;
	}

	for (int i = 0; i < must_find; ++i) {
		int val = date_vals[i];
		bool must_find_month = (date_keys[i] & MaybeDay) > 0 && val >= 29;
		bool must_find_day = (date_keys[i] & MaybeMonth) > 0;
		if (!must_find_month || !must_find_day)
			continue;
		for (int j = 0; j < 3; ++j) {
			if (j == i)
				continue;
			for (int k = 0; k < 2; ++k) {
				// 0 for month, 1 for day
				bool is_month = k == 0;
				bool is_day = k == 1;
				if (is_month && !(must_find_month && (date_keys[j] & MaybeMonth) > 0))
					continue;
				else if (is_day && !(must_find_day && (date_keys[j] & MaybeDay) > 0))
					continue;
				int m = val;
				int d = date_vals[j];
				if (k == 0)
					.swap(m, d);
				if (m == -1)
					m = month;
				bool found = true;
				switch(m) {
					case 2:
						if (d <= 29)
							found = false;
						break;
					case 4: case 6: case 9: case 11:
						if (d <= 30)
							found = false;
						break;
					default:
						if (d > 0 && d <= 31)
							found = false;
				}
				if (is_month) must_find_month = found;
				else if (is_day) must_find_day = found;
			}
		}
		if (must_find_month)
			date_keys[i] &= ~MaybeDay;
		if (must_find_day)
			date_keys[i] &= ~MaybeMonth;
	}

	for (int i = 0; i < must_find; ++i) {
		int unset;
		for (int j = 0; j < 3; ++j) {
			if (date_keys[j] == MaybeDay && day == -1) {
				day = date_vals[j];
				unset |= MaybeDay;
			} else if (date_keys[j] == MaybeMonth && month == -1) {
				month = date_vals[j];
				unset |= MaybeMonth;
			} else if (date_keys[j] == MaybeYear && year == -1) {
				year = date_vals[j];
				unset |= MaybeYear;
			} else break;
			date_keys[j] &= ~unset;
		}
	}

	for (int i = 0; i < must_find; ++i) {
		if ((date_keys[i] & MaybeYear) > 0 && year == -1) 
			year = date_vals[i];
		else if ((date_keys[i] & MaybeMonth) > 0 && month == -1)
			month = date_vals[i];
		else if ((date_keys[i] & MaybeDay) > 0 && day == -1) 
			day = date_vals[i];
	}
}