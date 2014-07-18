/**
	Multicaster Stream - multicasts an input stream to multiple output streams

	Copyright: © 2014 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Eric Cornelius
*/
module vibe.stream.multicaster;

import vibe.core.core;
import vibe.core.stream;
import vibe.utils.memory;

import std.exception;

class MulticasterStream : OutputStream {
	private {
		OutputStream[] m_outputs;
	}

	this(OutputStream[] outputs ...) { 
		// NOTE: investigate .dup dmd workaround
		m_outputs = outputs.dup;
	}

	void finalize() {
		flush();
	}

	void flush() {
		foreach (output; m_outputs) {
			output.flush();
		}
	}

	void write(in ubyte[] bytes) {
		foreach (output; m_outputs) {
			output.write(bytes);
		}
	}

	void write(InputStream source, ulong nbytes = 0) {
	        static struct Buffer { ubyte[64*1024] bytes = void; }
        	auto bufferobj = FreeListRef!(Buffer, false)();
	        auto buffer = bufferobj.bytes[];

	        auto least_size = source.leastSize;
	        while (nbytes > 0 || least_size > 0) {
			size_t chunk = min(nbytes > 0 ? nbytes : ulong.max, least_size, buffer.length);
			assert(chunk > 0, "leastSize returned zero for non-empty stream.");
			source.read(buffer[0 .. chunk]);

			foreach (output; m_outputs) {
				output.write(buffer[0 .. chunk]);
			}

			if (nbytes > 0) nbytes -= chunk;

			least_size = source.leastSize;
			if (!least_size) {
				enforce(nbytes == 0, "Reading past end of input.");
				break;
			}
		}
		foreach (output; m_outputs) {
			output.flush();
		}
	}
}
