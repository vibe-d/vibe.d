/**
	High level stream manipulation functions.

	Copyright: © 2012-2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.operations;

public import vibe.core.stream;

import vibe.core.log;
import vibe.stream.memory;
import vibe.utils.memory;

import std.algorithm;
import std.array;
import std.datetime;
import std.exception;
import std.typecons;


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Reads and returns a single line from the stream.

	Throws:
		An exception if either the stream end was hit without hitting a newline first, or
		if more than max_bytes have been read from the stream.
*/
ubyte[] readLine(InputStream stream, size_t max_bytes = size_t.max, string linesep = "\r\n", Allocator alloc = defaultAllocator()) /*@ufcs*/
{
	return readUntil(stream, cast(const(ubyte)[])linesep, max_bytes, alloc);
}

/**
	Reads all data of a stream until the specified end marker is detected.

	Params:
		stream = The input stream which is searched for end_marker
		end_marker = The byte sequence which is searched in the stream
		max_bytes = An optional limit of how much data is to be read from the
			input stream; if the limit is reaached before hitting the end
			marker, an exception is thrown.
		alloc = An optional allocator that is used to build the result string
			in the string variant of this function
		dst = The output stream, to which the prefix to the end marker of the
			input stream is written

	Returns:
		The string variant of this function returns the complete prefix to the
		end marker of the input stream, excluding the end marker itself.

	Throws:
		An exception if either the stream end was hit without hitting a marker
		first, or if more than max_bytes have been read from the stream in
		case of max_bytes != 0.

	Remarks:
		This function uses an algorithm inspired by the
		$(LINK2 http://en.wikipedia.org/wiki/Boyer%E2%80%93Moore_string_search_algorithm, 
		Boyer-Moore string search algorithm). However, contrary to the original
		algorithm, it will scan the whole input string exactly once, without
		jumping over portions of it. This allows the algorithm to work with
		constant memory requirements and without the memory copies that would
		be necessary for streams that do not hold their complete data in
		memory.

		The current implementation has a run time complexity of O(n*m+m²) and
		O(n+m) in typical cases, with n being the length of the scanned input
		string and m the length of the marker.
*/
ubyte[] readUntil(InputStream stream, in ubyte[] end_marker, size_t max_bytes = size_t.max, Allocator alloc = defaultAllocator()) /*@ufcs*/
{
	auto output = scoped!MemoryOutputStream(alloc);
	output.reserve(max_bytes < 64 ? max_bytes : 64);
	readUntil(stream, output, end_marker, max_bytes);
	return output.data();
}
/// ditto
void readUntil(InputStream stream, OutputStream dst, in ubyte[] end_marker, ulong max_bytes = ulong.max) /*@ufcs*/
{
	assert(max_bytes > 0 && end_marker.length > 0);
	
	// allocate internal jump table to optimize the number of comparisons
	size_t[8] nmatchoffsetbuffer;
	size_t[] nmatchoffset;
	if (end_marker.length <= nmatchoffsetbuffer.length) nmatchoffset = nmatchoffsetbuffer[0 .. end_marker.length];
	else nmatchoffset = new size_t[end_marker.length];
	
	// precompute the jump table
	nmatchoffset[0] = 0;
	foreach( i; 1 .. end_marker.length ){
		nmatchoffset[i] = i;
		foreach_reverse( j; 1 .. i )
			if( end_marker[j .. i] == end_marker[0 .. i-j] ){
				nmatchoffset[i] = i-j;
				break;
			}
		assert(nmatchoffset[i] > 0 && nmatchoffset[i] <= i);
	}

	size_t nmatched = 0;
	auto bufferobj = FreeListRef!(Buffer, false)();
	auto buf = bufferobj.bytes[];

	ulong bytes_read = 0;

	void skip(size_t nbytes)
	{
		bytes_read += nbytes;
		while( nbytes > 0 ){
			auto n = min(nbytes, buf.length);
			stream.read(buf[0 .. n]);
			nbytes -= n;
		}
	}

	while( !stream.empty ){
		enforce(bytes_read < max_bytes, "Reached byte limit before reaching end marker.");

		// try to get as much data as possible, either by peeking into the stream or
		// by reading as much as isguaranteed to not exceed the end marker length
		// the block size is also always limited by the max_bytes parameter.
		size_t nread = 0;
		auto least_size = stream.leastSize(); // NOTE: blocks until data is available
		auto max_read = max_bytes - bytes_read;
		auto str = stream.peek(); // try to get some data for free
		if( str.length == 0 ){ // if not, read as much as possible without reading past the end
			nread = min(least_size, end_marker.length-nmatched, buf.length, max_read);
			stream.read(buf[0 .. nread]);
			str = buf[0 .. nread];
			bytes_read += nread;
		} else if( str.length > max_read ){
			str.length = cast(size_t)max_read;
		}

		// remember how much of the marker was already matched before processing the current block
		size_t nmatched_start = nmatched;

		// go through the current block trying to match the marker
		size_t i = 0;
		for( i = 0; i < str.length; i++ ){
			auto ch = str[i];
			// if we have a mismatch, use the jump table to try other possible prefixes
			// of the marker
			while( nmatched > 0 && ch != end_marker[nmatched] )
				nmatched -= nmatchoffset[nmatched];

			// if we then have a match, increase the match count and test for full match
			if( ch == end_marker[nmatched] ){
				if( ++nmatched == end_marker.length ){
					// in case of a full match skip data in the stream until the end of
					// the marker
					skip(++i - nread);
					break;
				}
			}
		}


		// write out any false match part of previous blocks
		if( nmatched_start > 0 ){
			if( nmatched <= i ) dst.write(end_marker[0 .. nmatched_start]);
			else dst.write(end_marker[0 .. nmatched_start-nmatched+i]);
		}
		
		// write out any unmatched part of the current block
		if( nmatched < i ) dst.write(str[0 .. i-nmatched]);

		// got a full, match => out
		if( nmatched >= end_marker.length ) return;

		// otherwise skip this block in the stream
		skip(str.length - nread);
	}

	enforce(false, "Reached EOF before reaching end marker.");
}


unittest {
	import vibe.stream.memory;

	auto text = "1231234123111223123334221111112221231333123123123123123213123111111111114";
	auto stream = new MemoryStream(cast(ubyte[])text);
	void test(string s, size_t expected){
		stream.seek(0);
		auto result = cast(string)readUntil(stream, cast(ubyte[])s);
		assert(result.length == expected, "Wrong result index");
		assert(result == text[0 .. result.length], "Wrong result contents: "~result~" vs "~text[0 .. result.length]);
		assert(stream.leastSize() == stream.size() - expected - s.length, "Wrong number of bytes left in stream");
	}
	foreach( i; 0 .. text.length ){
		stream.peekWindow = i;
		test("1", 0);
		test("2", 1);
		test("3", 2);
		test("12", 0);
		test("23", 1);
		test("31", 2);
		test("123", 0);
		test("231", 1);
		test("1231", 0);
		test("3123", 2);
		test("11223", 11);
		test("11222", 28);
		test("114", 70);
		test("111111111114", 61);
	}
	// TODO: test 
}

/**
	Reads the complete contents of a stream, optionally limited by max_bytes.

	Throws:
		An exception is thrown if the stream contains more than max_bytes data.
*/
ubyte[] readAll(InputStream stream, size_t max_bytes = size_t.max, size_t reserve_bytes = 0) /*@ufcs*/
{
	if (max_bytes == 0) logDebug("Deprecated behavior: readAll() called with max_bytes==0, use max_bytes==size_t.max instead.");

	// prepare output buffer
	auto dst = appender!(ubyte[])();
	reserve_bytes = max(reserve_bytes, min(max_bytes, stream.leastSize));
	if (reserve_bytes) dst.reserve(reserve_bytes);

	auto bufferobj = FreeListRef!(Buffer, false)();
	auto buffer = bufferobj.bytes[];
	size_t n = 0;
	while (!stream.empty) {
		size_t chunk = cast(size_t)min(stream.leastSize, buffer.length);
		n += chunk;
		enforce(!max_bytes || n <= max_bytes, "Input data too long!");
		stream.read(buffer[0 .. chunk]);
		dst.put(buffer[0 .. chunk]);
	}
	return dst.data;
}

/**
	Reads the complete contents of a stream, assuming UTF-8 encoding.

	Params:
		stream = Specifies the stream from which to read.
		sanitize = If true, the input data will not be validated but will instead be made valid UTF-8.
		max_bytes = Optional size limit of the data that is read.

	Returns:
		The full contents of the stream, excluding a possible BOM, are returned as a UTF-8 string.

	Throws:
		An exception is thrown if max_bytes != 0 and the stream contains more than max_bytes data.
		If the sanitize parameter is fals and the stream contains invalid UTF-8 code sequences,
		a UTFException is thrown.
*/
string readAllUTF8(InputStream stream, bool sanitize = false, size_t max_bytes = size_t.max)
{
	import std.utf;
	import vibe.utils.string;
	auto data = readAll(stream, max_bytes);
	if( sanitize ) return stripUTF8Bom(sanitizeUTF8(data));
	else {
		validate(cast(string)data);
		return stripUTF8Bom(cast(string)data);
	}
}

/**
	Pipes a stream to another while keeping the latency within the specified threshold.

	Params:
		destination = The destination stram to pipe into
		source =      The source stream to read data from
		nbytes =      Number of bytes to pipe through. The default of zero means to pipe
		              the whole input stream.
		max_latency = The maximum time before data is flushed to destination. The default value
		              of 0 s will flush after each chunk of data read from source.

	See_also: OutputStream.write
*/
void pipeRealtime(OutputStream destination, ConnectionStream source, ulong nbytes = 0, Duration max_latency = 0.seconds)
{
	static struct Buffer { ubyte[64*1024] bytes = void; }
	auto bufferobj = FreeListRef!(Buffer, false)();
	auto buffer = bufferobj.bytes[];

	//logTrace("default write %d bytes, empty=%s", nbytes, stream.empty);
	auto least_size = source.leastSize;
	StopWatch sw;
	sw.start();
	while (nbytes > 0 || least_size > 0) {
		size_t chunk = min(nbytes > 0 ? nbytes : ulong.max, least_size, buffer.length);
		assert(chunk > 0, "leastSize returned zero for non-empty stream.");
		//logTrace("read pipe chunk %d", chunk);
		source.read(buffer[0 .. chunk]);
		destination.write(buffer[0 .. chunk]);
		if (nbytes > 0) nbytes -= chunk;

		if (max_latency <= 0.seconds || cast(Duration)sw.peek() >= max_latency || !source.waitForData(max_latency)) {
			logTrace("pipeRealtime flushing.");
			destination.flush();
			sw.reset();
		} else {
			logTrace("pipeRealtime not flushing.");
		}

		least_size = source.leastSize;
		if (!least_size) {
			enforce(nbytes == 0, "Reading past end of input.");
			break;
		}
	}
	destination.flush();
}

private struct Buffer { ubyte[64*1024-4] bytes = void; } // 64k - 4 bytes for reference count
