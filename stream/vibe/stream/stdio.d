/**
	Standard I/O streams

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig, Eric Cornelius
*/
module vibe.stream.stdio;

import vibe.core.core;
import vibe.core.stream;
import vibe.stream.taskpipe;

import std.stdio;
import core.thread;

import std.exception;

class StdFileStream : ConnectionStream {
	private {
		std.stdio.File m_file;
		TaskPipe m_readPipe;
		TaskPipe m_writePipe;
		Thread m_readThread;
		Thread m_writeThread;
	}

	this(bool read, bool write)
	{
		if (read) m_readPipe = new TaskPipe;
		if (write) m_writePipe = new TaskPipe;
	}

	void setup(std.stdio.File file)
	{
		m_file = file;

		if (m_readPipe) {
			m_readThread = new Thread(&readThreadFunc);
			m_readThread.name = "StdFileStream reader";
			m_readThread.start();
		}

		if (m_writePipe) {
			m_writeThread = new Thread(&writeThreadFunc);
			m_writeThread.name = "StdFileStream writer";
			m_writeThread.start();
		}
	}

	@property std.stdio.File stdFile() { return m_file; }

	override @property bool empty() { enforceReadable(); return m_readPipe.empty; }

	override @property ulong leastSize()
	{
		enforceReadable();
		return m_readPipe.leastSize;
	}

	override @property bool dataAvailableForRead()
	{
		enforceReadable();
		return m_readPipe.dataAvailableForRead;
	}

	override @property bool connected() const { return m_readPipe.connected; }

	override void close() { m_writePipe.close(); }

	override bool waitForData(Duration timeout) { return m_readPipe.waitForData(timeout); }

	override const(ubyte)[] peek()
	{
		enforceReadable();
		return m_readPipe.peek();
	}

	override size_t read(scope ubyte[] dst, IOMode mode)
	{
		enforceReadable();
		return m_readPipe.read(dst, mode);
	}

	alias read = ConnectionStream.read;

	override size_t write(in ubyte[] bytes_, IOMode mode)
	{
		enforceWritable();
		return m_writePipe.write(bytes_, mode);
	}

	alias write = ConnectionStream.write;

	override void flush()
	{
		enforceWritable();
		m_writePipe.flush();
	}

	override void finalize()
	{
		enforceWritable();
		if (!m_writePipe.connected) return;
		flush();
		m_writePipe.finalize();
	}

	void enforceReadable() @safe { enforce(m_readPipe, "Stream is not readable!"); }
	void enforceWritable() @safe { enforce(m_writePipe, "Stream is not writable!"); }

	private void readThreadFunc()
	{
		bool loop_flag = false;
		runTask({
			ubyte[1] buf;
			scope(exit) {
				if (m_file.isOpen) m_file.close();
				m_readPipe.finalize();
				if (loop_flag) exitEventLoop();
				else loop_flag = true;
			}
			while (!m_file.eof) {
				auto data = m_file.rawRead(buf);
				if (!data.length) break;
				m_readPipe.write(data, IOMode.all);
				vibe.core.core.yield();
			}
		});
		if (!loop_flag) {
			loop_flag = true;
			runEventLoop();
		}
	}

	private void writeThreadFunc()
	{
		import std.algorithm : min;

		bool loop_flag = false;
		runTask({
			ubyte[1024] buf;
			scope(exit) {
				if (m_file.isOpen) m_file.close();
				if (loop_flag) exitEventLoop();
				else loop_flag = true;
			}
			while (m_file.isOpen && !m_writePipe.empty) {
				auto len = min(buf.length, m_writePipe.leastSize);
				if (!len) break;
				m_writePipe.read(buf[0 .. len], IOMode.all);
				m_file.rawWrite(buf[0 .. len]);
				vibe.core.core.yield();
			}
		});
		if (!loop_flag) {
			loop_flag = true;
			runEventLoop();
		}
	}
}

/**
	OutputStream that writes to stdout
*/
final class StdoutStream : StdFileStream {
	this() {
		super(false, true);
		setup(stdout);
	}
}

/**
	OutputStream that writes to stderr
*/
final class StderrStream : StdFileStream {
	this() {
		super(false, true);
		setup(stderr);
	}
}

/**
	InputStream that reads from stdin
*/
final class StdinStream : StdFileStream {
	this() {
		super(true, false);
		setup(stdin);
	}
}
