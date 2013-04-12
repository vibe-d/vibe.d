/* ssl/ssl2.h */
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

module deimos.openssl.ssl2;

import deimos.openssl._d_util;

import deimos.openssl.ssl; // Needed for SSL_ST_CONNECT, etc.

extern (C):
nothrow:

/* Protocol Version Codes */
enum SSL2_VERSION = 0x0002;
enum SSL2_VERSION_MAJOR = 0x00;
enum SSL2_VERSION_MINOR = 0x02;
/* enum SSL2_CLIENT_VERSION = 0x0002; */
/* enum SSL2_SERVER_VERSION = 0x0002; */

/* Protocol Message Codes */
enum SSL2_MT_ERROR = 0;
enum SSL2_MT_CLIENT_HELLO = 1;
enum SSL2_MT_CLIENT_MASTER_KEY = 2;
enum SSL2_MT_CLIENT_FINISHED = 3;
enum SSL2_MT_SERVER_HELLO = 4;
enum SSL2_MT_SERVER_VERIFY = 5;
enum SSL2_MT_SERVER_FINISHED = 6;
enum SSL2_MT_REQUEST_CERTIFICATE = 7;
enum SSL2_MT_CLIENT_CERTIFICATE = 8;

/* Error Message Codes */
enum SSL2_PE_UNDEFINED_ERROR = 0x0000;
enum SSL2_PE_NO_CIPHER = 0x0001;
enum SSL2_PE_NO_CERTIFICATE = 0x0002;
enum SSL2_PE_BAD_CERTIFICATE = 0x0004;
enum SSL2_PE_UNSUPPORTED_CERTIFICATE_TYPE = 0x0006;

/* Cipher Kind Values */
enum SSL2_CK_NULL_WITH_MD5 = 0x02000000; /* v3 */
enum SSL2_CK_RC4_128_WITH_MD5 = 0x02010080;
enum SSL2_CK_RC4_128_EXPORT40_WITH_MD5 = 0x02020080;
enum SSL2_CK_RC2_128_CBC_WITH_MD5 = 0x02030080;
enum SSL2_CK_RC2_128_CBC_EXPORT40_WITH_MD5 = 0x02040080;
enum SSL2_CK_IDEA_128_CBC_WITH_MD5 = 0x02050080;
enum SSL2_CK_DES_64_CBC_WITH_MD5 = 0x02060040;
enum SSL2_CK_DES_64_CBC_WITH_SHA = 0x02060140; /* v3 */
enum SSL2_CK_DES_192_EDE3_CBC_WITH_MD5 = 0x020700c0;
enum SSL2_CK_DES_192_EDE3_CBC_WITH_SHA = 0x020701c0; /* v3 */
enum SSL2_CK_RC4_64_WITH_MD5 = 0x02080080; /* MS hack */

enum SSL2_CK_DES_64_CFB64_WITH_MD5_1 = 0x02ff0800; /* SSLeay */
enum SSL2_CK_NULL = 0x02ff0810; /* SSLeay */

enum SSL2_TXT_DES_64_CFB64_WITH_MD5_1 = "DES-CFB-M1";
enum SSL2_TXT_NULL_WITH_MD5 = "NULL-MD5";
enum SSL2_TXT_RC4_128_WITH_MD5 = "RC4-MD5";
enum SSL2_TXT_RC4_128_EXPORT40_WITH_MD5 = "EXP-RC4-MD5";
enum SSL2_TXT_RC2_128_CBC_WITH_MD5 = "RC2-CBC-MD5";
enum SSL2_TXT_RC2_128_CBC_EXPORT40_WITH_MD5 = "EXP-RC2-CBC-MD5";
enum SSL2_TXT_IDEA_128_CBC_WITH_MD5 = "IDEA-CBC-MD5";
enum SSL2_TXT_DES_64_CBC_WITH_MD5 = "DES-CBC-MD5";
enum SSL2_TXT_DES_64_CBC_WITH_SHA = "DES-CBC-SHA";
enum SSL2_TXT_DES_192_EDE3_CBC_WITH_MD5 = "DES-CBC3-MD5";
enum SSL2_TXT_DES_192_EDE3_CBC_WITH_SHA = "DES-CBC3-SHA";
enum SSL2_TXT_RC4_64_WITH_MD5 = "RC4-64-MD5";

enum SSL2_TXT_NULL = "NULL";

/* Flags for the SSL_CIPHER.algorithm2 field */
enum SSL2_CF_5_BYTE_ENC = 0x01;
enum SSL2_CF_8_BYTE_ENC = 0x02;

/* Certificate Type Codes */
enum SSL2_CT_X509_CERTIFICATE = 0x01;

/* Authentication Type Code */
enum SSL2_AT_MD5_WITH_RSA_ENCRYPTION = 0x01;

enum SSL2_MAX_SSL_SESSION_ID_LENGTH = 32;

/* Upper/Lower Bounds */
enum SSL2_MAX_MASTER_KEY_LENGTH_IN_BITS = 256;
version (OPENSSL_SYS_MPE) {
enum SSL2_MAX_RECORD_LENGTH_2_BYTE_HEADER = 29998u;
} else {
enum SSL2_MAX_RECORD_LENGTH_2_BYTE_HEADER = 32767u;  /* 2^15-1 */
}
enum SSL2_MAX_RECORD_LENGTH_3_BYTE_HEADER = 16383; /* 2^14-1 */

enum SSL2_CHALLENGE_LENGTH = 16;
/*enum SSL2_CHALLENGE_LENGTH = 32; */
enum SSL2_MIN_CHALLENGE_LENGTH = 16;
enum SSL2_MAX_CHALLENGE_LENGTH = 32;
enum SSL2_CONNECTION_ID_LENGTH = 16;
enum SSL2_MAX_CONNECTION_ID_LENGTH = 16;
enum SSL2_SSL_SESSION_ID_LENGTH = 16;
enum SSL2_MAX_CERT_CHALLENGE_LENGTH = 32;
enum SSL2_MIN_CERT_CHALLENGE_LENGTH = 16;
enum SSL2_MAX_KEY_MATERIAL_LENGTH = 24;

// #ifndef HEADER_SSL_LOCL_H
alias char  CERT;
// #endif

struct ssl2_state_st
	{
	int three_byte_header;
	int clear_text;		/* clear text */
	int escape;		/* not used in SSLv2 */
	int ssl2_rollback;	/* used if SSLv23 rolled back to SSLv2 */

	/* non-blocking io info, used to make sure the same
	 * args were passwd */
	uint wnum;	/* number of bytes sent so far */
	int wpend_tot;
	const(ubyte)* wpend_buf;

	int wpend_off;	/* offset to data to write */
	int wpend_len; 	/* number of bytes passwd to write */
	int wpend_ret; 	/* number of bytes to return to caller */

	/* buffer raw data */
	int rbuf_left;
	int rbuf_offs;
	ubyte* rbuf;
	ubyte* wbuf;

	ubyte* write_ptr;/* used to point to the start due to
				  * 2/3 byte header. */

	uint padding;
	uint rlength; /* passed to ssl2_enc */
	int ract_data_length; /* Set when things are encrypted. */
	uint wlength; /* passed to ssl2_enc */
	int wact_data_length; /* Set when things are decrypted. */
	ubyte* ract_data;
	ubyte* wact_data;
	ubyte* mac_data;

	ubyte* read_key;
	ubyte* write_key;

		/* Stuff specifically to do with this SSL session */
	uint challenge_length;
	ubyte challenge[SSL2_MAX_CHALLENGE_LENGTH];
	uint conn_id_length;
	ubyte conn_id[SSL2_MAX_CONNECTION_ID_LENGTH];
	uint key_material_length;
	ubyte key_material[SSL2_MAX_KEY_MATERIAL_LENGTH*2];

	c_ulong read_sequence;
	c_ulong write_sequence;

	struct tmp_{
		uint conn_id_length;
		uint cert_type;
		uint cert_length;
		uint csl;
		uint clear;
		uint enc;
		ubyte ccl[SSL2_MAX_CERT_CHALLENGE_LENGTH];
		uint cipher_spec_length;
		uint session_id_length;
		uint clen;
		uint rlen;
		}
	tmp_ tmp;
	}
alias ssl2_state_st SSL2_STATE;

/* SSLv2 */
/* client */
enum SSL2_ST_SEND_CLIENT_HELLO_A = (0x10|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_HELLO_B = (0x11|SSL_ST_CONNECT);
enum SSL2_ST_GET_SERVER_HELLO_A = (0x20|SSL_ST_CONNECT);
enum SSL2_ST_GET_SERVER_HELLO_B = (0x21|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_MASTER_KEY_A = (0x30|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_MASTER_KEY_B = (0x31|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_FINISHED_A = (0x40|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_FINISHED_B = (0x41|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_CERTIFICATE_A = (0x50|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_CERTIFICATE_B = (0x51|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_CERTIFICATE_C = (0x52|SSL_ST_CONNECT);
enum SSL2_ST_SEND_CLIENT_CERTIFICATE_D = (0x53|SSL_ST_CONNECT);
enum SSL2_ST_GET_SERVER_VERIFY_A = (0x60|SSL_ST_CONNECT);
enum SSL2_ST_GET_SERVER_VERIFY_B = (0x61|SSL_ST_CONNECT);
enum SSL2_ST_GET_SERVER_FINISHED_A = (0x70|SSL_ST_CONNECT);
enum SSL2_ST_GET_SERVER_FINISHED_B = (0x71|SSL_ST_CONNECT);
enum SSL2_ST_CLIENT_START_ENCRYPTION = (0x80|SSL_ST_CONNECT);
enum SSL2_ST_X509_GET_CLIENT_CERTIFICATE = (0x90|SSL_ST_CONNECT);
/* server */
enum SSL2_ST_GET_CLIENT_HELLO_A = (0x10|SSL_ST_ACCEPT);
enum SSL2_ST_GET_CLIENT_HELLO_B = (0x11|SSL_ST_ACCEPT);
enum SSL2_ST_GET_CLIENT_HELLO_C = (0x12|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_SERVER_HELLO_A = (0x20|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_SERVER_HELLO_B = (0x21|SSL_ST_ACCEPT);
enum SSL2_ST_GET_CLIENT_MASTER_KEY_A = (0x30|SSL_ST_ACCEPT);
enum SSL2_ST_GET_CLIENT_MASTER_KEY_B = (0x31|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_SERVER_VERIFY_A = (0x40|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_SERVER_VERIFY_B = (0x41|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_SERVER_VERIFY_C = (0x42|SSL_ST_ACCEPT);
enum SSL2_ST_GET_CLIENT_FINISHED_A = (0x50|SSL_ST_ACCEPT);
enum SSL2_ST_GET_CLIENT_FINISHED_B = (0x51|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_SERVER_FINISHED_A = (0x60|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_SERVER_FINISHED_B = (0x61|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_REQUEST_CERTIFICATE_A = (0x70|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_REQUEST_CERTIFICATE_B = (0x71|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_REQUEST_CERTIFICATE_C = (0x72|SSL_ST_ACCEPT);
enum SSL2_ST_SEND_REQUEST_CERTIFICATE_D = (0x73|SSL_ST_ACCEPT);
enum SSL2_ST_SERVER_START_ENCRYPTION = (0x80|SSL_ST_ACCEPT);
enum SSL2_ST_X509_GET_SERVER_CERTIFICATE = (0x90|SSL_ST_ACCEPT);
