/** Random access stream that caches a source input stream on disk.

	Copyright: © 2023 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.cached;

import vibe.core.file;
import vibe.core.log;
import vibe.core.path;
import vibe.core.stream;

import std.typecons : Flag, No, Yes;


/** Creates a new `CachedStream` instance.

	Data will be read as needed from the source stream sequentially and gets
	stored in the local file for random access. Note that the reported size
	of the stream may change for source streams that do not report their full
	size through the `leastSize` property.

	Also note that when making the cached file writable, parts of the file that
	have not yet been read from the source stream will get overwritten after
	write operations to the cached file. Write operations should ideally only be
	made after reading the complete source stream.

	Params:
		source = The source input stream to read from
		writable = Optional flag to make the cached file writable
		cached_file_path = Explicit path for storing the cached file - if not
			given, uses a temporary file that gets deleted upon close
*/
CachedFileStream!InputStream createCachedFileStream(InputStream)(InputStream source, Flag!"writable" writable = No.writable)
	if (isInputStream!InputStream)
{
	return CachedFileStream!InputStream(source, writable, NativePath.init);
}
/// ditto
CachedFileStream!InputStream createCachedFileStream(InputStream)(InputStream source, NativePath cached_file_path, Flag!"writable" writable = No.writable)
	if (isInputStream!InputStream)
{
	return CachedFileStream!InputStream(source, writable, cached_file_path);
}


/** File backed cached random access stream wrapper.

	See_also: `createCachedFileStream`
*/
struct CachedFileStream(InputStream)
	if (isInputStream!InputStream)
{
	import std.algorithm.comparison : max, min;

	enum outputStreamVersion = 2;

	private static struct CTX {
		ulong readPtr;
		ulong size;
	}

	private {
		InputStream m_source;
		FileStream m_cachedFile;
		CTX* m_ctx;
		bool m_canWrite;
		bool m_deleteOnClose;
	}

	private this(InputStream source, bool writable, NativePath cached_file_path)
	{
		m_source = source;
		m_canWrite = writable;
		m_ctx = new CTX;
		m_ctx.size = source.leastSize;

		if (cached_file_path == NativePath.init) {
			m_deleteOnClose = true;
			m_cachedFile = createTempFile();
		} else m_cachedFile = openFile(cached_file_path, FileMode.createTrunc);
	}

	@property int fd() const nothrow { return m_cachedFile.fd; }
	@property NativePath path() const nothrow { return m_cachedFile.path; }
	@property bool isOpen() const nothrow { return m_cachedFile.isOpen; }
	@property ulong size() const nothrow { return m_ctx ? max(m_cachedFile.size, m_ctx.size) : 0; }
	@property bool readable() const nothrow { return true; }
	@property bool writable() const nothrow { return m_canWrite; }
	@property ulong leastSize()
	@blocking {
		auto pos = tell();
		auto size = size();
		if (pos > size) return 0;
		return size - pos;
	}
	@property bool dataAvailableForRead()
	{
		if (!m_ctx)
			return false;
		if (m_cachedFile.dataAvailableForRead)
			return true;
		if (tell() == m_ctx.readPtr && m_source.dataAvailableForRead)
			return true;
		return false;
	}
	@property bool empty() @blocking { return leastSize() == 0; }

	void close()
	@blocking {
		bool was_open = m_cachedFile.isOpen;
		NativePath remove_path;
		if (was_open) remove_path = m_cachedFile.path;

		m_cachedFile.close();
		if (was_open && m_deleteOnClose) {
			try removeFile(remove_path);
			catch (Exception e) logException(e, "Failed to remove temporary cached stream file");
		}
	}

	void truncate(ulong size) @blocking { m_cachedFile.truncate(size); }
	void seek(ulong offset)
	@blocking {
		readUpTo(offset);
		m_cachedFile.seek(offset);
	}

	ulong tell() nothrow { return m_cachedFile.tell(); }

	size_t write(scope const(ubyte)[] bytes, IOMode mode) @blocking { return m_cachedFile.write(bytes, mode); }
	void write(scope const(ubyte)[] bytes) @blocking { auto n = write(bytes, IOMode.all); assert(n == bytes.length); }
	void write(scope const(char)[] bytes) @blocking { write(cast(const(ubyte)[])bytes); }

	void flush() @blocking { m_cachedFile.flush(); }
	void finalize() @blocking { m_cachedFile.flush(); }

	const(ubyte)[] peek()
	{
		if (m_cachedFile.tell == m_ctx.readPtr)
			return m_source.peek;
		return m_cachedFile.peek;
	}

	size_t read(scope ubyte[] dst, IOMode mode)
	@blocking {
		readUpTo(tell() + dst.length);
		return m_cachedFile.read(dst, mode);
	}
	void read(scope ubyte[] dst) @blocking { auto n = read(dst, IOMode.all); assert(n == dst.length); }

	private void readUpTo(ulong offset)
	{
		if (offset <= m_ctx.readPtr) return;

		auto ptr = m_cachedFile.tell;
		scope (exit) m_cachedFile.seek(ptr);

		m_cachedFile.seek(m_ctx.readPtr);

		while (offset > m_ctx.readPtr) {
			auto chunk = min(offset - m_ctx.readPtr, m_source.leastSize);
			if (chunk == 0) break;
			pipe(m_source, m_cachedFile, chunk);
			m_ctx.readPtr += chunk;
			m_ctx.size = m_ctx.readPtr + m_source.leastSize;
		}
	}
}

mixin validateClosableRandomAccessStream!(CachedFileStream!InputStream);

unittest { // basic random access reading
	import vibe.stream.memory : createMemoryStream;
	auto source = createMemoryStream([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
	auto cs = createCachedFileStream(source);
	auto path = cs.path;
	assert(cs.size == 10);

	assert(existsFile(path) && getFileInfo(path).size == 0);

	void testRead(const(ubyte)[] expected)
	{
		auto buf = new ubyte[](expected.length);
		cs.read(buf);
		assert(buf[] == expected[]);
	}

	testRead([1, 2]);
	assert(getFileInfo(path).size == 2);
	assert(cs.size == 10);
	assert(cs.leastSize == 8);

	testRead([3, 4, 5, 6, 7, 8, 9, 10]);
	assert(getFileInfo(path).size == 10);
	assert(cs.empty);

	cs.close();
	assert(!existsFile(path));
}

unittest { // explicit cache file path
	import vibe.stream.memory : createMemoryStream;
	ubyte[] data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
	auto source = createMemoryStream(data);
	auto path = NativePath("test-tmp-cached-file.dat");
	auto cs = createCachedFileStream(source, path);
	assert(existsFile(path));
	ubyte[10] buf;
	cs.read(buf);
	assert(buf[] == data[]);
	cs.close();
	assert(existsFile(path));
	assert(readFile(path) == data);
	removeFile(path);
}

unittest { // write operations during read
	import vibe.stream.memory : createMemoryStream;
	auto source = createMemoryStream([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
	auto cs = createCachedFileStream(source, Yes.writable);
	auto path = cs.path;
	assert(cs.size == 10);

	assert(existsFile(path) && getFileInfo(path).size == 0);

	void testRead(const(ubyte)[] expected)
	{
		auto buf = new ubyte[](expected.length);
		cs.read(buf);
		assert(buf[] == expected[]);
	}

	ubyte[] bts(ubyte[] bts...) { return bts.dup; }

	cs.write(bts(11, 12, 13));
	assert(cs.size == 10);
	testRead([4, 5, 6]);
	cs.seek(0);
	testRead([1, 2, 3, 4, 5, 6]);

	cs.write(bts(14, 15, 16, 17, 18, 19));
	assert(cs.size == 12);
	cs.seek(6);
	testRead([7, 8, 9, 10, 18, 19]);
	cs.close();
}
