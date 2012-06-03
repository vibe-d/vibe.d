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

import std.exception;
import std.string;

alias StrMapCI InetHeaderMap;

/**
	Parses an internet header according to RFC5322 (with RFC822 compatibility).
*/
void parseRfc5322Header(InputStream input, ref InetHeaderMap dst, size_t max_line_length = 1000)
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
	while( (ln = cast(string)input.readLine(max_line_length)).length > 0 ){
		logTrace("hdr: %s", ln);
		if( ln[0] != ' ' && ln[0] != '\t' ){
			addPreviousHeader();

			auto colonpos = ln.indexOf(':');
			enforce(colonpos > 0 && colonpos < ln.length-1, "Header is missing ':'.");
			hdr = ln[0..colonpos].strip();
			hdrvalue = ln[colonpos+1..$].strip();
		} else {
			hdrvalue ~= " " ~ ln.strip();
		}
	}
	addPreviousHeader();
}
