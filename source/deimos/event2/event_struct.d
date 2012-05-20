/*
 * Copyright (c) 2000-2007 Niels Provos <provos@citi.umich.edu>
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

/** @file event2/event_struct.h

  Structures used by event.h.  Using these structures directly WILL harm
  forward compatibility: be careful.

  No field declared in this file should be used directly in user code.  Except
  for historical reasons, these fields would not be exposed at all.
 */
module deimos.event2.event_struct;

import deimos.event2._d_util;

extern (C):
nothrow:


/* For int types. */
public import deimos.event2.util;

/* For evkeyvalq */
public import deimos.event2.keyvalq_struct;

import deimos.event2._tailq;

enum EVLIST_TIMEOUT = 0x01;
enum EVLIST_INSERTED = 0x02;
enum EVLIST_SIGNAL = 0x04;
enum EVLIST_ACTIVE = 0x08;
enum EVLIST_INTERNAL = 0x10;
enum EVLIST_INIT = 0x80;

/* EVLIST_X_ Private space: 0x1000-0xf000 */
enum EVLIST_ALL = (0xf000 | 0x9f);

struct event_base;
struct event {
	TAILQ_ENTRY!event ev_active_next;
	TAILQ_ENTRY!event ev_next;
	/* for managing timeouts */
	union ev_timeout_pos_ {
		TAILQ_ENTRY!event ev_next_with_common_timeout;
		int min_heap_idx;
	}
	ev_timeout_pos_ ev_timeout_pos;
	evutil_socket_t ev_fd;

	event_base* ev_base;

	union _ev_ {
		/* used for io events */
		struct ev_io_ {
			TAILQ_ENTRY!event ev_io_next;
			timeval ev_timeout;
		}
		ev_io_ ev_io;

		/* used by signal events */
		struct ev_signal_ {
			TAILQ_ENTRY!event ev_signal_next;
			short ev_ncalls;
			/* Allows deletes in callback */
			short* ev_pncalls;
		}
		ev_signal_ ev_signal;
	}
	_ev_ _ev;

	short ev_events;
	short ev_res;		/* result passed to event callback */
	short ev_flags;
	ev_uint8_t ev_pri;	/* smaller numbers are higher priority */
	ev_uint8_t ev_closure;
	timeval ev_timeout;

	/* allows us to adopt for different types of events */
	ExternC!(void function(evutil_socket_t, short, void* arg)) ev_callback;
	void* ev_arg;
};

mixin TAILQ_HEAD!("event_list", event);
