/**
	Utility definitions for socket handling.

	Copyright: © 2013 RejectedSoftware e.K.
	Authors: Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
*/
module vibe.core.drivers.utils;

import vibe.internal.exception : enforce;
import std.exception : ErrnoException;

version (Windows) {
	import core.sys.windows.windows;
	import core.sys.windows.winsock2;

	alias EWOULDBLOCK = WSAEWOULDBLOCK;

	extern(System) DWORD FormatMessageW(DWORD dwFlags, const(void)* lpSource, DWORD dwMessageId, DWORD dwLanguageId, LPWSTR lpBuffer, DWORD nSize, void* Arguments);

	class WSAErrorException : Exception {
		int error;

		this(string message, string file = __FILE__, size_t line = __LINE__)
		{
			error = WSAGetLastError();
			this(message, error, file, line);
		}

		this(string message, int error, string file = __FILE__, size_t line = __LINE__)
		{
			import std.string : format;
			ushort* errmsg;
			FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER|FORMAT_MESSAGE_FROM_SYSTEM|FORMAT_MESSAGE_IGNORE_INSERTS,
						   null, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), cast(LPWSTR)&errmsg, 0, null);
			size_t len = 0;
			while (errmsg[len]) len++;
			auto errmsgd = (cast(wchar[])errmsg[0 .. len]).idup;
			LocalFree(errmsg);
			super(format("%s: %s (%s)", message, errmsgd, error), file, line);
		}
	}

	alias SystemSocketException = WSAErrorException;
} else alias SystemSocketException = ErrnoException;

import core.sys.posix.sys.socket;
static if (!is(typeof(SO_REUSEPORT))) {
	version (linux) enum SO_REUSEPORT = 15;
	else enum SO_REUSEPORT = 0x200;
}

T socketEnforce(T)(T value, lazy string msg = null, string file = __FILE__, size_t line = __LINE__)
@trusted {
	return enforce!SystemSocketException(value, msg, file, line);
}
