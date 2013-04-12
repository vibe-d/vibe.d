/* ssl/dtls1.h */
/*
 * DTLS implementation written by Nagendra Modadugu
 * (nagendra@cs.stanford.edu) for the OpenSSL project 2005.
 */
/* ====================================================================
 * Copyright (c) 1999-2005 The OpenSSL Project.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in
 *   the documentation and/or other materials provided with the
 *   distribution.
 *
 * 3. All advertising materials mentioning features or use of this
 *   software must display the following acknowledgment:
 *   "This product includes software developed by the OpenSSL Project
 *   for use in the OpenSSL Toolkit. (http://www.OpenSSL.org/)"
 *
 * 4. The names "OpenSSL Toolkit" and "OpenSSL Project" must not be used to
 *   endorse or promote products derived from this software without
 *   prior written permission. For written permission, please contact
 *   openssl-core@OpenSSL.org.
 *
 * 5. Products derived from this software may not be called "OpenSSL"
 *   nor may "OpenSSL" appear in their names without prior written
 *   permission of the OpenSSL Project.
 *
 * 6. Redistributions of any form whatsoever must retain the following
 *   acknowledgment:
 *   "This product includes software developed by the OpenSSL Project
 *   for use in the OpenSSL Toolkit (http://www.OpenSSL.org/)"
 *
 * THIS SOFTWARE IS PROVIDED BY THE OpenSSL PROJECT ``AS IS'' AND ANY
 * EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE OpenSSL PROJECT OR
 * ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 * ====================================================================
 *
 * This product includes cryptographic software written by Eric Young
 * (eay@cryptsoft.com).  This product includes software written by Tim
 * Hudson (tjh@cryptsoft.com).
 *
 */

module deimos.openssl.dtls1;

import deimos.openssl._d_util;

import deimos.openssl.comp; // Needed for COMP_CTX.
import deimos.openssl.ssl; // Needed for SSL_SESSION.
import deimos.openssl.ssl3; // Needed for SSL3_BUFFER.

public import deimos.openssl.buffer;
public import deimos.openssl.pqueue;
// #ifdef OPENSSL_SYS_VMS
// #include <resource.h>
// #include <sys/timeb.h>
// #endif
version (Windows) {
/* Needed for timeval */
import std.c.windows.winsock;
// #elif defined(OPENSSL_SYS_NETWARE) && !defined(_WINSOCK2API_)
// #include <sys/timeval.h>
} else {
import core.sys.posix.sys.time;
}

extern (C):
nothrow:

enum DTLS1_VERSION = 0xFEFF;
enum DTLS1_BAD_VER = 0x0100;

version (none) {
/* this alert description is not specified anywhere... */
enum DTLS1_AD_MISSING_HANDSHAKE_MESSAGE = 110;
}

/* lengths of messages */
enum DTLS1_COOKIE_LENGTH = 256;

enum DTLS1_RT_HEADER_LENGTH = 13;

enum DTLS1_HM_HEADER_LENGTH = 12;

enum DTLS1_HM_BAD_FRAGMENT = -2;
enum DTLS1_HM_FRAGMENT_RETRY = -3;

enum DTLS1_CCS_HEADER_LENGTH = 1;

version (none) { // #ifdef DTLS1_AD_MISSING_HANDSHAKE_MESSAGE
enum DTLS1_AL_HEADER_LENGTH = 7;
} else {
enum DTLS1_AL_HEADER_LENGTH = 2;
}


struct dtls1_bitmap_st {
	c_ulong map;		/* track 32 packets on 32-bit systems
					   and 64 - on 64-bit systems */
	ubyte max_seq_num[8];	/* max record number seen so far,
					   64-bit value in big-endian
					   encoding */
	}
alias dtls1_bitmap_st DTLS1_BITMAP;

struct dtls1_retransmit_state
	{
	EVP_CIPHER_CTX* enc_write_ctx;	/* cryptographic state */
	EVP_MD_CTX* write_hash;			/* used for mac generation */
version(OPENSSL_NO_COMP) {
	char* compress;
} else {
	COMP_CTX* compress;				/* compression */
}
	SSL_SESSION* session;
	ushort epoch;
	};

struct hm_header_st
	{
	ubyte type;
	c_ulong msg_len;
	ushort seq;
	c_ulong frag_off;
	c_ulong frag_len;
	uint is_ccs;
	dtls1_retransmit_state saved_retransmit_state;
	};

struct ccs_header_st
	{
	ubyte type;
	ushort seq;
	};

struct dtls1_timeout_st
	{
	/* Number of read timeouts so far */
	uint read_timeouts;

	/* Number of write timeouts so far */
	uint write_timeouts;

	/* Number of alerts received so far */
	uint num_alerts;
	};

struct record_pqueue_st {
	ushort epoch;
	pqueue q;
	}
alias record_pqueue_st record_pqueue;

struct hm_fragment_st {
	hm_header_st msg_header;
	ubyte* fragment;
	ubyte* reassembly;
	}
alias hm_fragment_st hm_fragment;

struct dtls1_state_st {
	uint send_cookie;
	ubyte cookie[DTLS1_COOKIE_LENGTH];
	ubyte rcvd_cookie[DTLS1_COOKIE_LENGTH];
	uint cookie_len;

	/*
	 * The current data and handshake epoch.  This is initially
	 * undefined, and starts at zero once the initial handshake is
	 * completed
	 */
	ushort r_epoch;
	ushort w_epoch;

	/* records being received in the current epoch */
	DTLS1_BITMAP bitmap;

	/* renegotiation starts a new set of sequence numbers */
	DTLS1_BITMAP next_bitmap;

	/* handshake message numbers */
	ushort handshake_write_seq;
	ushort next_handshake_write_seq;

	ushort handshake_read_seq;

	/* save last sequence number for retransmissions */
	ubyte last_write_sequence[8];

	/* Received handshake records (processed and unprocessed) */
	record_pqueue unprocessed_rcds;
	record_pqueue processed_rcds;

	/* Buffered handshake messages */
	pqueue buffered_messages;

	/* Buffered (sent) handshake records */
	pqueue sent_messages;

	/* Buffered application records.
	 * Only for records between CCS and Finished
	 * to prevent either protocol violation or
	 * unnecessary message loss.
	 */
	record_pqueue buffered_app_data;

	/* Is set when listening for new connections with dtls1_listen() */
	uint listen;

	uint mtu; /* max DTLS packet size */

	hm_header_st w_msg_hdr;
	hm_header_st r_msg_hdr;

	dtls1_timeout_st timeout;

	/* Indicates when the last handshake msg sent will timeout */
	timeval next_timeout;

	/* Timeout duration */
	ushort timeout_duration;

	/* storage for Alert/Handshake protocol data received but not
	 * yet processed by ssl3_read_bytes: */
	ubyte alert_fragment[DTLS1_AL_HEADER_LENGTH];
	uint alert_fragment_len;
	ubyte handshake_fragment[DTLS1_HM_HEADER_LENGTH];
	uint handshake_fragment_len;

	uint retransmitting;
	uint change_cipher_spec_ok;

	}
alias dtls1_state_st DTLS1_STATE;

struct dtls1_record_data_st {
	ubyte* packet;
	uint   packet_length;
	SSL3_BUFFER    rbuf;
	SSL3_RECORD    rrec;
	}
alias dtls1_record_data_st DTLS1_RECORD_DATA;


/* Timeout multipliers (timeout slice is defined in apps/timeouts.h */
enum DTLS1_TMO_READ_COUNT = 2;
enum DTLS1_TMO_WRITE_COUNT = 2;

enum DTLS1_TMO_ALERT_COUNT = 12;
