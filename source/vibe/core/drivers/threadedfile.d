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

import std.algorithm;
import std.conv;
import std.exception;
import std.string;

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

		enum _S_IREAD = 0x0100;          /* read permission, owner */
		enum _S_IWRITE = 0x0080;          /* write permission, owner */
		alias struct_stat stat_t;
	}
}

private {
	enum O_BINARY = 0x8000;
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
	}
	
	this(string path, FileMode mode)
	{
		m_path = Path(path);
		m_mode = mode;
		final switch(m_mode){
			case FileMode.Read:
				m_fileDescriptor = open(path.toStringz(), O_RDONLY|O_BINARY);
				break;
			case FileMode.CreateTrunc:
				m_fileDescriptor = open(path.toStringz(), O_WRONLY|O_CREAT|O_TRUNC|O_BINARY, octal!644);
				break;
			case FileMode.Append:
				m_fileDescriptor = open(path.toStringz(), O_WRONLY|O_CREAT|O_APPEND|O_BINARY, octal!644);
				break;
		}
		if( m_fileDescriptor < 0 )
			throw new Exception("Failed to open '"~path~"' for " ~ (m_mode == FileMode.Read ?		 "reading.":
			                                                        m_mode == FileMode.CreateTrunc ? "writing." : 
			                                                                                         "appending."));
			
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
					chmod(path.toStringz(), S_IREAD|S_IWRITE);
			}
		}
		lseek(m_fileDescriptor, 0, SEEK_SET);
		
		logDebug("opened file %s with %d bytes as %d", path, m_size, m_fileDescriptor);
	}
	
	@property int fd() { return m_fileDescriptor; }
	@property Path path() const { return m_path; }
	@property ulong size() const { return m_size; }
	@property bool readable() const { return m_mode == FileMode.Read; }
	@property bool writable() const { return m_mode != FileMode.Read; }

	void acquire()
	{
		// TODO: store the owner and throw an exception if illegal calls happen
	}

	void release()
	{
		// TODO: store the owner and throw an exception if illegal calls happen
	}

	bool isOwner()
	{
		// TODO: really check ownership
		return true;
	}

	void seek(ulong offset)
	{
		enforce(.lseek(m_fileDescriptor, offset, SEEK_SET) == offset, "Failed to seek in file.");
		m_ptr = offset;
	}
	
	void close()
	{
		if( m_fileDescriptor != -1 ){
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
		enforce(dst.length <= leastSize);
		enforce(.read(m_fileDescriptor, dst.ptr, dst.length) == dst.length, "Failed to read data from disk.");
		m_ptr += dst.length;
	}

	alias Stream.write write;
	void write(in ubyte[] bytes, bool do_flush = true)
	{
		assert(this.writable);
		enforce(.write(m_fileDescriptor, bytes.ptr, bytes.length) == bytes.length, "Failed to write data to disk.");
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
