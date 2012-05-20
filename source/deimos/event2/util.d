/*
 * Copyright (c) 2007-2011 Niels Provos and Nick Mathewson
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *   derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/** @file event2/util.h

  Common convenience functions for cross-platform portability and
  related socket manipulations.

 */
module deimos.event2.util;

extern (C):
nothrow:

import deimos.event2._d_util;

import core.stdc.errno;
import core.stdc.string;
import core.stdc.stdint;
version (Posix) {
  public import core.sys.posix.sys.time : timeval;
  public import core.sys.posix.sys.socket;
} else version (Windows) {
  public import std.c.windows.winsock;
} else static assert(false, "Don't know timeval on this platform.");
version (Posix) {
  import core.sys.posix.sys.types;
}
import core.stdc.stddef;
import core.stdc.stdarg;
version (Posix) {
  import core.sys.posix.netdb;
}

version (Win32) {
  import std.c.windows.winsock;
  extern(Windows) void WSASetLastError(int iError);
} else {
  import core.sys.posix.sys.socket;
}

/**
* @name Standard integer types.
*
* Integer type definitions for types that are supposed to be defined in the
* C99-specified stdint.h.  Shamefully, some platforms do not include
* stdint.h, so we need to replace it.  (If you are on a platform like this,
* your C headers are now over 10 years out of date.  You should bug them to
* do something about this.)
*
* We define:
*
* <dl>
*   <dt>ev_uint64_t, ev_uint32_t, ev_uint16_t, ev_uint8_t</dt>
*      <dd>uinteger types of exactly 64, 32, 16, and 8 bits
*          respectively.</dd>
*    <dt>ev_int64_t, ev_int32_t, ev_int16_t, ev_int8_t</dt>
*      <dd>signed integer types of exactly 64, 32, 16, and 8 bits
*          respectively.</dd>
*    <dt>ev_uintptr_t, ev_intptr_t</dt>
*      <dd>unsigned/signed integers large enough
*      to hold a pointer without loss of bits.</dd>
*    <dt>ev_ssize_t</dt>
*      <dd>A signed type of the same size as size_t</dd>
*    <dt>ev_off_t</dt>
*      <dd>A signed type typically used to represent offsets within a
*      (potentially large) file</dd>
*
* @{
 */
alias ulong ev_uint64_t;
alias long ev_int64_t;

alias uint ev_uint32_t;
alias int ev_int32_t;

alias ushort ev_uint16_t;
alias short ev_int16_t;

alias ubyte ev_uint8_t;
alias byte ev_int8_t;

alias uintptr_t ev_uintptr_t;
alias intptr_t ev_intptr_t;

alias ptrdiff_t ev_ssize_t;

version (Win32) {
  alias ev_int64_t ev_off_t;
} else {
  alias off_t ev_off_t;
}
/**@}*/

/* Limits for integer types.

   We're making two assumptions here:
     - The compiler does constant folding properly.
     - The platform does signed arithmetic in two's complement.
*/

/**
   @name Limits for integer types

   These macros hold the largest or smallest values possible for the
   ev_[u]int*_t types.

   @{
*/
enum EV_UINT64_MAX = ulong.max;
enum EV_INT64_MAX  = long.max;
enum EV_INT64_MIN  = long.min;
enum EV_UINT32_MAX = uint.max;
enum EV_INT32_MAX  = int.max;
enum EV_INT32_MIN  = int.min;
enum EV_UINT16_MAX = ushort.max;
enum EV_INT16_MAX  = short.max;
enum EV_INT16_MIN  = short.min;
enum EV_UINT8_MAX  = ubyte.max;
enum EV_INT8_MAX   = byte.max;
enum EV_INT8_MIN   = byte.min;
/** @} */

/**
   @name Limits for SIZE_T and SSIZE_T

   @{
*/
enum EV_SIZE_MAX = size_t.max;
enum EV_SSIZE_MAX = ev_ssize_t.max;
enum EV_SSIZE_MIN = ev_ssize_t.min;
/**@}*/

version (Win32) {
  alias int ev_socklen_t;
} else {
  alias socklen_t ev_socklen_t;
}

/**
 * A type wide enough to hold the output of "socket()" or "accept()".  On
 * Windows, this is an intptr_t; elsewhere, it is an int. */
version (Win32) {
  alias intptr_t evutil_socket_t;
} else {
  alias int evutil_socket_t;
}

/** Create two new sockets that are connected to each other.

    On Unix, this simply calls socketpair().  On Windows, it uses the
    loopback network interface on 127.0.0.1, and only
    AF_INET,SOCK_STREAM are supported.

    (This may fail on some Windows hosts where firewall software has cleverly
    decided to keep 127.0.0.1 from talking to itself.)

    Parameters and return values are as for socketpair()
*/
int evutil_socketpair(int d, int type, int protocol, ref evutil_socket_t sv[2]);
/** Do platform-specific operations as needed to make a socket nonblocking.

    @param sock The socket to make nonblocking
    @return 0 on success, -1 on failure
 */
int evutil_make_socket_nonblocking(evutil_socket_t sock);

/** Do platform-specific operations to make a listener socket reusable.

    Specifically, we want to make sure that another program will be able
    to bind this address right after we've closed the listener.

    This differs from Windows's interpretation of "reusable", which
    allows multiple listeners to bind the same address at the same time.

    @param sock The socket to make reusable
    @return 0 on success, -1 on failure
 */
int evutil_make_listen_socket_reuseable(evutil_socket_t sock);

/** Do platform-specific operations as needed to close a socket upon a
    successful execution of one of the exec*() functions.

    @param sock The socket to be closed
    @return 0 on success, -1 on failure
 */
int evutil_make_socket_closeonexec(evutil_socket_t sock);

/** Do the platform-specific call needed to close a socket returned from
    socket() or accept().

    @param sock The socket to be closed
    @return 0 on success, -1 on failure
 */
int evutil_closesocket(evutil_socket_t sock);
alias evutil_closesocket EVUTIL_CLOSESOCKET;


version (Win32) {
  /** Return the most recent socket error.  Not idempotent on all platforms. */
  alias WSAGetLastError EVUTIL_SOCKET_ERROR;
  /** Replace the most recent socket error with errcode */
  alias WSASetLastError EVUTIL_SET_SOCKET_ERROR;

  /** Return the most recent socket error to occur on sock. */
  int evutil_socket_geterror(evutil_socket_t sock);
  /** Convert a socket error to a string. */
  const(char)* evutil_socket_error_to_string(int errcode);
} else {
  alias errno EVUTIL_SOCKET_ERROR;
  void EVUTIL_SET_SOCKET_ERROR()(int errcode) { errno = errcode; }
  auto EVUTIL_SET_SOCKET_ERROR()(evutil_socket_t sock) { return errno; }
  alias strerror evutil_socket_error_to_string;
}


/**
 * @name Manipulation macros for struct timeval.
 *
 * We define replacements
 * for timeradd, timersub, timerclear, timercmp, and timerisset.
 *
 * @{
 */
void evutil_timeradd()(timeval* tvp, timeval* uvp, timeval* vvp) {
	vvp.tv_sec = tvp.tv_sec + uvp.tv_sec;
	vvp.tv_usec = tvp.tv_usec + uvp.tv_usec;
	if (vvp.tv_usec >= 1000000) {
		vvp.tv_sec++;
		vvp.tv_usec -= 1000000;
	}
}

void evutil_timersub()(timeval* tvp, timeval* uvp, timeval* vvp) {
	vvp.tv_sec = tvp.tv_sec - uvp.tv_sec;
	vvp.tv_usec = tvp.tv_usec - uvp.tv_usec;
	if (vvp.tv_usec < 0) {
		vvp.tv_sec--;
		vvp.tv_usec += 1000000;
	}
}

void evutil_timerclear()(timeval* tvp) {
	tvp.tv_sec = tvp.tv_usec = 0;
}
/**@}*/

/** Return true iff the tvp is related to uvp according to the relational
* operator cmp.  Recognized values for cmp are ==, <=, <, >=, and >. */
// TODO: Port?
//#define	evutil_timercmp(tvp, uvp, cmp)					\
//	(((tvp)->tv_sec == (uvp)->tv_sec) ?				\
//	 ((tvp)->tv_usec cmp (uvp)->tv_usec) :				\
//	 ((tvp)->tv_sec cmp (uvp)->tv_sec))

bool evutil_timerisset()(timeval* tvp) {
  return tvp.tv_sec || tvp.tv_usec;
}

/** Replacement for offsetof on platforms that don't define it. */
template evutil_offsetof(type, string field) {
  enum evutil_offsetof = mixin("type." ~ field ~ ".offsetof");
}

/* big-int related functions */
/** Parse a 64-bit value from a string.  Arguments are as for strtol. */
ev_int64_t evutil_strtoll(const(char)* s, char* *endptr, int base);

/** Replacement for gettimeofday on platforms that lack it. */
static if (is(typeof(gettimeofday))) {
  alias gettimeofday evutil_gettimeofday;
} else {
  alias void timezone;
  int evutil_gettimeofday(timeval* tv, timezone* tz);
}

/** Replacement for snprintf to get consistent behavior on platforms for
    which the return value of snprintf does not conform to C99.
 */
int evutil_snprintf(char* buf, size_t buflen, const(char)* format, ...);
/** Replacement for vsnprintf to get consistent behavior on platforms for
    which the return value of snprintf does not conform to C99.
 */
int evutil_vsnprintf(char* buf, size_t buflen, const(char)* format, va_list ap);

/** Replacement for inet_ntop for platforms which lack it. */
const(char)* evutil_inet_ntop(int af, const(void)* src, char* dst, size_t len);
/** Replacement for inet_pton for platforms which lack it. */
int evutil_inet_pton(int af, const(char)* src, void* dst);

/** Parse an IPv4 or IPv6 address, with optional port, from a string.

    Recognized formats are:
    - [IPv6Address]:port
    - [IPv6Address]
    - IPv6Address
    - IPv4Address:port
    - IPv4Address

    If no port is specified, the port in the output is set to 0.

    @param str The string to parse.
    @param out A sockaddr to hold the result.  This should probably be
       a struct sockaddr_storage.
    @param outlen A pointer to the number of bytes that that 'out' can safely
       hold.  Set to the number of bytes used in 'out' on success.
    @return -1 if the address is not well-formed, if the port is out of range,
       or if out is not large enough to hold the result.  Otherwise returns
       0 on success.
*/
int evutil_parse_sockaddr_port(const(char)* str, sockaddr* out_, int* outlen);

/** Compare two sockaddrs; return 0 if they are equal, or less than 0 if sa1
 * preceeds sa2, or greater than 0 if sa1 follows sa2.  If include_port is
 * true, consider the port as well as the address.  Only implemented for
 * AF_INET and AF_INET6 addresses. The ordering is not guaranteed to remain
 * the same between Libevent versions. */
int evutil_sockaddr_cmp(const(sockaddr)* sa1, const(sockaddr)* sa2,
    int include_port);

/** As strcasecmp, but always compares the characters in locale-independent
    ASCII.  That's useful if you're handling data in ASCII-based protocols.
 */
int evutil_ascii_strcasecmp(const(char)* str1, const(char)* str2);
/** As strncasecmp, but always compares the characters in locale-independent
    ASCII.  That's useful if you're handling data in ASCII-based protocols.
 */
int evutil_ascii_strncasecmp(const(char)* str1, const(char)* str2, size_t n);

/* Here we define evutil_addrinfo to the native addrinfo type, or redefine it
 * if this system has no getaddrinfo(). */
static if (is(addrinfo)) {
  alias addrinfo evutil_addrinfo;
} else {
  /** A definition of addrinfo for systems that lack it.

      (This is just an alias for addrinfo if the system defines
      struct addrinfo.)
  */
  struct evutil_addrinfo {
  	int     ai_flags;     /* AI_PASSIVE, AI_CANONNAME, AI_NUMERICHOST */
  	int     ai_family;    /* PF_xxx */
  	int     ai_socktype;  /* SOCK_xxx */
  	int     ai_protocol;  /* 0 or IPPROTO_xxx for IPv4 and IPv6 */
  	size_t  ai_addrlen;   /* length of ai_addr */
  	char   *ai_canonname; /* canonical name for nodename */
  	sockaddr  *ai_addr; /* binary address */
  	evutil_addrinfo  *ai_next; /* next structure in linked list */
  }
}
/** @name evutil_getaddrinfo() error codes

    These values are possible error codes for evutil_getaddrinfo() and
    related functions.

    @{
*/
static if (is(typeof(EAI_ADDRFAMILY))) {
  enum EVUTIL_EAI_ADDRFAMILY = EAI_ADDRFAMILY;
} else {
  enum EVUTIL_EAI_ADDRFAMILY = -901;
}
static if (is(typeof(EAI_AGAIN))) {
  enum EVUTIL_EAI_AGAIN = EAI_AGAIN;
} else {
  enum EVUTIL_EAI_AGAIN = -902;
}
static if (is(typeof(EAI_BADFLAGS))) {
  enum EVUTIL_EAI_BADFLAGS = EAI_BADFLAGS;
} else {
  enum EVUTIL_EAI_BADFLAGS = -903;
}
static if (is(typeof(EAI_FAIL))) {
  enum EVUTIL_EAI_FAIL = EAI_FAIL;
} else {
  enum EVUTIL_EAI_FAIL = -904;
}
static if (is(typeof(EAI_FAMILY))) {
  enum EVUTIL_EAI_FAMILY = EAI_FAMILY;
} else {
  enum EVUTIL_EAI_FAMILY = -905;
}
static if (is(typeof(EAI_MEMORY))) {
  enum EVUTIL_EAI_MEMORY = EAI_MEMORY;
} else {
  enum EVUTIL_EAI_MEMORY = -906;
}
/* This test is a bit complicated, since some MS SDKs decide to
 * remove NODATA or redefine it to be the same as NONAME, in a
 * fun interpretation of RFC 2553 and RFC 3493. */
static if (is(typeof(EAI_NODATA)) && (!is(typeof(EAI_NONAME)) || EAI_NODATA != EAI_NONAME)) {
  enum EVUTIL_EAI_NODATA = EAI_NODATA;
} else {
  enum EVUTIL_EAI_NODATA = -907;
}
static if (is(typeof(EAI_NONAME))) {
  enum EVUTIL_EAI_NONAME = EAI_NONAME;
} else {
  enum EVUTIL_EAI_NONAME = -908;
}
static if (is(typeof(EAI_SERVICE))) {
  enum EVUTIL_EAI_SERVICE = EAI_SERVICE;
} else {
  enum EVUTIL_EAI_SERVICE = -909;
}
static if (is(typeof(EAI_SOCKTYPE))) {
  enum EVUTIL_EAI_SOCKTYPE = EAI_SOCKTYPE;
} else {
  enum EVUTIL_EAI_SOCKTYPE = -910;
}
static if (is(typeof(EAI_SYSTEM))) {
  enum EVUTIL_EAI_SYSTEM = EAI_SYSTEM;
} else {
  enum EVUTIL_EAI_SYSTEM = -911;
}

enum EVUTIL_EAI_CANCEL = -90001;

static if (is(typeof(AI_PASSIVE))) {
  enum EVUTIL_AI_PASSIVE = AI_PASSIVE;
} else {
  enum EVUTIL_AI_PASSIVE = 0x1000;
}
static if (is(typeof(AI_CANONNAME))) {
  enum EVUTIL_AI_CANONNAME = AI_CANONNAME;
} else {
  enum EVUTIL_AI_CANONNAME = 0x2000;
}
static if (is(typeof(AI_NUMERICHOST))) {
  enum EVUTIL_AI_NUMERICHOST = AI_NUMERICHOST;
} else {
  enum EVUTIL_AI_NUMERICHOST = 0x4000;
}
static if (is(typeof(AI_NUMERICSERV))) {
  enum EVUTIL_AI_NUMERICSERV = AI_NUMERICSERV;
} else {
  enum EVUTIL_AI_NUMERICSERV = 0x8000;
}
static if (is(typeof(AI_V4MAPPED))) {
  enum EVUTIL_AI_V4MAPPED = AI_V4MAPPED;
} else {
  enum EVUTIL_AI_V4MAPPED = 0x10000;
}
static if (is(typeof(AI_ALL))) {
  enum EVUTIL_AI_ALL = AI_ALL;
} else {
  enum EVUTIL_AI_ALL = 0x20000;
}
static if (is(typeof(AI_ADDRCONFIG))) {
  enum EVUTIL_AI_ADDRCONFIG = AI_ADDRCONFIG;
} else {
  enum EVUTIL_AI_ADDRCONFIG = 0x40000;
}
/**@}*/

/**
 * This function clones getaddrinfo for systems that don't have it.  For full
 * details, see RFC 3493, section 6.1.
 *
 * Limitations:
 * - When the system has no getaddrinfo, we fall back to gethostbyname_r or
 *  gethostbyname, with their attendant issues.
 * - The AI_V4MAPPED and AI_ALL flags are not currently implemented.
 *
 * For a nonblocking variant, see evdns_getaddrinfo.
 */
int evutil_getaddrinfo(const(char)* nodename, const(char)* servname,
    const(evutil_addrinfo)* hints_in_, evutil_addrinfo* *res);

/** Release storage allocated by evutil_getaddrinfo or evdns_getaddrinfo. */
void evutil_freeaddrinfo(evutil_addrinfo* ai);

const(char)* evutil_gai_strerror(int err);

/** Generate n bytes of secure pseudorandom data, and store them in buf.
 *
 * By default, Libevent uses an ARC4-based random number generator, seeded
 * using the platform's entropy source (/dev/urandom on Unix-like systems;
 * CryptGenRandom on Windows).
 */
void evutil_secure_rng_get_bytes(void* buf, size_t n);

/**
 * Seed the secure random number generator if needed, and return 0 on
 * success or -1 on failure.
 *
 * It is okay to call this function more than once; it will still return
 * 0 if the RNG has been successfully seeded and -1 if it can't be
 * seeded.
 *
 * Ordinarily you don't need to call this function from your own code;
 * Libevent will seed the RNG itself the first time it needs good random
 * numbers.  You only need to call it if (a) you want to double-check
 * that one of the seeding methods did succeed, or (b) you plan to drop
 * the capability to seed (by chrooting, or dropping capabilities, or
 * whatever), and you want to make sure that seeding happens before your
 * program loses the ability to do it.
 */
int evutil_secure_rng_init();

/** Seed the random number generator with extra random bytes.

    You should almost never need to call this function; it should be
    sufficient to invoke evutil_secure_rng_init(), or let Libevent take
    care of calling evutil_secure_rng_init() on its own.

    If you call this function as a _replacement_ for the regular
    entropy sources, then you need to be sure that your input
    contains a fairly large amount of strong entropy.  Doing so is
    notoriously hard: most people who try get it wrong.  Watch out!

    @param dat a buffer full of a strong source of random numbers
    @param datlen the number of bytes to read from datlen
 */
void evutil_secure_rng_add_bytes(const(char)* dat, size_t datlen);
