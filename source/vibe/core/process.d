/**
	Process spawning and controlling

	Copyright: © 2012 RejectedSoftware e.K.
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.process;

import vibe.core.log;

import std.array;
import std.exception;
import std.utf;
import core.sys.windows.windows;

version(Windows)
{
	private extern(Windows){
		struct SECURITY_ATTRIBUTES;
		struct STARTUPINFOW {
			DWORD  cb;
			LPWSTR lpReserved;
			LPWSTR lpDesktop;
			LPWSTR lpTitle;
			DWORD  dwX;
			DWORD  dwY;
			DWORD  dwXSize;
			DWORD  dwYSize;
			DWORD  dwXCountChars;
			DWORD  dwYCountChars;
			DWORD  dwFillAttribute;
			DWORD  dwFlags;
			WORD   wShowWindow;
			WORD   cbReserved2;
			BYTE* lpReserved2;
			HANDLE hStdInput;
			HANDLE hStdOutput;
			HANDLE hStdError;
		}

		struct PROCESS_INFORMATION {
			HANDLE hProcess;
			HANDLE hThread;
			DWORD dwProcessId;
			DWORD dwThreadId;
		}

		BOOL CreateProcessW(
			LPCWSTR lpApplicationName,
  			LPWSTR lpCommandLine,
  			SECURITY_ATTRIBUTES* lpProcessAttributes,
  			SECURITY_ATTRIBUTES* lpThreadAttributes,
  			BOOL bInheritHandles,
  			DWORD dwCreationFlags,
  			void* lpEnvironment,
  			LPCWSTR lpCurrentDirectory,
  			STARTUPINFOW* lpStartupInfo,
  			PROCESS_INFORMATION* lpProcessInformation);
	}
}


Process spawnProcess(string executable, string[] args, string working_dir)
{
	version(Windows){
		auto cmdlin = appender!(wchar[])();
		cmdlin.put("cmd.exe /c \"");
		cmdlin.put(executable);
		cmdlin.put("\" ");
		foreach( p; args ){
			cmdlin.put('"');
			cmdlin.put(p);
			cmdlin.put("\" ");
		}
		cmdlin.put('\0');
		cmdlin.put("notepad.exe");

		logInfo("Spawning '%s' in '%s'", cmdlin.data(), working_dir);
		PROCESS_INFORMATION pi;
		STARTUPINFOW si;
		si.cb = STARTUPINFOW.sizeof;
		auto succ = CreateProcessW(null, cmdlin.data().ptr,
			null, null, true, 0, null, toUTF16z(working_dir), &si, &pi);
		logInfo("result %s: %s", succ, GetLastError());
		enforce(succ, "Failed to spawn process.");
		logInfo("Spawned", cmdlin.data());

		CloseHandle(pi.hProcess);
		CloseHandle(pi.hThread);
		return new Process(pi.dwProcessId);
	} else {
		assert(false);
	}
}

class Process {
	private {
		int m_pid;
	}

	this(int pid)
	{
		m_pid = pid;
	}

	@property int id() const { return m_pid; }

	void term()
	{
		version(Posix){
			assert(false);
		} else {
			assert(false);
		}
	}
}