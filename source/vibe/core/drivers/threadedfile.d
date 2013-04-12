/**
	Thread based asynchronous file I/O fallback implementation

	Copyright: © 2012 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.threadedfile;


import vibe.core.log;
import vibe.core.driver;
import vibe.inet.url;
import vibe.utils.string;

import std.algorithm;
import std.conv;
import std.exception;
import std.string;
import core.stdc.errno;

version(Posix){
	import core.sys.posix.fcntl;
	import core.sys.posix.sys.stat;
	import core.sys.posix.unistd;
}
version(Windows){
	import std.c.windows.stat;

	private {
		extern(C){
			alias long off_t;
			int open(in char* name, int mode, ...);
			int chmod(in char* name, int mode);
			int close(int fd);
			int read(int fd, void *buffer, uint count);
			int write(int fd, in void *buffer, uint count);
			off_t lseek(int fd, off_t offset, int whence);
		}
		
		enum O_RDONLY = 0;
		enum O_WRONLY = 1;
		enum O_APPEND = 8;
		enum O_CREAT = 0x0100;
		enum O_TRUNC = 0x0200;
		enum O_BINARY = 0x8000;

		enum _S_IREAD = 0x0100;          /* read permission, owner */
		enum _S_IWRITE = 0x0080;          /* write permission, owner */
		alias struct_stat stat_t;
	}
}
else
{
	enum O_BINARY = 0;
}

private {
	enum SEEK_SET = 0;
	enum SEEK_CUR = 1;
	enum SEEK_END = 2;
}

class ThreadedFileStream : FileStream {
	private {
		int m_fileDescriptor;
		Path m_path;
		ulong m_size;
		ulong m_ptr = 0;
		FileMode m_mode;
		bool m_ownFD = true;
	}
	
	this(Path path, FileMode mode)
	{
		auto pathstr = path.toNativeString();
		final switch(mode){
			case FileMode.Read:
				m_fileDescriptor = open(pathstr.toStringz(), O_RDONLY|O_BINARY);
				break;
			case FileMode.ReadWrite:
				m_fileDescriptor = open(pathstr.toStringz(), O_BINARY);
				break;
			case FileMode.CreateTrunc:
				m_fileDescriptor = open(pathstr.toStringz(), O_WRONLY|O_CREAT|O_TRUNC|O_BINARY, octal!644);
				break;
			case FileMode.Append:
				m_fileDescriptor = open(pathstr.toStringz(), O_WRONLY|O_CREAT|O_APPEND|O_BINARY, octal!644);
				break;
		}
		if( m_fileDescriptor < 0 )
			//throw new Exception(format("Failed to open '%s' with %s: %d", pathstr, cast(int)mode, errno));
			throw new Exception("Failed to open file '"~pathstr~"'.");
		
		this(m_fileDescriptor, path, mode);
	}

	this(int fd, Path path, FileMode mode)
	{
		assert(fd >= 0);
		m_fileDescriptor = fd;
		m_path = path;
		m_mode = mode;

		version(linux){
			// stat_t seems to be defined wrong on linux/64
			m_size = .lseek(m_fileDescriptor, 0, SEEK_END);
		} else {
			stat_t st;
			fstat(m_fileDescriptor, &st);
			m_size = st.st_size;
			
			// (at least) on windows, the created file is write protected
			version(Windows){
				if( mode == FileMode.CreateTrunc )
					chmod(path.toNativeString().toStringz(), S_IREAD|S_IWRITE);
			}
		}
		lseek(m_fileDescriptor, 0, SEEK_SET);
		
		logDebug("opened file %s with %d bytes as %d", path.toNativeString(), m_size, m_fileDescriptor);
	}

	~this()
	{
		close();
	}
	
	@property int fd() { return m_fileDescriptor; }
	@property Path path() const { return m_path; }
	@property ulong size() const { return m_size; }
	@property bool readable() const { return m_mode != FileMode.Append; }
	@property bool writable() const { return m_mode != FileMode.Read; }

	void acquire()
	{
		// TODO: store the owner and throw an exception if illegal calls happen
	}

	void release()
	{
		// TODO: store the owner and throw an exception if illegal calls happen
	}

	bool amOwner()
	{
		// TODO: really check ownership
		return true;
	}

	void takeOwnershipOfFD()
	{
		enforce(m_ownFD);
		m_ownFD = false;
	}

	void seek(ulong offset)
	{
		enforce(.lseek(m_fileDescriptor, offset, SEEK_SET) == offset, "Failed to seek in file.");
		m_ptr = offset;
	}

	ulong tell() { return m_ptr; }
	
	void close()
	{
		if( m_fileDescriptor != -1 && m_ownFD ){
			.close(m_fileDescriptor);
			m_fileDescriptor = -1;
		}
	}

	@property bool empty() const { assert(this.readable); return m_ptr >= m_size; }
	@property ulong leastSize() const { assert(this.readable); return m_size - m_ptr; }
	@property bool dataAvailableForRead() { return true; }

	const(ubyte)[] peek()
	{
		return null;
	}

	void read(ubyte[] dst)
	{
		assert(this.readable);
		assert(dst.length <= int.max);
		enforce(dst.length <= leastSize);
		enforce(.read(m_fileDescriptor, dst.ptr, cast(int)dst.length) == dst.length, "Failed to read data from disk.");
		m_ptr += dst.length;
	}

	alias Stream.write write;
	void write(in ubyte[] bytes, bool do_flush = true)
	{
		assert(this.writable);
		assert(bytes.length <= int.max);
		auto ret = .write(m_fileDescriptor, bytes.ptr, cast(int)bytes.length);
		enforce(ret == bytes.length, "Failed to write data to disk."~to!string(bytes.length)~" "~to!string(errno)~" "~to!string(ret)~" "~to!string(m_fileDescriptor));
		m_ptr += bytes.length;
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}

	void flush()
	{
		assert(this.writable);
	}

	void finalize()
	{
		flush();
	}
}
