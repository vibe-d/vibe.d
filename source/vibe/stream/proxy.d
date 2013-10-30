/**
	Stream proxy facilities.

	Copyright: © 2013 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.stream.proxy;

public import vibe.core.stream;

import std.exception;


/**
	Provides a way to access varying streams using a constant stream reference.
*/
class ProxyStream : Stream {
	private {
		Stream m_underlying;
	}

	/// The stream that is wrapped by this one
	@property inout(Stream) underlying() inout { return m_underlying; }
	/// ditto
	@property void underlying(Stream value) { m_underlying = value; }

	@property bool empty() { return m_underlying ? m_underlying.empty : true; }

	@property ulong leastSize() { return m_underlying ? m_underlying.leastSize : 0; }

	@property bool dataAvailableForRead() { return m_underlying ? m_underlying.dataAvailableForRead : false; }

	const(ubyte)[] peek() { return m_underlying.peek(); }

	void read(ubyte[] dst) { m_underlying.read(dst); }

	alias Stream.write write;
	void write(in ubyte[] bytes) { import vibe.core.log; logDebug("WRITE: %s", cast(string)bytes); m_underlying.write(bytes); }

	void flush() { m_underlying.flush(); }

	void finalize() { m_underlying.finalize(); }

	void write(InputStream stream, ulong nbytes = 0) { m_underlying.write(stream, nbytes); }
}
