/**
	High level stream manipulation functions.

	Copyright: © 2012-2016 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.operations;

public import vibe.core.stream;

import vibe.core.log;
import vibe.utils.array : AllocAppender;
import vibe.internal.allocator;
import vibe.internal.freelistref;
import vibe.stream.wrapper : ProxyStream;

import std.algorithm;
import std.array;
import std.exception;
import std.range : isOutputRange;
import core.time : Duration, seconds;


/**************************************************************************************************/
/* Public functions                                                                               */
/**************************************************************************************************/

/**
	Reads and returns a single line from the stream.

	Throws:
		An exception if either the stream end was hit without hitting a newline first, or
		if more than max_bytes have been read from the stream.
*/
ubyte[] readLine(InputStream)(InputStream stream, size_t max_bytes = size_t.max, string linesep = "\r\n", IAllocator alloc = vibeThreadAllocator()) /*@ufcs*/
	if (isInputStream!InputStream)
{
	auto output = AllocAppender!(ubyte[])(alloc);
	output.reserve(max_bytes < 64 ? max_bytes : 64);
	readLine(stream, output, max_bytes, linesep);
	return output.data();
}
/// ditto
void readLine(InputStream, OutputStream)(InputStream stream, OutputStream dst, size_t max_bytes = size_t.max, string linesep = "\r\n")
	if (isInputStream!InputStream && isOutputStream!OutputStream)
{
	import vibe.stream.wrapper;
	auto dstrng = StreamOutputRange(dst);
	readLine(stream, dstrng, max_bytes, linesep);
}
/// ditto
void readLine(R, InputStream)(InputStream stream, ref R dst, size_t max_bytes = size_t.max, string linesep = "\r\n")
	if (isOutputRange!(R, ubyte))
{
	readUntil(stream, dst, cast(const(ubyte)[])linesep, max_bytes);
}

@safe unittest {
	import vibe.stream.memory : createMemoryOutputStream, createMemoryStream;

	auto inp = createMemoryStream(cast(ubyte[])"Hello, World!\r\nThis is a test.\r\nNot a full line.".dup);
	assert(inp.readLine() == cast(const(ubyte)[])"Hello, World!");
	assert(inp.readLine() == cast(const(ubyte)[])"This is a test.");
	assertThrown(inp.readLine);

	// start over
	inp.seek(0);

	// read into an output buffer
	auto app = appender!(ubyte[]);
	inp.readLine(app);
	assert(app.data == cast(const(ubyte)[])"Hello, World!");

	// read into an output stream
	auto os = createMemoryOutputStream();
	inp.readLine(os);
	assert(os.data == cast(const(ubyte)[])"This is a test.");
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
ubyte[] readUntil(InputStream)(InputStream stream, in ubyte[] end_marker, size_t max_bytes = size_t.max, IAllocator alloc = vibeThreadAllocator()) /*@ufcs*/
	if (isInputStream!InputStream)
{
	auto output = AllocAppender!(ubyte[])(alloc);
	output.reserve(max_bytes < 64 ? max_bytes : 64);
	readUntil(stream, output, end_marker, max_bytes);
	return output.data();
}
/// ditto
void readUntil(InputStream, OutputStream)(InputStream stream, OutputStream dst, in ubyte[] end_marker, ulong max_bytes = ulong.max) /*@ufcs*/
	if (isInputStream!InputStream && isOutputStream!OutputStream)
{
	import vibe.stream.wrapper;
	auto dstrng = streamOutputRange(dst);
	readUntil(stream, dstrng, end_marker, max_bytes);
}
/// ditto
void readUntil(R, InputStream)(InputStream stream, ref R dst, in ubyte[] end_marker, ulong max_bytes = ulong.max) /*@ufcs*/
	if (isOutputRange!(R, ubyte) && isInputStream!InputStream)
{
	assert(max_bytes > 0 && end_marker.length > 0);

	if (end_marker.length <= 2)
		readUntilSmall(stream, dst, end_marker, max_bytes);
	else
		readUntilGeneric(stream, dst, end_marker, max_bytes);
}

@safe unittest {
	import vibe.stream.memory;

	auto text = "1231234123111223123334221111112221231333123123123123123213123111111111114".dup;
	auto stream = createMemoryStream(cast(ubyte[])text);
	void test(string s, size_t expected) @safe {
		stream.seek(0);
		auto result = cast(char[])readUntil(stream, cast(const(ubyte)[])s);
		assert(result.length == expected, "Wrong result index");
		assert(result == text[0 .. result.length], "Wrong result contents: "~result~" vs "~text[0 .. result.length]);
		assert(stream.leastSize() == stream.size() - expected - s.length, "Wrong number of bytes left in stream");

		stream.seek(0);
		auto inp2 = new NoPeekProxy!InputStream(stream);
		result = cast(char[])readUntil(inp2, cast(const(ubyte)[])s);
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

@safe unittest {
	import vibe.stream.memory : createMemoryOutputStream, createMemoryStream, MemoryStream;
	import vibe.stream.wrapper : ProxyStream;

	auto text = cast(ubyte[])"ab\nc\rd\r\ne".dup;
	void test(string marker, size_t idx)
	{
		// code path for peek support
		auto inp = createMemoryStream(text);
		auto dst = appender!(ubyte[]);
		readUntil(inp, dst, cast(const(ubyte)[])marker);
		assert(dst.data == text[0 .. idx]);
		assert(inp.peek == text[idx+marker.length .. $]);

		// code path for no peek support
		inp.seek(0);
		dst = appender!(ubyte[]);
		auto inp2 = new NoPeekProxy!MemoryStream(inp);
		readUntil(inp2, dst, cast(const(ubyte)[])marker);
		assert(dst.data == text[0 .. idx]);
		assert(inp.readAll() == text[idx+marker.length .. $]);
	}
	test("\r\n", 6);
	test("\r", 4);
	test("\n", 2);
}

/**
	Reads the complete contents of a stream, optionally limited by max_bytes.

	Throws:
		An exception is thrown if the stream contains more than max_bytes data.
*/
ubyte[] readAll(InputStream)(InputStream stream, size_t max_bytes = size_t.max, size_t reserve_bytes = 0) /*@ufcs*/
	if (isInputStream!InputStream)
{
	import vibe.internal.freelistref;

	if (max_bytes == 0) logDebug("Deprecated behavior: readAll() called with max_bytes==0, use max_bytes==size_t.max instead.");

	// prepare output buffer
	auto dst = AllocAppender!(ubyte[])(() @trusted { return GCAllocator.instance.allocatorObject; } ());
	reserve_bytes = max(reserve_bytes, min(max_bytes, stream.leastSize));
	if (reserve_bytes) dst.reserve(reserve_bytes);

	size_t n = 0;
	while (!stream.empty) {
		size_t chunk = min(stream.leastSize, size_t.max);
		n += chunk;
		enforce(!max_bytes || n <= max_bytes, "Input data too long!");
		dst.reserve(chunk);
		dst.append((scope buf) {
			stream.read(buf[0 .. chunk]);
			return chunk;
		});
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
		If the sanitize parameter is false and the stream contains invalid UTF-8 code sequences,
		a UTFException is thrown.
*/
string readAllUTF8(InputStream)(InputStream stream, bool sanitize = false, size_t max_bytes = size_t.max)
	if (isInputStream!InputStream)
{
	import std.utf;
	import vibe.utils.string;
	auto data = readAll(stream, max_bytes);
	if( sanitize ) return stripUTF8Bom(sanitizeUTF8(data));
	else {
		auto ret = () @trusted { return cast(string)data; } ();
		validate(ret);
		return stripUTF8Bom(ret);
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
void pipeRealtime(OutputStream, ConnectionStream)(OutputStream destination, ConnectionStream source, ulong nbytes = 0, Duration max_latency = 0.seconds)
	if (isOutputStream!OutputStream && isConnectionStream!ConnectionStream)
{
	static if (__VERSION__ >= 2077)
		import std.datetime.stopwatch : StopWatch;
	else import std.datetime : StopWatch;

	import vibe.internal.freelistref;

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

		auto remaining_latency = max_latency - cast(Duration)sw.peek();
		if (remaining_latency > 0.seconds)
			source.waitForData(remaining_latency);

		if (cast(Duration)sw.peek >= max_latency) {
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

unittest {
	import vibe.core.net : TCPConnection;
	import vibe.core.stream : nullSink;

	void test()
	{
		TCPConnection c;
		pipeRealtime(nullSink, c);
	}
}


/**
	Consumes `bytes.length` bytes of the stream and determines if the contents
	match up.

	Returns: True $(I iff) the consumed bytes equal the passed array.
	Throws: Throws an exception if reading from the stream fails.
*/
bool skipBytes(InputStream)(InputStream stream, const(ubyte)[] bytes)
	if (isInputStream!InputStream)
{
	bool matched = true;
	ubyte[128] buf = void;
	while (bytes.length) {
		auto len = min(buf.length, bytes.length);
		stream.read(buf[0 .. len], IOMode.all);
		if (buf[0 .. len] != bytes[0 .. len]) matched = false;
		bytes = bytes[len .. $];
	}
	return matched;
}

private struct Buffer { ubyte[64*1024-4] bytes = void; } // 64k - 4 bytes for reference count

private void readUntilSmall(R, InputStream)(InputStream stream, ref R dst, in ubyte[] end_marker, ulong max_bytes = ulong.max)
	if (isInputStream!InputStream)
{
	assert(end_marker.length >= 1 && end_marker.length <= 2);

	size_t nmatched = 0;
	size_t nmarker = end_marker.length;

	while (true) {
		enforce(!stream.empty, "Reached EOF while searching for end marker.");
		enforce(max_bytes > 0, "Reached maximum number of bytes while searching for end marker.");
		auto max_peek = max(max_bytes, max_bytes+nmarker); // account for integer overflow
		auto pm = stream.peek()[0 .. min($, max_bytes)];
		if (!pm.length || nmatched == 1) { // no peek support - inefficient route
			ubyte[2] buf = void;
			auto l = nmarker - nmatched;
			stream.read(buf[0 .. l], IOMode.all);
			foreach (i; 0 .. l) {
				if (buf[i] == end_marker[nmatched]) {
					nmatched++;
				} else if (buf[i] == end_marker[0]) {
					foreach (j; 0 .. nmatched) dst.put(end_marker[j]);
					nmatched = 1;
				} else {
					foreach (j; 0 .. nmatched) dst.put(end_marker[j]);
					nmatched = 0;
					dst.put(buf[i]);
				}
				if (nmatched == nmarker) return;
			}
		} else {
			assert(nmatched == 0);

			auto idx = pm.countUntil(end_marker[0]);
			if (idx < 0) {
				dst.put(pm);
				max_bytes -= pm.length;
				stream.skip(pm.length);
			} else {
				dst.put(pm[0 .. idx]);
				if (nmarker == 1) {
					stream.skip(idx+1);
					return;
				} else if (idx+1 < pm.length && pm[idx+1] == end_marker[1]) {
					assert(nmarker == 2);
					stream.skip(idx+2);
					return;
				} else {
					nmatched++;
					stream.skip(idx+1);
				}
			}
		}
	}
}

@safe unittest { // issue #1741
	static class S : InputStream {
		ubyte[] src;
		ubyte[] buf;
		size_t nread;

		this(scope ubyte[] bytes...)
		{
			src = bytes.dup;
		}

		@property bool empty() { return nread >= src.length; }
		@property ulong leastSize() { if (!buf.length && !nread) buf = src; return src.length - nread; }
		@property bool dataAvailableForRead() { return buf.length > 0; }
		const(ubyte)[] peek() { return buf; }
		size_t read(scope ubyte[] dst, IOMode) {
			if (!buf.length) buf = src;
			dst[] = buf[0 .. dst.length];
			nread += dst.length;
			buf = buf[dst.length .. $];
			return dst.length;
		}
		alias InputStream.read read;
	}


	auto s = new S('X', '\r', '\n');
	auto dst = appender!(ubyte[]);
	readUntilSmall(s, dst, ['\r', '\n']);
	assert(dst.data == ['X']);
}


private void readUntilGeneric(R, InputStream)(InputStream stream, ref R dst, in ubyte[] end_marker, ulong max_bytes = ulong.max) /*@ufcs*/
	if (isOutputRange!(R, ubyte) && isInputStream!InputStream)
{
	// allocate internal jump table to optimize the number of comparisons
	size_t[8] nmatchoffsetbuffer = void;
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
	Buffer* bufferobj;
	bufferobj = new Buffer;
	scope (exit) () @trusted {
		static if (__VERSION__ >= 2079) {
			import core.memory : __delete;
			__delete(bufferobj);
		} else mixin("delete bufferobj;");
	} ();
	auto buf = bufferobj.bytes[];

	ulong bytes_read = 0;

	void skip2(size_t nbytes)
	{
		bytes_read += nbytes;
		stream.skip(nbytes);
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
		for (i = 0; i < str.length; i++) {
			auto ch = str[i];
			// if we have a mismatch, use the jump table to try other possible prefixes
			// of the marker
			while( nmatched > 0 && ch != end_marker[nmatched] )
				nmatched -= nmatchoffset[nmatched];

			// if we then have a match, increase the match count and test for full match
			if (ch == end_marker[nmatched])
				if (++nmatched == end_marker.length) {
					i++;
					break;
				}
		}


		// write out any false match part of previous blocks
		if( nmatched_start > 0 ){
			if( nmatched <= i ) () @trusted { dst.put(end_marker[0 .. nmatched_start]); } ();
			else () @trusted { dst.put(end_marker[0 .. nmatched_start-nmatched+i]); } ();
		}

		// write out any unmatched part of the current block
		if( nmatched < i ) () @trusted { dst.put(str[0 .. i-nmatched]); } ();

		// got a full, match => out
		if (nmatched >= end_marker.length) {
			// in case of a full match skip data in the stream until the end of
			// the marker
			skip2(i - nread);
			return;
		}

		// otherwise skip this block in the stream
		skip2(str.length - nread);
	}

	enforce(false, "Reached EOF before reaching end marker.");
}

private void skip(InputStream)(InputStream str, ulong count)
	if (isInputStream!InputStream)
{
	ubyte[256] buf = void;
	while (count > 0) {
		auto n = min(buf.length, count);
		str.read(buf[0 .. n], IOMode.all);
		count -= n;
	}
}

private class NoPeekProxy(InputStream) : ProxyStream
	if (isInputStream!InputStream)
{
	this(InputStream stream)
	{
		import vibe.internal.interfaceproxy : InterfaceProxy, interfaceProxy;
		super(interfaceProxy!(.InputStream)(stream), InterfaceProxy!OutputStream.init, true);
	}

	override const(ubyte)[] peek() { return null; }
}
