/// [internal]
module vibe.internal.win32;

version(Windows):

static if (__VERSION__ >= 2070) {
	public import core.sys.windows.windows;
	public import core.sys.windows.winsock2;
} else {
	public import core.sys.windows.windows;
	public import std.c.windows.windows;
	public import std.c.windows.winsock;

	extern(System) nothrow:
	enum HWND HWND_MESSAGE = cast(HWND)-3;
	enum {
		GWLP_WNDPROC = -4,
		GWLP_HINSTANCE = -6,
		GWLP_HWNDPARENT = -8,
		GWLP_USERDATA = -21,
		GWLP_ID = -12,
	}

	version(Win32){ // avoiding linking errors with out-of-the-box dmd
		alias SetWindowLongPtrA = SetWindowLongA;
		alias GetWindowLongPtrA = GetWindowLongA;
	} else {
		LONG_PTR SetWindowLongPtrA(HWND hWnd, int nIndex, LONG_PTR dwNewLong);
		LONG_PTR GetWindowLongPtrA(HWND hWnd, int nIndex);
	}
	LONG_PTR SetWindowLongPtrW(HWND hWnd, int nIndex, LONG_PTR dwNewLong);
	LONG_PTR GetWindowLongPtrW(HWND hWnd, int nIndex);
	LONG_PTR SetWindowLongA(HWND hWnd, int nIndex, LONG dwNewLong);
	LONG_PTR GetWindowLongA(HWND hWnd, int nIndex);

	alias LPOVERLAPPED_COMPLETION_ROUTINE = void function(DWORD, DWORD, OVERLAPPED*);

	HANDLE CreateEventW(SECURITY_ATTRIBUTES* lpEventAttributes, BOOL bManualReset, BOOL bInitialState, LPCWSTR lpName);
	BOOL PostThreadMessageW(DWORD idThread, UINT Msg, WPARAM wParam, LPARAM lParam);
	DWORD MsgWaitForMultipleObjectsEx(DWORD nCount, const(HANDLE) *pHandles, DWORD dwMilliseconds, DWORD dwWakeMask, DWORD dwFlags);
	static if (!is(typeof(&CreateFileW))) BOOL CloseHandle(HANDLE hObject);
	static if (!is(typeof(&CreateFileW))) HANDLE CreateFileW(LPCWSTR lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, LPSECURITY_ATTRIBUTES lpSecurityAttributes,
					   DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
	BOOL WriteFileEx(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite, OVERLAPPED* lpOverlapped,
					 LPOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);
	BOOL ReadFileEx(HANDLE hFile, LPVOID lpBuffer, DWORD nNumberOfBytesToRead, OVERLAPPED* lpOverlapped,
					LPOVERLAPPED_COMPLETION_ROUTINE lpCompletionRoutine);
	BOOL SetEndOfFile(HANDLE hFile);
	BOOL GetOverlappedResult(HANDLE hFile, OVERLAPPED* lpOverlapped, DWORD* lpNumberOfBytesTransferred, BOOL bWait);
	BOOL PostMessageW(HWND hwnd, UINT msg, WPARAM wPara, LPARAM lParam);

	static if (__VERSION__ < 2065) {
		BOOL PeekMessageW(MSG *lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg);
		LONG DispatchMessageW(MSG *lpMsg);

		enum {
			ERROR_ALREADY_EXISTS = 183,
			ERROR_IO_PENDING = 997
		}
	}

	struct FILE_NOTIFY_INFORMATION {
		DWORD NextEntryOffset;
		DWORD Action;
		DWORD FileNameLength;
	    WCHAR _FileName;
	    WCHAR* FileName() { return &_FileName; }
	}

	BOOL ReadDirectoryChangesW(HANDLE hDirectory, void* lpBuffer, DWORD nBufferLength, BOOL bWatchSubtree, DWORD dwNotifyFilter, LPDWORD lpBytesReturned, void* lpOverlapped, void* lpCompletionRoutine);
	HANDLE FindFirstChangeNotificationW(LPCWSTR lpPathName, BOOL bWatchSubtree, DWORD dwNotifyFilter);
	HANDLE FindNextChangeNotification(HANDLE hChangeHandle);


	enum {
		NS_ALL = 0,
		NS_DNS = 12
	}


	struct GUID
	{
		DWORD Data1;
		WORD Data2;
		WORD Data3;
		BYTE[8]  Data4;
	}

	enum WM_USER = 0x0400;

	enum {
		QS_ALLPOSTMESSAGE = 0x0100,
		QS_HOTKEY = 0x0080,
		QS_KEY = 0x0001,
		QS_MOUSEBUTTON = 0x0004,
		QS_MOUSEMOVE = 0x0002,
		QS_PAINT = 0x0020,
		QS_POSTMESSAGE = 0x0008,
		QS_RAWINPUT = 0x0400,
		QS_SENDMESSAGE = 0x0040,
		QS_TIMER = 0x0010,

		QS_MOUSE = (QS_MOUSEMOVE | QS_MOUSEBUTTON),
		QS_INPUT = (QS_MOUSE | QS_KEY | QS_RAWINPUT),
		QS_ALLEVENTS = (QS_INPUT | QS_POSTMESSAGE | QS_TIMER | QS_PAINT | QS_HOTKEY),
		QS_ALLINPUT = (QS_INPUT | QS_POSTMESSAGE | QS_TIMER | QS_PAINT | QS_HOTKEY | QS_SENDMESSAGE),
	}

	enum {
		MWMO_ALERTABLE = 0x0002,
		MWMO_INPUTAVAILABLE = 0x0004,
		MWMO_WAITALL = 0x0001,
	}
}


extern(System) nothrow:

BOOL GetFileSizeEx(HANDLE hFile, long *lpFileSize);


enum {
	FD_READ = 0x0001,
	FD_WRITE = 0x0002,
	FD_OOB = 0x0004,
	FD_ACCEPT = 0x0008,
	FD_CONNECT = 0x0010,
	FD_CLOSE = 0x0020,
	FD_QOS = 0x0040,
	FD_GROUP_QOS = 0x0080,
	FD_ROUTING_INTERFACE_CHANGE = 0x0100,
	FD_ADDRESS_LIST_CHANGE = 0x0200
}


enum {
	WSA_FLAG_OVERLAPPED = 0x01
}

enum {
	WSAPROTOCOL_LEN  = 255,
	MAX_PROTOCOL_CHAIN = 7,
}

enum WSA_IO_PENDING = 997;

struct WSAPROTOCOL_INFOW {
	DWORD            dwServiceFlags1;
	DWORD            dwServiceFlags2;
	DWORD            dwServiceFlags3;
	DWORD            dwServiceFlags4;
	DWORD            dwProviderFlags;
	GUID             ProviderId;
	DWORD            dwCatalogEntryId;
	WSAPROTOCOLCHAIN ProtocolChain;
	int              iVersion;
	int              iAddressFamily;
	int              iMaxSockAddr;
	int              iMinSockAddr;
	int              iSocketType;
	int              iProtocol;
	int              iProtocolMaxOffset;
	int              iNetworkByteOrder;
	int              iSecurityScheme;
	DWORD            dwMessageSize;
	DWORD            dwProviderReserved;
	WCHAR[WSAPROTOCOL_LEN+1] szProtocol;
}

struct WSAPROTOCOLCHAIN {
	int ChainLen;
	DWORD[MAX_PROTOCOL_CHAIN] ChainEntries;
}

struct WSABUF {
	size_t   len;
	ubyte *buf;
}

struct ADDRINFOEXW {
	int ai_flags;
	int ai_family;
	int ai_socktype;
	int ai_protocol;
	size_t ai_addrlen;
	LPCWSTR ai_canonname;
	sockaddr* ai_addr;
	void* ai_blob;
	size_t ai_bloblen;
	GUID* ai_provider;
	ADDRINFOEXW* ai_next;
}

struct ADDRINFOA {
	int ai_flags;
	int ai_family;
	int ai_socktype;
	int ai_protocol;
	size_t ai_addrlen;
	LPSTR ai_canonname;
	sockaddr* ai_addr;
	ADDRINFOA* ai_next;
}

struct ADDRINFOW {
	int ai_flags;
	int ai_family;
	int ai_socktype;
	int ai_protocol;
	size_t ai_addrlen;
	LPWSTR ai_canonname;
	sockaddr* ai_addr;
	ADDRINFOW* ai_next;
}

struct WSAPROTOCOL_INFO {
	DWORD            dwServiceFlags1;
	DWORD            dwServiceFlags2;
	DWORD            dwServiceFlags3;
	DWORD            dwServiceFlags4;
	DWORD            dwProviderFlags;
	GUID             ProviderId;
	DWORD            dwCatalogEntryId;
	WSAPROTOCOLCHAIN ProtocolChain;
	int              iVersion;
	int              iAddressFamily;
	int              iMaxSockAddr;
	int              iMinSockAddr;
	int              iSocketType;
	int              iProtocol;
	int              iProtocolMaxOffset;
	int              iNetworkByteOrder;
	int              iSecurityScheme;
	DWORD            dwMessageSize;
	DWORD            dwProviderReserved;
	CHAR[WSAPROTOCOL_LEN+1] szProtocol;
}
alias SOCKADDR = sockaddr;

alias LPWSAOVERLAPPED_COMPLETION_ROUTINEX = void function(DWORD, DWORD, WSAOVERLAPPEDX*, DWORD);
alias LPLOOKUPSERVICE_COMPLETION_ROUTINE = void function(DWORD, DWORD, WSAOVERLAPPEDX*);
alias LPCONDITIONPROC = void*;
alias LPTRANSMIT_FILE_BUFFERS = void*;

SOCKET WSAAccept(SOCKET s, sockaddr *addr, INT* addrlen, LPCONDITIONPROC lpfnCondition, DWORD_PTR dwCallbackData);
int WSAAsyncSelect(SOCKET s, HWND hWnd, uint wMsg, sizediff_t lEvent);
SOCKET WSASocketW(int af, int type, int protocol, WSAPROTOCOL_INFOW *lpProtocolInfo, uint g, DWORD dwFlags);
int WSARecv(SOCKET s, WSABUF* lpBuffers, DWORD dwBufferCount, DWORD* lpNumberOfBytesRecvd, DWORD* lpFlags, in WSAOVERLAPPEDX* lpOverlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINEX lpCompletionRoutine);
int WSASend(SOCKET s, in WSABUF* lpBuffers, DWORD dwBufferCount, DWORD* lpNumberOfBytesSent, DWORD dwFlags, in WSAOVERLAPPEDX* lpOverlapped, LPWSAOVERLAPPED_COMPLETION_ROUTINEX lpCompletionRoutine);
int WSASendDisconnect(SOCKET s, WSABUF* lpOutboundDisconnectData);
INT WSAStringToAddressA(in LPTSTR AddressString, INT AddressFamily, in WSAPROTOCOL_INFO* lpProtocolInfo, SOCKADDR* lpAddress, INT* lpAddressLength);
INT WSAStringToAddressW(in LPWSTR AddressString, INT AddressFamily, in WSAPROTOCOL_INFOW* lpProtocolInfo, SOCKADDR* lpAddress, INT* lpAddressLength);
INT WSAAddressToStringW(in SOCKADDR* lpsaAddress, DWORD dwAddressLength, in WSAPROTOCOL_INFO* lpProtocolInfo, LPWSTR lpszAddressString, DWORD* lpdwAddressStringLength);
int GetAddrInfoExW(LPCWSTR pName, LPCWSTR pServiceName, DWORD dwNameSpace, GUID* lpNspId, const ADDRINFOEXW *pHints, ADDRINFOEXW **ppResult, timeval *timeout, WSAOVERLAPPEDX* lpOverlapped, LPLOOKUPSERVICE_COMPLETION_ROUTINE lpCompletionRoutine, HANDLE* lpNameHandle);
int GetAddrInfoW(LPCWSTR pName, LPCWSTR pServiceName, const ADDRINFOW *pHints, ADDRINFOW **ppResult);
int getaddrinfo(LPCSTR pName, LPCSTR pServiceName, const ADDRINFOA *pHints, ADDRINFOA **ppResult);
void FreeAddrInfoW(ADDRINFOW* pAddrInfo);
void FreeAddrInfoExW(ADDRINFOEXW* pAddrInfo);
void freeaddrinfo(ADDRINFOA* ai);
BOOL TransmitFile(SOCKET hSocket, HANDLE hFile, DWORD nNumberOfBytesToWrite, DWORD nNumberOfBytesPerSend, OVERLAPPED* lpOverlapped, LPTRANSMIT_FILE_BUFFERS lpTransmitBuffers, DWORD dwFlags);

struct WSAOVERLAPPEDX {
	ULONG_PTR Internal;
	ULONG_PTR InternalHigh;
	union {
		struct {
			DWORD Offset;
			DWORD OffsetHigh;
		}
		PVOID  Pointer;
	}
	HANDLE hEvent;
}
