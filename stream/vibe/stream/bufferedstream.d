/** Implements a buffered random access wrapper stream.

	Copyright: © 2020-2021 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.bufferedstream;

import vibe.core.stream;

import std.algorithm;
import std.traits : Unqual;


/** Creates a new buffered stream wrapper.

	Params:
		stream = The stream that is going to be wrapped
		buffer_size = Size of a single buffer segment
		buffer_count = Number of buffer segments
*/
auto bufferedStream(S)(S stream, size_t buffer_size = 16_384, size_t buffer_count = 4)
	if (isRandomAccessStream!S)
	in { assert(buffer_size > 0 && buffer_count > 0); }
do {
	return BufferedStream!S(stream.move, buffer_size, buffer_count);
}


/** Random access stream that provides buffering on top of a wrapped stream.

	The source stream is logically split up into chunks of equal size, where
	a defined maximum number of those chunks can be cached in memory. Cached
	chunks are managed using a LRU strategy.
*/
struct BufferedStream(S) {
	import std.experimental.allocator;
	import std.experimental.allocator.mallocator;

	private static struct State {
		S stream;
		int refCount = 1;
		ulong ptr;
		ulong size;
		size_t bufferSize;
		int bufferSizeBits;
		Buffer[] buffers;
		ulong accessCount;
		ubyte[] buffermemory;
		// slice into the matching chunk buffer, beginning at the current ptr
		ubyte[] peekBuffer;

		this(size_t buffer_size, size_t buffer_count, S stream)
		{
			import core.bitop : bsr;

			this.bufferSizeBits = max(bsr(buffer_size), 1);
			this.bufferSize = 1 << this.bufferSizeBits;
			this.buffers = Mallocator.instance.makeArray!Buffer(buffer_count);
			this.buffermemory = Mallocator.instance.makeArray!ubyte(buffer_count * buffer_size);
			foreach (i, ref b; this.buffers)
				b.memory = this.buffermemory[i * buffer_size .. (i+1) * buffer_size];
			this.size = stream.size;
			this.stream = stream.move;
		}

		~this()
		{
			if (this.buffers is null) return;

			if (this.stream.writable) {
				try flush();
				catch (Exception e) {
					() @trusted {
						Mallocator.instance.dispose(this.buffermemory);
						Mallocator.instance.dispose(this.buffers);
						this.buffermemory = null;
						this.buffers = null;
						destroy(stream);
					} ();
					throw e;
				}
			}

			() @trusted {
				Mallocator.instance.dispose(this.buffermemory);
				Mallocator.instance.dispose(this.buffers);
			} ();
		}

		@disable this(this);

		void flush()
		{
			foreach (i; 0 .. this.buffers.length)
				flushBuffer(i);
			this.stream.flush();
		}

		private size_t bufferChunk(ulong chunk_index)
		{
			auto idx = this.buffers.countUntil!((ref b) => b.chunk == chunk_index);
			if (idx >= 0) return idx;

			auto offset = chunk_index << this.bufferSizeBits;
			if (offset >= this.size) this.size = this.stream.size;
			if (offset >= this.size) throw new Exception("Reading past end of stream.");

			auto newidx = this.buffers.minIndex!((ref a, ref b) => a.lastAccess < b.lastAccess);
			flushBuffer(newidx);

			// clear peek buffer in case it points to the reused buffer
			if (this.buffers[newidx].chunk == this.ptr >> this.bufferSizeBits)
				this.peekBuffer = null;
			this.buffers[newidx].fill = 0;
			this.buffers[newidx].chunk = chunk_index;
			fillBuffer(newidx, min(this.size - (chunk_index << this.bufferSizeBits), this.bufferSize));
			return newidx;
		}

		private void fillBuffer(size_t buffer, size_t size)
		{
			auto b = &this.buffers[buffer];
			if (size <= b.fill) return;
			assert(size <= this.bufferSize);

			this.stream.seek((b.chunk << this.bufferSizeBits) + b.fill);
			this.stream.read(b.memory[b.fill .. size]);
			b.fill = size;
			touchBuffer(buffer);
		}

		private void flushBuffer(size_t buffer)
		{
			auto b = &this.buffers[buffer];
			if (!b.fill || !b.dirty) return;
			this.stream.seek(b.chunk << this.bufferSizeBits);
			this.stream.write(b.memory[0 .. b.fill]);
			if ((b.chunk << this.bufferSizeBits) + b.fill > this.size)
				this.size = (b.chunk << this.bufferSizeBits) + b.fill;
			b.dirty = false;
			touchBuffer(buffer);
		}

		private void touchBuffer(size_t buffer)
		{
			this.buffers[buffer].lastAccess = ++this.accessCount;
		}

		private void iterateChunks(B)(ulong offset, scope B[] bytes,
			scope bool delegate(ulong offset, ulong chunk, scope B[] bytes, sizediff_t buffer, size_t buffer_begin, size_t buffer_end) @safe del)
		@safe {
			doIterateChunks!B(offset, bytes, del);
		}

		private void iterateChunks(B)(ulong offset, scope B[] bytes,
			scope bool delegate(ulong offset, ulong chunk, scope B[] bytes, sizediff_t buffer, size_t buffer_begin, size_t buffer_end) @safe nothrow del)
		@safe nothrow {
			doIterateChunks!B(offset, bytes, del);
		}

		private void doIterateChunks(B, DEL)(ulong offset, scope B[] bytes,
			scope DEL del)
		@safe {
			auto begin = offset;
			auto end = offset + bytes.length;

			if (bytes.length == 0) return;

			ulong chunk_begin, chunk_end, chunk_off;
			chunk_begin = begin >> this.bufferSizeBits;
			chunk_end = (end + this.bufferSize - 1) >> this.bufferSizeBits;
			chunk_off = chunk_begin << this.bufferSizeBits;

			foreach (i; chunk_begin .. chunk_end) {
				auto cstart = max(chunk_off, begin);
				auto cend = min(chunk_off + this.bufferSize, end);
				assert(cend > cstart);

				auto buf = this.buffers.countUntil!((ref b) => b.chunk == i);
				auto buf_begin = cast(size_t)(cstart - chunk_off);
				auto buf_end = cast(size_t)(cend - chunk_off);

				auto bytes_chunk = bytes[cast(size_t)(cstart - begin) .. cast(size_t)(cend - begin)];

				if (!del(cstart, i, bytes_chunk, buf, buf_begin, buf_end))
					break;

				chunk_off += this.bufferSize;
			}
		}
	}

	private {
		// makes the stream copyable and makes it small enough to be put into
		// a stream proxy
		State* m_state;
	}

	private this(S stream, size_t buffer_size, size_t buffer_count)
	@safe {
		m_state = new State(buffer_size, buffer_count, stream.move);
	}

	this(this)
	{
		if (m_state) m_state.refCount++;
	}

	~this()
	@safe {
		if (m_state) {
			if (!--m_state.refCount) {
				auto st = m_state;
				m_state = null;
				destroy(*st);
			}
		}
	}

	@property bool empty() @blocking { return state.ptr >= state.size; }
	@property ulong leastSize() @blocking { return state.size - state.ptr; }
	@property bool dataAvailableForRead() { return peek().length > 0; }
	@property ulong size() const nothrow { return state.size; }
	@property bool readable() const nothrow { return state.stream.readable; }
	@property bool writable() const nothrow { return state.stream.writable; }

	@property ref inout(S) underlying() inout { return state.stream; }

	static if (isClosableRandomAccessStream!S) {
		void close()
		{
			sync();
			state.stream.close();
		}

		@property bool isOpen()
		const {
			return state.stream.isOpen();
		}
	}

	static if (is(typeof(S.init.truncate(ulong.init))))
		void truncate(ulong size)
		{
			sync();
			state.stream.truncate(size);
			state.size = size;
			state.peekBuffer = null;
		}

	const(ubyte)[] peek()
	{
		return state.peekBuffer;
	}

	size_t read(scope ubyte[] dst, IOMode mode)
	@blocking {
		if (dst.length <= state.peekBuffer.length) {
			dst[] = state.peekBuffer[0 .. dst.length];
			state.peekBuffer = state.peekBuffer[dst.length .. $];
			state.ptr += dst.length;
			return dst.length;
		}

		size_t nread = 0;

		// update size if a read past EOF is expected
		if (state.ptr + dst.length > state.size) state.size = state.stream.size;

		ubyte[] newpeek;

		state.iterateChunks!ubyte(state.ptr, dst, (offset, chunk, scope dst_chunk, buf, buf_begin, buf_end) {
			if (buf < 0) {
				if (mode == IOMode.immediate) return false;
				if (mode == IOMode.once && nread) return false;
				buf = state.bufferChunk(chunk);
			} else state.touchBuffer(buf);

			if (state.buffers[buf].fill < buf_end) {
				if (mode == IOMode.immediate) return false;
				if (mode == IOMode.once && nread) return false;
				state.fillBuffer(buf, buf_end);
			}

			// the whole of dst_chunk is now in the buffer
			assert((buf_begin & ((1<<state.bufferSizeBits)-1)) == (offset & ((1<<state.bufferSizeBits)-1)));
			assert(dst_chunk.length <= buf_end - buf_begin);
			dst_chunk[] = state.buffers[buf].memory[buf_begin .. buf_begin + dst_chunk.length];
			nread += dst_chunk.length;

			// any remaining buffer space of the last chunk will be used for
			// quick access on the next read
			newpeek = state.buffers[buf].memory[buf_begin + dst_chunk.length .. state.buffers[buf].fill];

			return true;
		});

		if (mode == IOMode.all && dst.length != nread)
			throw new Exception("Reading past end of stream.");

		state.ptr += nread;
		state.peekBuffer = newpeek;

		return nread;
	}

	void read(scope ubyte[] dst) @blocking { auto n = read(dst, IOMode.all); assert(n == dst.length); }

	size_t write(in ubyte[] bytes, IOMode mode)
	@blocking {
		size_t nwritten = 0;

		ubyte[] newpeek;

		state.iterateChunks!(const(ubyte))(state.ptr, bytes, (offset, chunk, scope src_chunk, buf, buf_begin, buf_end) {
			if (buf < 0) { // write through if not buffered
				if (mode == IOMode.immediate) return false;
				if (mode == IOMode.once && nwritten) return false;

				state.stream.seek(offset);
				state.stream.write(src_chunk);
			} else {
				auto b = &state.buffers[buf];
				b.memory[buf_begin .. buf_begin + src_chunk.length] = src_chunk;
				b.fill = max(b.fill, buf_begin + src_chunk.length);
				b.dirty = true;
			}

			nwritten += src_chunk.length;
			if (offset + src_chunk.length > state.size)
				state.size = offset + src_chunk.length;

			// any remaining buffer space of the last chunk will be used for
			// quick access on the next read
			if (buf >= 0)
				newpeek = state.buffers[buf].memory[buf_begin + src_chunk.length .. $];

			return true;
		});

		assert(mode != IOMode.all || nwritten == bytes.length);

		state.ptr += nwritten;
		state.peekBuffer = newpeek;

		return nwritten;
	}

	void write(in ubyte[] bytes) @blocking { auto n = write(bytes, IOMode.all); assert(n == bytes.length); }
	void write(in char[] bytes) @blocking { write(cast(const(ubyte)[])bytes); }

	void flush() @blocking { state.flush(); }

	/** Flushes and releases all buffers and updates the buffer size.

		This forces the buffered view of the source stream to be in sync with
		the actual source stream.
	*/
	void sync()
	@blocking {
		flush();
		foreach (ref b; state.buffers) {
			b.chunk = ulong.max;
			b.fill = 0;
		}
		state.size = state.stream.size;
		state.peekBuffer = null;
	}

	void finalize() @blocking { flush(); }

	void seek(ulong offset)
	nothrow {
		state.ptr = offset;

		if (offset > state.ptr && offset < state.ptr + state.peekBuffer.length) {
			state.peekBuffer = state.peekBuffer[cast(size_t)(offset - state.ptr) .. $];
		} else {
			ubyte[1] dummy;
			state.peekBuffer = null;
			state.iterateChunks!ubyte(offset, dummy[], (offset, chunk, scope bytes, buffer, buffer_begin, buffer_end) @safe nothrow {
				if (buffer >= 0 && buffer_begin < state.buffers[buffer].fill) {
					state.peekBuffer = state.buffers[buffer].memory[buffer_begin .. state.buffers[buffer].fill];
					state.touchBuffer(buffer);
				}
				return true;
			});
		}
	}
	ulong tell() nothrow { return state.ptr; }

	private ref inout(State) state() @trusted nothrow return inout { return *m_state; }
}

mixin validateRandomAccessStream!(BufferedStream!RandomAccessStream);

@safe unittest {
	import std.exception : assertThrown;
	import vibe.stream.memory : createMemoryStream;
	import vibe.stream.operations : readAll;

	auto buf = new ubyte[](256);
	foreach (i, ref b; buf) b = cast(ubyte)i;
	auto str = createMemoryStream(buf, true, 128);
	auto bstr = bufferedStream(str, 16, 4);

	// test empty method
	assert(!bstr.empty);
	bstr.readAll();
	assert(bstr.empty);

	bstr.seek(0);

	ubyte[1] bb;

	// test that each byte is readable
	foreach (i; 0 .. 128) {
		bstr.read(bb);
		assert(bb[0] == i);
	}

	// same in reverse
	foreach_reverse (i; 0 .. 128) {
		bstr.seek(i);
		bstr.read(bb);
		assert(bb[0] == i);
	}

	// the first chunk should be cached now
	assert(bstr.dataAvailableForRead);
	assert(bstr.peek().length == 15);
	assert(bstr.peek()[0] == 1);

	// the last one should not
	bstr.seek(126);
	assert(!bstr.dataAvailableForRead);
	assert(bstr.peek().length == 0);
	assert(bstr.leastSize == 2);

	// a read brings it back
	bstr.read(bb);
	assert(bb[0] == 126);
	assert(bstr.dataAvailableForRead);
	assert(bstr.peek() == [127]);

	// the first to third ones should still be there
	ubyte[3*16-8] mb;
	bstr.seek(0);
	assert(bstr.dataAvailableForRead);
	assert(bstr.read(mb, IOMode.immediate) == mb.length);
	foreach (i, b; mb) assert(i == b);

	// should read only the remaining 8 buffered bytes
	assert(bstr.read(mb, IOMode.immediate) == 8);
	assert(bstr.tell == 3*16);
	bstr.seek(mb.length);

	// should also read only the remaining 8 buffered bytes
	assert(bstr.read(mb, IOMode.once) == 8);
	assert(bstr.tell == 3*16);
	bstr.seek(mb.length);

	// should read the whole buffer, caching the fourth and fifth chunk
	assert(bstr.read(mb, IOMode.all) == mb.length);
	assert(bstr.tell == 2*mb.length);
	foreach (i, b; mb) assert(i + mb.length == b);

	// the first chunk should now be out of cache
	bstr.seek(0);
	assert(!bstr.dataAvailableForRead);

	// reading with immediate should consequently fail
	assert(bstr.read(mb, IOMode.immediate) == 0);

	// the second/third ones should still be in
	bstr.seek(16);
	assert(bstr.dataAvailableForRead);
	bstr.seek(2*16);
	assert(bstr.dataAvailableForRead);

	// reading uncached data followed by cached data should succeed for "once"
	bstr.seek(0);
	assert(bstr.read(mb, IOMode.once) == mb.length);
	foreach (i, b; mb) assert(i == b);

	// the first three and the fifth chunk should now be cached
	bstr.seek(0);
	assert(bstr.dataAvailableForRead);
	bstr.seek(16);
	assert(bstr.dataAvailableForRead);
	bstr.seek(32);
	assert(bstr.dataAvailableForRead);
	bstr.seek(48);
	assert(!bstr.dataAvailableForRead);
	bstr.seek(64);
	assert(bstr.dataAvailableForRead);

	// reading once should read until the end of the cached chunk sequence
	bstr.seek(0);
	assert(bstr.read(mb, IOMode.once) == mb.length);
	foreach (i, b; mb) assert(i == b);

	// produce an EOF error
	bstr.seek(128);
	assertThrown(bstr.read(bb));
	assert(bstr.tell == 128);

	// add more data from the outside
	str.seek(str.size);
	str.write([cast(ubyte)128]);

	// should now succeed
	bstr.read(bb);
	assert(bb[0] == 128);

	// next byte should produce an EOF error again
	assertThrown(bstr.read(bb));

	// add more data from the inside
	bstr.write([ubyte(129)]);

	// should now succeed
	bstr.seek(129);
	bstr.read(bb);
	assert(bb[0] == 129);
	assert(bstr.size == 130);
	assert(str.size == 129);
	bstr.flush();
	assert(str.size == 130);

	// next byte should produce an EOF error again
	bstr.seek(130);
	assertThrown(bstr.read(bb));
	assert(bstr.tell == 130);
	assertThrown(bstr.read(bb, IOMode.once));
	assert(bstr.tell == 130);

	// add more data from the inside (chunk now cached)
	bstr.write([ubyte(130)]);
	assert(bstr.size == 131);
	assert(str.size == 130);

	// should now succeed
	bstr.seek(130);
	bstr.read(bb);
	assert(bb[0] == 130);

	// flush should write though to the file
	bstr.flush();
	assert(str.size == 131);

	// read back the written data from the underlying file
	bstr.sync();
	bstr.seek(129);
	bstr.read(bb);
	assert(bb[0] == 129);
	bstr.read(bb);
	assert(bb[0] == 130);
}

@safe unittest { // regression: write after read causes write to be missed during flush
	import std.exception : assertThrown;
	import vibe.stream.memory : createMemoryStream;
	import vibe.stream.operations : readAll;

	auto buf = new ubyte[](256);
	foreach (i, ref b; buf) b = cast(ubyte)i;
	auto str = createMemoryStream(buf, true, 128);
	auto bstr = bufferedStream(str, 16, 4);

	ubyte[1] ob;
	bstr.read(ob[]);
	assert(ob[0] == 0);
	bstr.seek(0);
	bstr.write([cast(ubyte)1]);
	bstr.seek(0);
	bstr.read(ob[]);
	assert(ob[0] == 1);
	bstr.finalize();
	str.seek(0);
	str.read(ob[]);
	assert(ob[0] == 1);
}

@safe unittest { // regression seeking past end of file within the last chunk
	import std.exception : assertThrown;
	import vibe.stream.memory : createMemoryStream;
	import vibe.stream.operations : readAll;

	auto buf = new ubyte[](256);
	foreach (i, ref b; buf) b = cast(ubyte)i;
	auto str = createMemoryStream(buf, true, 1);
	auto bstr = bufferedStream(str, 16, 4);

	ubyte[1] ob;
	bstr.read(ob[]);
	assert(ob[0] == 0);
	bstr.seek(10);
	bstr.write([cast(ubyte)1]);
	bstr.seek(10);
	bstr.read(ob[]);
	assert(ob[0] == 1);
}

unittest {
	static assert(isTruncatableStream!(BufferedStream!TruncatableStream));
	static assert(isClosableRandomAccessStream!(BufferedStream!ClosableRandomAccessStream));
}

private struct Buffer {
	ulong chunk = ulong.max; // chunk index (offset = chunk * state.bufferSize)
	ubyte[] memory;
	ulong lastAccess;
	size_t fill;
	bool dirty;
}
