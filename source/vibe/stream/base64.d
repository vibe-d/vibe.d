/**
	Base64 encoding routines

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Jan Krüger
*/
module vibe.stream.base64;

import vibe.core.stream;


/**
*/
class Base64OutputStream : OutputStream {
	void write(in ubyte[] bytes, bool do_flush = true)
	{
		assert(false, "Unimplemented");
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		assert(false, "Unimplemented");
	}

	void flush()
	{
		assert(false, "Unimplemented");
	}

	void finalize()
	{
		assert(false, "Unimplemented");
	}
}
