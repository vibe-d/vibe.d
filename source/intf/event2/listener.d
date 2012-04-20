/* Converted to D from ..\event2\listener.h by htod */
module intf.event2.listener;
/*
 * Copyright (c) 2000-2007 Niels Provos <provos@citi.umich.edu>
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
//C     #ifndef _EVENT2_LISTENER_H_
//C     #define _EVENT2_LISTENER_H_

//C     #ifdef __cplusplus
//C     extern "C" {
//C     #endif

//C     #include <event2/event.h>
import intf.event2.event;

//C     struct sockaddr;
//C     struct evconnlistener;

/**
   A callback that we invoke when a listener has a new connection.

   @param listener The evconnlistener
   @param fd The new file descriptor
   @param addr The source address of the connection
   @param socklen The length of addr
   @param user_arg the pointer passed to evconnlistener_new()
 */
//C     typedef void (*evconnlistener_cb)(struct evconnlistener *, evutil_socket_t, struct sockaddr *, int socklen, void *);
extern (C):
alias void  function(evconnlistener *, evutil_socket_t , sockaddr *, int socklen, void *)evconnlistener_cb;

/**
   A callback that we invoke when a listener encounters a non-retriable error.

   @param listener The evconnlistener
   @param user_arg the pointer passed to evconnlistener_new()
 */
//C     typedef void (*evconnlistener_errorcb)(struct evconnlistener *, void *);
alias void  function(evconnlistener *, void *)evconnlistener_errorcb;

/** Flag: Indicates that we should not make incoming sockets nonblocking
 * before passing them to the callback. */
//C     #define LEV_OPT_LEAVE_SOCKETS_BLOCKING	(1u<<0)
/** Flag: Indicates that freeing the listener should close the underlying
 * socket. */
//C     #define LEV_OPT_CLOSE_ON_FREE		(1u<<1)
/** Flag: Indicates that we should set the close-on-exec flag, if possible */
//C     #define LEV_OPT_CLOSE_ON_EXEC		(1u<<2)
/** Flag: Indicates that we should disable the timeout (if any) between when
 * this socket is closed and when we can listen again on the same port. */
//C     #define LEV_OPT_REUSEABLE		(1u<<3)
/** Flag: Indicates that the listener should be locked so it's safe to use
 * from multiple threadcs at once. */
//C     #define LEV_OPT_THREADSAFE		(1u<<4)

/**
   Allocate a new evconnlistener object to listen for incoming TCP connections
   on a given file descriptor.

   @param base The event base to associate the listener with.
   @param cb A callback to be invoked when a new connection arrives.  If the
      callback is NULL, the listener will be treated as disabled until the
      callback is set.
   @param ptr A user-supplied pointer to give to the callback.
   @param flags Any number of LEV_OPT_* flags
   @param backlog Passed to the listen() call to determine the length of the
      acceptable connection backlog.  Set to -1 for a reasonable default.
      Set to 0 if the socket is already listening.
   @param fd The file descriptor to listen on.  It must be a nonblocking
      file descriptor, and it should already be bound to an appropriate
      port and address.
*/
//C     struct evconnlistener *evconnlistener_new(struct event_base *base,
//C         evconnlistener_cb cb, void *ptr, unsigned flags, int backlog,
//C         evutil_socket_t fd);
evconnlistener * evconnlistener_new(event_base *base, evconnlistener_cb cb, void *ptr, uint flags, int backlog, evutil_socket_t fd);
/**
   Allocate a new evconnlistener object to listen for incoming TCP connections
   on a given address.

   @param base The event base to associate the listener with.
   @param cb A callback to be invoked when a new connection arrives. If the
      callback is NULL, the listener will be treated as disabled until the
      callback is set.
   @param ptr A user-supplied pointer to give to the callback.
   @param flags Any number of LEV_OPT_* flags
   @param backlog Passed to the listen() call to determine the length of the
      acceptable connection backlog.  Set to -1 for a reasonable default.
   @param addr The address to listen for connections on.
   @param socklen The length of the address.
 */
//C     struct evconnlistener *evconnlistener_new_bind(struct event_base *base,
//C         evconnlistener_cb cb, void *ptr, unsigned flags, int backlog,
//C         const struct sockaddr *sa, int socklen);
evconnlistener * evconnlistener_new_bind(event_base *base, evconnlistener_cb cb, void *ptr, uint flags, int backlog, sockaddr *sa, int socklen);
/**
   Disable and deallocate an evconnlistener.
 */
//C     void evconnlistener_free(struct evconnlistener *lev);
void  evconnlistener_free(evconnlistener *lev);
/**
   Re-enable an evconnlistener that has been disabled.
 */
//C     int evconnlistener_enable(struct evconnlistener *lev);
int  evconnlistener_enable(evconnlistener *lev);
/**
   Stop listening for connections on an evconnlistener.
 */
//C     int evconnlistener_disable(struct evconnlistener *lev);
int  evconnlistener_disable(evconnlistener *lev);

/** Return an evconnlistener's associated event_base. */
//C     struct event_base *evconnlistener_get_base(struct evconnlistener *lev);
event_base * evconnlistener_get_base(evconnlistener *lev);

/** Return the socket that an evconnlistner is listening on. */
//C     evutil_socket_t evconnlistener_get_fd(struct evconnlistener *lev);
evutil_socket_t  evconnlistener_get_fd(evconnlistener *lev);

/** Change the callback on the listener to cb and its user_data to arg.
 */
//C     void evconnlistener_set_cb(struct evconnlistener *lev,
//C         evconnlistener_cb cb, void *arg);
void  evconnlistener_set_cb(evconnlistener *lev, evconnlistener_cb cb, void *arg);

/** Set an evconnlistener's error callback. */
//C     void evconnlistener_set_error_cb(struct evconnlistener *lev,
//C         evconnlistener_errorcb errorcb);
void  evconnlistener_set_error_cb(evconnlistener *lev, evconnlistener_errorcb errorcb);

//C     #ifdef __cplusplus
//C     }
//C     #endif

//C     #endif
