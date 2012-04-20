/* Converted to D from ..\event2\util.h by htod */
module intf.event2.util;
/*
 * Copyright (c) 2007-2011 Niels Provos and Nick Mathewson
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
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
//C     #ifndef _EVENT2_UTIL_H_
//C     #define _EVENT2_UTIL_H_

/** @file event2/util.h

  Common convenience functions for cross-platform portability and
  related socket manipulations.

 */

//C     #ifdef __cplusplus
//C     extern "C" {
//C     #endif

//C     #include <event2/event-config.h>
import intf.event2.config;
//C     #ifdef _EVENT_HAVE_SYS_TIME_H
//C     #include <sys/time.h>
import core.stdc.time;
//C     #endif
//C     #ifdef _EVENT_HAVE_STDINT_H
//C     #include <stdint.h>
import core.stdc.stdint;
//C     #elif defined(_EVENT_HAVE_INTTYPES_H)
//C     #include <inttypes.h>
//C     #endif
//C     #ifdef _EVENT_HAVE_SYS_TYPES_H
//C     #include <sys/types.h>
import core.stdc.ctype;
//C     #endif
//C     #ifdef _EVENT_HAVE_STDDEF_H
//#include <stddef.h>
//C     #endif
//C     #ifdef _MSC_VER
//C     #include <BaseTsd.h>
//C     #endif
//C     #include <stdarg.h>
import core.stdc.stdarg;
//C     #ifdef _EVENT_HAVE_NETDB_H
//C     #if !defined(_GNU_SOURCE)
//C     #define _GNU_SOURCE
//C     #endif
//C     #include <netdb.h>
//C     #endif

//C     #ifdef WIN32
//C     #include <winsock2.h>
version(Windows){
  public import std.c.windows.winsock;
} else {
  public import core.sys.posix.sys.socket;
  public import core.sys.posix.sys.time;
  public import core.sys.posix.netdb;
  public import core.sys.posix.netinet.in_;
}
//C     #else
//C     #include <sys/socket.h>
//C     #endif

/* Some openbsd autoconf versions get the name of this macro wrong. */
//C     #if defined(_EVENT_SIZEOF_VOID__) && !defined(_EVENT_SIZEOF_VOID_P)
//C     #define _EVENT_SIZEOF_VOID_P _EVENT_SIZEOF_VOID__
//C     #endif

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
 *      <dd>unsigned integer types of exactly 64, 32, 16, and 8 bits
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
//C     #ifdef _EVENT_HAVE_UINT64_T
//C     #define ev_uint64_t ulong
//C     #define ev_int64_t long
alias ulong ev_uint64_t;
//C     #elif defined(WIN32)
alias long ev_int64_t;
//C     #define ev_uint64_t unsigned __int64
//C     #define ev_int64_t signed __int64
//C     #elif _EVENT_SIZEOF_LONG_LONG == 8
//C     #define ev_uint64_t unsigned long long
//C     #define ev_int64_t long long
//C     #elif _EVENT_SIZEOF_LONG == 8
//C     #define ev_uint64_t unsigned long
//C     #define ev_int64_t long
//C     #elif defined(_EVENT_IN_DOXYGEN)
//C     #define ev_uint64_t ...
//C     #define ev_int64_t ...
//C     #else
//C     #error "No way to define ev_uint64_t"
//C     #endif

//C     #ifdef _EVENT_HAVE_UINT32_T
//C     #define ev_uint32_t uint
//C     #define ev_int32_t int32_t
alias uint ev_uint32_t;
//C     #elif defined(WIN32)
alias int32_t ev_int32_t;
//C     #define ev_uint32_t unsigned int
//C     #define ev_int32_t signed int
//C     #elif _EVENT_SIZEOF_LONG == 4
//C     #define ev_uint32_t unsigned long
//C     #define ev_int32_t signed long
//C     #elif _EVENT_SIZEOF_INT == 4
//C     #define ev_uint32_t unsigned int
//C     #define ev_int32_t signed int
//C     #elif defined(_EVENT_IN_DOXYGEN)
//C     #define ev_uint32_t ...
//C     #define ev_int32_t ...
//C     #else
//C     #error "No way to define ev_uint32_t"
//C     #endif

//C     #ifdef _EVENT_HAVE_UINT16_T
//C     #define ev_uint16_t ushort
//C     #define ev_int16_t  int16_t
alias ushort ev_uint16_t;
//C     #elif defined(WIN32)
alias int16_t ev_int16_t;
//C     #define ev_uint16_t unsigned short
//C     #define ev_int16_t  signed short
//C     #elif _EVENT_SIZEOF_INT == 2
//C     #define ev_uint16_t unsigned int
//C     #define ev_int16_t  signed int
//C     #elif _EVENT_SIZEOF_SHORT == 2
//C     #define ev_uint16_t unsigned short
//C     #define ev_int16_t  signed short
//C     #elif defined(_EVENT_IN_DOXYGEN)
//C     #define ev_uint16_t ...
//C     #define ev_int16_t ...
//C     #else
//C     #error "No way to define ev_uint16_t"
//C     #endif

//C     #ifdef _EVENT_HAVE_UINT8_T
//C     #define ev_uint8_t uint8_t
//C     #define ev_int8_t int8_t
alias uint8_t ev_uint8_t;
//C     #elif defined(_EVENT_IN_DOXYGEN)
alias int8_t ev_int8_t;
//C     #define ev_uint8_t ...
//C     #define ev_int8_t ...
//C     #else
//C     #define ev_uint8_t unsigned char
//C     #define ev_int8_t signed char
//C     #endif

//C     #ifdef _EVENT_HAVE_UINTPTR_T
//C     #define ev_uintptr_t uintptr_t
//C     #define ev_intptr_t intptr_t
alias uintptr_t ev_uintptr_t;
//C     #elif _EVENT_SIZEOF_VOID_P <= 4
alias intptr_t ev_intptr_t;
//C     #define ev_uintptr_t ev_uint32_t
//C     #define ev_intptr_t ev_int32_t
//C     #elif _EVENT_SIZEOF_VOID_P <= 8
//C     #define ev_uintptr_t ev_uint64_t
//C     #define ev_intptr_t ev_int64_t
//C     #elif defined(_EVENT_IN_DOXYGEN)
//C     #define ev_uintptr_t ...
//C     #define ev_intptr_t ...
//C     #else
//C     #error "No way to define ev_uintptr_t"
//C     #endif

/*#ifdef _EVENT_ssize_t
#define ev_ssize_t _EVENT_ssize_t
#else*/
//C     typedef int ptrdiff_t;
extern (C):
alias int ptrdiff_t;
//C     typedef ptrdiff_t ev_ssize_t;
alias ptrdiff_t ev_ssize_t;
//#endif

//C     #ifdef WIN32
//C     #define ev_off_t ev_int64_t
//C     #else
alias ev_int64_t ev_off_t;
//C     #define ev_off_t off_t
//C     #endif
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
//C     #define EV_UINT64_MAX ((((ev_uint64_t)0xffffffffUL) << 32) | 0xffffffffUL)
//C     #define EV_INT64_MAX  ((((ev_int64_t) 0x7fffffffL) << 32) | 0xffffffffL)
//C     #define EV_INT64_MIN  ((-EV_INT64_MAX) - 1)
//C     #define EV_UINT32_MAX ((ev_uint32_t)0xffffffffUL)
//C     #define EV_INT32_MAX  ((ev_int32_t) 0x7fffffffL)
//C     #define EV_INT32_MIN  ((-EV_INT32_MAX) - 1)
//C     #define EV_UINT16_MAX ((ev_uint16_t)0xffffUL)
//C     #define EV_INT16_MAX  ((ev_int16_t) 0x7fffL)
//C     #define EV_INT16_MIN  ((-EV_INT16_MAX) - 1)
//C     #define EV_UINT8_MAX  255
//C     #define EV_INT8_MAX   127
const EV_UINT8_MAX = 255;
//C     #define EV_INT8_MIN   ((-EV_INT8_MAX) - 1)
const EV_INT8_MAX = 127;
/** @} */

/**
   @name Limits for SIZE_T and SSIZE_T

   @{
*/
//C     #if _EVENT_SIZEOF_SIZE_T == 8
//C     #define EV_SIZE_MAX EV_UINT64_MAX
//C     #define EV_SSIZE_MAX EV_INT64_MAX
//C     #elif _EVENT_SIZEOF_SIZE_T == 4
//C     #define EV_SIZE_MAX EV_UINT32_MAX
//C     #define EV_SSIZE_MAX EV_INT32_MAX
enum EV_SIZE_MAX = size_t.max;
//C     #elif defined(_EVENT_IN_DOXYGEN)
enum EV_SSIZE_MAX = sizediff_t.max;
//C     #define EV_SIZE_MAX ...
//C     #define EV_SSIZE_MAX ...
//C     #else
//C     #error "No way to define SIZE_MAX"
//C     #endif

//C     #define EV_SSIZE_MIN ((-EV_SSIZE_MAX) - 1)
/**@}*/

//C     #ifdef WIN32
//C     #define ev_socklen_t int
//C     #elif defined(_EVENT_socklen_t)
alias int ev_socklen_t;
//C     #define ev_socklen_t _EVENT_socklen_t
//C     #else
//C     #define ev_socklen_t socklen_t
//C     #endif

//C     #ifdef _EVENT_HAVE_STRUCT_SOCKADDR_STORAGE___SS_FAMILY
//C     #if !defined(_EVENT_HAVE_STRUCT_SOCKADDR_STORAGE_SS_FAMILY)  && !defined(ss_family)
//C     #define ss_family __ss_family
//C     #endif
//C     #endif

/**
 * A type wide enough to hold the output of "socket()" or "accept()".  On
 * Windows, this is an intptr_t; elsewhere, it is an int. */
//C     #ifdef WIN32
//C     typedef intptr_t evutil_socket_t;
alias intptr_t evutil_socket_t;
//C     #else
//C     #define evutil_socket_t int
//C     #endif

/** Create two new sockets that are connected to each other.

    On Unix, this simply calls socketpair().  On Windows, it uses the
    loopback network interface on 127.0.0.1, and only
    AF_INET,SOCK_STREAM are supported.

    (This may fail on some Windows hosts where firewall software has cleverly
    decided to keep 127.0.0.1 from talking to itself.)

    Parameters and return values are as for socketpair()
*/
//C     int evutil_socketpair(int d, int type, int protocol, evutil_socket_t sv[2]);
int  evutil_socketpair(int d, int type, int protocol, evutil_socket_t *sv);
/** Do platform-specific operations as needed to make a socket nonblocking.

    @param sock The socket to make nonblocking
    @return 0 on success, -1 on failure
 */
//C     int evutil_make_socket_nonblocking(evutil_socket_t sock);
int  evutil_make_socket_nonblocking(evutil_socket_t sock);

/** Do platform-specific operations to make a listener socket reusable.

    Specifically, we want to make sure that another program will be able
    to bind this address right after we've closed the listener.

    This differs from Windows's interpretation of "reusable", which
    allows multiple listeners to bind the same address at the same time.

    @param sock The socket to make reusable
    @return 0 on success, -1 on failure
 */
//C     int evutil_make_listen_socket_reuseable(evutil_socket_t sock);
int  evutil_make_listen_socket_reuseable(evutil_socket_t sock);

/** Do platform-specific operations as needed to close a socket upon a
    successful execution of one of the exec*() functions.

    @param sock The socket to be closed
    @return 0 on success, -1 on failure
 */
//C     int evutil_make_socket_closeonexec(evutil_socket_t sock);
int  evutil_make_socket_closeonexec(evutil_socket_t sock);

/** Do the platform-specific call needed to close a socket returned from
    socket() or accept().

    @param sock The socket to be closed
    @return 0 on success, -1 on failure
 */
//C     int evutil_closesocket(evutil_socket_t sock);
int  evutil_closesocket(evutil_socket_t sock);
//C     #define EVUTIL_CLOSESOCKET(s) evutil_closesocket(s)


//C     #ifdef WIN32
/** Return the most recent socket error.  Not idempotent on all platforms. */
//C     #define EVUTIL_SOCKET_ERROR() WSAGetLastError()
/** Replace the most recent socket error with errcode */
//C     #define EVUTIL_SET_SOCKET_ERROR(errcode)			do { WSASetLastError(errcode); } while (0)
/** Return the most recent socket error to occur on sock. */
//C     int evutil_socket_geterror(evutil_socket_t sock);
int  evutil_socket_geterror(evutil_socket_t sock);
/** Convert a socket error to a string. */
//C     const char *evutil_socket_error_to_string(int errcode);
char * evutil_socket_error_to_string(int errcode);
//C     #elif defined(_EVENT_IN_DOXYGEN)
/**
   @name Socket error functions

   These functions are needed for making programs compatible between
   Windows and Unix-like platforms.

   You see, Winsock handles socket errors differently from the rest of
   the world.  Elsewhere, a socket error is like any other error and is
   stored in errno.  But winsock functions require you to retrieve the
   error with a special function, and don't let you use strerror for
   the error codes.  And handling EWOULDBLOCK is ... different.

   @{
*/
/** Return the most recent socket error.  Not idempotent on all platforms. */
//C     #define EVUTIL_SOCKET_ERROR() ...
/** Replace the most recent socket error with errcode */
//C     #define EVUTIL_SET_SOCKET_ERROR(errcode) ...
/** Return the most recent socket error to occur on sock. */
//C     #define evutil_socket_geterror(sock) ...
/** Convert a socket error to a string. */
//C     #define evutil_socket_error_to_string(errcode) ...
/**@}*/
//C     #else
//C     #define EVUTIL_SOCKET_ERROR() (errno)
//C     #define EVUTIL_SET_SOCKET_ERROR(errcode)				do { errno = (errcode); } while (0)
//C     #define evutil_socket_geterror(sock) (errno)
//C     #define evutil_socket_error_to_string(errcode) (strerror(errcode))
//C     #endif


/**
 * @name Manipulation macros for struct timeval.
 *
 * We define replacements
 * for timeradd, timersub, timerclear, timercmp, and timerisset.
 *
 * @{
 */
//C     #ifdef _EVENT_HAVE_TIMERADD
//C     #define evutil_timeradd(tvp, uvp, vvp) timeradd((tvp), (uvp), (vvp))
//C     #define evutil_timersub(tvp, uvp, vvp) timersub((tvp), (uvp), (vvp))
//C     #else
//C     #define evutil_timeradd(tvp, uvp, vvp)						do {										(vvp)->tv_sec = (tvp)->tv_sec + (uvp)->tv_sec;				(vvp)->tv_usec = (tvp)->tv_usec + (uvp)->tv_usec;       		if ((vvp)->tv_usec >= 1000000) {						(vvp)->tv_sec++;							(vvp)->tv_usec -= 1000000;					}								} while (0)
//C     #define	evutil_timersub(tvp, uvp, vvp)						do {										(vvp)->tv_sec = (tvp)->tv_sec - (uvp)->tv_sec;				(vvp)->tv_usec = (tvp)->tv_usec - (uvp)->tv_usec;			if ((vvp)->tv_usec < 0) {							(vvp)->tv_sec--;							(vvp)->tv_usec += 1000000;					}								} while (0)
//C     #endif /* !_EVENT_HAVE_HAVE_TIMERADD */

//C     #ifdef _EVENT_HAVE_TIMERCLEAR
//C     #define evutil_timerclear(tvp) timerclear(tvp)
//C     #else
//C     #define	evutil_timerclear(tvp)	(tvp)->tv_sec = (tvp)->tv_usec = 0
//C     #endif
/**@}*/

/** Return true iff the tvp is related to uvp according to the relational
 * operator cmp.  Recognized values for cmp are ==, <=, <, >=, and >. */
//C     #define	evutil_timercmp(tvp, uvp, cmp)						(((tvp)->tv_sec == (uvp)->tv_sec) ?					 ((tvp)->tv_usec cmp (uvp)->tv_usec) :					 ((tvp)->tv_sec cmp (uvp)->tv_sec))

//C     #ifdef _EVENT_HAVE_TIMERISSET
//C     #define evutil_timerisset(tvp) timerisset(tvp)
//C     #else
//C     #define	evutil_timerisset(tvp)	((tvp)->tv_sec || (tvp)->tv_usec)
//C     #endif

/** Replacement for offsetof on platforms that don't define it. */
//C     #ifdef offsetof
//C     #define evutil_offsetof(type, field) offsetof(type, field)
//C     #else
//C     #define evutil_offsetof(type, field) ((off_t)(&((type *)0)->field))
//C     #endif

/* big-int related functions */
/** Parse a 64-bit value from a string.  Arguments are as for strtol. */
//C     ev_int64_t evutil_strtoll(const char *s, char **endptr, int base);
long  evutil_strtoll(char *s, char **endptr, int base);

/** Replacement for gettimeofday on platforms that lack it. */
//C     #ifdef _EVENT_HAVE_GETTIMEOFDAY
//C     #define evutil_gettimeofday(tv, tz) gettimeofday((tv), (tz))
//C     #else
//C     struct timezone;
//C     int evutil_gettimeofday(struct timeval *tv, struct timezone *tz);
//C     #endif

/** Replacement for snprintf to get consistent behavior on platforms for
    which the return value of snprintf does not conform to C99.
 */
//C     int evutil_snprintf(char *buf, size_t buflen, const char *format, ...)
//C     #ifdef __GNUC__
//C     	__attribute__((format(printf, 3, 4)))
//C     #endif
//C     ;
int  evutil_snprintf(char *buf, size_t buflen, char *format,...);
/** Replacement for vsnprintf to get consistent behavior on platforms for
    which the return value of snprintf does not conform to C99.
 */
//C     int evutil_vsnprintf(char *buf, size_t buflen, const char *format, va_list ap);
int  evutil_vsnprintf(char *buf, size_t buflen, char *format, va_list ap);

/** Replacement for inet_ntop for platforms which lack it. */
//C     const char *evutil_inet_ntop(int af, const void *src, char *dst, size_t len);
char * evutil_inet_ntop(int af, void *src, char *dst, size_t len);
/** Replacement for inet_pton for platforms which lack it. */
//C     int evutil_inet_pton(int af, const char *src, void *dst);
int  evutil_inet_pton(int af, const char *src, void *dst);
//C     struct sockaddr;

/** Parse an IPv4 or IPv6 address, with optional port, from a string.

    Recognized formats are:
    - [IPv6Address]:port
    - [IPv6Address]
    - IPv6Address
    - IPv4Address:port
    - IPv4Address

    If no port is specified, the port in the output is set to 0.

    @param str The string to parse.
    @param out A struct sockaddr to hold the result.  This should probably be
       a struct sockaddr_storage.
    @param outlen A pointer to the number of bytes that that 'out' can safely
       hold.  Set to the number of bytes used in 'out' on success.
    @return -1 if the address is not well-formed, if the port is out of range,
       or if out is not large enough to hold the result.  Otherwise returns
       0 on success.
*/
//C     int evutil_parse_sockaddr_port(const char *str, struct sockaddr *out, int *outlen);
int  evutil_parse_sockaddr_port(char *str, sockaddr *out_, int *outlen);

/** Compare two sockaddrs; return 0 if they are equal, or less than 0 if sa1
 * preceeds sa2, or greater than 0 if sa1 follows sa2.  If include_port is
 * true, consider the port as well as the address.  Only implemented for
 * AF_INET and AF_INET6 addresses. The ordering is not guaranteed to remain
 * the same between Libevent versions. */
//C     int evutil_sockaddr_cmp(const struct sockaddr *sa1, const struct sockaddr *sa2,
//C         int include_port);
int  evutil_sockaddr_cmp(sockaddr *sa1, sockaddr *sa2, int include_port);

/** As strcasecmp, but always compares the characters in locale-independent
    ASCII.  That's useful if you're handling data in ASCII-based protocols.
 */
//C     int evutil_ascii_strcasecmp(const char *str1, const char *str2);
int  evutil_ascii_strcasecmp(char *str1, char *str2);
/** As strncasecmp, but always compares the characters in locale-independent
    ASCII.  That's useful if you're handling data in ASCII-based protocols.
 */
//C     int evutil_ascii_strncasecmp(const char *str1, const char *str2, size_t n);
int  evutil_ascii_strncasecmp(char *str1, char *str2, size_t n);

/* Here we define evutil_addrinfo to the native addrinfo type, or redefine it
 * if this system has no getaddrinfo(). */
//C     #ifdef _EVENT_HAVE_STRUCT_ADDRINFO
//C     #define evutil_addrinfo addrinfo
//C     #else
alias addrinfo evutil_addrinfo;
/** A definition of struct addrinfo for systems that lack it.

    (This is just an alias for struct addrinfo if the system defines
    struct addrinfo.)
*/
//C     struct evutil_addrinfo {
//C     	int     ai_flags;     /* AI_PASSIVE, AI_CANONNAME, AI_NUMERICHOST */
//C     	int     ai_family;    /* PF_xxx */
//C     	int     ai_socktype;  /* SOCK_xxx */
//C     	int     ai_protocol;  /* 0 or IPPROTO_xxx for IPv4 and IPv6 */
//C     	size_t  ai_addrlen;   /* length of ai_addr */
//C     	char   *ai_canonname; /* canonical name for nodename */
//C     	struct sockaddr  *ai_addr; /* binary address */
//C     	struct evutil_addrinfo  *ai_next; /* next structure in linked list */
//C     };
//C     #endif
/** @name evutil_getaddrinfo() error codes

    These values are possible error codes for evutil_getaddrinfo() and
    related functions.

    @{
*/
//C     #ifdef EAI_ADDRFAMILY
//C     #define EVUTIL_EAI_ADDRFAMILY EAI_ADDRFAMILY
//C     #else
//C     #define EVUTIL_EAI_ADDRFAMILY -901
//C     #endif
const EVUTIL_EAI_ADDRFAMILY = -901;
//C     #ifdef EAI_AGAIN
//C     #define EVUTIL_EAI_AGAIN EAI_AGAIN
//C     #else
//C     #define EVUTIL_EAI_AGAIN -902
//C     #endif
const EVUTIL_EAI_AGAIN = -902;
//C     #ifdef EAI_BADFLAGS
//C     #define EVUTIL_EAI_BADFLAGS EAI_BADFLAGS
//C     #else
//C     #define EVUTIL_EAI_BADFLAGS -903
//C     #endif
const EVUTIL_EAI_BADFLAGS = -903;
//C     #ifdef EAI_FAIL
//C     #define EVUTIL_EAI_FAIL EAI_FAIL
//C     #else
//C     #define EVUTIL_EAI_FAIL -904
//C     #endif
const EVUTIL_EAI_FAIL = -904;
//C     #ifdef EAI_FAMILY
//C     #define EVUTIL_EAI_FAMILY EAI_FAMILY
//C     #else
//C     #define EVUTIL_EAI_FAMILY -905
//C     #endif
const EVUTIL_EAI_FAMILY = -905;
//C     #ifdef EAI_MEMORY
//C     #define EVUTIL_EAI_MEMORY EAI_MEMORY
//C     #else
//C     #define EVUTIL_EAI_MEMORY -906
//C     #endif
const EVUTIL_EAI_MEMORY = -906;
/* This test is a bit complicated, since some MS SDKs decide to
 * remove NODATA or redefine it to be the same as NONAME, in a
 * fun interpretation of RFC 2553 and RFC 3493. */
//C     #if defined(EAI_NODATA) && (!defined(EAI_NONAME) || EAI_NODATA != EAI_NONAME)
//C     #define EVUTIL_EAI_NODATA EAI_NODATA
//C     #else
//C     #define EVUTIL_EAI_NODATA -907
//C     #endif
const EVUTIL_EAI_NODATA = -907;
//C     #ifdef EAI_NONAME
//C     #define EVUTIL_EAI_NONAME EAI_NONAME
//C     #else
//C     #define EVUTIL_EAI_NONAME -908
//C     #endif
const EVUTIL_EAI_NONAME = -908;
//C     #ifdef EAI_SERVICE
//C     #define EVUTIL_EAI_SERVICE EAI_SERVICE
//C     #else
//C     #define EVUTIL_EAI_SERVICE -909
//C     #endif
const EVUTIL_EAI_SERVICE = -909;
//C     #ifdef EAI_SOCKTYPE
//C     #define EVUTIL_EAI_SOCKTYPE EAI_SOCKTYPE
//C     #else
//C     #define EVUTIL_EAI_SOCKTYPE -910
//C     #endif
const EVUTIL_EAI_SOCKTYPE = -910;
//C     #ifdef EAI_SYSTEM
//C     #define EVUTIL_EAI_SYSTEM EAI_SYSTEM
//C     #else
//C     #define EVUTIL_EAI_SYSTEM -911
//C     #endif
const EVUTIL_EAI_SYSTEM = -911;

//C     #define EVUTIL_EAI_CANCEL -90001

const EVUTIL_EAI_CANCEL = -90001;
//C     #ifdef AI_PASSIVE
//C     #define EVUTIL_AI_PASSIVE AI_PASSIVE
//C     #else
//C     #define EVUTIL_AI_PASSIVE 0x1000
//C     #endif
const EVUTIL_AI_PASSIVE = 0x1000;
//C     #ifdef AI_CANONNAME
//C     #define EVUTIL_AI_CANONNAME AI_CANONNAME
//C     #else
//C     #define EVUTIL_AI_CANONNAME 0x2000
//C     #endif
const EVUTIL_AI_CANONNAME = 0x2000;
//C     #ifdef AI_NUMERICHOST
//C     #define EVUTIL_AI_NUMERICHOST AI_NUMERICHOST
//C     #else
//C     #define EVUTIL_AI_NUMERICHOST 0x4000
//C     #endif
const EVUTIL_AI_NUMERICHOST = 0x4000;
//C     #ifdef AI_NUMERICSERV
//C     #define EVUTIL_AI_NUMERICSERV AI_NUMERICSERV
//C     #else
//C     #define EVUTIL_AI_NUMERICSERV 0x8000
//C     #endif
const EVUTIL_AI_NUMERICSERV = 0x8000;
//C     #ifdef AI_V4MAPPED
//C     #define EVUTIL_AI_V4MAPPED AI_V4MAPPED
//C     #else
//C     #define EVUTIL_AI_V4MAPPED 0x10000
//C     #endif
const EVUTIL_AI_V4MAPPED = 0x10000;
//C     #ifdef AI_ALL
//C     #define EVUTIL_AI_ALL AI_ALL
//C     #else
//C     #define EVUTIL_AI_ALL 0x20000
//C     #endif
const EVUTIL_AI_ALL = 0x20000;
//C     #ifdef AI_ADDRCONFIG
//C     #define EVUTIL_AI_ADDRCONFIG AI_ADDRCONFIG
//C     #else
//C     #define EVUTIL_AI_ADDRCONFIG 0x40000
//C     #endif
const EVUTIL_AI_ADDRCONFIG = 0x40000;
/**@}*/

//C     struct evutil_addrinfo;
/**
 * This function clones getaddrinfo for systems that don't have it.  For full
 * details, see RFC 3493, section 6.1.
 *
 * Limitations:
 * - When the system has no getaddrinfo, we fall back to gethostbyname_r or
 *   gethostbyname, with their attendant issues.
 * - The AI_V4MAPPED and AI_ALL flags are not currently implemented.
 *
 * For a nonblocking variant, see evdns_getaddrinfo.
 */
//C     int evutil_getaddrinfo(const char *nodename, const char *servname,
//C         const struct evutil_addrinfo *hints_in, struct evutil_addrinfo **res);
int  evutil_getaddrinfo(char *nodename, char *servname, addrinfo *hints_in, addrinfo **res);

/** Release storage allocated by evutil_getaddrinfo or evdns_getaddrinfo. */
//C     void evutil_freeaddrinfo(struct evutil_addrinfo *ai);
void  evutil_freeaddrinfo(addrinfo *ai);

//C     const char *evutil_gai_strerror(int err);
char * evutil_gai_strerror(int err);

/** Generate n bytes of secure pseudorandom data, and store them in buf.
 *
 * By default, Libevent uses an ARC4-based random number generator, seeded
 * using the platform's entropy source (/dev/urandom on Unix-like systems;
 * CryptGenRandom on Windows).
 */
//C     void evutil_secure_rng_get_bytes(void *buf, size_t n);
void  evutil_secure_rng_get_bytes(void *buf, size_t n);

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
//C     int evutil_secure_rng_init(void);
int  evutil_secure_rng_init();

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
//C     void evutil_secure_rng_add_bytes(const char *dat, size_t datlen);
void  evutil_secure_rng_add_bytes(char *dat, size_t datlen);

//C     #ifdef __cplusplus
//C     }
//C     #endif

//C     #endif /* _EVUTIL_H_ */
