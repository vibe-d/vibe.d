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

/** @file event2/tag.h

  Helper functions for reading and writing tagged data onto buffers.

 */
module deimos.event2.tag;

extern (C):
nothrow:


/* For int types. */
public import deimos.event2.util;
import deimos.event2._d_util;

struct evbuffer;

/*
 * Marshaling tagged data - We assume that all tags are inserted in their
 * numeric order - so that unknown tags will always be higher than the
 * known ones - and we can just ignore the end of an event buffer.
 */

void evtag_init();

/**
   Unmarshals the header and returns the length of the payload

   @param evbuf the buffer from which to unmarshal data
   @param ptag a pointer in which the tag id is being stored
   @returns -1 on failure or the number of bytes in the remaining payload.
*/
int evtag_unmarshal_header(evbuffer* evbuf, ev_uint32_t* ptag);

void evtag_marshal(evbuffer* evbuf, ev_uint32_t tag, const(void)* data,
    ev_uint32_t len);
void evtag_marshal_buffer(evbuffer* evbuf, ev_uint32_t tag,
    evbuffer* data);

/**
  Encode an integer and store it in an evbuffer.

  We encode integers by nybbles; the first nibble contains the number
  of significant nibbles - 1;  this allows us to encode up to 64-bit
  integers.  This function is byte-order independent.

  @param evbuf evbuffer to store the encoded number
  @param number a 32-bit integer
 */
void evtag_encode_int(evbuffer* evbuf, ev_uint32_t number);
void evtag_encode_int64(evbuffer* evbuf, ev_uint64_t number);

void evtag_marshal_int(evbuffer* evbuf, ev_uint32_t tag,
    ev_uint32_t integer);
void evtag_marshal_int64(evbuffer* evbuf, ev_uint32_t tag,
    ev_uint64_t integer);

void evtag_marshal_string(evbuffer* buf, ev_uint32_t tag,
    const(char)* string);

void evtag_marshal_timeval(evbuffer* evbuf, ev_uint32_t tag,
    timeval* tv);

int evtag_unmarshal(evbuffer* src, ev_uint32_t* ptag,
    evbuffer* dst);
int evtag_peek(evbuffer* evbuf, ev_uint32_t* ptag);
int evtag_peek_length(evbuffer* evbuf, ev_uint32_t* plength);
int evtag_payload_length(evbuffer* evbuf, ev_uint32_t* plength);
int evtag_consume(evbuffer* evbuf);

int evtag_unmarshal_int(evbuffer* evbuf, ev_uint32_t need_tag,
    ev_uint32_t* pinteger);
int evtag_unmarshal_int64(evbuffer* evbuf, ev_uint32_t need_tag,
    ev_uint64_t* pinteger);

int evtag_unmarshal_fixed(evbuffer* src, ev_uint32_t need_tag,
    void* data, size_t len);

int evtag_unmarshal_string(evbuffer* evbuf, ev_uint32_t need_tag,
    char* *pstring);

int evtag_unmarshal_timeval(evbuffer* evbuf, ev_uint32_t need_tag,
    timeval* ptv);
