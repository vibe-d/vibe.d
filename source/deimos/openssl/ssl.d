/* ssl/ssl.h */
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
 * Copyright (c) 1998-2007 The OpenSSL Project.  All rights reserved.
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
/* ====================================================================
 * Copyright 2005 Nokia. All rights reserved.
 *
 * The portions of the attached software ("Contribution") is developed by
 * Nokia Corporation and is licensed pursuant to the OpenSSL open source
 * license.
 *
 * The Contribution, originally written by Mika Kousa and Pasi Eronen of
 * Nokia Corporation, consists of the "PSK" (Pre-Shared Key) ciphersuites
 * support (see RFC 4279) to OpenSSL.
 *
 * No patent licenses or other rights except those expressly stated in
 * the OpenSSL open source license shall be deemed granted or received
 * expressly, by implication, estoppel, or otherwise.
 *
 * No assurances are provided by Nokia that the Contribution does not
 * infringe the patent or other intellectual property rights of any third
 * party or that the license provides you with all the necessary rights
 * to make use of the Contribution.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND. IN
 * ADDITION TO THE DISCLAIMERS INCLUDED IN THE LICENSE, NOKIA
 * SPECIFICALLY DISCLAIMS ANY LIABILITY FOR CLAIMS BROUGHT BY YOU OR ANY
 * OTHER ENTITY BASED ON INFRINGEMENT OF INTELLECTUAL PROPERTY RIGHTS OR
 * OTHERWISE.
 */

module deimos.openssl.ssl;

import deimos.openssl._d_util;

import deimos.openssl.x509_vfy; // Needed for x509_store_st.
import deimos.openssl.ssl2; // Needed for SSL2_TXT_NULL_WITH_MD5, etc.
import deimos.openssl.ssl3; // Needed for SSL3_TXT_KRB5_DES_64_CBC_SHA, etc.
version (OPENSSL_NO_KRB5) {} else {
	import deimos.openssl.kssl; // Needed for KSSL_CTX.
}

// Declare cert_st used multiple times below.
struct cert_st;

public import deimos.openssl.e_os2;

version(OPENSSL_NO_COMP) {} else {
public import deimos.openssl.comp;
}
version(OPENSSL_NO_BIO) {} else {
public import deimos.openssl.bio;
}
version (OPENSSL_NO_DEPRECATED) {} else {
version(OPENSSL_NO_X509) {} else {
public import deimos.openssl.x509;
}
public import deimos.openssl.crypto;
public import deimos.openssl.buffer;
}
public import deimos.openssl.lhash; // Needed for DECLARE_LHASH_OF.
public import deimos.openssl.pem;
public import deimos.openssl.hmac;

public import deimos.openssl.kssl;
public import deimos.openssl.safestack;
public import deimos.openssl.symhacks;

extern (C):
nothrow:

/* SSLeay version number for ASN.1 encoding of the session information */
/* Version 0 - initial version
 * Version 1 - added the optional peer certificate
 */
enum SSL_SESSION_ASN1_VERSION = 0x0001;

/* text strings for the ciphers */
alias SSL2_TXT_NULL_WITH_MD5 SSL_TXT_NULL_WITH_MD5;
alias SSL2_TXT_RC4_128_WITH_MD5 SSL_TXT_RC4_128_WITH_MD5;
alias SSL2_TXT_RC4_128_EXPORT40_WITH_MD5 SSL_TXT_RC4_128_EXPORT40_WITH_MD5;
alias SSL2_TXT_RC2_128_CBC_WITH_MD5 SSL_TXT_RC2_128_CBC_WITH_MD5;
alias SSL2_TXT_RC2_128_CBC_EXPORT40_WITH_MD5 SSL_TXT_RC2_128_CBC_EXPORT40_WITH_MD5;
alias SSL2_TXT_IDEA_128_CBC_WITH_MD5 SSL_TXT_IDEA_128_CBC_WITH_MD5;
alias SSL2_TXT_DES_64_CBC_WITH_MD5 SSL_TXT_DES_64_CBC_WITH_MD5;
alias SSL2_TXT_DES_64_CBC_WITH_SHA SSL_TXT_DES_64_CBC_WITH_SHA;
alias SSL2_TXT_DES_192_EDE3_CBC_WITH_MD5 SSL_TXT_DES_192_EDE3_CBC_WITH_MD5;
alias SSL2_TXT_DES_192_EDE3_CBC_WITH_SHA SSL_TXT_DES_192_EDE3_CBC_WITH_SHA;

/*   VRS Additional Kerberos5 entries
 */
alias SSL3_TXT_KRB5_DES_64_CBC_SHA SSL_TXT_KRB5_DES_64_CBC_SHA;
alias SSL3_TXT_KRB5_DES_192_CBC3_SHA SSL_TXT_KRB5_DES_192_CBC3_SHA;
alias SSL3_TXT_KRB5_RC4_128_SHA SSL_TXT_KRB5_RC4_128_SHA;
alias SSL3_TXT_KRB5_IDEA_128_CBC_SHA SSL_TXT_KRB5_IDEA_128_CBC_SHA;
alias SSL3_TXT_KRB5_DES_64_CBC_MD5 SSL_TXT_KRB5_DES_64_CBC_MD5;
alias SSL3_TXT_KRB5_DES_192_CBC3_MD5 SSL_TXT_KRB5_DES_192_CBC3_MD5;
alias SSL3_TXT_KRB5_RC4_128_MD5 SSL_TXT_KRB5_RC4_128_MD5;
alias SSL3_TXT_KRB5_IDEA_128_CBC_MD5 SSL_TXT_KRB5_IDEA_128_CBC_MD5;

alias SSL3_TXT_KRB5_DES_40_CBC_SHA SSL_TXT_KRB5_DES_40_CBC_SHA;
alias SSL3_TXT_KRB5_RC2_40_CBC_SHA SSL_TXT_KRB5_RC2_40_CBC_SHA;
alias SSL3_TXT_KRB5_RC4_40_SHA SSL_TXT_KRB5_RC4_40_SHA;
alias SSL3_TXT_KRB5_DES_40_CBC_MD5 SSL_TXT_KRB5_DES_40_CBC_MD5;
alias SSL3_TXT_KRB5_RC2_40_CBC_MD5 SSL_TXT_KRB5_RC2_40_CBC_MD5;
alias SSL3_TXT_KRB5_RC4_40_MD5 SSL_TXT_KRB5_RC4_40_MD5;

// Oversight in the original headers: Already defined above.
// alias SSL3_TXT_KRB5_DES_40_CBC_SHA SSL_TXT_KRB5_DES_40_CBC_SHA;
// alias SSL3_TXT_KRB5_DES_40_CBC_MD5 SSL_TXT_KRB5_DES_40_CBC_MD5;
// alias SSL3_TXT_KRB5_DES_64_CBC_SHA SSL_TXT_KRB5_DES_64_CBC_SHA;
// alias SSL3_TXT_KRB5_DES_64_CBC_MD5 SSL_TXT_KRB5_DES_64_CBC_MD5;
// alias SSL3_TXT_KRB5_DES_192_CBC3_SHA SSL_TXT_KRB5_DES_192_CBC3_SHA;
// alias SSL3_TXT_KRB5_DES_192_CBC3_MD5 SSL_TXT_KRB5_DES_192_CBC3_MD5;
enum SSL_MAX_KRB5_PRINCIPAL_LENGTH = 256;

enum SSL_MAX_SSL_SESSION_ID_LENGTH = 32;
enum SSL_MAX_SID_CTX_LENGTH = 32;

enum SSL_MIN_RSA_MODULUS_LENGTH_IN_BYTES = (512/8);
enum SSL_MAX_KEY_ARG_LENGTH = 8;
enum SSL_MAX_MASTER_KEY_LENGTH = 48;


/* These are used to specify which ciphers to use and not to use */

enum SSL_TXT_EXP40 = "EXPORT40";
enum SSL_TXT_EXP56 = "EXPORT56";
enum SSL_TXT_LOW = "LOW";
enum SSL_TXT_MEDIUM = "MEDIUM";
enum SSL_TXT_HIGH = "HIGH";
enum SSL_TXT_FIPS = "FIPS";

enum SSL_TXT_kFZA = "kFZA"; /* unused! */
enum SSL_TXT_aFZA = "aFZA"; /* unused! */
enum SSL_TXT_eFZA = "eFZA"; /* unused! */
enum SSL_TXT_FZA = "FZA";  /* unused! */

enum SSL_TXT_aNULL = "aNULL";
enum SSL_TXT_eNULL = "eNULL";
enum SSL_TXT_NULL = "NULL";

enum SSL_TXT_kRSA = "kRSA";
enum SSL_TXT_kDHr = "kDHr"; /* no such ciphersuites supported! */
enum SSL_TXT_kDHd = "kDHd"; /* no such ciphersuites supported! */
enum SSL_TXT_kDH = "kDH";  /* no such ciphersuites supported! */
enum SSL_TXT_kEDH = "kEDH";
enum SSL_TXT_kKRB5 = "kKRB5";
enum SSL_TXT_kECDHr = "kECDHr";
enum SSL_TXT_kECDHe = "kECDHe";
enum SSL_TXT_kECDH = "kECDH";
enum SSL_TXT_kEECDH = "kEECDH";
enum SSL_TXT_kPSK = "kPSK";
enum SSL_TXT_kGOST = "kGOST";

enum SSL_TXT_aRSA = "aRSA";
enum SSL_TXT_aDSS = "aDSS";
enum SSL_TXT_aDH = "aDH"; /* no such ciphersuites supported! */
enum SSL_TXT_aECDH = "aECDH";
enum SSL_TXT_aKRB5 = "aKRB5";
enum SSL_TXT_aECDSA = "aECDSA";
enum SSL_TXT_aPSK = "aPSK";
enum SSL_TXT_aGOST94 = "aGOST94";
enum SSL_TXT_aGOST01 = "aGOST01";
enum SSL_TXT_aGOST = "aGOST";

enum SSL_TXT_DSS = "DSS";
enum SSL_TXT_DH = "DH";
enum SSL_TXT_EDH = "EDH"; /* same as "kEDH:-ADH" */
enum SSL_TXT_ADH = "ADH";
enum SSL_TXT_RSA = "RSA";
enum SSL_TXT_ECDH = "ECDH";
enum SSL_TXT_EECDH = "EECDH"; /* same as "kEECDH:-AECDH" */
enum SSL_TXT_AECDH = "AECDH";
enum SSL_TXT_ECDSA = "ECDSA";
enum SSL_TXT_KRB5 = "KRB5";
enum SSL_TXT_PSK = "PSK";

enum SSL_TXT_DES = "DES";
enum SSL_TXT_3DES = "3DES";
enum SSL_TXT_RC4 = "RC4";
enum SSL_TXT_RC2 = "RC2";
enum SSL_TXT_IDEA = "IDEA";
enum SSL_TXT_SEED = "SEED";
enum SSL_TXT_AES128 = "AES128";
enum SSL_TXT_AES256 = "AES256";
enum SSL_TXT_AES = "AES";
enum SSL_TXT_CAMELLIA128 = "CAMELLIA128";
enum SSL_TXT_CAMELLIA256 = "CAMELLIA256";
enum SSL_TXT_CAMELLIA = "CAMELLIA";

enum SSL_TXT_MD5 = "MD5";
enum SSL_TXT_SHA1 = "SHA1";
enum SSL_TXT_SHA = "SHA"; /* same as "SHA1" */
enum SSL_TXT_GOST94 = "GOST94";
enum SSL_TXT_GOST89MAC = "GOST89MAC";

enum SSL_TXT_SSLV2 = "SSLv2";
enum SSL_TXT_SSLV3 = "SSLv3";
enum SSL_TXT_TLSV1 = "TLSv1";

enum SSL_TXT_EXP = "EXP";
enum SSL_TXT_EXPORT = "EXPORT";

enum SSL_TXT_ALL = "ALL";

/*
 * COMPLEMENTOF* definitions. These identifiers are used to (de-select)
 * ciphers normally not being used.
 * Example: "RC4" will activate all ciphers using RC4 including ciphers
 * without authentication, which would normally disabled by DEFAULT (due
 * the "!ADH" being part of default). Therefore "RC4:!COMPLEMENTOFDEFAULT"
 * will make sure that it is also disabled in the specific selection.
 * COMPLEMENTOF* identifiers are portable between version_, as adjustments
 * to the default cipher setup will also be included here.
 *
 * COMPLEMENTOFDEFAULT does not experience the same special treatment that
 * DEFAULT gets, as only selection is being done and no sorting as needed
 * for DEFAULT.
 */
enum SSL_TXT_CMPALL = "COMPLEMENTOFALL";
enum SSL_TXT_CMPDEF = "COMPLEMENTOFDEFAULT";

/* The following cipher list is used by default.
 * It also is substituted when an application-defined cipher list string
 * starts with 'DEFAULT'. */
enum SSL_DEFAULT_CIPHER_LIST = "ALL:!aNULL:!eNULL:!SSLv2";
/* As of OpenSSL 1.0.0, ssl_create_cipher_list() in ssl/ssl_ciph.c always
 * starts with a reasonable order, and all we have to do for DEFAULT is
 * throwing out anonymous and unencrypted ciphersuites!
 * (The latter are not actually enabled by ALL, but "ALL:RSA" would enable
 * some of them.)
 */

/* Used in SSL_set_shutdown()/SSL_get_shutdown(); */
enum SSL_SENT_SHUTDOWN = 1;
enum SSL_RECEIVED_SHUTDOWN = 2;

extern (C):
nothrow:

version (OPENSSL_NO_RSA) { version = OPENSSL_NO_SSL2; }
version (OPENSSL_NO_MD5) { version = OPENSSL_NO_SSL2; }

alias X509_FILETYPE_ASN1 SSL_FILETYPE_ASN1;
alias X509_FILETYPE_PEM SSL_FILETYPE_PEM;

/* This is needed to stop compilers complaining about the
 * 'ssl_st* ' function parameters used to prototype callbacks
 * in SSL_CTX. */
alias ssl_st* ssl_crock_st;
import deimos.openssl.tls1;
alias tls_session_ticket_ext_st TLS_SESSION_TICKET_EXT;

/* used to hold info on the particular ciphers used */
struct ssl_cipher_st {
	int valid;
	const(char)* name;		/* text name */
	c_ulong id;		/* id, 4 bytes, first is version */

	/* changed in 0.9.9: these four used to be portions of a single value 'algorithms' */
	c_ulong algorithm_mkey;	/* key exchange algorithm */
	c_ulong algorithm_auth;	/* server authentication */
	c_ulong algorithm_enc;	/* symmetric encryption */
	c_ulong algorithm_mac;	/* symmetric authentication */
	c_ulong algorithm_ssl;	/* (major) protocol version */

	c_ulong algo_strength;	/* strength and export flags */
	c_ulong algorithm2;	/* Extra flags */
	int strength_bits;		/* Number of bits really used */
	int alg_bits;			/* Number of bits for algorithm */
	}
alias ssl_cipher_st SSL_CIPHER;

/+mixin DECLARE_STACK_OF!(SSL_CIPHER);+/

alias ExternC!(int function(SSL* s, const(ubyte)* data, int len, void* arg)) tls_session_ticket_ext_cb_fn;
alias ExternC!(int function(SSL* s, void* secret, int* secret_len, STACK_OF!(SSL_CIPHER) *peer_ciphers, SSL_CIPHER** cipher, void* arg)) tls_session_secret_cb_fn;

/* Used to hold functions for SSLv2 or SSLv3/TLSv1 functions */
struct ssl_method_st {
	int version_;
	ExternC!(int function(SSL* s)) ssl_new;
	ExternC!(void function(SSL* s)) ssl_clear;
	ExternC!(void function(SSL* s)) ssl_free;
	ExternC!(int function(SSL* s)) ssl_accept;
	ExternC!(int function(SSL* s)) ssl_connect;
	ExternC!(int function(SSL* s,void* buf,int len)) ssl_read;
	ExternC!(int function(SSL* s,void* buf,int len)) ssl_peek;
	ExternC!(int function(SSL* s,const(void)* buf,int len)) ssl_write;
	ExternC!(int function(SSL* s)) ssl_shutdown;
	ExternC!(int function(SSL* s)) ssl_renegotiate;
	ExternC!(int function(SSL* s)) ssl_renegotiate_check;
	ExternC!(c_long function(SSL* s, int st1, int stn, int mt, c_long
		max, int* ok)) ssl_get_message;
	ExternC!(int function(SSL* s, int type, ubyte* buf, int len,
		int peek)) ssl_read_bytes;
	ExternC!(int function(SSL* s, int type, const(void)* buf_, int len)) ssl_write_bytes;
	ExternC!(int function(SSL* s)) ssl_dispatch_alert;
	ExternC!(c_long function(SSL* s,int cmd,c_long larg,void* parg)) ssl_ctrl;
	ExternC!(c_long function(SSL_CTX* ctx,int cmd,c_long larg,void* parg)) ssl_ctx_ctrl;
	const ExternC!(SSL_CIPHER* function(const(ubyte)* ptr)) get_cipher_by_char;
	ExternC!(int function(const(SSL_CIPHER)* cipher,ubyte* ptr)) put_cipher_by_char;
	ExternC!(int function(const(SSL)* s)) ssl_pending;
	ExternC!(int function()) num_ciphers;
	const ExternC!(SSL_CIPHER* function(uint ncipher)) get_cipher;
	const ExternC!(ssl_method_st* function(int version_)) get_ssl_method;
	ExternC!(c_long function()) get_timeout;
	struct ssl3_enc_method;
	ssl3_enc_method* ssl3_enc; /* Extra SSLv3/TLS stuff */
	ExternC!(int function()) ssl_version;
	ExternC!(c_long function(SSL* s, int cb_id, ExternC!(void function()) fp)) ssl_callback_ctrl;
	ExternC!(c_long function(SSL_CTX* s, int cb_id, ExternC!(void function()) fp)) ssl_ctx_callback_ctrl;
	}
alias ssl_method_st SSL_METHOD;

/* Lets make this into an ASN.1 type structure as follows
 * SSL_SESSION_ID ::= SEQUENCE {
 *	version 		INTEGER,	-- structure version number
 *	SSLversion 		INTEGER,	-- SSL version number
 *	Cipher 			OCTET STRING,	-- the 3 byte cipher ID
 *	Session_ID 		OCTET STRING,	-- the Session ID
 *	Master_key 		OCTET STRING,	-- the master key
 *	KRB5_principal		OCTET STRING	-- optional Kerberos principal
 *	Key_Arg [ 0 ] IMPLICIT	OCTET STRING,	-- the optional Key argument
 *	Time [ 1 ] EXPLICIT	INTEGER,	-- optional Start Time
 *	Timeout [ 2 ] EXPLICIT	INTEGER,	-- optional Timeout ins seconds
 *	Peer [ 3 ] EXPLICIT	X509,		-- optional Peer Certificate
 *	Session_ID_context [ 4 ] EXPLICIT OCTET STRING,   -- the Session ID context
 *	Verify_result [ 5 ] EXPLICIT INTEGER,   -- X509_V_... code for `Peer'
 *	HostName [ 6 ] EXPLICIT OCTET STRING,   -- optional HostName from servername TLS extension
 *	ECPointFormatList [ 7 ] OCTET STRING,     -- optional EC point format list from TLS extension
 *	PSK_identity_hint [ 8 ] EXPLICIT OCTET STRING, -- optional PSK identity hint
 *	PSK_identity [ 9 ] EXPLICIT OCTET STRING -- optional PSK identity
 *	}
 * Look in ssl/ssl_asn1.c for more details
 * I'm using EXPLICIT tags so I can read the damn things using asn1parse :-).
 */
struct ssl_session_st
	{
	int ssl_version;	/* what ssl version session info is
				 * being kept in here? */

	/* only really used in SSLv2 */
	uint key_arg_length;
	ubyte key_arg[SSL_MAX_KEY_ARG_LENGTH];
	int master_key_length;
	ubyte master_key[SSL_MAX_MASTER_KEY_LENGTH];
	/* session_id - valid? */
	uint session_id_length;
	ubyte session_id[SSL_MAX_SSL_SESSION_ID_LENGTH];
	/* this is used to determine whether the session is being reused in
	 * the appropriate context. It is up to the application to set this,
	 * via SSL_new */
	uint sid_ctx_length;
	ubyte sid_ctx[SSL_MAX_SID_CTX_LENGTH];

version(OPENSSL_NO_KRB5) {} else {
        uint krb5_client_princ_len;
        ubyte krb5_client_princ[SSL_MAX_KRB5_PRINCIPAL_LENGTH];
} /* OPENSSL_NO_KRB5 */
version(OPENSSL_NO_PSK) {} else {
	char* psk_identity_hint;
	char* psk_identity;
}
	int not_resumable;

	/* The cert is the certificate used to establish this connection */
	struct sess_cert_st;
	sess_cert_st /* SESS_CERT */ *sess_cert;

	/* This is the cert for the other end.
	 * On clients, it will be the same as sess_cert->peer_key->x509
	 * (the latter is not enough as sess_cert is not retained
	 * in the external representation of sessions, see ssl_asn1.c). */
	X509* peer;
	/* when app_verify_callback accepts a session where the peer's certificate
	 * is not ok, we must remember the error for session reuse: */
	c_long verify_result; /* only for servers */

	int references;
	c_long timeout;
	c_long time;

	uint compress_meth;	/* Need to lookup the method */

	const(SSL_CIPHER)* cipher;
	c_ulong cipher_id;	/* when ASN.1 loaded, this
					 * needs to be used to load
					 * the 'cipher' structure */

	STACK_OF!(SSL_CIPHER) *ciphers; /* shared ciphers? */

	CRYPTO_EX_DATA ex_data; /* application specific data */

	/* These are used to make removal of session-ids more
	 * efficient and to implement a maximum cache size. */
	ssl_session_st* prev,next;
version (OPENSSL_NO_TLSEXT) {} else {
	char* tlsext_hostname;
version(OPENSSL_NO_EC) {} else {
	size_t tlsext_ecpointformatlist_length;
	ubyte* tlsext_ecpointformatlist; /* peer's list */
	size_t tlsext_ellipticcurvelist_length;
	ubyte* tlsext_ellipticcurvelist; /* peer's list */
} /* OPENSSL_NO_EC */
	/* RFC4507 info */
	ubyte* tlsext_tick;	/* Session ticket */
	size_t	tlsext_ticklen;		/* Session ticket length */
	c_long tlsext_tick_lifetime_hint;	/* Session lifetime hint in seconds */
}
	}
alias ssl_session_st SSL_SESSION;


enum SSL_OP_MICROSOFT_SESS_ID_BUG = 0x00000001;
enum SSL_OP_NETSCAPE_CHALLENGE_BUG = 0x00000002;
/* Allow initial connection to servers that don't support RI */
enum SSL_OP_LEGACY_SERVER_CONNECT = 0x00000004;
enum SSL_OP_NETSCAPE_REUSE_CIPHER_CHANGE_BUG = 0x00000008;
enum SSL_OP_SSLREF2_REUSE_CERT_TYPE_BUG = 0x00000010;
enum SSL_OP_MICROSOFT_BIG_SSLV3_BUFFER = 0x00000020;
enum SSL_OP_MSIE_SSLV2_RSA_PADDING = 0x00000040; /* no effect since 0.9.7h and 0.9.8b */
enum SSL_OP_SSLEAY_080_CLIENT_DH_BUG = 0x00000080;
enum SSL_OP_TLS_D5_BUG = 0x00000100;
enum SSL_OP_TLS_BLOCK_PADDING_BUG = 0x00000200;

/* Disable SSL 3.0/TLS 1.0 CBC vulnerability workaround that was added
 * in OpenSSL 0.9.6d.  Usually (depending on the application protocol)
 * the workaround is not needed.  Unfortunately some broken SSL/TLS
 * implementations cannot handle it at all, which is why we include
 * it in SSL_OP_ALL. */
enum SSL_OP_DONT_INSERT_EMPTY_FRAGMENTS = 0x00000800; /* added in 0.9.6e */

/* SSL_OP_ALL: various bug workarounds that should be rather harmless.
 *            This used to be 0x000FFFFFL before 0.9.7. */
enum SSL_OP_ALL = 0x80000FFF;

/* DTLS options */
enum SSL_OP_NO_QUERY_MTU = 0x00001000;
/* Turn on Cookie Exchange (on relevant for servers) */
enum SSL_OP_COOKIE_EXCHANGE = 0x00002000;
/* Don't use RFC4507 ticket extension */
enum SSL_OP_NO_TICKET = 0x00004000;
/* Use Cisco's "speshul" version of DTLS_BAD_VER (as client)  */
enum SSL_OP_CISCO_ANYCONNECT = 0x00008000;

/* As server, disallow session resumption on renegotiation */
enum SSL_OP_NO_SESSION_RESUMPTION_ON_RENEGOTIATION = 0x00010000;
/* Don't use compression even if supported */
enum SSL_OP_NO_COMPRESSION = 0x00020000;
/* Permit unsafe legacy renegotiation */
enum SSL_OP_ALLOW_UNSAFE_LEGACY_RENEGOTIATION = 0x00040000;
/* If set, always create a new key when using tmp_ecdh parameters */
enum SSL_OP_SINGLE_ECDH_USE = 0x00080000;
/* If set, always create a new key when using tmp_dh parameters */
enum SSL_OP_SINGLE_DH_USE = 0x00100000;
/* Set to always use the tmp_rsa key when doing RSA operations,
 * even when this violates protocol specs */
enum SSL_OP_EPHEMERAL_RSA = 0x00200000;
/* Set on servers to choose the cipher according to the server's
 * preferences */
enum SSL_OP_CIPHER_SERVER_PREFERENCE = 0x00400000;
/* If set, a server will allow a client to issue a SSLv3.0 version number
 * as latest version supported in the premaster secret, even when TLSv1.0
 * (version 3.1) was announced in the client hello. Normally this is
 * forbidden to prevent version rollback attacks. */
enum SSL_OP_TLS_ROLLBACK_BUG = 0x00800000;

enum SSL_OP_NO_SSLv2 = 0x01000000;
enum SSL_OP_NO_SSLv3 = 0x02000000;
enum SSL_OP_NO_TLSv1 = 0x04000000;

/* The next flag deliberately changes the ciphertest, this is a check
 * for the PKCS#1 attack */
enum SSL_OP_PKCS1_CHECK_1 = 0x08000000;
enum SSL_OP_PKCS1_CHECK_2 = 0x10000000;
enum SSL_OP_NETSCAPE_CA_DN_BUG = 0x20000000;
enum SSL_OP_NETSCAPE_DEMO_CIPHER_CHANGE_BUG = 0x40000000;
/* Make server add server-hello extension from early version of
 * cryptopro draft, when GOST ciphersuite is negotiated.
 * Required for interoperability with CryptoPro CSP 3.x
 */
enum SSL_OP_CRYPTOPRO_TLSEXT_BUG = 0x80000000;

/* Allow SSL_write(..., n) to return r with 0 < r < n (i.e. report success
 * when just a single record has been written): */
enum SSL_MODE_ENABLE_PARTIAL_WRITE = 0x00000001;
/* Make it possible to retry SSL_write() with changed buffer location
 * (buffer contents must stay the same!); this is not the default to avoid
 * the misconception that non-blocking SSL_write() behaves like
 * non-blocking write(): */
enum SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER = 0x00000002;
/* Never bother the application with retries if the transport
 * is blocking: */
enum SSL_MODE_AUTO_RETRY = 0x00000004;
/* Don't attempt to automatically build certificate chain */
enum SSL_MODE_NO_AUTO_CHAIN = 0x00000008;
/* Save RAM by releasing read and write buffers when they're empty. (SSL3 and
 * TLS only.)  "Released" buffers are put onto a free-list in the context
 * or just freed (depending on the context's setting for freelist_max_len). */
enum SSL_MODE_RELEASE_BUFFERS = 0x00000010;

/* Note: SSL[_CTX]_set_{options,mode} use |= op on the previous value,
 * they cannot be used to clear bits. */

auto SSL_CTX_set_options()(SSL_CTX* ctx, c_long op) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_OPTIONS,op,null);
}
auto SSL_CTX_clear_options()(SSL_CTX* ctx, c_long op) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_CLEAR_OPTIONS,op,null);
}
auto SSL_CTX_get_options()(SSL_CTX* ctx) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_OPTIONS,0,null);
}
auto SSL_set_options()(SSL* ssl, c_long op) {
	return SSL_ctrl(ssl,SSL_CTRL_OPTIONS,op,null);
}
auto SSL_clear_options()(SSL* ssl, c_long op) {
	return SSL_ctrl(ssl,SSL_CTRL_CLEAR_OPTIONS,op,null);
}
auto SSL_get_options()(SSL* ssl) {
	return SSL_ctrl(ssl,SSL_CTRL_OPTIONS,0,null);
}

auto SSL_CTX_set_mode()(SSL_CTX* ctx, c_long op) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_MODE,op,null);
}
auto SSL_CTX_clear_mode()(SSL_CTX* ctx, c_long op) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_CLEAR_MODE,op,null);
}
auto SSL_CTX_get_mode()(SSL_CTX* ctx) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_MODE,0,null);
}
auto SSL_clear_mode()(SSL* ssl, c_long op) {
	return SSL_ctrl(ssl,SSL_CTRL_CLEAR_MODE,op,null);
}
auto SSL_set_mode()(SSL* ssl, c_long op) {
	return SSL_ctrl(ssl,SSL_CTRL_MODE,op,null);
}
auto SSL_get_mode()(SSL* ssl) {
	return SSL_ctrl(ssl,SSL_CTRL_MODE,0,null);
}
auto SSL_set_mtu()(SSL* ssl, c_long mtu) {
	return SSL_ctrl(ssl,SSL_CTRL_MTU,mtu,null);
}

auto SSL_get_secure_renegotiation_support()(SSL* ssl) {
	return SSL_ctrl(ssl,SSL_CTRL_GET_RI_SUPPORT,0,null);
}

void SSL_CTX_set_msg_callback(SSL_CTX* ctx, ExternC!(void function(int write_p, int version_, int content_type, const(void)* buf, size_t len, SSL* ssl, void* arg)) cb);
void SSL_set_msg_callback(SSL* ssl, ExternC!(void function(int write_p, int version_, int content_type, const(void)* buf, size_t len, SSL* ssl, void* arg)) cb);
auto SSL_CTX_set_msg_callback_arg()(SSL_CTX* ctx, void* arg) {
    return SSL_CTX_ctrl(ctx, SSL_CTRL_SET_MSG_CALLBACK_ARG, 0, arg);
}
auto SSL_CTX_set_msg_callback_arg()(SSL* ssl, void* arg) {
    return SSL_CTX_ctrl(ssl, SSL_CTRL_SET_MSG_CALLBACK_ARG, 0, arg);
}



version (Win32) {
enum SSL_MAX_CERT_LIST_DEFAULT = 1024*30; /* 30k max cert list :-) */
} else {
enum SSL_MAX_CERT_LIST_DEFAULT = 1024*100; /* 100k max cert list :-) */
}

enum SSL_SESSION_CACHE_MAX_SIZE_DEFAULT = (1024*20);

/* This callback type is used inside SSL_CTX, SSL, and in the functions that set
 * them. It is used to override the generation of SSL/TLS session IDs in a
 * server. Return value should be zero on an error, non-zero to proceed. Also,
 * callbacks should themselves check if the id they generate is unique otherwise
 * the SSL handshake will fail with an error - callbacks can do this using the
 * 'ssl' value they're passed by;
 *     SSL_has_matching_session_id(ssl, id, *id_len)
 * The length value passed in is set at the maximum size the session ID can be.
 * In SSLv2 this is 16 bytes, whereas SSLv3/TLSv1 it is 32 bytes. The callback
 * can alter this length to be less if desired, but under SSLv2 session IDs are
 * supposed to be fixed at 16 bytes so the id will be padded after the callback
 * returns in this case. It is also an error for the callback to set the size to
 * zero. */
alias ExternC!(int function(/+ FIXME: @@BUG7127@@ const+/ SSL* ssl, ubyte* id,
uint* id_len)) GEN_SESSION_CB;

struct ssl_comp_st {
	int id;
	const(char)* name;
version(OPENSSL_NO_COMP) {
	char* method;
} else {
	COMP_METHOD* method;
}
	}
alias ssl_comp_st SSL_COMP;

/+mixin DECLARE_STACK_OF!(SSL_COMP);+/
mixin DECLARE_LHASH_OF!(SSL_SESSION);

struct ssl_ctx_st
	{
	const(SSL_METHOD)* method;

	STACK_OF!(SSL_CIPHER) *cipher_list;
	/* same as above but sorted for lookup */
	STACK_OF!(SSL_CIPHER) *cipher_list_by_id;

	x509_store_st /* X509_STORE */ *cert_store;
	LHASH_OF!(SSL_SESSION) *sessions;
	/* Most session-ids that will be cached, default is
	 * SSL_SESSION_CACHE_MAX_SIZE_DEFAULT. 0 is unlimited. */
	c_ulong session_cache_size;
	ssl_session_st* session_cache_head;
	ssl_session_st* session_cache_tail;

	/* This can have one of 2 values, ored together,
	 * SSL_SESS_CACHE_CLIENT,
	 * SSL_SESS_CACHE_SERVER,
	 * Default is SSL_SESSION_CACHE_SERVER, which means only
	 * SSL_accept which cache SSL_SESSIONS. */
	int session_cache_mode;

	/* If timeout is not 0, it is the default timeout value set
	 * when SSL_new() is called.  This has been put in to make
	 * life easier to set things up */
	c_long session_timeout;

	/* If this callback is not null, it will be called each
	 * time a session id is added to the cache.  If this function
	 * returns 1, it means that the callback will do a
	 * SSL_SESSION_free() when it has finished using it.  Otherwise,
	 * on 0, it means the callback has finished with it.
	 * If remove_session_cb is not null, it will be called when
	 * a session-id is removed from the cache.  After the call,
	 * OpenSSL will SSL_SESSION_free() it. */
	ExternC!(int function(ssl_st* ssl,SSL_SESSION* sess)) new_session_cb;
	ExternC!(void function(ssl_ctx_st* ctx,SSL_SESSION* sess)) remove_session_cb;
	ExternC!(SSL_SESSION* function(ssl_st* ssl,
		ubyte* data,int len,int* copy)) get_session_cb;

	struct stats_
		{
		int sess_connect;	/* SSL new conn - started */
		int sess_connect_renegotiate;/* SSL reneg - requested */
		int sess_connect_good;	/* SSL new conne/reneg - finished */
		int sess_accept;	/* SSL new accept - started */
		int sess_accept_renegotiate;/* SSL reneg - requested */
		int sess_accept_good;	/* SSL accept/reneg - finished */
		int sess_miss;		/* session lookup misses  */
		int sess_timeout;	/* reuse attempt on timeouted session */
		int sess_cache_full;	/* session removed due to full cache */
		int sess_hit;		/* session reuse actually done */
		int sess_cb_hit;	/* session-id that was not
					 * in the cache was
					 * passed back via the callback.  This
					 * indicates that the application is
					 * supplying session-id's from other
					 * processes - spooky :-) */
		}
	stats_ stats;

	int references;

	/* if defined, these override the X509_verify_cert() calls */
	ExternC!(int function(X509_STORE_CTX*, void*)) app_verify_callback;
	void* app_verify_arg;
	/* before OpenSSL 0.9.7, 'app_verify_arg' was ignored
	 * ('app_verify_callback' was called with just one argument) */

	/* Default password callback. */
	pem_password_cb* default_passwd_callback;

	/* Default password callback user data. */
	void* default_passwd_callback_userdata;

	/* get client cert callback */
	ExternC!(int function(SSL* ssl, X509** x509, EVP_PKEY** pkey)) client_cert_cb;

    /* cookie generate callback */
    ExternC!(int function(SSL* ssl, ubyte* cookie,
        uint* cookie_len)) app_gen_cookie_cb;

    /* verify cookie callback */
    ExternC!(int function(SSL* ssl, ubyte* cookie,
        uint cookie_len)) app_verify_cookie_cb;

	CRYPTO_EX_DATA ex_data;

	const(EVP_MD)* rsa_md5;/* For SSLv2 - name is 'ssl2-md5' */
	const(EVP_MD)* md5;	/* For SSLv3/TLSv1 'ssl3-md5' */
	const(EVP_MD)* sha1;   /* For SSLv3/TLSv1 'ssl3->sha1' */

	STACK_OF!(X509) *extra_certs;
	STACK_OF!(SSL_COMP) *comp_methods; /* stack of SSL_COMP, SSLv3/TLSv1 */


	/* Default values used when no per-SSL value is defined follow */

	ExternC!(void function(const(SSL)* ssl,int type,int val)) info_callback; /* used if SSL's info_callback is NULL */

	/* what we put in client cert requests */
	STACK_OF!(X509_NAME) *client_CA;


	/* Default values to use in SSL structures follow (these are copied by SSL_new) */

	c_ulong options;
	c_ulong mode;
	c_long max_cert_list;

	cert_st /* CERT */ *cert;
	int read_ahead;

	/* callback that allows applications to peek at protocol messages */
	ExternC!(void function(int write_p, int version_, int content_type, const(void)* buf, size_t len, SSL* ssl, void* arg)) msg_callback;
	void* msg_callback_arg;

	int verify_mode;
	uint sid_ctx_length;
	ubyte sid_ctx[SSL_MAX_SID_CTX_LENGTH];
	ExternC!(int function(int ok,X509_STORE_CTX* ctx)) default_verify_callback; /* called 'verify_callback' in the SSL */

	/* Default generate session ID callback. */
	GEN_SESSION_CB generate_session_id;

	X509_VERIFY_PARAM* param;

version (none) {
	int purpose;		/* Purpose setting */
	int trust;		/* Trust setting */
}

	int quiet_shutdown;

	/* Maximum amount of data to send in one fragment.
	 * actual record size can be more than this due to
	 * padding and MAC overheads.
	 */
	uint max_send_fragment;

version (OPENSSL_ENGINE) {} else {
	/* Engine to pass requests for client certs to
	 */
	ENGINE* client_cert_engine;
}

version(OPENSSL_NO_TLSEXT) {} else {
	/* TLS extensions servername callback */
	ExternC!(int function(SSL*, int*, void*)) tlsext_servername_callback;
	void* tlsext_servername_arg;
	/* RFC 4507 session ticket keys */
	ubyte tlsext_tick_key_name[16];
	ubyte tlsext_tick_hmac_key[16];
	ubyte tlsext_tick_aes_key[16];
	/* Callback to support customisation of ticket key setting */
	ExternC!(int function(SSL* ssl,
					ubyte* name, ubyte* iv,
					EVP_CIPHER_CTX* ectx,
 					HMAC_CTX* hctx, int enc)) tlsext_ticket_key_cb;

	/* certificate status request info */
	/* Callback for status request */
	ExternC!(int function(SSL* ssl, void* arg)) tlsext_status_cb;
	void* tlsext_status_arg;

	/* draft-rescorla-tls-opaque-prf-input-00.txt information */
	ExternC!(int function(SSL*, void* peerinput, size_t len, void* arg)) tlsext_opaque_prf_input_callback;
	void* tlsext_opaque_prf_input_callback_arg;
}

version(OPENSSL_NO_PSK) {} else {
	char* psk_identity_hint;
	ExternC!(uint function(SSL* ssl, const(char)* hint, char* identity,
		uint max_identity_len, ubyte* psk,
		uint max_psk_len)) psk_client_callback;
	ExternC!(uint function(SSL* ssl, const(char)* identity,
		ubyte* psk, uint max_psk_len)) psk_server_callback;
}

version(OPENSSL_NO_BUF_FREELISTS) {} else {
enum SSL_MAX_BUF_FREELIST_LEN_DEFAULT = 32;
	uint freelist_max_len;
	struct ssl3_buf_freelist_st;
	ssl3_buf_freelist_st* wbuf_freelist;
	ssl3_buf_freelist_st* rbuf_freelist;
}
	};

enum SSL_SESS_CACHE_OFF = 0x0000;
enum SSL_SESS_CACHE_CLIENT = 0x0001;
enum SSL_SESS_CACHE_SERVER = 0x0002;
enum SSL_SESS_CACHE_BOTH = (SSL_SESS_CACHE_CLIENT|SSL_SESS_CACHE_SERVER);
enum SSL_SESS_CACHE_NO_AUTO_CLEAR = 0x0080;
/* enough comments already ... see SSL_CTX_set_session_cache_mode(3) */
enum SSL_SESS_CACHE_NO_INTERNAL_LOOKUP = 0x0100;
enum SSL_SESS_CACHE_NO_INTERNAL_STORE = 0x0200;
enum SSL_SESS_CACHE_NO_INTERNAL = (SSL_SESS_CACHE_NO_INTERNAL_LOOKUP|SSL_SESS_CACHE_NO_INTERNAL_STORE);

LHASH_OF!(SSL_SESSION) *SSL_CTX_sessions(SSL_CTX* ctx);
auto SSL_CTX_sess_number()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_NUMBER,0,null);
}
auto SSL_CTX_sess_connect()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_CONNECT,0,null);
}
auto SSL_CTX_sess_connect_good()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_CONNECT_GOOD,0,null);
}
auto SSL_CTX_sess_connect_renegotiate()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_CONNECT_RENEGOTIATE,0,null);
}
auto SSL_CTX_sess_accept()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_ACCEPT,0,null);
}
auto SSL_CTX_sess_accept_renegotiate()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_ACCEPT_RENEGOTIATE,0,null);
}
auto SSL_CTX_sess_accept_good()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_ACCEPT_GOOD,0,null);
}
auto SSL_CTX_sess_hits()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_HIT,0,null);
}
auto SSL_CTX_sess_cb_hits()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_CB_HIT,0,null);
}
auto SSL_CTX_sess_misses()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_MISSES,0,null);
}
auto SSL_CTX_sess_timeouts()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_TIMEOUTS,0,null);
}
auto SSL_CTX_sess_cache_full()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SESS_CACHE_FULL,0,null);
}

void SSL_CTX_sess_set_new_cb(SSL_CTX* ctx, ExternC!(int function(ssl_st* ssl,SSL_SESSION* sess)) new_session_cb);
ExternC!(int function(ssl_st* ssl, SSL_SESSION* sess)) SSL_CTX_sess_get_new_cb(SSL_CTX* ctx);
void SSL_CTX_sess_set_remove_cb(SSL_CTX* ctx, ExternC!(void function(ssl_ctx_st* ctx,SSL_SESSION* sess)) remove_session_cb);
ExternC!(void function(ssl_st* ssl, SSL_SESSION* sess)) SSL_CTX_sess_get_remove_cb(SSL_CTX* ctx);
void SSL_CTX_sess_set_get_cb(SSL_CTX* ctx, ExternC!(SSL_SESSION* function(ssl_st* ssl, ubyte* data,int len,int* copy)) get_session_cb);
ExternC!(SSL_SESSION* function(ssl_st* ssl, ubyte* Data, int len, int* copy)) SSL_CTX_sess_get_get_cb(SSL_CTX* ctx);
void SSL_CTX_set_info_callback(SSL_CTX* ctx, ExternC!(void function(const(SSL)* ssl,int type,int val)) cb);
ExternC!(void function(const(SSL)* ssl,int type,int val)) SSL_CTX_get_info_callback(SSL_CTX* ctx);
void SSL_CTX_set_client_cert_cb(SSL_CTX* ctx, ExternC!(int function(SSL* ssl, X509** x509, EVP_PKEY** pkey)) client_cert_cb);
ExternC!(int function(SSL* ssl, X509** x509, EVP_PKEY** pkey)) SSL_CTX_get_client_cert_cb(SSL_CTX* ctx);
version(OPENSSL_NO_ENGINE) {} else {
int SSL_CTX_set_client_cert_engine(SSL_CTX* ctx, ENGINE* e);
}
void SSL_CTX_set_cookie_generate_cb(SSL_CTX* ctx, ExternC!(int function(SSL* ssl, ubyte* cookie, uint* cookie_len)) app_gen_cookie_cb);
void SSL_CTX_set_cookie_verify_cb(SSL_CTX* ctx, ExternC!(int function(SSL* ssl, ubyte* cookie, uint cookie_len)) app_verify_cookie_cb);

version(OPENSSL_NO_PSK) {} else {
/* the maximum length of the buffer given to callbacks containing the
 * resulting identity/psk */
enum PSK_MAX_IDENTITY_LEN = 128;
enum PSK_MAX_PSK_LEN = 256;
void SSL_CTX_set_psk_client_callback(SSL_CTX* ctx,
	ExternC!(uint function(SSL* ssl, const(char)* hint,
		char* identity, uint max_identity_len, ubyte* psk,
		uint max_psk_len)) psk_client_callback);
void SSL_set_psk_client_callback(SSL* ssl,
	ExternC!(uint function(SSL* ssl, const(char)* hint,
		char* identity, uint max_identity_len, ubyte* psk,
		uint max_psk_len)) psk_client_callback);
void SSL_CTX_set_psk_server_callback(SSL_CTX* ctx,
	ExternC!(uint function(SSL* ssl, const(char)* identity,
		ubyte* psk, uint max_psk_len)) psk_server_callback);
void SSL_set_psk_server_callback(SSL* ssl,
	ExternC!(uint function(SSL* ssl, const(char)* identity,
		ubyte* psk, uint max_psk_len)) psk_server_callback);
int SSL_CTX_use_psk_identity_hint(SSL_CTX* ctx, const(char)* identity_hint);
int SSL_use_psk_identity_hint(SSL* s, const(char)* identity_hint);
const(char)* SSL_get_psk_identity_hint(const(SSL)* s);
const(char)* SSL_get_psk_identity(const(SSL)* s);
}

enum SSL_NOTHING = 1;
enum SSL_WRITING = 2;
enum SSL_READING = 3;
enum SSL_X509_LOOKUP = 4;

/* These will only be used when doing non-blocking IO */
auto SSL_want_nothing()(const(SSL)* s) { return (SSL_want(s) == SSL_NOTHING); }
auto SSL_want_read()(const(SSL)* s) { return (SSL_want(s) == SSL_READING); }
auto SSL_want_write()(const(SSL)* s) { return (SSL_want(s) == SSL_WRITING); }
auto SSL_want_x509_lookup()(const(SSL)* s) { return (SSL_want(s) == SSL_X509_LOOKUP); }

enum SSL_MAC_FLAG_READ_MAC_STREAM = 1;
enum SSL_MAC_FLAG_WRITE_MAC_STREAM = 2;

struct ssl_st
	{
	/* protocol version
	 * (one of SSL2_VERSION, SSL3_VERSION, TLS1_VERSION, DTLS1_VERSION)
	 */
	int version_;
	int type; /* SSL_ST_CONNECT or SSL_ST_ACCEPT */

	const(SSL_METHOD)* method; /* SSLv3 */

	/* There are 2 BIO's even though they are normally both the
	 * same.  This is so data can be read and written to different
	 * handlers */

version(OPENSSL_NO_BIO) {
	char* rbio; /* used by SSL_read */
	char* wbio; /* used by SSL_write */
	char* bbio;
} else {
	BIO* rbio; /* used by SSL_read */
	BIO* wbio; /* used by SSL_write */
	BIO* bbio; /* used during session-id reuse to concatenate
		    * messages */
}
	/* This holds a variable that indicates what we were doing
	 * when a 0 or -1 is returned.  This is needed for
	 * non-blocking IO so we know what request needs re-doing when
	 * in SSL_accept or SSL_connect */
	int rwstate;

	/* true when we are actually in SSL_accept() or SSL_connect() */
	int in_handshake;
	ExternC!(int function(SSL*)) handshake_func;

	/* Imagine that here's a boolean member "init" that is
	 * switched as soon as SSL_set_{accept/connect}_state
	 * is called for the first time, so that "state" and
	 * "handshake_func" are properly initialized.  But as
	 * handshake_func is == 0 until then, we use this
	 * test instead of an "init" member.
	 */

	int server;	/* are we the server side? - mostly used by SSL_clear*/

	int new_session;/* 1 if we are to use a new session.
	                 * 2 if we are a server and are inside a handshake
	                 *  (i.e. not just sending a HelloRequest)
	                 * NB: For servers, the 'new' session may actually be a previously
	                 * cached session or even the previous session unless
	                 * SSL_OP_NO_SESSION_RESUMPTION_ON_RENEGOTIATION is set */
	int quiet_shutdown;/* don't send shutdown packets */
	int shutdown;	/* we have shut things down, 0x01 sent, 0x02
			 * for received */
	int state;	/* where we are */
	int rstate;	/* where we are when reading */

	BUF_MEM* init_buf;	/* buffer used during init */
	void* init_msg;   	/* pointer to handshake message body, set by ssl3_get_message() */
	int init_num;		/* amount read/written */
	int init_off;		/* amount read/written */

	/* used internally to point at a raw packet */
	ubyte* packet;
	uint packet_length;

	ssl2_state_st* s2; /* SSLv2 variables */
	ssl3_state_st* s3; /* SSLv3 variables */
	import deimos.openssl.dtls1;
	dtls1_state_st* d1; /* DTLSv1 variables */

	int read_ahead;		/* Read as many input bytes as possible
	               	 	 * (for non-blocking reads) */

	/* callback that allows applications to peek at protocol messages */
	ExternC!(void function(int write_p, int version_, int content_type, const(void)* buf, size_t len, SSL* ssl, void* arg)) msg_callback;
	void* msg_callback_arg;

	int hit;		/* reusing a previous session */

	X509_VERIFY_PARAM* param;

version (none) {
	int purpose;		/* Purpose setting */
	int trust;		/* Trust setting */
}

	/* crypto */
	STACK_OF!(SSL_CIPHER) *cipher_list;
	STACK_OF!(SSL_CIPHER) *cipher_list_by_id;

	/* These are the ones being used, the ones in SSL_SESSION are
	 * the ones to be 'copied' into these ones */
	int mac_flags;
	EVP_CIPHER_CTX* enc_read_ctx;		/* cryptographic state */
	EVP_MD_CTX* read_hash;		/* used for mac generation */
version(OPENSSL_NO_COMP) {
	char* expand;
} else {
	COMP_CTX* expand;			/* uncompress */
}

	EVP_CIPHER_CTX* enc_write_ctx;		/* cryptographic state */
	EVP_MD_CTX* write_hash;		/* used for mac generation */
version(OPENSSL_NO_COMP) {
	char* compress;
} else {
	COMP_CTX* compress;			/* compression */
}

	/* session info */

	/* client cert? */
	/* This is used to hold the server certificate used */
	cert_st /* CERT */ *cert;

	/* the session_id_context is used to ensure sessions are only reused
	 * in the appropriate context */
	uint sid_ctx_length;
	ubyte sid_ctx[SSL_MAX_SID_CTX_LENGTH];

	/* This can also be in the session once a session is established */
	SSL_SESSION* session;

	/* Default generate session ID callback. */
	GEN_SESSION_CB generate_session_id;

	/* Used in SSL2 and SSL3 */
	int verify_mode;	/* 0 don't care about verify failure.
				 * 1 fail if verify fails */
	ExternC!(int function(int ok,X509_STORE_CTX* ctx)) verify_callback; /* fail if callback returns 0 */

	ExternC!(void function(/+ FIXME: @@BUG7127@@ const+/ SSL* ssl,int type,int val)) info_callback; /* optional informational callback */

	int error;		/* error bytes to be written */
	int error_code;		/* actual code */

version(OPENSSL_NO_KRB5) {} else {
	KSSL_CTX* kssl_ctx;     /* Kerberos 5 context */
}	/* OPENSSL_NO_KRB5 */

version(OPENSSL_NO_PSK) {} else {
	ExternC!(uint function(SSL* ssl, const(char)* hint, char* identity,
		uint max_identity_len, ubyte* psk,
		uint max_psk_len)) psk_client_callback;
	ExternC!(uint function(SSL* ssl, const(char)* identity,
		ubyte* psk, uint max_psk_len)) psk_server_callback;
}

	SSL_CTX* ctx;
	/* set this flag to 1 and a sleep(1) is put into all SSL_read()
	 * and SSL_write() calls, good for nbio debuging :-) */
	int debug_;

	/* extra application data */
	c_long verify_result;
	CRYPTO_EX_DATA ex_data;

	/* for server side, keep the list of CA_dn we can use */
	STACK_OF!(X509_NAME) *client_CA;

	int references;
	c_ulong options; /* protocol behaviour */
	c_ulong mode; /* API behaviour */
	c_long max_cert_list;
	int first_packet;
	int client_version;	/* what was passed, used for
				 * SSLv3/TLS rollback check */
	uint max_send_fragment;
version(OPENSSL_NO_TLSEXT) {
alias ctx session_ctx;
} else {
	/* TLS extension debug callback */
	ExternC!(void function(SSL* s, int client_server, int type,
					ubyte* data, int len,
					void* arg)) tlsext_debug_cb;
	void* tlsext_debug_arg;
	char* tlsext_hostname;
	int servername_done;   /* no further mod of servername
	                          0 : call the servername extension callback.
	                          1 : prepare 2, allow last ack just after in server callback.
	                          2 : don't call servername callback, no ack in server hello
	                       */
	/* certificate status request info */
	/* Status type or -1 if no status type */
	int tlsext_status_type;
	/* Expect OCSP CertificateStatus message */
	int tlsext_status_expected;
	/* OCSP status request only */
	STACK_OF!(OCSP_RESPID) *tlsext_ocsp_ids;
	X509_EXTENSIONS* tlsext_ocsp_exts;
	/* OCSP response received or to be sent */
	ubyte* tlsext_ocsp_resp;
	int tlsext_ocsp_resplen;

	/* RFC4507 session ticket expected to be received or sent */
	int tlsext_ticket_expected;
version(OPENSSL_NO_EC) {} else {
	size_t tlsext_ecpointformatlist_length;
	ubyte* tlsext_ecpointformatlist; /* our list */
	size_t tlsext_ellipticcurvelist_length;
	ubyte* tlsext_ellipticcurvelist; /* our list */
} /* OPENSSL_NO_EC */

	/* draft-rescorla-tls-opaque-prf-input-00.txt information to be used for handshakes */
	void* tlsext_opaque_prf_input;
	size_t tlsext_opaque_prf_input_len;

	/* TLS Session Ticket extension override */
	TLS_SESSION_TICKET_EXT* tlsext_session_ticket;

	/* TLS Session Ticket extension callback */
	tls_session_ticket_ext_cb_fn tls_session_ticket_ext_cb;
	void* tls_session_ticket_ext_cb_arg;

	/* TLS pre-shared secret session resumption */
	tls_session_secret_cb_fn tls_session_secret_cb;
	void* tls_session_secret_cb_arg;

	SSL_CTX* initial_ctx; /* initial ctx, used to store sessions */
alias initial_ctx session_ctx;
}
	};

public import deimos.openssl.ssl2;
public import deimos.openssl.ssl3;
public import deimos.openssl.tls1; /* This is mostly sslv3 with a few tweaks */
public import deimos.openssl.dtls1; /* Datagram TLS */
public import deimos.openssl.ssl23;

extern (C):
nothrow:

/* compatibility */
auto SSL_set_app_data()(SSL* s, char* arg) { return (SSL_set_ex_data()(SSL* s,0,arg)); }
auto SSL_get_app_data()(const(SSL)* s) { return (SSL_get_ex_data()(SSL* s,0)); }
auto SSL_SESSION_set_app_data()(SSL_SESSION* s, char* a) { return (SSL_SESSION_set_ex_data()(SSL* s,0,a)); }
auto SSL_SESSION_get_app_data()(const(SSL_SESSION)* s) { return (SSL_SESSION_get_ex_data()(SSL* s,0)); }
auto SSL_CTX_get_app_data()(const(SSL_CTX)* ctx) { return (SSL_CTX_get_ex_data(ctx,0)); }
auto SSL_CTX_set_app_data()(SSL_CTX* ctx, char* arg) { return (SSL_CTX_set_ex_data(ctx,0,arg)); }

/* The following are the possible values for ssl->state are are
 * used to indicate where we are up to in the SSL connection establishment.
 * The macros that follow are about the only things you should need to use
 * and even then, only when using non-blocking IO.
 * It can also be useful to work out where you were when the connection
 * failed */

enum SSL_ST_CONNECT = 0x1000;
enum SSL_ST_ACCEPT = 0x2000;
enum SSL_ST_MASK = 0x0FFF;
enum SSL_ST_INIT = (SSL_ST_CONNECT|SSL_ST_ACCEPT);
enum SSL_ST_BEFORE = 0x4000;
enum SSL_ST_OK = 0x03;
enum SSL_ST_RENEGOTIATE = (0x04|SSL_ST_INIT);

enum SSL_CB_LOOP = 0x01;
enum SSL_CB_EXIT = 0x02;
enum SSL_CB_READ = 0x04;
enum SSL_CB_WRITE = 0x08;
enum SSL_CB_ALERT = 0x4000; /* used in callback */
enum SSL_CB_READ_ALERT = (SSL_CB_ALERT|SSL_CB_READ);
enum SSL_CB_WRITE_ALERT = (SSL_CB_ALERT|SSL_CB_WRITE);
enum SSL_CB_ACCEPT_LOOP = (SSL_ST_ACCEPT|SSL_CB_LOOP);
enum SSL_CB_ACCEPT_EXIT = (SSL_ST_ACCEPT|SSL_CB_EXIT);
enum SSL_CB_CONNECT_LOOP = (SSL_ST_CONNECT|SSL_CB_LOOP);
enum SSL_CB_CONNECT_EXIT = (SSL_ST_CONNECT|SSL_CB_EXIT);
enum SSL_CB_HANDSHAKE_START = 0x10;
enum SSL_CB_HANDSHAKE_DONE = 0x20;

/* Is the SSL_connection established? */
auto SSL_get_state()(const(SSL)* a) { return SSL_state(a); }
auto SSL_is_init_finished()(const(SSL)* a) { return (SSL_state(a) == SSL_ST_OK); }
auto SSL_in_init()(const(SSL)* a) { return (SSL_state(a)&SSL_ST_INIT); }
auto SSL_in_before()(const(SSL)* a) { return (SSL_state(a)&SSL_ST_BEFORE); }
auto SSL_in_connect_init()(const(SSL)* a) { return (SSL_state(a)&SSL_ST_CONNECT); }
auto SSL_in_accept_init()(const(SSL)* a) { return (SSL_state(a)&SSL_ST_ACCEPT); }

/* The following 2 states are kept in ssl->rstate when reads fail,
 * you should not need these */
enum SSL_ST_READ_HEADER = 0xF0;
enum SSL_ST_READ_BODY = 0xF1;
enum SSL_ST_READ_DONE = 0xF2;

/* Obtain latest Finished message
 *  -- that we sent (SSL_get_finished)
 *  -- that we expected from peer (SSL_get_peer_finished).
 * Returns length (0 == no Finished so far), copies up to 'count' bytes. */
size_t SSL_get_finished(const(SSL)* s, void* buf, size_t count);
size_t SSL_get_peer_finished(const(SSL)* s, void* buf, size_t count);

/* use either SSL_VERIFY_NONE or SSL_VERIFY_PEER, the last 2 options
 * are 'ored' with SSL_VERIFY_PEER if they are desired */
enum SSL_VERIFY_NONE = 0x00;
enum SSL_VERIFY_PEER = 0x01;
enum SSL_VERIFY_FAIL_IF_NO_PEER_CERT = 0x02;
enum SSL_VERIFY_CLIENT_ONCE = 0x04;

alias SSL_library_init OpenSSL_add_ssl_algorithms;
alias SSL_library_init SSLeay_add_ssl_algorithms;

/* this is for backward compatibility */
//#if 0 /* NEW_SSLEAY */
//#define SSL_CTX_set_default_verify(a,b,c) SSL_CTX_set_verify(a,b,c)
//#define SSL_set_pref_cipher(c,n)	SSL_set_cipher_list(c,n)
//#define SSL_add_session(a,b)            SSL_CTX_add_session((a),(b))
//#define SSL_remove_session(a,b)		SSL_CTX_remove_session((a),(b))
//#define SSL_flush_sessions(a,b)		SSL_CTX_flush_sessions((a),(b))
//#endif
/* More backward compatibility */
auto SSL_get_cipher()(const(SSL)* s) {
    return SSL_CIPHER_get_name(SSL_get_current_cipher(s));
}
auto SSL_get_cipher_bits()(const(SSL)* s, int np) {
    return SSL_CIPHER_get_bits(SSL_get_current_cipher(s),np);
}
auto SSL_get_cipher_version()(const(SSL)* s) {
    return SSL_CIPHER_get_version(SSL_get_current_cipher(s));
}
auto SSL_get_cipher_name()(const(SSL)* s) {
    return SSL_CIPHER_get_name(SSL_get_current_cipher(s));
}
alias SSL_SESSION_get_time SSL_get_time;
alias SSL_SESSION_set_time SSL_set_time;
alias SSL_SESSION_get_timeout SSL_get_timeout;
alias SSL_SESSION_set_timeout SSL_set_timeout;

auto d2i_SSL_SESSION_bio()(BIO* bp,SSL_SESSION** s_id) {
    return ASN1_d2i_bio_of!SSL_SESSION(&SSL_SESSION_new,&d2i_SSL_SESSION,bp,s_id);
}
auto i2d_SSL_SESSION_bio()(BIO* bp,SSL_SESSION** s_id) {
    return ASN1_i2d_bio_of!SSL_SESSION(&i2d_SSL_SESSION,bp,s_id);
}

mixin DECLARE_PEM_rw!("SSL_SESSION", SSL_SESSION);

enum SSL_AD_REASON_OFFSET = 1000; /* offset to get SSL_R_... value from SSL_AD_... */

/* These alert types are for SSLv3 and TLSv1 */
alias SSL3_AD_CLOSE_NOTIFY SSL_AD_CLOSE_NOTIFY;
alias SSL3_AD_UNEXPECTED_MESSAGE SSL_AD_UNEXPECTED_MESSAGE; /* fatal */
alias SSL3_AD_BAD_RECORD_MAC SSL_AD_BAD_RECORD_MAC;     /* fatal */
alias TLS1_AD_DECRYPTION_FAILED SSL_AD_DECRYPTION_FAILED;
alias TLS1_AD_RECORD_OVERFLOW SSL_AD_RECORD_OVERFLOW;
alias SSL3_AD_DECOMPRESSION_FAILURE SSL_AD_DECOMPRESSION_FAILURE;/* fatal */
alias SSL3_AD_HANDSHAKE_FAILURE SSL_AD_HANDSHAKE_FAILURE;/* fatal */
alias SSL3_AD_NO_CERTIFICATE SSL_AD_NO_CERTIFICATE; /* Not for TLS */
alias SSL3_AD_BAD_CERTIFICATE SSL_AD_BAD_CERTIFICATE;
alias SSL3_AD_UNSUPPORTED_CERTIFICATE SSL_AD_UNSUPPORTED_CERTIFICATE;
alias SSL3_AD_CERTIFICATE_REVOKED SSL_AD_CERTIFICATE_REVOKED;
alias SSL3_AD_CERTIFICATE_EXPIRED SSL_AD_CERTIFICATE_EXPIRED;
alias SSL3_AD_CERTIFICATE_UNKNOWN SSL_AD_CERTIFICATE_UNKNOWN;
alias SSL3_AD_ILLEGAL_PARAMETER SSL_AD_ILLEGAL_PARAMETER;   /* fatal */
alias TLS1_AD_UNKNOWN_CA SSL_AD_UNKNOWN_CA;	/* fatal */
alias TLS1_AD_ACCESS_DENIED SSL_AD_ACCESS_DENIED;	/* fatal */
alias TLS1_AD_DECODE_ERROR SSL_AD_DECODE_ERROR;	/* fatal */
alias TLS1_AD_DECRYPT_ERROR SSL_AD_DECRYPT_ERROR;
alias TLS1_AD_EXPORT_RESTRICTION SSL_AD_EXPORT_RESTRICTION;/* fatal */
alias TLS1_AD_PROTOCOL_VERSION SSL_AD_PROTOCOL_VERSION; /* fatal */
alias TLS1_AD_INSUFFICIENT_SECURITY SSL_AD_INSUFFICIENT_SECURITY;/* fatal */
alias TLS1_AD_INTERNAL_ERROR SSL_AD_INTERNAL_ERROR;	/* fatal */
alias TLS1_AD_USER_CANCELLED SSL_AD_USER_CANCELLED;
alias TLS1_AD_NO_RENEGOTIATION SSL_AD_NO_RENEGOTIATION;
alias TLS1_AD_UNSUPPORTED_EXTENSION SSL_AD_UNSUPPORTED_EXTENSION;
alias TLS1_AD_CERTIFICATE_UNOBTAINABLE SSL_AD_CERTIFICATE_UNOBTAINABLE;
alias TLS1_AD_UNRECOGNIZED_NAME SSL_AD_UNRECOGNIZED_NAME;
alias TLS1_AD_BAD_CERTIFICATE_STATUS_RESPONSE SSL_AD_BAD_CERTIFICATE_STATUS_RESPONSE;
alias TLS1_AD_BAD_CERTIFICATE_HASH_VALUE SSL_AD_BAD_CERTIFICATE_HASH_VALUE;
alias TLS1_AD_UNKNOWN_PSK_IDENTITY SSL_AD_UNKNOWN_PSK_IDENTITY; /* fatal */

enum SSL_ERROR_NONE = 0;
enum SSL_ERROR_SSL = 1;
enum SSL_ERROR_WANT_READ = 2;
enum SSL_ERROR_WANT_WRITE = 3;
enum SSL_ERROR_WANT_X509_LOOKUP = 4;
enum SSL_ERROR_SYSCALL = 5; /* look at error stack/return value/errno */
enum SSL_ERROR_ZERO_RETURN = 6;
enum SSL_ERROR_WANT_CONNECT = 7;
enum SSL_ERROR_WANT_ACCEPT = 8;

enum SSL_CTRL_NEED_TMP_RSA = 1;
enum SSL_CTRL_SET_TMP_RSA = 2;
enum SSL_CTRL_SET_TMP_DH = 3;
enum SSL_CTRL_SET_TMP_ECDH = 4;
enum SSL_CTRL_SET_TMP_RSA_CB = 5;
enum SSL_CTRL_SET_TMP_DH_CB = 6;
enum SSL_CTRL_SET_TMP_ECDH_CB = 7;

enum SSL_CTRL_GET_SESSION_REUSED = 8;
enum SSL_CTRL_GET_CLIENT_CERT_REQUEST = 9;
enum SSL_CTRL_GET_NUM_RENEGOTIATIONS = 10;
enum SSL_CTRL_CLEAR_NUM_RENEGOTIATIONS = 11;
enum SSL_CTRL_GET_TOTAL_RENEGOTIATIONS = 12;
enum SSL_CTRL_GET_FLAGS = 13;
enum SSL_CTRL_EXTRA_CHAIN_CERT = 14;

enum SSL_CTRL_SET_MSG_CALLBACK = 15;
enum SSL_CTRL_SET_MSG_CALLBACK_ARG = 16;

/* only applies to datagram connections */
enum SSL_CTRL_SET_MTU = 17;
/* Stats */
enum SSL_CTRL_SESS_NUMBER = 20;
enum SSL_CTRL_SESS_CONNECT = 21;
enum SSL_CTRL_SESS_CONNECT_GOOD = 22;
enum SSL_CTRL_SESS_CONNECT_RENEGOTIATE = 23;
enum SSL_CTRL_SESS_ACCEPT = 24;
enum SSL_CTRL_SESS_ACCEPT_GOOD = 25;
enum SSL_CTRL_SESS_ACCEPT_RENEGOTIATE = 26;
enum SSL_CTRL_SESS_HIT = 27;
enum SSL_CTRL_SESS_CB_HIT = 28;
enum SSL_CTRL_SESS_MISSES = 29;
enum SSL_CTRL_SESS_TIMEOUTS = 30;
enum SSL_CTRL_SESS_CACHE_FULL = 31;
enum SSL_CTRL_OPTIONS = 32;
enum SSL_CTRL_MODE = 33;

enum SSL_CTRL_GET_READ_AHEAD = 40;
enum SSL_CTRL_SET_READ_AHEAD = 41;
enum SSL_CTRL_SET_SESS_CACHE_SIZE = 42;
enum SSL_CTRL_GET_SESS_CACHE_SIZE = 43;
enum SSL_CTRL_SET_SESS_CACHE_MODE = 44;
enum SSL_CTRL_GET_SESS_CACHE_MODE = 45;

enum SSL_CTRL_GET_MAX_CERT_LIST = 50;
enum SSL_CTRL_SET_MAX_CERT_LIST = 51;

enum SSL_CTRL_SET_MAX_SEND_FRAGMENT = 52;

/* see tls1.h for macros based on these */
version(OPENSSL_NO_TLSEXT) {} else {
enum SSL_CTRL_SET_TLSEXT_SERVERNAME_CB = 53;
enum SSL_CTRL_SET_TLSEXT_SERVERNAME_ARG = 54;
enum SSL_CTRL_SET_TLSEXT_HOSTNAME = 55;
enum SSL_CTRL_SET_TLSEXT_DEBUG_CB = 56;
enum SSL_CTRL_SET_TLSEXT_DEBUG_ARG = 57;
enum SSL_CTRL_GET_TLSEXT_TICKET_KEYS = 58;
enum SSL_CTRL_SET_TLSEXT_TICKET_KEYS = 59;
enum SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT = 60;
enum SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT_CB = 61;
enum SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT_CB_ARG = 62;
enum SSL_CTRL_SET_TLSEXT_STATUS_REQ_CB = 63;
enum SSL_CTRL_SET_TLSEXT_STATUS_REQ_CB_ARG = 64;
enum SSL_CTRL_SET_TLSEXT_STATUS_REQ_TYPE = 65;
enum SSL_CTRL_GET_TLSEXT_STATUS_REQ_EXTS = 66;
enum SSL_CTRL_SET_TLSEXT_STATUS_REQ_EXTS = 67;
enum SSL_CTRL_GET_TLSEXT_STATUS_REQ_IDS = 68;
enum SSL_CTRL_SET_TLSEXT_STATUS_REQ_IDS = 69;
enum SSL_CTRL_GET_TLSEXT_STATUS_REQ_OCSP_RESP = 70;
enum SSL_CTRL_SET_TLSEXT_STATUS_REQ_OCSP_RESP = 71;

enum SSL_CTRL_SET_TLSEXT_TICKET_KEY_CB = 72;
}

enum DTLS_CTRL_GET_TIMEOUT = 73;
enum DTLS_CTRL_HANDLE_TIMEOUT = 74;
enum DTLS_CTRL_LISTEN = 75;

enum SSL_CTRL_GET_RI_SUPPORT = 76;
enum SSL_CTRL_CLEAR_OPTIONS = 77;
enum SSL_CTRL_CLEAR_MODE = 78;

auto DTLSv1_get_timeout()(SSL* ssl, void* arg) {
    return SSL_ctrl(ssl,DTLS_CTRL_GET_TIMEOUT,0,arg);
}
auto DTLSv1_handle_timeout()(SSL* ssl) {
    return SSL_ctrl(ssl,DTLS_CTRL_HANDLE_TIMEOUT,0,null);
}
auto DTLSv1_listen()(SSL* ssl, void* peer) {
    return SSL_ctrl(ssl,DTLS_CTRL_LISTEN,0,peer);
}

auto SSL_session_reused()(SSL* ssl) {
    return SSL_ctrl(ssl,SSL_CTRL_GET_SESSION_REUSED,0,null);
}
auto SSL_session_reused()(SSL* ssl) {
    return SSL_ctrl(ssl,SSL_CTRL_GET_SESSION_REUSED,0,null);
}
auto SSL_num_renegotiations()(SSL* ssl) {
    return SSL_ctrl(ssl,SSL_CTRL_GET_NUM_RENEGOTIATIONS,0,null);
}
auto SSL_clear_num_renegotiations()(SSL* ssl) {
    return SSL_ctrl(ssl,SSL_CTRL_CLEAR_NUM_RENEGOTIATIONS,0,null);
}
auto SSL_total_renegotiations()(SSL* ssl) {
    return SSL_ctrl(ssl,SSL_CTRL_GET_TOTAL_RENEGOTIATIONS,0,null);
}

auto SSL_CTX_need_tmp_RSA()(SSL_CTX* ctx) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_NEED_TMP_RSA,0,null);
}
auto SSL_CTX_set_tmp_rsa()(SSL_CTX* ctx, void* rsa) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_TMP_RSA,0,rsa);
}
auto SSL_CTX_set_tmp_dh()(SSL_CTX* ctx, void* dh) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_TMP_DH,0,dh);
}
auto SSL_CTX_set_tmp_ecdh()(SSL_CTX* ctx, void* ecdh) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_TMP_ECDH,0,ecdh);
}

auto SSL_need_tmp_RSA()(SSL* ssl) {
    return SSL_ctrl(ssl,SSL_CTRL_NEED_TMP_RSA,0,null);
}
auto SSL_set_tmp_rsa()(SSL* ssl, void* rsa) {
    return SSL_ctrl(ssl,SSL_CTRL_SET_TMP_RSA,0,rsa);
}
auto SSL_set_tmp_dh()(SSL* ssl, void* dh) {
    return SSL_ctrl(ssl,SSL_CTRL_SET_TMP_DH,0,dh);
}
auto SSL_set_tmp_ecdh()(SSL* ssl, void* ecdh) {
    return SSL_ctrl(ssl,SSL_CTRL_SET_TMP_ECDH,0,ecdh);
}

auto SSL_CTX_add_extra_chain_cert()(SSL_CTX* ctx, void* x509) {
    return SSL_CTX_ctrl(ctx,SSL_CTRL_EXTRA_CHAIN_CERT,0,x509);
}

version(OPENSSL_NO_BIO) {} else {
BIO_METHOD* BIO_f_ssl();
BIO* BIO_new_ssl(SSL_CTX* ctx,int client);
BIO* BIO_new_ssl_connect(SSL_CTX* ctx);
BIO* BIO_new_buffer_ssl_connect(SSL_CTX* ctx);
int BIO_ssl_copy_session_id(BIO* to,BIO* from);
void BIO_ssl_shutdown(BIO* ssl_bio);

}

int	SSL_CTX_set_cipher_list(SSL_CTX*,const(char)* str);
SSL_CTX* SSL_CTX_new(const(SSL_METHOD)* meth);
void	SSL_CTX_free(SSL_CTX*);
c_long SSL_CTX_set_timeout(SSL_CTX* ctx,c_long t);
c_long SSL_CTX_get_timeout(const(SSL_CTX)* ctx);
X509_STORE* SSL_CTX_get_cert_store(const(SSL_CTX)*);
void SSL_CTX_set_cert_store(SSL_CTX*,X509_STORE*);
int SSL_want(const(SSL)* s);
int	SSL_clear(SSL* s);

void	SSL_CTX_flush_sessions(SSL_CTX* ctx,c_long tm);

const(SSL_CIPHER)* SSL_get_current_cipher(const(SSL)* s);
int	SSL_CIPHER_get_bits(const(SSL_CIPHER)* c,int* alg_bits);
char* 	SSL_CIPHER_get_version(const(SSL_CIPHER)* c);
const(char)* 	SSL_CIPHER_get_name(const(SSL_CIPHER)* c);

int	SSL_get_fd(const(SSL)* s);
int	SSL_get_rfd(const(SSL)* s);
int	SSL_get_wfd(const(SSL)* s);
const(char)* SSL_get_cipher_list(const(SSL)* s,int n);
char* 	SSL_get_shared_ciphers(const(SSL)* s, char* buf, int len);
int	SSL_get_read_ahead(const(SSL)* s);
int	SSL_pending(const(SSL)* s);
version(OPENSSL_NO_SOCK) {} else {
int	SSL_set_fd(SSL* s, int fd);
int	SSL_set_rfd(SSL* s, int fd);
int	SSL_set_wfd(SSL* s, int fd);
}
version(OPENSSL_NO_BIO) {} else {
void	SSL_set_bio(SSL* s, BIO* rbio,BIO* wbio);
BIO* 	SSL_get_rbio(const(SSL)* s);
BIO* 	SSL_get_wbio(const(SSL)* s);
}
int	SSL_set_cipher_list(SSL* s, const(char)* str);
void	SSL_set_read_ahead(SSL* s, int yes);
int	SSL_get_verify_mode(const(SSL)* s);
int	SSL_get_verify_depth(const(SSL)* s);
int	function(int,X509_STORE_CTX*) SSL_get_verify_callback(const(SSL)* s);
void	SSL_set_verify(SSL* s, int mode,
		       ExternC!(int function(int ok,X509_STORE_CTX* ctx)) callback);
void	SSL_set_verify_depth(SSL* s, int depth);
version(OPENSSL_NO_RSA) {} else {
int	SSL_use_RSAPrivateKey(SSL* ssl, RSA* rsa);
}
int	SSL_use_RSAPrivateKey_ASN1(SSL* ssl, ubyte* d, c_long len);
int	SSL_use_PrivateKey(SSL* ssl, EVP_PKEY* pkey);
int	SSL_use_PrivateKey_ASN1(int pk,SSL* ssl, const(ubyte)* d, c_long len);
int	SSL_use_certificate(SSL* ssl, X509* x);
int	SSL_use_certificate_ASN1(SSL* ssl, const(ubyte)* d, int len);

version (OPENSSL_NO_STDIO) {} else {
int	SSL_use_RSAPrivateKey_file(SSL* ssl, const(char)* file, int type);
int	SSL_use_PrivateKey_file(SSL* ssl, const(char)* file, int type);
int	SSL_use_certificate_file(SSL* ssl, const(char)* file, int type);
int	SSL_CTX_use_RSAPrivateKey_file(SSL_CTX* ctx, const(char)* file, int type);
int	SSL_CTX_use_PrivateKey_file(SSL_CTX* ctx, const(char)* file, int type);
int	SSL_CTX_use_certificate_file(SSL_CTX* ctx, const(char)* file, int type);
int	SSL_CTX_use_certificate_chain_file(SSL_CTX* ctx, const(char)* file); /* PEM type */
STACK_OF!(X509_NAME) *SSL_load_client_CA_file(const(char)* file);
int	SSL_add_file_cert_subjects_to_stack(STACK_OF!(X509_NAME) *stackCAs,
					    const(char)* file);
//#ifndef OPENSSL_SYS_VMS
//#ifndef OPENSSL_SYS_MACINTOSH_CLASSIC /* XXXXX: Better scheme needed! [was: #ifndef MAC_OS_pre_X] */
int	SSL_add_dir_cert_subjects_to_stack(STACK_OF!(X509_NAME) *stackCAs,
					   const(char)* dir);
//#endif
//#endif
}

void	SSL_load_error_strings();
const(char)* SSL_state_string(const(SSL)* s);
const(char)* SSL_rstate_string(const(SSL)* s);
const(char)* SSL_state_string_long(const(SSL)* s);
const(char)* SSL_rstate_string_long(const(SSL)* s);
c_long	SSL_SESSION_get_time(const(SSL_SESSION)* s);
c_long	SSL_SESSION_set_time(SSL_SESSION* s, c_long t);
c_long	SSL_SESSION_get_timeout(const(SSL_SESSION)* s);
c_long	SSL_SESSION_set_timeout(SSL_SESSION* s, c_long t);
void	SSL_copy_session_id(SSL* to,const(SSL)* from);

SSL_SESSION* SSL_SESSION_new();
const(ubyte)* SSL_SESSION_get_id(const(SSL_SESSION)* s,
					uint* len);
version(OPENSSL_NO_FP_API) {} else {
int	SSL_SESSION_print_fp(FILE* fp,const(SSL_SESSION)* ses);
}
version(OPENSSL_NO_BIO) {} else {
int	SSL_SESSION_print(BIO* fp,const(SSL_SESSION)* ses);
}
void	SSL_SESSION_free(SSL_SESSION* ses);
int	i2d_SSL_SESSION(SSL_SESSION* in_,ubyte** pp);
int	SSL_set_session(SSL* to, SSL_SESSION* session);
int	SSL_CTX_add_session(SSL_CTX* s, SSL_SESSION* c);
int	SSL_CTX_remove_session(SSL_CTX*,SSL_SESSION* c);
int	SSL_CTX_set_generate_session_id(SSL_CTX*, GEN_SESSION_CB);
int	SSL_set_generate_session_id(SSL*, GEN_SESSION_CB);
int	SSL_has_matching_session_id(const(SSL)* ssl, const(ubyte)* id,
					uint id_len);
SSL_SESSION* d2i_SSL_SESSION(SSL_SESSION** a,const(ubyte)** pp,
			     c_long length);

//#ifdef HEADER_X509_H
X509* 	SSL_get_peer_certificate(const(SSL)* s);
//#endif

STACK_OF!(X509) *SSL_get_peer_cert_chain(const(SSL)* s);

int SSL_CTX_get_verify_mode(const(SSL_CTX)* ctx);
int SSL_CTX_get_verify_depth(const(SSL_CTX)* ctx);
ExternC!(int function(int,X509_STORE_CTX*)) SSL_CTX_get_verify_callback(const(SSL_CTX)* ctx);
void SSL_CTX_set_verify(SSL_CTX* ctx,int mode,
			ExternC!(int function(int, X509_STORE_CTX*)) callback);
void SSL_CTX_set_verify_depth(SSL_CTX* ctx,int depth);
void SSL_CTX_set_cert_verify_callback(SSL_CTX* ctx, ExternC!(int function(X509_STORE_CTX*,void*)) cb, void* arg);
version(OPENSSL_NO_RSA) {} else {
int SSL_CTX_use_RSAPrivateKey(SSL_CTX* ctx, RSA* rsa);
}
int SSL_CTX_use_RSAPrivateKey_ASN1(SSL_CTX* ctx, const(ubyte)* d, c_long len);
int SSL_CTX_use_PrivateKey(SSL_CTX* ctx, EVP_PKEY* pkey);
int SSL_CTX_use_PrivateKey_ASN1(int pk,SSL_CTX* ctx,
	const(ubyte)* d, c_long len);
int SSL_CTX_use_certificate(SSL_CTX* ctx, X509* x);
int SSL_CTX_use_certificate_ASN1(SSL_CTX* ctx, int len, const(ubyte)* d);

void SSL_CTX_set_default_passwd_cb(SSL_CTX* ctx, pem_password_cb* cb);
void SSL_CTX_set_default_passwd_cb_userdata(SSL_CTX* ctx, void* u);

int SSL_CTX_check_private_key(const(SSL_CTX)* ctx);
int SSL_check_private_key(const(SSL)* ctx);

int	SSL_CTX_set_session_id_context(SSL_CTX* ctx,const(ubyte)* sid_ctx,
				       uint sid_ctx_len);

SSL* 	SSL_new(SSL_CTX* ctx);
int	SSL_set_session_id_context(SSL* ssl,const(ubyte)* sid_ctx,
				   uint sid_ctx_len);

int SSL_CTX_set_purpose(SSL_CTX* s, int purpose);
int SSL_set_purpose(SSL* s, int purpose);
int SSL_CTX_set_trust(SSL_CTX* s, int trust);
int SSL_set_trust(SSL* s, int trust);

int SSL_CTX_set1_param(SSL_CTX* ctx, X509_VERIFY_PARAM* vpm);
int SSL_set1_param(SSL* ssl, X509_VERIFY_PARAM* vpm);

void	SSL_free(SSL* ssl);
int 	SSL_accept(SSL* ssl);
int 	SSL_connect(SSL* ssl);
int 	SSL_read(SSL* ssl,void* buf,int num);
int 	SSL_peek(SSL* ssl,void* buf,int num);
int 	SSL_write(SSL* ssl,const(void)* buf,int num);
c_long	SSL_ctrl(SSL* ssl,int cmd, c_long larg, void* parg);
c_long	SSL_callback_ctrl(SSL*, int, ExternC!(void function()) );
c_long	SSL_CTX_ctrl(SSL_CTX* ctx,int cmd, c_long larg, void* parg);
c_long	SSL_CTX_callback_ctrl(SSL_CTX*, int, ExternC!(void function()) );

int	SSL_get_error(const(SSL)* s,int ret_code);
const(char)* SSL_get_version(const(SSL)* s);

/* This sets the 'default' SSL version that SSL_new() will create */
int SSL_CTX_set_ssl_version(SSL_CTX* ctx, const(SSL_METHOD)* meth);

version(OPENSSL_NO_SSL2) {} else {
const(SSL_METHOD)* SSLv2_method();		/* SSLv2 */
const(SSL_METHOD)* SSLv2_server_method();	/* SSLv2 */
const(SSL_METHOD)* SSLv2_client_method();	/* SSLv2 */
}

const(SSL_METHOD)* SSLv3_method();		/* SSLv3 */
const(SSL_METHOD)* SSLv3_server_method();	/* SSLv3 */
const(SSL_METHOD)* SSLv3_client_method();	/* SSLv3 */

const(SSL_METHOD)* SSLv23_method();	/* SSLv3 but can rollback to v2 */
const(SSL_METHOD)* SSLv23_server_method();	/* SSLv3 but can rollback to v2 */
const(SSL_METHOD)* SSLv23_client_method();	/* SSLv3 but can rollback to v2 */

const(SSL_METHOD)* TLSv1_method();		/* TLSv1.0 */
const(SSL_METHOD)* TLSv1_server_method();	/* TLSv1.0 */
const(SSL_METHOD)* TLSv1_client_method();	/* TLSv1.0 */

const(SSL_METHOD)* DTLSv1_method();		/* DTLSv1.0 */
const(SSL_METHOD)* DTLSv1_server_method();	/* DTLSv1.0 */
const(SSL_METHOD)* DTLSv1_client_method();	/* DTLSv1.0 */

STACK_OF!(SSL_CIPHER) *SSL_get_ciphers(const(SSL)* s);

int SSL_do_handshake(SSL* s);
int SSL_renegotiate(SSL* s);
int SSL_renegotiate_pending(SSL* s);
int SSL_shutdown(SSL* s);

const(SSL_METHOD)* SSL_get_ssl_method(SSL* s);
int SSL_set_ssl_method(SSL* s, const(SSL_METHOD)* method);
const(char)* SSL_alert_type_string_long(int value);
const(char)* SSL_alert_type_string(int value);
const(char)* SSL_alert_desc_string_long(int value);
const(char)* SSL_alert_desc_string(int value);

void SSL_set_client_CA_list(SSL* s, STACK_OF!(X509_NAME) *name_list);
void SSL_CTX_set_client_CA_list(SSL_CTX* ctx, STACK_OF!(X509_NAME) *name_list);
STACK_OF!(X509_NAME) *SSL_get_client_CA_list(const(SSL)* s);
STACK_OF!(X509_NAME) *SSL_CTX_get_client_CA_list(const(SSL_CTX)* s);
int SSL_add_client_CA(SSL* ssl,X509* x);
int SSL_CTX_add_client_CA(SSL_CTX* ctx,X509* x);

void SSL_set_connect_state(SSL* s);
void SSL_set_accept_state(SSL* s);

c_long SSL_get_default_timeout(const(SSL)* s);

int SSL_library_init();

char* SSL_CIPHER_description(const(SSL_CIPHER)*,char* buf,int size);
STACK_OF!(X509_NAME) *SSL_dup_CA_list(STACK_OF!(X509_NAME) *sk);

SSL* SSL_dup(SSL* ssl);

X509* SSL_get_certificate(const(SSL)* ssl);
/* EVP_PKEY */ evp_pkey_st* SSL_get_privatekey(SSL* ssl);

void SSL_CTX_set_quiet_shutdown(SSL_CTX* ctx,int mode);
int SSL_CTX_get_quiet_shutdown(const(SSL_CTX)* ctx);
void SSL_set_quiet_shutdown(SSL* ssl,int mode);
int SSL_get_quiet_shutdown(const(SSL)* ssl);
void SSL_set_shutdown(SSL* ssl,int mode);
int SSL_get_shutdown(const(SSL)* ssl);
int SSL_version(const(SSL)* ssl);
int SSL_CTX_set_default_verify_paths(SSL_CTX* ctx);
int SSL_CTX_load_verify_locations(SSL_CTX* ctx, const(char)* CAfile,
	const(char)* CApath);
alias SSL_get_session SSL_get0_session; /* just peek at pointer */
SSL_SESSION* SSL_get_session(const(SSL)* ssl);
SSL_SESSION* SSL_get1_session(SSL* ssl); /* obtain a reference count */
SSL_CTX* SSL_get_SSL_CTX(const(SSL)* ssl);
SSL_CTX* SSL_set_SSL_CTX(SSL* ssl, SSL_CTX* ctx);
void SSL_set_info_callback(SSL* ssl,
			   ExternC!(void function(const(SSL)* ssl,int type,int val)) cb);
ExternC!(void function(const(SSL)* ssl,int type,int val)) SSL_get_info_callback(const(SSL)* ssl);
int SSL_state(const(SSL)* ssl);

void SSL_set_verify_result(SSL* ssl,c_long v);
c_long SSL_get_verify_result(const(SSL)* ssl);

int SSL_set_ex_data(SSL* ssl,int idx,void* data);
void* SSL_get_ex_data(const(SSL)* ssl,int idx);
int SSL_get_ex_new_index(c_long argl, void* argp, CRYPTO_EX_new* new_func,
	CRYPTO_EX_dup* dup_func, CRYPTO_EX_free* free_func);

int SSL_SESSION_set_ex_data(SSL_SESSION* ss,int idx,void* data);
void* SSL_SESSION_get_ex_data(const(SSL_SESSION)* ss,int idx);
int SSL_SESSION_get_ex_new_index(c_long argl, void* argp, CRYPTO_EX_new* new_func,
	CRYPTO_EX_dup* dup_func, CRYPTO_EX_free* free_func);

int SSL_CTX_set_ex_data(SSL_CTX* ssl,int idx,void* data);
void* SSL_CTX_get_ex_data(const(SSL_CTX)* ssl,int idx);
int SSL_CTX_get_ex_new_index(c_long argl, void* argp, CRYPTO_EX_new* new_func,
	CRYPTO_EX_dup* dup_func, CRYPTO_EX_free* free_func);

int SSL_get_ex_data_X509_STORE_CTX_idx();

auto SSL_CTX_sess_set_cache_size()(SSL_CTX* ctx, c_long t) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_SESS_CACHE_SIZE,t,null);
}
auto SSL_CTX_sess_get_cache_size()(SSL_CTX* ctx) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_GET_SESS_CACHE_SIZE,0,null);
}
auto SSL_CTX_set_session_cache_mode()(SSL_CTX* ctx, c_long m) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_SESS_CACHE_MODE,m,null);
}
auto SSL_CTX_get_session_cache_mode()(SSL_CTX* ctx) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_GET_SESS_CACHE_MODE,0,null);
}

alias SSL_CTX_get_read_ahead SSL_CTX_get_default_read_ahead;
alias SSL_CTX_set_read_ahead SSL_CTX_set_default_read_ahead;
auto SSL_CTX_get_read_ahead()(SSL_CTX* ctx) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_GET_READ_AHEAD,0,null);
}
auto SSL_CTX_set_read_ahead()(SSL_CTX* ctx, c_long m) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_READ_AHEAD,m,null);
}
auto SSL_CTX_get_max_cert_list()(SSL_CTX* ctx) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_GET_MAX_CERT_LIST,0,null);
}
auto SSL_CTX_set_max_cert_list()(SSL_CTX* ctx, c_long m) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_MAX_CERT_LIST,m,null);
}
auto SSL_get_max_cert_list()(SSL* ssl) {
	SSL_ctrl(ssl,SSL_CTRL_GET_MAX_CERT_LIST,0,null);
}
auto SSL_set_max_cert_list()(SSL* ssl,c_long m) {
	SSL_ctrl(ssl,SSL_CTRL_SET_MAX_CERT_LIST,m,null);
}

auto SSL_CTX_set_max_send_fragment()(SSL_CTX* ctx, c_long m) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_MAX_SEND_FRAGMENT,m,null);
}
auto SSL_set_max_send_fragment()(SSL* ssl,m) {
	SSL_ctrl(ssl,SSL_CTRL_SET_MAX_SEND_FRAGMENT,m,null);
}

     /* NB: the keylength is only applicable when is_export is true */
version(OPENSSL_NO_RSA) {} else {
void SSL_CTX_set_tmp_rsa_callback(SSL_CTX* ctx,
				  ExternC!(RSA* function(SSL* ssl,int is_export,
					     int keylength)) cb);

void SSL_set_tmp_rsa_callback(SSL* ssl,
				  ExternC!(RSA* function(SSL* ssl,int is_export,
					     int keylength)) cb);
}
version(OPENSSL_NO_DH) {} else {
void SSL_CTX_set_tmp_dh_callback(SSL_CTX* ctx,
				 ExternC!(DH* function(SSL* ssl,int is_export,
					   int keylength)) dh);
void SSL_set_tmp_dh_callback(SSL* ssl,
				 ExternC!(DH* function(SSL* ssl,int is_export,
					   int keylength)) dh);
}
version(OPENSSL_NO_ECDH) {} else {
void SSL_CTX_set_tmp_ecdh_callback(SSL_CTX* ctx,
				 ExternC!(EC_KEY* function(SSL* ssl,int is_export,
					   int keylength)) ecdh);
void SSL_set_tmp_ecdh_callback(SSL* ssl,
				 ExternC!(EC_KEY* function(SSL* ssl,int is_export,
					   int keylength)) ecdh);
}

version(OPENSSL_NO_COMP) {
const(void)* SSL_get_current_compression(SSL* s);
const(void)* SSL_get_current_expansion(SSL* s);
const(char)* SSL_COMP_get_name(const(void)* comp);
void* SSL_COMP_get_compression_methods();
int SSL_COMP_add_compression_method(int id,void* cm);
} else {
const(COMP_METHOD)* SSL_get_current_compression(SSL* s);
const(COMP_METHOD)* SSL_get_current_expansion(SSL* s);
const(char)* SSL_COMP_get_name(const(COMP_METHOD)* comp);
STACK_OF!(SSL_COMP) *SSL_COMP_get_compression_methods();
int SSL_COMP_add_compression_method(int id,COMP_METHOD* cm);
}

/* TLS extensions functions */
int SSL_set_session_ticket_ext(SSL* s, void* ext_data, int ext_len);

int SSL_set_session_ticket_ext_cb(SSL* s, tls_session_ticket_ext_cb_fn cb,
				  void* arg);

/* Pre-shared secret session resumption functions */
int SSL_set_session_secret_cb(SSL* s, tls_session_secret_cb_fn tls_session_secret_cb, void* arg);

/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
void ERR_load_SSL_strings();

/* Error codes for the SSL functions. */

/* Function codes. */
enum SSL_F_CLIENT_CERTIFICATE = 100;
enum SSL_F_CLIENT_FINISHED = 167;
enum SSL_F_CLIENT_HELLO = 101;
enum SSL_F_CLIENT_MASTER_KEY = 102;
enum SSL_F_D2I_SSL_SESSION = 103;
enum SSL_F_DO_DTLS1_WRITE = 245;
enum SSL_F_DO_SSL3_WRITE = 104;
enum SSL_F_DTLS1_ACCEPT = 246;
enum SSL_F_DTLS1_ADD_CERT_TO_BUF = 295;
enum SSL_F_DTLS1_BUFFER_RECORD = 247;
enum SSL_F_DTLS1_CLIENT_HELLO = 248;
enum SSL_F_DTLS1_CONNECT = 249;
enum SSL_F_DTLS1_ENC = 250;
enum SSL_F_DTLS1_GET_HELLO_VERIFY = 251;
enum SSL_F_DTLS1_GET_MESSAGE = 252;
enum SSL_F_DTLS1_GET_MESSAGE_FRAGMENT = 253;
enum SSL_F_DTLS1_GET_RECORD = 254;
enum SSL_F_DTLS1_HANDLE_TIMEOUT = 297;
enum SSL_F_DTLS1_OUTPUT_CERT_CHAIN = 255;
enum SSL_F_DTLS1_PREPROCESS_FRAGMENT = 288;
enum SSL_F_DTLS1_PROCESS_OUT_OF_SEQ_MESSAGE = 256;
enum SSL_F_DTLS1_PROCESS_RECORD = 257;
enum SSL_F_DTLS1_READ_BYTES = 258;
enum SSL_F_DTLS1_READ_FAILED = 259;
enum SSL_F_DTLS1_SEND_CERTIFICATE_REQUEST = 260;
enum SSL_F_DTLS1_SEND_CLIENT_CERTIFICATE = 261;
enum SSL_F_DTLS1_SEND_CLIENT_KEY_EXCHANGE = 262;
enum SSL_F_DTLS1_SEND_CLIENT_VERIFY = 263;
enum SSL_F_DTLS1_SEND_HELLO_VERIFY_REQUEST = 264;
enum SSL_F_DTLS1_SEND_SERVER_CERTIFICATE = 265;
enum SSL_F_DTLS1_SEND_SERVER_HELLO = 266;
enum SSL_F_DTLS1_SEND_SERVER_KEY_EXCHANGE = 267;
enum SSL_F_DTLS1_WRITE_APP_DATA_BYTES = 268;
enum SSL_F_GET_CLIENT_FINISHED = 105;
enum SSL_F_GET_CLIENT_HELLO = 106;
enum SSL_F_GET_CLIENT_MASTER_KEY = 107;
enum SSL_F_GET_SERVER_FINISHED = 108;
enum SSL_F_GET_SERVER_HELLO = 109;
enum SSL_F_GET_SERVER_VERIFY = 110;
enum SSL_F_I2D_SSL_SESSION = 111;
enum SSL_F_READ_N = 112;
enum SSL_F_REQUEST_CERTIFICATE = 113;
enum SSL_F_SERVER_FINISH = 239;
enum SSL_F_SERVER_HELLO = 114;
enum SSL_F_SERVER_VERIFY = 240;
enum SSL_F_SSL23_ACCEPT = 115;
enum SSL_F_SSL23_CLIENT_HELLO = 116;
enum SSL_F_SSL23_CONNECT = 117;
enum SSL_F_SSL23_GET_CLIENT_HELLO = 118;
enum SSL_F_SSL23_GET_SERVER_HELLO = 119;
enum SSL_F_SSL23_PEEK = 237;
enum SSL_F_SSL23_READ = 120;
enum SSL_F_SSL23_WRITE = 121;
enum SSL_F_SSL2_ACCEPT = 122;
enum SSL_F_SSL2_CONNECT = 123;
enum SSL_F_SSL2_ENC_INIT = 124;
enum SSL_F_SSL2_GENERATE_KEY_MATERIAL = 241;
enum SSL_F_SSL2_PEEK = 234;
enum SSL_F_SSL2_READ = 125;
enum SSL_F_SSL2_READ_INTERNAL = 236;
enum SSL_F_SSL2_SET_CERTIFICATE = 126;
enum SSL_F_SSL2_WRITE = 127;
enum SSL_F_SSL3_ACCEPT = 128;
enum SSL_F_SSL3_ADD_CERT_TO_BUF = 296;
enum SSL_F_SSL3_CALLBACK_CTRL = 233;
enum SSL_F_SSL3_CHANGE_CIPHER_STATE = 129;
enum SSL_F_SSL3_CHECK_CERT_AND_ALGORITHM = 130;
enum SSL_F_SSL3_CLIENT_HELLO = 131;
enum SSL_F_SSL3_CONNECT = 132;
enum SSL_F_SSL3_CTRL = 213;
enum SSL_F_SSL3_CTX_CTRL = 133;
enum SSL_F_SSL3_DIGEST_CACHED_RECORDS = 293;
enum SSL_F_SSL3_DO_CHANGE_CIPHER_SPEC = 292;
enum SSL_F_SSL3_ENC = 134;
enum SSL_F_SSL3_GENERATE_KEY_BLOCK = 238;
enum SSL_F_SSL3_GET_CERTIFICATE_REQUEST = 135;
enum SSL_F_SSL3_GET_CERT_STATUS = 289;
enum SSL_F_SSL3_GET_CERT_VERIFY = 136;
enum SSL_F_SSL3_GET_CLIENT_CERTIFICATE = 137;
enum SSL_F_SSL3_GET_CLIENT_HELLO = 138;
enum SSL_F_SSL3_GET_CLIENT_KEY_EXCHANGE = 139;
enum SSL_F_SSL3_GET_FINISHED = 140;
enum SSL_F_SSL3_GET_KEY_EXCHANGE = 141;
enum SSL_F_SSL3_GET_MESSAGE = 142;
enum SSL_F_SSL3_GET_NEW_SESSION_TICKET = 283;
enum SSL_F_SSL3_GET_RECORD = 143;
enum SSL_F_SSL3_GET_SERVER_CERTIFICATE = 144;
enum SSL_F_SSL3_GET_SERVER_DONE = 145;
enum SSL_F_SSL3_GET_SERVER_HELLO = 146;
enum SSL_F_SSL3_HANDSHAKE_MAC = 285;
enum SSL_F_SSL3_NEW_SESSION_TICKET = 287;
enum SSL_F_SSL3_OUTPUT_CERT_CHAIN = 147;
enum SSL_F_SSL3_PEEK = 235;
enum SSL_F_SSL3_READ_BYTES = 148;
enum SSL_F_SSL3_READ_N = 149;
enum SSL_F_SSL3_SEND_CERTIFICATE_REQUEST = 150;
enum SSL_F_SSL3_SEND_CLIENT_CERTIFICATE = 151;
enum SSL_F_SSL3_SEND_CLIENT_KEY_EXCHANGE = 152;
enum SSL_F_SSL3_SEND_CLIENT_VERIFY = 153;
enum SSL_F_SSL3_SEND_SERVER_CERTIFICATE = 154;
enum SSL_F_SSL3_SEND_SERVER_HELLO = 242;
enum SSL_F_SSL3_SEND_SERVER_KEY_EXCHANGE = 155;
enum SSL_F_SSL3_SETUP_KEY_BLOCK = 157;
enum SSL_F_SSL3_SETUP_READ_BUFFER = 156;
enum SSL_F_SSL3_SETUP_WRITE_BUFFER = 291;
enum SSL_F_SSL3_WRITE_BYTES = 158;
enum SSL_F_SSL3_WRITE_PENDING = 159;
enum SSL_F_SSL_ADD_CLIENTHELLO_RENEGOTIATE_EXT = 298;
enum SSL_F_SSL_ADD_CLIENTHELLO_TLSEXT = 277;
enum SSL_F_SSL_ADD_DIR_CERT_SUBJECTS_TO_STACK = 215;
enum SSL_F_SSL_ADD_FILE_CERT_SUBJECTS_TO_STACK = 216;
enum SSL_F_SSL_ADD_SERVERHELLO_RENEGOTIATE_EXT = 299;
enum SSL_F_SSL_ADD_SERVERHELLO_TLSEXT = 278;
enum SSL_F_SSL_BAD_METHOD = 160;
enum SSL_F_SSL_BYTES_TO_CIPHER_LIST = 161;
enum SSL_F_SSL_CERT_DUP = 221;
enum SSL_F_SSL_CERT_INST = 222;
enum SSL_F_SSL_CERT_INSTANTIATE = 214;
enum SSL_F_SSL_CERT_NEW = 162;
enum SSL_F_SSL_CHECK_PRIVATE_KEY = 163;
enum SSL_F_SSL_CHECK_SERVERHELLO_TLSEXT = 280;
enum SSL_F_SSL_CHECK_SRVR_ECC_CERT_AND_ALG = 279;
enum SSL_F_SSL_CIPHER_PROCESS_RULESTR = 230;
enum SSL_F_SSL_CIPHER_STRENGTH_SORT = 231;
enum SSL_F_SSL_CLEAR = 164;
enum SSL_F_SSL_COMP_ADD_COMPRESSION_METHOD = 165;
enum SSL_F_SSL_CREATE_CIPHER_LIST = 166;
enum SSL_F_SSL_CTRL = 232;
enum SSL_F_SSL_CTX_CHECK_PRIVATE_KEY = 168;
enum SSL_F_SSL_CTX_NEW = 169;
enum SSL_F_SSL_CTX_SET_CIPHER_LIST = 269;
enum SSL_F_SSL_CTX_SET_CLIENT_CERT_ENGINE = 290;
enum SSL_F_SSL_CTX_SET_PURPOSE = 226;
enum SSL_F_SSL_CTX_SET_SESSION_ID_CONTEXT = 219;
enum SSL_F_SSL_CTX_SET_SSL_VERSION = 170;
enum SSL_F_SSL_CTX_SET_TRUST = 229;
enum SSL_F_SSL_CTX_USE_CERTIFICATE = 171;
enum SSL_F_SSL_CTX_USE_CERTIFICATE_ASN1 = 172;
enum SSL_F_SSL_CTX_USE_CERTIFICATE_CHAIN_FILE = 220;
enum SSL_F_SSL_CTX_USE_CERTIFICATE_FILE = 173;
enum SSL_F_SSL_CTX_USE_PRIVATEKEY = 174;
enum SSL_F_SSL_CTX_USE_PRIVATEKEY_ASN1 = 175;
enum SSL_F_SSL_CTX_USE_PRIVATEKEY_FILE = 176;
enum SSL_F_SSL_CTX_USE_PSK_IDENTITY_HINT = 272;
enum SSL_F_SSL_CTX_USE_RSAPRIVATEKEY = 177;
enum SSL_F_SSL_CTX_USE_RSAPRIVATEKEY_ASN1 = 178;
enum SSL_F_SSL_CTX_USE_RSAPRIVATEKEY_FILE = 179;
enum SSL_F_SSL_DO_HANDSHAKE = 180;
enum SSL_F_SSL_GET_NEW_SESSION = 181;
enum SSL_F_SSL_GET_PREV_SESSION = 217;
enum SSL_F_SSL_GET_SERVER_SEND_CERT = 182;
enum SSL_F_SSL_GET_SIGN_PKEY = 183;
enum SSL_F_SSL_INIT_WBIO_BUFFER = 184;
enum SSL_F_SSL_LOAD_CLIENT_CA_FILE = 185;
enum SSL_F_SSL_NEW = 186;
enum SSL_F_SSL_PARSE_CLIENTHELLO_RENEGOTIATE_EXT = 300;
enum SSL_F_SSL_PARSE_CLIENTHELLO_TLSEXT = 302;
enum SSL_F_SSL_PARSE_SERVERHELLO_RENEGOTIATE_EXT = 301;
enum SSL_F_SSL_PARSE_SERVERHELLO_TLSEXT = 303;
enum SSL_F_SSL_PEEK = 270;
enum SSL_F_SSL_PREPARE_CLIENTHELLO_TLSEXT = 281;
enum SSL_F_SSL_PREPARE_SERVERHELLO_TLSEXT = 282;
enum SSL_F_SSL_READ = 223;
enum SSL_F_SSL_RSA_PRIVATE_DECRYPT = 187;
enum SSL_F_SSL_RSA_PUBLIC_ENCRYPT = 188;
enum SSL_F_SSL_SESSION_NEW = 189;
enum SSL_F_SSL_SESSION_PRINT_FP = 190;
enum SSL_F_SSL_SESS_CERT_NEW = 225;
enum SSL_F_SSL_SET_CERT = 191;
enum SSL_F_SSL_SET_CIPHER_LIST = 271;
enum SSL_F_SSL_SET_FD = 192;
enum SSL_F_SSL_SET_PKEY = 193;
enum SSL_F_SSL_SET_PURPOSE = 227;
enum SSL_F_SSL_SET_RFD = 194;
enum SSL_F_SSL_SET_SESSION = 195;
enum SSL_F_SSL_SET_SESSION_ID_CONTEXT = 218;
enum SSL_F_SSL_SET_SESSION_TICKET_EXT = 294;
enum SSL_F_SSL_SET_TRUST = 228;
enum SSL_F_SSL_SET_WFD = 196;
enum SSL_F_SSL_SHUTDOWN = 224;
enum SSL_F_SSL_UNDEFINED_CONST_FUNCTION = 243;
enum SSL_F_SSL_UNDEFINED_FUNCTION = 197;
enum SSL_F_SSL_UNDEFINED_VOID_FUNCTION = 244;
enum SSL_F_SSL_USE_CERTIFICATE = 198;
enum SSL_F_SSL_USE_CERTIFICATE_ASN1 = 199;
enum SSL_F_SSL_USE_CERTIFICATE_FILE = 200;
enum SSL_F_SSL_USE_PRIVATEKEY = 201;
enum SSL_F_SSL_USE_PRIVATEKEY_ASN1 = 202;
enum SSL_F_SSL_USE_PRIVATEKEY_FILE = 203;
enum SSL_F_SSL_USE_PSK_IDENTITY_HINT = 273;
enum SSL_F_SSL_USE_RSAPRIVATEKEY = 204;
enum SSL_F_SSL_USE_RSAPRIVATEKEY_ASN1 = 205;
enum SSL_F_SSL_USE_RSAPRIVATEKEY_FILE = 206;
enum SSL_F_SSL_VERIFY_CERT_CHAIN = 207;
enum SSL_F_SSL_WRITE = 208;
enum SSL_F_TLS1_CERT_VERIFY_MAC = 286;
enum SSL_F_TLS1_CHANGE_CIPHER_STATE = 209;
enum SSL_F_TLS1_CHECK_SERVERHELLO_TLSEXT = 274;
enum SSL_F_TLS1_ENC = 210;
enum SSL_F_TLS1_PREPARE_CLIENTHELLO_TLSEXT = 275;
enum SSL_F_TLS1_PREPARE_SERVERHELLO_TLSEXT = 276;
enum SSL_F_TLS1_PRF = 284;
enum SSL_F_TLS1_SETUP_KEY_BLOCK = 211;
enum SSL_F_WRITE_PENDING = 212;

/* Reason codes. */
enum SSL_R_APP_DATA_IN_HANDSHAKE = 100;
enum SSL_R_ATTEMPT_TO_REUSE_SESSION_IN_DIFFERENT_CONTEXT = 272;
enum SSL_R_BAD_ALERT_RECORD = 101;
enum SSL_R_BAD_AUTHENTICATION_TYPE = 102;
enum SSL_R_BAD_CHANGE_CIPHER_SPEC = 103;
enum SSL_R_BAD_CHECKSUM = 104;
enum SSL_R_BAD_DATA_RETURNED_BY_CALLBACK = 106;
enum SSL_R_BAD_DECOMPRESSION = 107;
enum SSL_R_BAD_DH_G_LENGTH = 108;
enum SSL_R_BAD_DH_PUB_KEY_LENGTH = 109;
enum SSL_R_BAD_DH_P_LENGTH = 110;
enum SSL_R_BAD_DIGEST_LENGTH = 111;
enum SSL_R_BAD_DSA_SIGNATURE = 112;
enum SSL_R_BAD_ECC_CERT = 304;
enum SSL_R_BAD_ECDSA_SIGNATURE = 305;
enum SSL_R_BAD_ECPOINT = 306;
enum SSL_R_BAD_HANDSHAKE_LENGTH = 332;
enum SSL_R_BAD_HELLO_REQUEST = 105;
enum SSL_R_BAD_LENGTH = 271;
enum SSL_R_BAD_MAC_DECODE = 113;
enum SSL_R_BAD_MAC_LENGTH = 333;
enum SSL_R_BAD_MESSAGE_TYPE = 114;
enum SSL_R_BAD_PACKET_LENGTH = 115;
enum SSL_R_BAD_PROTOCOL_VERSION_NUMBER = 116;
enum SSL_R_BAD_PSK_IDENTITY_HINT_LENGTH = 316;
enum SSL_R_BAD_RESPONSE_ARGUMENT = 117;
enum SSL_R_BAD_RSA_DECRYPT = 118;
enum SSL_R_BAD_RSA_ENCRYPT = 119;
enum SSL_R_BAD_RSA_E_LENGTH = 120;
enum SSL_R_BAD_RSA_MODULUS_LENGTH = 121;
enum SSL_R_BAD_RSA_SIGNATURE = 122;
enum SSL_R_BAD_SIGNATURE = 123;
enum SSL_R_BAD_SSL_FILETYPE = 124;
enum SSL_R_BAD_SSL_SESSION_ID_LENGTH = 125;
enum SSL_R_BAD_STATE = 126;
enum SSL_R_BAD_WRITE_RETRY = 127;
enum SSL_R_BIO_NOT_SET = 128;
enum SSL_R_BLOCK_CIPHER_PAD_IS_WRONG = 129;
enum SSL_R_BN_LIB = 130;
enum SSL_R_CA_DN_LENGTH_MISMATCH = 131;
enum SSL_R_CA_DN_TOO_LONG = 132;
enum SSL_R_CCS_RECEIVED_EARLY = 133;
enum SSL_R_CERTIFICATE_VERIFY_FAILED = 134;
enum SSL_R_CERT_LENGTH_MISMATCH = 135;
enum SSL_R_CHALLENGE_IS_DIFFERENT = 136;
enum SSL_R_CIPHER_CODE_WRONG_LENGTH = 137;
enum SSL_R_CIPHER_OR_HASH_UNAVAILABLE = 138;
enum SSL_R_CIPHER_TABLE_SRC_ERROR = 139;
enum SSL_R_CLIENTHELLO_TLSEXT = 226;
enum SSL_R_COMPRESSED_LENGTH_TOO_LONG = 140;
enum SSL_R_COMPRESSION_DISABLED = 343;
enum SSL_R_COMPRESSION_FAILURE = 141;
enum SSL_R_COMPRESSION_ID_NOT_WITHIN_PRIVATE_RANGE = 307;
enum SSL_R_COMPRESSION_LIBRARY_ERROR = 142;
enum SSL_R_CONNECTION_ID_IS_DIFFERENT = 143;
enum SSL_R_CONNECTION_TYPE_NOT_SET = 144;
enum SSL_R_COOKIE_MISMATCH = 308;
enum SSL_R_DATA_BETWEEN_CCS_AND_FINISHED = 145;
enum SSL_R_DATA_LENGTH_TOO_LONG = 146;
enum SSL_R_DECRYPTION_FAILED = 147;
enum SSL_R_DECRYPTION_FAILED_OR_BAD_RECORD_MAC = 281;
enum SSL_R_DH_PUBLIC_VALUE_LENGTH_IS_WRONG = 148;
enum SSL_R_DIGEST_CHECK_FAILED = 149;
enum SSL_R_DTLS_MESSAGE_TOO_BIG = 334;
enum SSL_R_DUPLICATE_COMPRESSION_ID = 309;
enum SSL_R_ECC_CERT_NOT_FOR_KEY_AGREEMENT = 317;
enum SSL_R_ECC_CERT_NOT_FOR_SIGNING = 318;
enum SSL_R_ECC_CERT_SHOULD_HAVE_RSA_SIGNATURE = 322;
enum SSL_R_ECC_CERT_SHOULD_HAVE_SHA1_SIGNATURE = 323;
enum SSL_R_ECGROUP_TOO_LARGE_FOR_CIPHER = 310;
enum SSL_R_ENCRYPTED_LENGTH_TOO_LONG = 150;
enum SSL_R_ERROR_GENERATING_TMP_RSA_KEY = 282;
enum SSL_R_ERROR_IN_RECEIVED_CIPHER_LIST = 151;
enum SSL_R_EXCESSIVE_MESSAGE_SIZE = 152;
enum SSL_R_EXTRA_DATA_IN_MESSAGE = 153;
enum SSL_R_GOT_A_FIN_BEFORE_A_CCS = 154;
enum SSL_R_HTTPS_PROXY_REQUEST = 155;
enum SSL_R_HTTP_REQUEST = 156;
enum SSL_R_ILLEGAL_PADDING = 283;
enum SSL_R_INCONSISTENT_COMPRESSION = 340;
enum SSL_R_INVALID_CHALLENGE_LENGTH = 158;
enum SSL_R_INVALID_COMMAND = 280;
enum SSL_R_INVALID_COMPRESSION_ALGORITHM = 341;
enum SSL_R_INVALID_PURPOSE = 278;
enum SSL_R_INVALID_STATUS_RESPONSE = 328;
enum SSL_R_INVALID_TICKET_KEYS_LENGTH = 325;
enum SSL_R_INVALID_TRUST = 279;
enum SSL_R_KEY_ARG_TOO_LONG = 284;
enum SSL_R_KRB5 = 285;
enum SSL_R_KRB5_C_CC_PRINC = 286;
enum SSL_R_KRB5_C_GET_CRED = 287;
enum SSL_R_KRB5_C_INIT = 288;
enum SSL_R_KRB5_C_MK_REQ = 289;
enum SSL_R_KRB5_S_BAD_TICKET = 290;
enum SSL_R_KRB5_S_INIT = 291;
enum SSL_R_KRB5_S_RD_REQ = 292;
enum SSL_R_KRB5_S_TKT_EXPIRED = 293;
enum SSL_R_KRB5_S_TKT_NYV = 294;
enum SSL_R_KRB5_S_TKT_SKEW = 295;
enum SSL_R_LENGTH_MISMATCH = 159;
enum SSL_R_LENGTH_TOO_SHORT = 160;
enum SSL_R_LIBRARY_BUG = 274;
enum SSL_R_LIBRARY_HAS_NO_CIPHERS = 161;
enum SSL_R_MESSAGE_TOO_LONG = 296;
enum SSL_R_MISSING_DH_DSA_CERT = 162;
enum SSL_R_MISSING_DH_KEY = 163;
enum SSL_R_MISSING_DH_RSA_CERT = 164;
enum SSL_R_MISSING_DSA_SIGNING_CERT = 165;
enum SSL_R_MISSING_EXPORT_TMP_DH_KEY = 166;
enum SSL_R_MISSING_EXPORT_TMP_RSA_KEY = 167;
enum SSL_R_MISSING_RSA_CERTIFICATE = 168;
enum SSL_R_MISSING_RSA_ENCRYPTING_CERT = 169;
enum SSL_R_MISSING_RSA_SIGNING_CERT = 170;
enum SSL_R_MISSING_TMP_DH_KEY = 171;
enum SSL_R_MISSING_TMP_ECDH_KEY = 311;
enum SSL_R_MISSING_TMP_RSA_KEY = 172;
enum SSL_R_MISSING_TMP_RSA_PKEY = 173;
enum SSL_R_MISSING_VERIFY_MESSAGE = 174;
enum SSL_R_NON_SSLV2_INITIAL_PACKET = 175;
enum SSL_R_NO_CERTIFICATES_RETURNED = 176;
enum SSL_R_NO_CERTIFICATE_ASSIGNED = 177;
enum SSL_R_NO_CERTIFICATE_RETURNED = 178;
enum SSL_R_NO_CERTIFICATE_SET = 179;
enum SSL_R_NO_CERTIFICATE_SPECIFIED = 180;
enum SSL_R_NO_CIPHERS_AVAILABLE = 181;
enum SSL_R_NO_CIPHERS_PASSED = 182;
enum SSL_R_NO_CIPHERS_SPECIFIED = 183;
enum SSL_R_NO_CIPHER_LIST = 184;
enum SSL_R_NO_CIPHER_MATCH = 185;
enum SSL_R_NO_CLIENT_CERT_METHOD = 331;
enum SSL_R_NO_CLIENT_CERT_RECEIVED = 186;
enum SSL_R_NO_COMPRESSION_SPECIFIED = 187;
enum SSL_R_NO_GOST_CERTIFICATE_SENT_BY_PEER = 330;
enum SSL_R_NO_METHOD_SPECIFIED = 188;
enum SSL_R_NO_PRIVATEKEY = 189;
enum SSL_R_NO_PRIVATE_KEY_ASSIGNED = 190;
enum SSL_R_NO_PROTOCOLS_AVAILABLE = 191;
enum SSL_R_NO_PUBLICKEY = 192;
enum SSL_R_NO_RENEGOTIATION = 339;
enum SSL_R_NO_REQUIRED_DIGEST = 324;
enum SSL_R_NO_SHARED_CIPHER = 193;
enum SSL_R_NO_VERIFY_CALLBACK = 194;
enum SSL_R_NULL_SSL_CTX = 195;
enum SSL_R_NULL_SSL_METHOD_PASSED = 196;
enum SSL_R_OLD_SESSION_CIPHER_NOT_RETURNED = 197;
enum SSL_R_OLD_SESSION_COMPRESSION_ALGORITHM_NOT_RETURNED = 344;
enum SSL_R_ONLY_TLS_ALLOWED_IN_FIPS_MODE = 297;
enum SSL_R_OPAQUE_PRF_INPUT_TOO_LONG = 327;
enum SSL_R_PACKET_LENGTH_TOO_LONG = 198;
enum SSL_R_PARSE_TLSEXT = 227;
enum SSL_R_PATH_TOO_LONG = 270;
enum SSL_R_PEER_DID_NOT_RETURN_A_CERTIFICATE = 199;
enum SSL_R_PEER_ERROR = 200;
enum SSL_R_PEER_ERROR_CERTIFICATE = 201;
enum SSL_R_PEER_ERROR_NO_CERTIFICATE = 202;
enum SSL_R_PEER_ERROR_NO_CIPHER = 203;
enum SSL_R_PEER_ERROR_UNSUPPORTED_CERTIFICATE_TYPE = 204;
enum SSL_R_PRE_MAC_LENGTH_TOO_LONG = 205;
enum SSL_R_PROBLEMS_MAPPING_CIPHER_FUNCTIONS = 206;
enum SSL_R_PROTOCOL_IS_SHUTDOWN = 207;
enum SSL_R_PSK_IDENTITY_NOT_FOUND = 223;
enum SSL_R_PSK_NO_CLIENT_CB = 224;
enum SSL_R_PSK_NO_SERVER_CB = 225;
enum SSL_R_PUBLIC_KEY_ENCRYPT_ERROR = 208;
enum SSL_R_PUBLIC_KEY_IS_NOT_RSA = 209;
enum SSL_R_PUBLIC_KEY_NOT_RSA = 210;
enum SSL_R_READ_BIO_NOT_SET = 211;
enum SSL_R_READ_TIMEOUT_EXPIRED = 312;
enum SSL_R_READ_WRONG_PACKET_TYPE = 212;
enum SSL_R_RECORD_LENGTH_MISMATCH = 213;
enum SSL_R_RECORD_TOO_LARGE = 214;
enum SSL_R_RECORD_TOO_SMALL = 298;
enum SSL_R_RENEGOTIATE_EXT_TOO_LONG = 335;
enum SSL_R_RENEGOTIATION_ENCODING_ERR = 336;
enum SSL_R_RENEGOTIATION_MISMATCH = 337;
enum SSL_R_REQUIRED_CIPHER_MISSING = 215;
enum SSL_R_REQUIRED_COMPRESSSION_ALGORITHM_MISSING = 342;
enum SSL_R_REUSE_CERT_LENGTH_NOT_ZERO = 216;
enum SSL_R_REUSE_CERT_TYPE_NOT_ZERO = 217;
enum SSL_R_REUSE_CIPHER_LIST_NOT_ZERO = 218;
enum SSL_R_SCSV_RECEIVED_WHEN_RENEGOTIATING = 345;
enum SSL_R_SERVERHELLO_TLSEXT = 275;
enum SSL_R_SESSION_ID_CONTEXT_UNINITIALIZED = 277;
enum SSL_R_SHORT_READ = 219;
enum SSL_R_SIGNATURE_FOR_NON_SIGNING_CERTIFICATE = 220;
enum SSL_R_SSL23_DOING_SESSION_ID_REUSE = 221;
enum SSL_R_SSL2_CONNECTION_ID_TOO_LONG = 299;
enum SSL_R_SSL3_EXT_INVALID_ECPOINTFORMAT = 321;
enum SSL_R_SSL3_EXT_INVALID_SERVERNAME = 319;
enum SSL_R_SSL3_EXT_INVALID_SERVERNAME_TYPE = 320;
enum SSL_R_SSL3_SESSION_ID_TOO_LONG = 300;
enum SSL_R_SSL3_SESSION_ID_TOO_SHORT = 222;
enum SSL_R_SSLV3_ALERT_BAD_CERTIFICATE = 1042;
enum SSL_R_SSLV3_ALERT_BAD_RECORD_MAC = 1020;
enum SSL_R_SSLV3_ALERT_CERTIFICATE_EXPIRED = 1045;
enum SSL_R_SSLV3_ALERT_CERTIFICATE_REVOKED = 1044;
enum SSL_R_SSLV3_ALERT_CERTIFICATE_UNKNOWN = 1046;
enum SSL_R_SSLV3_ALERT_DECOMPRESSION_FAILURE = 1030;
enum SSL_R_SSLV3_ALERT_HANDSHAKE_FAILURE = 1040;
enum SSL_R_SSLV3_ALERT_ILLEGAL_PARAMETER = 1047;
enum SSL_R_SSLV3_ALERT_NO_CERTIFICATE = 1041;
enum SSL_R_SSLV3_ALERT_UNEXPECTED_MESSAGE = 1010;
enum SSL_R_SSLV3_ALERT_UNSUPPORTED_CERTIFICATE = 1043;
enum SSL_R_SSL_CTX_HAS_NO_DEFAULT_SSL_VERSION = 228;
enum SSL_R_SSL_HANDSHAKE_FAILURE = 229;
enum SSL_R_SSL_LIBRARY_HAS_NO_CIPHERS = 230;
enum SSL_R_SSL_SESSION_ID_CALLBACK_FAILED = 301;
enum SSL_R_SSL_SESSION_ID_CONFLICT = 302;
enum SSL_R_SSL_SESSION_ID_CONTEXT_TOO_LONG = 273;
enum SSL_R_SSL_SESSION_ID_HAS_BAD_LENGTH = 303;
enum SSL_R_SSL_SESSION_ID_IS_DIFFERENT = 231;
enum SSL_R_TLSV1_ALERT_ACCESS_DENIED = 1049;
enum SSL_R_TLSV1_ALERT_DECODE_ERROR = 1050;
enum SSL_R_TLSV1_ALERT_DECRYPTION_FAILED = 1021;
enum SSL_R_TLSV1_ALERT_DECRYPT_ERROR = 1051;
enum SSL_R_TLSV1_ALERT_EXPORT_RESTRICTION = 1060;
enum SSL_R_TLSV1_ALERT_INSUFFICIENT_SECURITY = 1071;
enum SSL_R_TLSV1_ALERT_INTERNAL_ERROR = 1080;
enum SSL_R_TLSV1_ALERT_NO_RENEGOTIATION = 1100;
enum SSL_R_TLSV1_ALERT_PROTOCOL_VERSION = 1070;
enum SSL_R_TLSV1_ALERT_RECORD_OVERFLOW = 1022;
enum SSL_R_TLSV1_ALERT_UNKNOWN_CA = 1048;
enum SSL_R_TLSV1_ALERT_USER_CANCELLED = 1090;
enum SSL_R_TLSV1_BAD_CERTIFICATE_HASH_VALUE = 1114;
enum SSL_R_TLSV1_BAD_CERTIFICATE_STATUS_RESPONSE = 1113;
enum SSL_R_TLSV1_CERTIFICATE_UNOBTAINABLE = 1111;
enum SSL_R_TLSV1_UNRECOGNIZED_NAME = 1112;
enum SSL_R_TLSV1_UNSUPPORTED_EXTENSION = 1110;
enum SSL_R_TLS_CLIENT_CERT_REQ_WITH_ANON_CIPHER = 232;
enum SSL_R_TLS_INVALID_ECPOINTFORMAT_LIST = 157;
enum SSL_R_TLS_PEER_DID_NOT_RESPOND_WITH_CERTIFICATE_LIST = 233;
enum SSL_R_TLS_RSA_ENCRYPTED_VALUE_LENGTH_IS_WRONG = 234;
enum SSL_R_TRIED_TO_USE_UNSUPPORTED_CIPHER = 235;
enum SSL_R_UNABLE_TO_DECODE_DH_CERTS = 236;
enum SSL_R_UNABLE_TO_DECODE_ECDH_CERTS = 313;
enum SSL_R_UNABLE_TO_EXTRACT_PUBLIC_KEY = 237;
enum SSL_R_UNABLE_TO_FIND_DH_PARAMETERS = 238;
enum SSL_R_UNABLE_TO_FIND_ECDH_PARAMETERS = 314;
enum SSL_R_UNABLE_TO_FIND_PUBLIC_KEY_PARAMETERS = 239;
enum SSL_R_UNABLE_TO_FIND_SSL_METHOD = 240;
enum SSL_R_UNABLE_TO_LOAD_SSL2_MD5_ROUTINES = 241;
enum SSL_R_UNABLE_TO_LOAD_SSL3_MD5_ROUTINES = 242;
enum SSL_R_UNABLE_TO_LOAD_SSL3_SHA1_ROUTINES = 243;
enum SSL_R_UNEXPECTED_MESSAGE = 244;
enum SSL_R_UNEXPECTED_RECORD = 245;
enum SSL_R_UNINITIALIZED = 276;
enum SSL_R_UNKNOWN_ALERT_TYPE = 246;
enum SSL_R_UNKNOWN_CERTIFICATE_TYPE = 247;
enum SSL_R_UNKNOWN_CIPHER_RETURNED = 248;
enum SSL_R_UNKNOWN_CIPHER_TYPE = 249;
enum SSL_R_UNKNOWN_KEY_EXCHANGE_TYPE = 250;
enum SSL_R_UNKNOWN_PKEY_TYPE = 251;
enum SSL_R_UNKNOWN_PROTOCOL = 252;
enum SSL_R_UNKNOWN_REMOTE_ERROR_TYPE = 253;
enum SSL_R_UNKNOWN_SSL_VERSION = 254;
enum SSL_R_UNKNOWN_STATE = 255;
enum SSL_R_UNSAFE_LEGACY_RENEGOTIATION_DISABLED = 338;
enum SSL_R_UNSUPPORTED_CIPHER = 256;
enum SSL_R_UNSUPPORTED_COMPRESSION_ALGORITHM = 257;
enum SSL_R_UNSUPPORTED_DIGEST_TYPE = 326;
enum SSL_R_UNSUPPORTED_ELLIPTIC_CURVE = 315;
enum SSL_R_UNSUPPORTED_PROTOCOL = 258;
enum SSL_R_UNSUPPORTED_SSL_VERSION = 259;
enum SSL_R_UNSUPPORTED_STATUS_TYPE = 329;
enum SSL_R_WRITE_BIO_NOT_SET = 260;
enum SSL_R_WRONG_CIPHER_RETURNED = 261;
enum SSL_R_WRONG_MESSAGE_TYPE = 262;
enum SSL_R_WRONG_NUMBER_OF_KEY_BITS = 263;
enum SSL_R_WRONG_SIGNATURE_LENGTH = 264;
enum SSL_R_WRONG_SIGNATURE_SIZE = 265;
enum SSL_R_WRONG_SSL_VERSION = 266;
enum SSL_R_WRONG_VERSION_NUMBER = 267;
enum SSL_R_X509_LIB = 268;
enum SSL_R_X509_VERIFICATION_SETUP_PROBLEMS = 269;
