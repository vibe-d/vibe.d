/**
	Standard I/O streams

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Eric Cornelius
*/
module vibe.stream.stdio;

import vibe.core.core;
import vibe.core.stream;

import std.stdio;

/**
	OutputStream that wraps a standard File object
*/
class StdOutStreamImpl : OutputStream {
	private {
		File _impl;
	}

	this(File f) {
		_impl = f;
	}

	void finalize() {
		flush();
        }

	void flush() {
		_impl.flush();
	}

	void write(in ubyte[] bytes) {
		_impl.rawWrite(bytes);
	}

	void write(InputStream input, ulong nbytes = 0) {
		writeDefault(input, nbytes);
	}
}


/**
	InputStream that wraps a standard File object
*/
class StdInStreamImpl : InputStream {
	private {
		File _impl;
		ubyte buf[4096];
		ubyte[] slice;
	}

	this(File f) { 
		_impl = f;
	}

	void finalize() { }

	bool empty() {
		return !_impl.isOpen || _impl.eof();
	}

	ulong leastSize() {
		if (slice.length > 0) return slice.length;
		if (empty()) return 0;

		slice = _impl.rawRead(buf);
		return slice.length;
	}

	bool dataAvailableForRead() {
		return leastSize() > 0;
	}

	const(ubyte)[] peek() {
		leastSize();
		return slice;
	}

	void read(ubyte[] dst) {
		dst[0 .. $] = slice[0 .. dst.length];
		slice = slice[dst.length .. $];
	}
}

/**
	OutputStream that writes to stdout
*/
final class StdoutStream : StdOutStreamImpl {
	this() {
		super(stdout);
	}
}

/**
	OutputStream that writes to stderr
*/
final class StderrStream : StdOutStreamImpl {
	this() {
		super(stderr);
	}
}

/**
	InputStream that reads from stdin
*/
final class StdinStream : StdInStreamImpl {
	this() {
		super(stdin);
	}
}
