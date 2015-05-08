/**
	Cookie Date Parsing

	Copyright: © 2011-. Benjamin C. Meyer
	Authors: Sönke Ludwig, Etienne Cimon, Benjamin C. Meyer
	License: 3-BSD
	// todo: rewrite this or move it
*/
module vibe.http.internal.cookiejar_dates;

import std.algorithm;
import std.datetime;
import std.typecons;
import std.conv : parse, to;
import std.exception;

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

// taken from libhttp2
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