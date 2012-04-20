/* Converted to D from ..\event2\tag.h by htod */
module intf.event2.tag;
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
//C     #ifndef _EVENT2_TAG_H_
//C     #define _EVENT2_TAG_H_

/** @file event2/tag.h

  Helper functions for reading and writing tagged data onto buffers.

 */

//C     #ifdef __cplusplus
//C     extern "C" {
//C     #endif

//C     #include <event2/event-config.h>
import intf.event2.config;
//C     #ifdef _EVENT_HAVE_SYS_TYPES_H
//C     #include <sys/types.h>
import core.stdc.ctype;
//C     #endif
//C     #ifdef _EVENT_HAVE_SYS_TIME_H
//C     #include <sys/time.h>
import core.stdc.time;
//C     #endif

/* For int types. */
//C     #include <event2/util.h>
import intf.event2.util;

//C     struct evbuffer;

/*
 * Marshaling tagged data - We assume that all tags are inserted in their
 * numeric order - so that unknown tags will always be higher than the
 * known ones - and we can just ignore the end of an event buffer.
 */

//C     void evtag_init(void);
extern (C):
void  evtag_init();

/**
   Unmarshals the header and returns the length of the payload

   @param evbuf the buffer from which to unmarshal data
   @param ptag a pointer in which the tag id is being stored
   @returns -1 on failure or the number of bytes in the remaining payload.
*/
//C     int evtag_unmarshal_header(struct evbuffer *evbuf, ev_uint32_t *ptag);
int  evtag_unmarshal_header(evbuffer *evbuf, uint *ptag);

//C     void evtag_marshal(struct evbuffer *evbuf, ev_uint32_t tag, const void *data,
//C         ev_uint32_t len);
void  evtag_marshal(evbuffer *evbuf, uint tag, void *data, uint len);
//C     void evtag_marshal_buffer(struct evbuffer *evbuf, ev_uint32_t tag,
//C         struct evbuffer *data);
void  evtag_marshal_buffer(evbuffer *evbuf, uint tag, evbuffer *data);

/**
  Encode an integer and store it in an evbuffer.

  We encode integers by nybbles; the first nibble contains the number
  of significant nibbles - 1;  this allows us to encode up to 64-bit
  integers.  This function is byte-order independent.

  @param evbuf evbuffer to store the encoded number
  @param number a 32-bit integer
 */
//C     void evtag_encode_int(struct evbuffer *evbuf, ev_uint32_t number);
void  evtag_encode_int(evbuffer *evbuf, uint number);
//C     void evtag_encode_int64(struct evbuffer *evbuf, ev_uint64_t number);
void  evtag_encode_int64(evbuffer *evbuf, ulong number);

//C     void evtag_marshal_int(struct evbuffer *evbuf, ev_uint32_t tag,
//C         ev_uint32_t integer);
void  evtag_marshal_int(evbuffer *evbuf, uint tag, uint integer);
//C     void evtag_marshal_int64(struct evbuffer *evbuf, ev_uint32_t tag,
//C         ev_uint64_t integer);
void  evtag_marshal_int64(evbuffer *evbuf, uint tag, ulong integer);

//C     void evtag_marshal_string(struct evbuffer *buf, ev_uint32_t tag,
//C         const char *string);
void  evtag_marshal_string(evbuffer *buf, uint tag, char *string);

//C     void evtag_marshal_timeval(struct evbuffer *evbuf, ev_uint32_t tag,
//C         struct timeval *tv);
void  evtag_marshal_timeval(evbuffer *evbuf, uint tag, timeval *tv);

//C     int evtag_unmarshal(struct evbuffer *src, ev_uint32_t *ptag,
//C         struct evbuffer *dst);
int  evtag_unmarshal(evbuffer *src, uint *ptag, evbuffer *dst);
//C     int evtag_peek(struct evbuffer *evbuf, ev_uint32_t *ptag);
int  evtag_peek(evbuffer *evbuf, uint *ptag);
//C     int evtag_peek_length(struct evbuffer *evbuf, ev_uint32_t *plength);
int  evtag_peek_length(evbuffer *evbuf, uint *plength);
//C     int evtag_payload_length(struct evbuffer *evbuf, ev_uint32_t *plength);
int  evtag_payload_length(evbuffer *evbuf, uint *plength);
//C     int evtag_consume(struct evbuffer *evbuf);
int  evtag_consume(evbuffer *evbuf);

//C     int evtag_unmarshal_int(struct evbuffer *evbuf, ev_uint32_t need_tag,
//C         ev_uint32_t *pinteger);
int  evtag_unmarshal_int(evbuffer *evbuf, uint need_tag, uint *pinteger);
//C     int evtag_unmarshal_int64(struct evbuffer *evbuf, ev_uint32_t need_tag,
//C         ev_uint64_t *pinteger);
int  evtag_unmarshal_int64(evbuffer *evbuf, uint need_tag, ulong *pinteger);

//C     int evtag_unmarshal_fixed(struct evbuffer *src, ev_uint32_t need_tag,
//C         void *data, size_t len);
int  evtag_unmarshal_fixed(evbuffer *src, uint need_tag, void *data, size_t len);

//C     int evtag_unmarshal_string(struct evbuffer *evbuf, ev_uint32_t need_tag,
//C         char **pstring);
int  evtag_unmarshal_string(evbuffer *evbuf, uint need_tag, char **pstring);

//C     int evtag_unmarshal_timeval(struct evbuffer *evbuf, ev_uint32_t need_tag,
//C         struct timeval *ptv);
int  evtag_unmarshal_timeval(evbuffer *evbuf, uint need_tag, timeval *ptv);

//C     #ifdef __cplusplus
//C     }
//C     #endif

//C     #endif /* _EVENT2_TAG_H_ */
