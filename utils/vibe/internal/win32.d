/// [internal]
module vibe.internal.win32;

version(Windows):

public import core.sys.windows.windows;
public import core.sys.windows.winsock2;

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
