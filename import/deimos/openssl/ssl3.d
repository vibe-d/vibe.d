/* ssl/ssl3.h */
/* Copyright (C) 1995-1998 Eric Young (eay@cryptsoft.com)
 * All rights reserved.
 *
 * This package is an SSL implementation written
 * by Eric Young (eay@cryptsoft.com).
 * The implementation was written so as to conform with Netscapes SSL.
 *
 * This library is free for commercial and non-commercial use as long as
 * the following conditions are aheared to.  The following conditions
 * apply to all code found in this distribution, be it the RC4, RSA,
 * lhash, DES, etc., code; not just the SSL code.  The SSL documentation
 * included with this distribution is covered by the same copyright terms
 * except that the holder is Tim Hudson (tjh@cryptsoft.com).
 *
 * Copyright remains Eric Young's, and as such any Copyright notices in
 * the code are not to be removed.
 * If this package is used in a product, Eric Young should be given attribution
 * as the author of the parts of the library used.
 * This can be in the form of a textual message at program startup or
 * in documentation (online or textual) provided with the package.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the copyright
 *   notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *   must display the following acknowledgement:
 *   "This product includes cryptographic software written by
 *    Eric Young (eay@cryptsoft.com)"
 *   The word 'cryptographic' can be left out if the rouines from the library
 *   being used are not cryptographic related :-).
 * 4. If you include any Windows specific code (or a derivative thereof) from
 *   the apps directory (application code) you must include an acknowledgement:
 *   "This product includes software written by Tim Hudson (tjh@cryptsoft.com)"
 *
 * THIS SOFTWARE IS PROVIDED BY ERIC YOUNG ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * The licence and distribution terms for any publically available version or
 * derivative of this code cannot be changed.  i.e. this code cannot simply be
 * copied and put under another distribution licence
 * [including the GNU Public Licence.]
 */
/* ====================================================================
 * Copyright (c) 1998-2002 The OpenSSL Project.  All rights reserved.
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
 *   for use in the OpenSSL Toolkit. (http://www.openssl.org/)"
 *
 * 4. The names "OpenSSL Toolkit" and "OpenSSL Project" must not be used to
 *   endorse or promote products derived from this software without
 *   prior written permission. For written permission, please contact
 *   openssl-core@openssl.org.
 *
 * 5. Products derived from this software may not be called "OpenSSL"
 *   nor may "OpenSSL" appear in their names without prior written
 *   permission of the OpenSSL Project.
 *
 * 6. Redistributions of any form whatsoever must retain the following
 *   acknowledgment:
 *   "This product includes software developed by the OpenSSL Project
 *   for use in the OpenSSL Toolkit (http://www.openssl.org/)"
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
/* ====================================================================
 * Copyright 2002 Sun Microsystems, Inc. ALL RIGHTS RESERVED.
 * ECC cipher suite support in OpenSSL originally developed by
 * SUN MICROSYSTEMS, INC., and contributed to the OpenSSL project.
 */

module deimos.openssl.ssl3;

import deimos.openssl._d_util;

version(OPENSSL_NO_COMP) {} else {
public import deimos.openssl.comp;
}
public import deimos.openssl.buffer;
public import deimos.openssl.evp;
public import deimos.openssl.ssl;

extern (C):
nothrow:

/* Signalling cipher suite value: from draft-ietf-tls-renegotiation-03.txt */
enum SSL3_CK_SCSV = 0x030000FF;

enum SSL3_CK_RSA_NULL_MD5 = 0x03000001;
enum SSL3_CK_RSA_NULL_SHA = 0x03000002;
enum SSL3_CK_RSA_RC4_40_MD5 = 0x03000003;
enum SSL3_CK_RSA_RC4_128_MD5 = 0x03000004;
enum SSL3_CK_RSA_RC4_128_SHA = 0x03000005;
enum SSL3_CK_RSA_RC2_40_MD5 = 0x03000006;
enum SSL3_CK_RSA_IDEA_128_SHA = 0x03000007;
enum SSL3_CK_RSA_DES_40_CBC_SHA = 0x03000008;
enum SSL3_CK_RSA_DES_64_CBC_SHA = 0x03000009;
enum SSL3_CK_RSA_DES_192_CBC3_SHA = 0x0300000A;

enum SSL3_CK_DH_DSS_DES_40_CBC_SHA = 0x0300000B;
enum SSL3_CK_DH_DSS_DES_64_CBC_SHA = 0x0300000C;
enum SSL3_CK_DH_DSS_DES_192_CBC3_SHA = 0x0300000D;
enum SSL3_CK_DH_RSA_DES_40_CBC_SHA = 0x0300000E;
enum SSL3_CK_DH_RSA_DES_64_CBC_SHA = 0x0300000F;
enum SSL3_CK_DH_RSA_DES_192_CBC3_SHA = 0x03000010;

enum SSL3_CK_EDH_DSS_DES_40_CBC_SHA = 0x03000011;
enum SSL3_CK_EDH_DSS_DES_64_CBC_SHA = 0x03000012;
enum SSL3_CK_EDH_DSS_DES_192_CBC3_SHA = 0x03000013;
enum SSL3_CK_EDH_RSA_DES_40_CBC_SHA = 0x03000014;
enum SSL3_CK_EDH_RSA_DES_64_CBC_SHA = 0x03000015;
enum SSL3_CK_EDH_RSA_DES_192_CBC3_SHA = 0x03000016;

enum SSL3_CK_ADH_RC4_40_MD5 = 0x03000017;
enum SSL3_CK_ADH_RC4_128_MD5 = 0x03000018;
enum SSL3_CK_ADH_DES_40_CBC_SHA = 0x03000019;
enum SSL3_CK_ADH_DES_64_CBC_SHA = 0x0300001A;
enum SSL3_CK_ADH_DES_192_CBC_SHA = 0x0300001B;

version (none) {
	enum SSL3_CK_FZA_DMS_NULL_SHA = 0x0300001C;
	enum SSL3_CK_FZA_DMS_FZA_SHA = 0x0300001D;
	version (none) { /* Because it clashes with KRB5, is never used any more, and is safe
		 to remove according to David Hopwood <david.hopwood@zetnet.co.uk>
		 of the ietf-tls list */
	enum SSL3_CK_FZA_DMS_RC4_SHA = 0x0300001E;
	}
}

/*   VRS Additional Kerberos5 entries
 */
enum SSL3_CK_KRB5_DES_64_CBC_SHA = 0x0300001E;
enum SSL3_CK_KRB5_DES_192_CBC3_SHA = 0x0300001F;
enum SSL3_CK_KRB5_RC4_128_SHA = 0x03000020;
enum SSL3_CK_KRB5_IDEA_128_CBC_SHA = 0x03000021;
enum SSL3_CK_KRB5_DES_64_CBC_MD5 = 0x03000022;
enum SSL3_CK_KRB5_DES_192_CBC3_MD5 = 0x03000023;
enum SSL3_CK_KRB5_RC4_128_MD5 = 0x03000024;
enum SSL3_CK_KRB5_IDEA_128_CBC_MD5 = 0x03000025;

enum SSL3_CK_KRB5_DES_40_CBC_SHA = 0x03000026;
enum SSL3_CK_KRB5_RC2_40_CBC_SHA = 0x03000027;
enum SSL3_CK_KRB5_RC4_40_SHA = 0x03000028;
enum SSL3_CK_KRB5_DES_40_CBC_MD5 = 0x03000029;
enum SSL3_CK_KRB5_RC2_40_CBC_MD5 = 0x0300002A;
enum SSL3_CK_KRB5_RC4_40_MD5 = 0x0300002B;

enum SSL3_TXT_RSA_NULL_MD5 = "NULL-MD5";
enum SSL3_TXT_RSA_NULL_SHA = "NULL-SHA";
enum SSL3_TXT_RSA_RC4_40_MD5 = "EXP-RC4-MD5";
enum SSL3_TXT_RSA_RC4_128_MD5 = "RC4-MD5";
enum SSL3_TXT_RSA_RC4_128_SHA = "RC4-SHA";
enum SSL3_TXT_RSA_RC2_40_MD5 = "EXP-RC2-CBC-MD5";
enum SSL3_TXT_RSA_IDEA_128_SHA = "IDEA-CBC-SHA";
enum SSL3_TXT_RSA_DES_40_CBC_SHA = "EXP-DES-CBC-SHA";
enum SSL3_TXT_RSA_DES_64_CBC_SHA = "DES-CBC-SHA";
enum SSL3_TXT_RSA_DES_192_CBC3_SHA = "DES-CBC3-SHA";

enum SSL3_TXT_DH_DSS_DES_40_CBC_SHA = "EXP-DH-DSS-DES-CBC-SHA";
enum SSL3_TXT_DH_DSS_DES_64_CBC_SHA = "DH-DSS-DES-CBC-SHA";
enum SSL3_TXT_DH_DSS_DES_192_CBC3_SHA = "DH-DSS-DES-CBC3-SHA";
enum SSL3_TXT_DH_RSA_DES_40_CBC_SHA = "EXP-DH-RSA-DES-CBC-SHA";
enum SSL3_TXT_DH_RSA_DES_64_CBC_SHA = "DH-RSA-DES-CBC-SHA";
enum SSL3_TXT_DH_RSA_DES_192_CBC3_SHA = "DH-RSA-DES-CBC3-SHA";

enum SSL3_TXT_EDH_DSS_DES_40_CBC_SHA = "EXP-EDH-DSS-DES-CBC-SHA";
enum SSL3_TXT_EDH_DSS_DES_64_CBC_SHA = "EDH-DSS-DES-CBC-SHA";
enum SSL3_TXT_EDH_DSS_DES_192_CBC3_SHA = "EDH-DSS-DES-CBC3-SHA";
enum SSL3_TXT_EDH_RSA_DES_40_CBC_SHA = "EXP-EDH-RSA-DES-CBC-SHA";
enum SSL3_TXT_EDH_RSA_DES_64_CBC_SHA = "EDH-RSA-DES-CBC-SHA";
enum SSL3_TXT_EDH_RSA_DES_192_CBC3_SHA = "EDH-RSA-DES-CBC3-SHA";

enum SSL3_TXT_ADH_RC4_40_MD5 = "EXP-ADH-RC4-MD5";
enum SSL3_TXT_ADH_RC4_128_MD5 = "ADH-RC4-MD5";
enum SSL3_TXT_ADH_DES_40_CBC_SHA = "EXP-ADH-DES-CBC-SHA";
enum SSL3_TXT_ADH_DES_64_CBC_SHA = "ADH-DES-CBC-SHA";
enum SSL3_TXT_ADH_DES_192_CBC_SHA = "ADH-DES-CBC3-SHA";

version (none) {
	enum SSL3_TXT_FZA_DMS_NULL_SHA = "FZA-NULL-SHA";
	enum SSL3_TXT_FZA_DMS_FZA_SHA = "FZA-FZA-CBC-SHA";
	enum SSL3_TXT_FZA_DMS_RC4_SHA = "FZA-RC4-SHA";
}

enum SSL3_TXT_KRB5_DES_64_CBC_SHA = "KRB5-DES-CBC-SHA";
enum SSL3_TXT_KRB5_DES_192_CBC3_SHA = "KRB5-DES-CBC3-SHA";
enum SSL3_TXT_KRB5_RC4_128_SHA = "KRB5-RC4-SHA";
enum SSL3_TXT_KRB5_IDEA_128_CBC_SHA = "KRB5-IDEA-CBC-SHA";
enum SSL3_TXT_KRB5_DES_64_CBC_MD5 = "KRB5-DES-CBC-MD5";
enum SSL3_TXT_KRB5_DES_192_CBC3_MD5 = "KRB5-DES-CBC3-MD5";
enum SSL3_TXT_KRB5_RC4_128_MD5 = "KRB5-RC4-MD5";
enum SSL3_TXT_KRB5_IDEA_128_CBC_MD5 = "KRB5-IDEA-CBC-MD5";

enum SSL3_TXT_KRB5_DES_40_CBC_SHA = "EXP-KRB5-DES-CBC-SHA";
enum SSL3_TXT_KRB5_RC2_40_CBC_SHA = "EXP-KRB5-RC2-CBC-SHA";
enum SSL3_TXT_KRB5_RC4_40_SHA = "EXP-KRB5-RC4-SHA";
enum SSL3_TXT_KRB5_DES_40_CBC_MD5 = "EXP-KRB5-DES-CBC-MD5";
enum SSL3_TXT_KRB5_RC2_40_CBC_MD5 = "EXP-KRB5-RC2-CBC-MD5";
enum SSL3_TXT_KRB5_RC4_40_MD5 = "EXP-KRB5-RC4-MD5";

enum SSL3_SSL_SESSION_ID_LENGTH = 32;
enum SSL3_MAX_SSL_SESSION_ID_LENGTH = 32;

enum SSL3_MASTER_SECRET_SIZE = 48;
enum SSL3_RANDOM_SIZE = 32;
enum SSL3_SESSION_ID_SIZE = 32;
enum SSL3_RT_HEADER_LENGTH = 5;

/+
#ifndef SSL3_ALIGN_PAYLOAD
 /* Some will argue that this increases memory footprint, but it's
  * not actually true. Point is that malloc has to return at least
  * 64-bit aligned pointers, meaning that allocating 5 bytes wastes
  * 3 bytes in either case. Suggested pre-gaping simply moves these
  * wasted bytes from the end of allocated region to its front,
  * but makes data payload aligned, which improves performance:-) */
# define SSL3_ALIGN_PAYLOAD			8
#else
# if (SSL3_ALIGN_PAYLOAD&(SSL3_ALIGN_PAYLOAD-1))!=0
#  error "insane SSL3_ALIGN_PAYLOAD"
#  undef SSL3_ALIGN_PAYLOAD
# endif
#endif+/

/* This is the maximum MAC (digest) size used by the SSL library.
 * Currently maximum of 20 is used by SHA1, but we reserve for
 * future extension for 512-bit hashes.
 */

enum SSL3_RT_MAX_MD_SIZE = 64;

/* Maximum block size used in all ciphersuites. Currently 16 for AES.
 */

enum SSL_RT_MAX_CIPHER_BLOCK_SIZE = 16;

enum SSL3_RT_MAX_EXTRA = (16384);

/* Maximum plaintext length: defined by SSL/TLS standards */
enum SSL3_RT_MAX_PLAIN_LENGTH = 16384;
/* Maximum compression overhead: defined by SSL/TLS standards */
enum SSL3_RT_MAX_COMPRESSED_OVERHEAD = 1024;

/* The standards give a maximum encryption overhead of 1024 bytes.
 * In practice the value is lower than this. The overhead is the maximum
 * number of padding bytes (256) plus the mac size.
 */
enum SSL3_RT_MAX_ENCRYPTED_OVERHEAD = (256 + SSL3_RT_MAX_MD_SIZE);

/* OpenSSL currently only uses a padding length of at most one block so
 * the send overhead is smaller.
 */

enum SSL3_RT_SEND_MAX_ENCRYPTED_OVERHEAD =
			(SSL_RT_MAX_CIPHER_BLOCK_SIZE + SSL3_RT_MAX_MD_SIZE);

/* If compression isn't used don't include the compression overhead */

version (OPENSSL_NO_COMP) {
	enum SSL3_RT_MAX_COMPRESSED_LENGTH = SSL3_RT_MAX_PLAIN_LENGTH;
} else {
	enum SSL3_RT_MAX_COMPRESSED_LENGTH =
		(SSL3_RT_MAX_PLAIN_LENGTH+SSL3_RT_MAX_COMPRESSED_OVERHEAD);
}
enum SSL3_RT_MAX_ENCRYPTED_LENGTH =
		(SSL3_RT_MAX_ENCRYPTED_OVERHEAD+SSL3_RT_MAX_COMPRESSED_LENGTH);
enum SSL3_RT_MAX_PACKET_SIZE =
		(SSL3_RT_MAX_ENCRYPTED_LENGTH+SSL3_RT_HEADER_LENGTH);

enum SSL3_MD_CLIENT_FINISHED_CONST = "\x43\x4C\x4E\x54";
enum SSL3_MD_SERVER_FINISHED_CONST = "\x53\x52\x56\x52";

enum SSL3_VERSION = 0x0300;
enum SSL3_VERSION_MAJOR = 0x03;
enum SSL3_VERSION_MINOR = 0x00;

enum SSL3_RT_CHANGE_CIPHER_SPEC = 20;
enum SSL3_RT_ALERT = 21;
enum SSL3_RT_HANDSHAKE = 22;
enum SSL3_RT_APPLICATION_DATA = 23;

enum SSL3_AL_WARNING = 1;
enum SSL3_AL_FATAL = 2;

enum SSL3_AD_CLOSE_NOTIFY = 0;
enum SSL3_AD_UNEXPECTED_MESSAGE = 10;	/* fatal */
enum SSL3_AD_BAD_RECORD_MAC = 20;	/* fatal */
enum SSL3_AD_DECOMPRESSION_FAILURE = 30;	/* fatal */
enum SSL3_AD_HANDSHAKE_FAILURE = 40;	/* fatal */
enum SSL3_AD_NO_CERTIFICATE = 41;
enum SSL3_AD_BAD_CERTIFICATE = 42;
enum SSL3_AD_UNSUPPORTED_CERTIFICATE = 43;
enum SSL3_AD_CERTIFICATE_REVOKED = 44;
enum SSL3_AD_CERTIFICATE_EXPIRED = 45;
enum SSL3_AD_CERTIFICATE_UNKNOWN = 46;
enum SSL3_AD_ILLEGAL_PARAMETER = 47;	/* fatal */

struct ssl3_record_st {
/*r */	int type;               /* type of record */
/*rw*/	uint length;    /* How many bytes available */
/*r */	uint off;       /* read/write offset into 'buf' */
/*rw*/	ubyte* data;    /* pointer to the record data */
/*rw*/	ubyte* input;   /* where the decode bytes are */
/*r */	ubyte* comp;    /* only used with decompression - malloc()ed */
/*r */  c_ulong epoch;    /* epoch number, needed by DTLS1 */
/*r */  ubyte seq_num[8]; /* sequence number, needed by DTLS1 */
	}
alias ssl3_record_st SSL3_RECORD;

struct ssl3_buffer_st {
	ubyte* buf;     /* at least SSL3_RT_MAX_PACKET_SIZE bytes,
	                         * see ssl3_setup_buffers() */
	size_t len;             /* buffer size */
	int offset;             /* where to 'copy from' */
	int left;               /* how many bytes left */
	}
alias ssl3_buffer_st SSL3_BUFFER;

enum SSL3_CT_RSA_SIGN = 1;
enum SSL3_CT_DSS_SIGN = 2;
enum SSL3_CT_RSA_FIXED_DH = 3;
enum SSL3_CT_DSS_FIXED_DH = 4;
enum SSL3_CT_RSA_EPHEMERAL_DH = 5;
enum SSL3_CT_DSS_EPHEMERAL_DH = 6;
enum SSL3_CT_FORTEZZA_DMS = 20;
/* SSL3_CT_NUMBER is used to size arrays and it must be large
 * enough to contain all of the cert types defined either for
 * SSLv3 and TLSv1.
 */
enum SSL3_CT_NUMBER = 9;


enum SSL3_FLAGS_NO_RENEGOTIATE_CIPHERS = 0x0001;
enum SSL3_FLAGS_DELAY_CLIENT_FINISHED = 0x0002;
enum SSL3_FLAGS_POP_BUFFER = 0x0004;
enum TLS1_FLAGS_TLS_PADDING_BUG = 0x0008;
enum TLS1_FLAGS_SKIP_CERT_VERIFY = 0x0010;

struct ssl3_state_st
	{
	c_long flags;
	int delay_buf_pop_ret;

	ubyte read_sequence[8];
	int read_mac_secret_size;
	ubyte read_mac_secret[EVP_MAX_MD_SIZE];
	ubyte write_sequence[8];
	int write_mac_secret_size;
	ubyte write_mac_secret[EVP_MAX_MD_SIZE];

	ubyte server_random[SSL3_RANDOM_SIZE];
	ubyte client_random[SSL3_RANDOM_SIZE];

	/* flags for countermeasure against known-IV weakness */
	int need_empty_fragments;
	int empty_fragment_done;

	/* The value of 'extra' when the buffers were initialized */
	int init_extra;

	SSL3_BUFFER rbuf;	/* read IO goes into here */
	SSL3_BUFFER wbuf;	/* write IO goes into here */

	SSL3_RECORD rrec;	/* each decoded record goes in here */
	SSL3_RECORD wrec;	/* goes out from here */

	/* storage for Alert/Handshake protocol data received but not
	 * yet processed by ssl3_read_bytes: */
	ubyte alert_fragment[2];
	uint alert_fragment_len;
	ubyte handshake_fragment[4];
	uint handshake_fragment_len;

	/* partial write - check the numbers match */
	uint wnum;	/* number of bytes sent so far */
	int wpend_tot;		/* number bytes written */
	int wpend_type;
	int wpend_ret;		/* number of bytes submitted */
	const(ubyte)* wpend_buf;

	/* used during startup, digest all incoming/outgoing packets */
	BIO* handshake_buffer;
	/* When set of handshake digests is determined, buffer is hashed
	 * and freed and MD_CTX-es for all required digests are stored in
	 * this array */
	EVP_MD_CTX** handshake_dgst;
	/* this is set whenerver we see a change_cipher_spec message
	 * come in when we are not looking for one */
	int change_cipher_spec;

	int warn_alert;
	int fatal_alert;
	/* we allow one fatal and one warning alert to be outstanding,
	 * send close alert via the warning alert */
	int alert_dispatch;
	ubyte send_alert[2];

	/* This flag is set when we should renegotiate ASAP, basically when
	 * there is no more data in the read or write buffers */
	int renegotiate;
	int total_renegotiations;
	int num_renegotiations;

	int in_read_app_data;

	/* Opaque PRF input as used for the current handshake.
	 * These fields are used only if TLSEXT_TYPE_opaque_prf_input is defined
	 * (otherwise, they are merely present to improve binary compatibility) */
	void* client_opaque_prf_input;
	size_t client_opaque_prf_input_len;
	void* server_opaque_prf_input;
	size_t server_opaque_prf_input_len;

	struct tmp_ {
		/* actually only needs to be 16+20 */
		ubyte cert_verify_md[EVP_MAX_MD_SIZE*2];

		/* actually only need to be 16+20 for SSLv3 and 12 for TLS */
		ubyte finish_md[EVP_MAX_MD_SIZE*2];
		int finish_md_len;
		ubyte peer_finish_md[EVP_MAX_MD_SIZE*2];
		int peer_finish_md_len;

		c_ulong message_size;
		int message_type;

		/* used to hold the new cipher we are going to use */
		const(SSL_CIPHER)* new_cipher;
version(OPENSSL_NO_DH) {} else {
		DH* dh;
}

version(OPENSSL_NO_ECDH) {} else {
		EC_KEY* ecdh; /* holds short lived ECDH key */
}

		/* used when SSL_ST_FLUSH_DATA is entered */
		int next_state;

		int reuse_message;

		/* used for certificate requests */
		int cert_req;
		int ctype_num;
		char ctype[SSL3_CT_NUMBER];
		STACK_OF!(X509_NAME) *ca_names;

		int use_rsa_tmp;

		int key_block_length;
		ubyte* key_block;

		const(EVP_CIPHER)* new_sym_enc;
		const(EVP_MD)* new_hash;
		int new_mac_pkey_type;
		int new_mac_secret_size;
version(OPENSSL_NO_COMP) {
		char* new_compression;
} else {
		const(SSL_COMP)* new_compression;
}
		int cert_request;
		}
	tmp_ tmp;

        /* Connection binding to prevent renegotiation attacks */
        ubyte previous_client_finished[EVP_MAX_MD_SIZE];
        ubyte previous_client_finished_len;
        ubyte previous_server_finished[EVP_MAX_MD_SIZE];
        ubyte previous_server_finished_len;
        int send_connection_binding; /* TODOEKR */
	}
alias ssl3_state_st SSL3_STATE;


/* SSLv3 */
/*client */
/* extra state */
enum SSL3_ST_CW_FLUSH = (0x100|SSL_ST_CONNECT);
/* write to server */
enum SSL3_ST_CW_CLNT_HELLO_A = (0x110|SSL_ST_CONNECT);
enum SSL3_ST_CW_CLNT_HELLO_B = (0x111|SSL_ST_CONNECT);
/* read from server */
enum SSL3_ST_CR_SRVR_HELLO_A = (0x120|SSL_ST_CONNECT);
enum SSL3_ST_CR_SRVR_HELLO_B = (0x121|SSL_ST_CONNECT);
enum DTLS1_ST_CR_HELLO_VERIFY_REQUEST_A = (0x126|SSL_ST_CONNECT);
enum DTLS1_ST_CR_HELLO_VERIFY_REQUEST_B = (0x127|SSL_ST_CONNECT);
enum SSL3_ST_CR_CERT_A = (0x130|SSL_ST_CONNECT);
enum SSL3_ST_CR_CERT_B = (0x131|SSL_ST_CONNECT);
enum SSL3_ST_CR_KEY_EXCH_A = (0x140|SSL_ST_CONNECT);
enum SSL3_ST_CR_KEY_EXCH_B = (0x141|SSL_ST_CONNECT);
enum SSL3_ST_CR_CERT_REQ_A = (0x150|SSL_ST_CONNECT);
enum SSL3_ST_CR_CERT_REQ_B = (0x151|SSL_ST_CONNECT);
enum SSL3_ST_CR_SRVR_DONE_A = (0x160|SSL_ST_CONNECT);
enum SSL3_ST_CR_SRVR_DONE_B = (0x161|SSL_ST_CONNECT);
/* write to server */
enum SSL3_ST_CW_CERT_A = (0x170|SSL_ST_CONNECT);
enum SSL3_ST_CW_CERT_B = (0x171|SSL_ST_CONNECT);
enum SSL3_ST_CW_CERT_C = (0x172|SSL_ST_CONNECT);
enum SSL3_ST_CW_CERT_D = (0x173|SSL_ST_CONNECT);
enum SSL3_ST_CW_KEY_EXCH_A = (0x180|SSL_ST_CONNECT);
enum SSL3_ST_CW_KEY_EXCH_B = (0x181|SSL_ST_CONNECT);
enum SSL3_ST_CW_CERT_VRFY_A = (0x190|SSL_ST_CONNECT);
enum SSL3_ST_CW_CERT_VRFY_B = (0x191|SSL_ST_CONNECT);
enum SSL3_ST_CW_CHANGE_A = (0x1A0|SSL_ST_CONNECT);
enum SSL3_ST_CW_CHANGE_B = (0x1A1|SSL_ST_CONNECT);
enum SSL3_ST_CW_FINISHED_A = (0x1B0|SSL_ST_CONNECT);
enum SSL3_ST_CW_FINISHED_B = (0x1B1|SSL_ST_CONNECT);
/* read from server */
enum SSL3_ST_CR_CHANGE_A = (0x1C0|SSL_ST_CONNECT);
enum SSL3_ST_CR_CHANGE_B = (0x1C1|SSL_ST_CONNECT);
enum SSL3_ST_CR_FINISHED_A = (0x1D0|SSL_ST_CONNECT);
enum SSL3_ST_CR_FINISHED_B = (0x1D1|SSL_ST_CONNECT);
enum SSL3_ST_CR_SESSION_TICKET_A = (0x1E0|SSL_ST_CONNECT);
enum SSL3_ST_CR_SESSION_TICKET_B = (0x1E1|SSL_ST_CONNECT);
enum SSL3_ST_CR_CERT_STATUS_A = (0x1F0|SSL_ST_CONNECT);
enum SSL3_ST_CR_CERT_STATUS_B = (0x1F1|SSL_ST_CONNECT);

/* server */
/* extra state */
enum SSL3_ST_SW_FLUSH = (0x100|SSL_ST_ACCEPT);
/* read from client */
/* Do not change the number values, they do matter */
enum SSL3_ST_SR_CLNT_HELLO_A = (0x110|SSL_ST_ACCEPT);
enum SSL3_ST_SR_CLNT_HELLO_B = (0x111|SSL_ST_ACCEPT);
enum SSL3_ST_SR_CLNT_HELLO_C = (0x112|SSL_ST_ACCEPT);
/* write to client */
enum DTLS1_ST_SW_HELLO_VERIFY_REQUEST_A = (0x113|SSL_ST_ACCEPT);
enum DTLS1_ST_SW_HELLO_VERIFY_REQUEST_B = (0x114|SSL_ST_ACCEPT);
enum SSL3_ST_SW_HELLO_REQ_A = (0x120|SSL_ST_ACCEPT);
enum SSL3_ST_SW_HELLO_REQ_B = (0x121|SSL_ST_ACCEPT);
enum SSL3_ST_SW_HELLO_REQ_C = (0x122|SSL_ST_ACCEPT);
enum SSL3_ST_SW_SRVR_HELLO_A = (0x130|SSL_ST_ACCEPT);
enum SSL3_ST_SW_SRVR_HELLO_B = (0x131|SSL_ST_ACCEPT);
enum SSL3_ST_SW_CERT_A = (0x140|SSL_ST_ACCEPT);
enum SSL3_ST_SW_CERT_B = (0x141|SSL_ST_ACCEPT);
enum SSL3_ST_SW_KEY_EXCH_A = (0x150|SSL_ST_ACCEPT);
enum SSL3_ST_SW_KEY_EXCH_B = (0x151|SSL_ST_ACCEPT);
enum SSL3_ST_SW_CERT_REQ_A = (0x160|SSL_ST_ACCEPT);
enum SSL3_ST_SW_CERT_REQ_B = (0x161|SSL_ST_ACCEPT);
enum SSL3_ST_SW_SRVR_DONE_A = (0x170|SSL_ST_ACCEPT);
enum SSL3_ST_SW_SRVR_DONE_B = (0x171|SSL_ST_ACCEPT);
/* read from client */
enum SSL3_ST_SR_CERT_A = (0x180|SSL_ST_ACCEPT);
enum SSL3_ST_SR_CERT_B = (0x181|SSL_ST_ACCEPT);
enum SSL3_ST_SR_KEY_EXCH_A = (0x190|SSL_ST_ACCEPT);
enum SSL3_ST_SR_KEY_EXCH_B = (0x191|SSL_ST_ACCEPT);
enum SSL3_ST_SR_CERT_VRFY_A = (0x1A0|SSL_ST_ACCEPT);
enum SSL3_ST_SR_CERT_VRFY_B = (0x1A1|SSL_ST_ACCEPT);
enum SSL3_ST_SR_CHANGE_A = (0x1B0|SSL_ST_ACCEPT);
enum SSL3_ST_SR_CHANGE_B = (0x1B1|SSL_ST_ACCEPT);
enum SSL3_ST_SR_FINISHED_A = (0x1C0|SSL_ST_ACCEPT);
enum SSL3_ST_SR_FINISHED_B = (0x1C1|SSL_ST_ACCEPT);
/* write to client */
enum SSL3_ST_SW_CHANGE_A = (0x1D0|SSL_ST_ACCEPT);
enum SSL3_ST_SW_CHANGE_B = (0x1D1|SSL_ST_ACCEPT);
enum SSL3_ST_SW_FINISHED_A = (0x1E0|SSL_ST_ACCEPT);
enum SSL3_ST_SW_FINISHED_B = (0x1E1|SSL_ST_ACCEPT);
enum SSL3_ST_SW_SESSION_TICKET_A = (0x1F0|SSL_ST_ACCEPT);
enum SSL3_ST_SW_SESSION_TICKET_B = (0x1F1|SSL_ST_ACCEPT);
enum SSL3_ST_SW_CERT_STATUS_A = (0x200|SSL_ST_ACCEPT);
enum SSL3_ST_SW_CERT_STATUS_B = (0x201|SSL_ST_ACCEPT);

enum SSL3_MT_HELLO_REQUEST = 0;
enum SSL3_MT_CLIENT_HELLO = 1;
enum SSL3_MT_SERVER_HELLO = 2;
enum SSL3_MT_NEWSESSION_TICKET = 4;
enum SSL3_MT_CERTIFICATE = 11;
enum SSL3_MT_SERVER_KEY_EXCHANGE = 12;
enum SSL3_MT_CERTIFICATE_REQUEST = 13;
enum SSL3_MT_SERVER_DONE = 14;
enum SSL3_MT_CERTIFICATE_VERIFY = 15;
enum SSL3_MT_CLIENT_KEY_EXCHANGE = 16;
enum SSL3_MT_FINISHED = 20;
enum SSL3_MT_CERTIFICATE_STATUS = 22;
enum DTLS1_MT_HELLO_VERIFY_REQUEST = 3;


enum SSL3_MT_CCS = 1;

/* These are used when changing over to a new cipher */
enum SSL3_CC_READ = 0x01;
enum SSL3_CC_WRITE = 0x02;
enum SSL3_CC_CLIENT = 0x10;
enum SSL3_CC_SERVER = 0x20;
enum SSL3_CHANGE_CIPHER_CLIENT_WRITE = (SSL3_CC_CLIENT|SSL3_CC_WRITE);
enum SSL3_CHANGE_CIPHER_SERVER_READ = (SSL3_CC_SERVER|SSL3_CC_READ);
enum SSL3_CHANGE_CIPHER_CLIENT_READ = (SSL3_CC_CLIENT|SSL3_CC_READ);
enum SSL3_CHANGE_CIPHER_SERVER_WRITE = (SSL3_CC_SERVER|SSL3_CC_WRITE);
