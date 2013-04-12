/* ssl/tls1.h */
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
 * Copyright (c) 1998-2006 The OpenSSL Project.  All rights reserved.
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
 *
 * Portions of the attached software ("Contribution") are developed by
 * SUN MICROSYSTEMS, INC., and are contributed to the OpenSSL project.
 *
 * The Contribution is licensed pursuant to the OpenSSL open source
 * license provided above.
 *
 * ECC cipher suite support in OpenSSL originally written by
 * Vipul Gupta and Sumit Gupta of Sun Microsystems Laboratories.
 *
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

module deimos.openssl.tls1;

import deimos.openssl._d_util;

import deimos.openssl.ssl; // Needed for SSL_CTX_*.
public import deimos.openssl.buffer;

extern (C):
nothrow:

enum TLS1_ALLOW_EXPERIMENTAL_CIPHERSUITES = 0;

enum TLS1_VERSION = 0x0301;
enum TLS1_VERSION_MAJOR = 0x03;
enum TLS1_VERSION_MINOR = 0x01;

enum TLS1_AD_DECRYPTION_FAILED = 21;
enum TLS1_AD_RECORD_OVERFLOW = 22;
enum TLS1_AD_UNKNOWN_CA = 48;	/* fatal */
enum TLS1_AD_ACCESS_DENIED = 49;	/* fatal */
enum TLS1_AD_DECODE_ERROR = 50;	/* fatal */
enum TLS1_AD_DECRYPT_ERROR = 51;
enum TLS1_AD_EXPORT_RESTRICTION = 60;	/* fatal */
enum TLS1_AD_PROTOCOL_VERSION = 70;	/* fatal */
enum TLS1_AD_INSUFFICIENT_SECURITY = 71;	/* fatal */
enum TLS1_AD_INTERNAL_ERROR = 80;	/* fatal */
enum TLS1_AD_USER_CANCELLED = 90;
enum TLS1_AD_NO_RENEGOTIATION = 100;
/* codes 110-114 are from RFC3546 */
enum TLS1_AD_UNSUPPORTED_EXTENSION = 110;
enum TLS1_AD_CERTIFICATE_UNOBTAINABLE = 111;
enum TLS1_AD_UNRECOGNIZED_NAME = 112;
enum TLS1_AD_BAD_CERTIFICATE_STATUS_RESPONSE = 113;
enum TLS1_AD_BAD_CERTIFICATE_HASH_VALUE = 114;
enum TLS1_AD_UNKNOWN_PSK_IDENTITY = 115;	/* fatal */

/* ExtensionType values from RFC3546 / RFC4366 */
enum TLSEXT_TYPE_server_name = 0;
enum TLSEXT_TYPE_max_fragment_length = 1;
enum TLSEXT_TYPE_client_certificate_url = 2;
enum TLSEXT_TYPE_trusted_ca_keys = 3;
enum TLSEXT_TYPE_truncated_hmac = 4;
enum TLSEXT_TYPE_status_request = 5;
/* ExtensionType values from RFC4492 */
enum TLSEXT_TYPE_elliptic_curves = 10;
enum TLSEXT_TYPE_ec_point_formats = 11;
enum TLSEXT_TYPE_session_ticket = 35;
/* ExtensionType value from draft-rescorla-tls-opaque-prf-input-00.txt */
/+#if 0 /* will have to be provided externally for now ,
       * i.e. build with -DTLSEXT_TYPE_opaque_prf_input=38183
       * using whatever extension number you'd like to try */
# define TLSEXT_TYPE_opaque_prf_input		?? */
#endif+/

/* Temporary extension type */
enum TLSEXT_TYPE_renegotiate = 0xff01;

/* NameType value from RFC 3546 */
enum TLSEXT_NAMETYPE_host_name = 0;
/* status request value from RFC 3546 */
enum TLSEXT_STATUSTYPE_ocsp = 1;

/* ECPointFormat values from draft-ietf-tls-ecc-12 */
enum TLSEXT_ECPOINTFORMAT_first = 0;
enum TLSEXT_ECPOINTFORMAT_uncompressed = 0;
enum TLSEXT_ECPOINTFORMAT_ansiX962_compressed_prime = 1;
enum TLSEXT_ECPOINTFORMAT_ansiX962_compressed_char2 = 2;
enum TLSEXT_ECPOINTFORMAT_last = 2;

version (OPENSSL_NO_TLSEXT) {} else {

enum TLSEXT_MAXLEN_host_name = 255;

const(char)* SSL_get_servername(const(SSL)* s, const int type) ;
int SSL_get_servername_type(const(SSL)* s) ;

auto SSL_set_tlsext_host_name()(SSL* s,char* name) {
	return SSL_ctrl(s,SSL_CTRL_SET_TLSEXT_HOSTNAME,TLSEXT_NAMETYPE_host_name,name);
}

auto SSL_set_tlsext_debug_callback()(SSL* ssl, ExternC!(void function()) cb) {
	return SSL_callback_ctrl(ssl,SSL_CTRL_SET_TLSEXT_DEBUG_CB,cb);
}

auto SSL_set_tlsext_debug_arg()(SSL* ssl, void* arg) {
	return SSL_ctrl(ssl,SSL_CTRL_SET_TLSEXT_DEBUG_ARG,0, arg);
}

auto SSL_set_tlsext_status_type()(SSL* ssl, type) {
	return SSL_ctrl(ssl,SSL_CTRL_SET_TLSEXT_STATUS_REQ_TYPE,type, null);
}

auto SSL_get_tlsext_status_exts()(SSL* ssl, void* arg) {
	return SSL_ctrl(ssl,SSL_CTRL_GET_TLSEXT_STATUS_REQ_EXTS,0, arg);
}

auto SSL_set_tlsext_status_exts()(SSL* ssl, void* arg) {
	return SSL_ctrl(ssl,SSL_CTRL_SET_TLSEXT_STATUS_REQ_EXTS,0, arg);
}

auto SSL_get_tlsext_status_ids()(SSL* ssl, void* arg) {
	return SSL_ctrl(ssl,SSL_CTRL_GET_TLSEXT_STATUS_REQ_IDS,0, arg);
}

auto SSL_set_tlsext_status_ids()(SSL* ssl, void* arg) {
	return SSL_ctrl(ssl,SSL_CTRL_SET_TLSEXT_STATUS_REQ_IDS,0, arg);
}

auto SSL_get_tlsext_status_ocsp_resp()(SSL* ssl, void* arg) {
	return SSL_ctrl(ssl,SSL_CTRL_GET_TLSEXT_STATUS_REQ_OCSP_RESP,0, arg);
}

auto SSL_set_tlsext_status_ocsp_resp()(SSL* ssl, void* arg, void* arglen) {
	return SSL_ctrl(ssl,SSL_CTRL_SET_TLSEXT_STATUS_REQ_OCSP_RESP,arglen, arg);
}

auto SSL_CTX_set_tlsext_servername_callback(SSL_CTX* ctx, ExternC!(void function()) cb) {
	return SSL_CTX_callback_ctrl(ctx,SSL_CTRL_SET_TLSEXT_SERVERNAME_CB,cb);
}

enum SSL_TLSEXT_ERR_OK = 0;
enum SSL_TLSEXT_ERR_ALERT_WARNING = 1;
enum SSL_TLSEXT_ERR_ALERT_FATAL = 2;
enum SSL_TLSEXT_ERR_NOACK = 3;

auto SSL_CTX_set_tlsext_servername_arg(SSL_CTX* ctx, void* arg) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_TLSEXT_SERVERNAME_ARG,0,arg);
}

auto SSL_CTX_get_tlsext_ticket_keys(SSL_CTX* ctx, c_long keylen, void* keys) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_GET_TLSEXT_TICKET_KEYS,keylen,keys);
}
auto SSL_CTX_set_tlsext_ticket_keys(SSL_CTX* ctx, c_long keylen, void* keys) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_TLSEXT_TICKET_KEYS,keylen,keys);
}

auto SSL_CTX_set_tlsext_status_cb(SSL_CTX* ctx, ExternC!(void function()) cb) {
	return SSL_CTX_callback_ctrl(ctx,SSL_CTRL_SET_TLSEXT_STATUS_REQ_CB,cb);
}

auto SSL_CTX_set_tlsext_status_arg(SSL_CTX* ctx, void* arg) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_TLSEXT_STATUS_REQ_CB_ARG,0,arg);
}

auto SSL_set_tlsext_opaque_prf_input(SSL* s, void* src, c_long len) {
	return SSL_ctrl(s,SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT, len, src);
}

auto SSL_CTX_set_tlsext_opaque_prf_input_callback(SSL_CTX* ctx, ExternC!(void function()) cb) {
	return SSL_CTX_callback_ctrl(ctx,SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT_CB, cb);
}
auto SSL_CTX_set_tlsext_opaque_prf_input_callback_arg(SSL_CTX* ctx, void* arg) {
	return SSL_CTX_ctrl(ctx,SSL_CTRL_SET_TLSEXT_OPAQUE_PRF_INPUT_CB_ARG, 0, arg);
}

auto SSL_CTX_set_tlsext_ticket_key_cb()(ssl, ExternC!(void function()) cb) {
	return SSL_CTX_callback_ctrl(ssl,SSL_CTRL_SET_TLSEXT_TICKET_KEY_CB,cb);
}

}

/* PSK ciphersuites from 4279 */
enum TLS1_CK_PSK_WITH_RC4_128_SHA = 0x0300008A;
enum TLS1_CK_PSK_WITH_3DES_EDE_CBC_SHA = 0x0300008B;
enum TLS1_CK_PSK_WITH_AES_128_CBC_SHA = 0x0300008C;
enum TLS1_CK_PSK_WITH_AES_256_CBC_SHA = 0x0300008D;

/* Additional TLS ciphersuites from expired Internet Draft
 * draft-ietf-tls-56-bit-ciphersuites-01.txt
 * (available if TLS1_ALLOW_EXPERIMENTAL_CIPHERSUITES is defined, see
 * s3_lib.c).  We actually treat them like SSL 3.0 ciphers, which we probably
 * shouldn't.  Note that the first two are actually not in the IDs. */
enum TLS1_CK_RSA_EXPORT1024_WITH_RC4_56_MD5 = 0x03000060; /* not in ID */
enum TLS1_CK_RSA_EXPORT1024_WITH_RC2_CBC_56_MD5 = 0x03000061; /* not in ID */
enum TLS1_CK_RSA_EXPORT1024_WITH_DES_CBC_SHA = 0x03000062;
enum TLS1_CK_DHE_DSS_EXPORT1024_WITH_DES_CBC_SHA = 0x03000063;
enum TLS1_CK_RSA_EXPORT1024_WITH_RC4_56_SHA = 0x03000064;
enum TLS1_CK_DHE_DSS_EXPORT1024_WITH_RC4_56_SHA = 0x03000065;
enum TLS1_CK_DHE_DSS_WITH_RC4_128_SHA = 0x03000066;

/* AES ciphersuites from RFC3268 */

enum TLS1_CK_RSA_WITH_AES_128_SHA = 0x0300002F;
enum TLS1_CK_DH_DSS_WITH_AES_128_SHA = 0x03000030;
enum TLS1_CK_DH_RSA_WITH_AES_128_SHA = 0x03000031;
enum TLS1_CK_DHE_DSS_WITH_AES_128_SHA = 0x03000032;
enum TLS1_CK_DHE_RSA_WITH_AES_128_SHA = 0x03000033;
enum TLS1_CK_ADH_WITH_AES_128_SHA = 0x03000034;

enum TLS1_CK_RSA_WITH_AES_256_SHA = 0x03000035;
enum TLS1_CK_DH_DSS_WITH_AES_256_SHA = 0x03000036;
enum TLS1_CK_DH_RSA_WITH_AES_256_SHA = 0x03000037;
enum TLS1_CK_DHE_DSS_WITH_AES_256_SHA = 0x03000038;
enum TLS1_CK_DHE_RSA_WITH_AES_256_SHA = 0x03000039;
enum TLS1_CK_ADH_WITH_AES_256_SHA = 0x0300003A;

/* Camellia ciphersuites from RFC4132 */
enum TLS1_CK_RSA_WITH_CAMELLIA_128_CBC_SHA = 0x03000041;
enum TLS1_CK_DH_DSS_WITH_CAMELLIA_128_CBC_SHA = 0x03000042;
enum TLS1_CK_DH_RSA_WITH_CAMELLIA_128_CBC_SHA = 0x03000043;
enum TLS1_CK_DHE_DSS_WITH_CAMELLIA_128_CBC_SHA = 0x03000044;
enum TLS1_CK_DHE_RSA_WITH_CAMELLIA_128_CBC_SHA = 0x03000045;
enum TLS1_CK_ADH_WITH_CAMELLIA_128_CBC_SHA = 0x03000046;

enum TLS1_CK_RSA_WITH_CAMELLIA_256_CBC_SHA = 0x03000084;
enum TLS1_CK_DH_DSS_WITH_CAMELLIA_256_CBC_SHA = 0x03000085;
enum TLS1_CK_DH_RSA_WITH_CAMELLIA_256_CBC_SHA = 0x03000086;
enum TLS1_CK_DHE_DSS_WITH_CAMELLIA_256_CBC_SHA = 0x03000087;
enum TLS1_CK_DHE_RSA_WITH_CAMELLIA_256_CBC_SHA = 0x03000088;
enum TLS1_CK_ADH_WITH_CAMELLIA_256_CBC_SHA = 0x03000089;

/* SEED ciphersuites from RFC4162 */
enum TLS1_CK_RSA_WITH_SEED_SHA = 0x03000096;
enum TLS1_CK_DH_DSS_WITH_SEED_SHA = 0x03000097;
enum TLS1_CK_DH_RSA_WITH_SEED_SHA = 0x03000098;
enum TLS1_CK_DHE_DSS_WITH_SEED_SHA = 0x03000099;
enum TLS1_CK_DHE_RSA_WITH_SEED_SHA = 0x0300009A;
enum TLS1_CK_ADH_WITH_SEED_SHA = 0x0300009B;

/* ECC ciphersuites from draft-ietf-tls-ecc-12.txt with changes soon to be in draft 13 */
enum TLS1_CK_ECDH_ECDSA_WITH_NULL_SHA = 0x0300C001;
enum TLS1_CK_ECDH_ECDSA_WITH_RC4_128_SHA = 0x0300C002;
enum TLS1_CK_ECDH_ECDSA_WITH_DES_192_CBC3_SHA = 0x0300C003;
enum TLS1_CK_ECDH_ECDSA_WITH_AES_128_CBC_SHA = 0x0300C004;
enum TLS1_CK_ECDH_ECDSA_WITH_AES_256_CBC_SHA = 0x0300C005;

enum TLS1_CK_ECDHE_ECDSA_WITH_NULL_SHA = 0x0300C006;
enum TLS1_CK_ECDHE_ECDSA_WITH_RC4_128_SHA = 0x0300C007;
enum TLS1_CK_ECDHE_ECDSA_WITH_DES_192_CBC3_SHA = 0x0300C008;
enum TLS1_CK_ECDHE_ECDSA_WITH_AES_128_CBC_SHA = 0x0300C009;
enum TLS1_CK_ECDHE_ECDSA_WITH_AES_256_CBC_SHA = 0x0300C00A;

enum TLS1_CK_ECDH_RSA_WITH_NULL_SHA = 0x0300C00B;
enum TLS1_CK_ECDH_RSA_WITH_RC4_128_SHA = 0x0300C00C;
enum TLS1_CK_ECDH_RSA_WITH_DES_192_CBC3_SHA = 0x0300C00D;
enum TLS1_CK_ECDH_RSA_WITH_AES_128_CBC_SHA = 0x0300C00E;
enum TLS1_CK_ECDH_RSA_WITH_AES_256_CBC_SHA = 0x0300C00F;

enum TLS1_CK_ECDHE_RSA_WITH_NULL_SHA = 0x0300C010;
enum TLS1_CK_ECDHE_RSA_WITH_RC4_128_SHA = 0x0300C011;
enum TLS1_CK_ECDHE_RSA_WITH_DES_192_CBC3_SHA = 0x0300C012;
enum TLS1_CK_ECDHE_RSA_WITH_AES_128_CBC_SHA = 0x0300C013;
enum TLS1_CK_ECDHE_RSA_WITH_AES_256_CBC_SHA = 0x0300C014;

enum TLS1_CK_ECDH_anon_WITH_NULL_SHA = 0x0300C015;
enum TLS1_CK_ECDH_anon_WITH_RC4_128_SHA = 0x0300C016;
enum TLS1_CK_ECDH_anon_WITH_DES_192_CBC3_SHA = 0x0300C017;
enum TLS1_CK_ECDH_anon_WITH_AES_128_CBC_SHA = 0x0300C018;
enum TLS1_CK_ECDH_anon_WITH_AES_256_CBC_SHA = 0x0300C019;

/* XXX
 * Inconsistency alert:
 * The OpenSSL names of ciphers with ephemeral DH here include the string
 * "DHE", while elsewhere it has always been "EDH".
 * (The alias for the list of all such ciphers also is "EDH".)
 * The specifications speak of "EDH"; maybe we should allow both forms
 * for everything. */
enum TLS1_TXT_RSA_EXPORT1024_WITH_RC4_56_MD5 = "EXP1024-RC4-MD5";
enum TLS1_TXT_RSA_EXPORT1024_WITH_RC2_CBC_56_MD5 = "EXP1024-RC2-CBC-MD5";
enum TLS1_TXT_RSA_EXPORT1024_WITH_DES_CBC_SHA = "EXP1024-DES-CBC-SHA";
enum TLS1_TXT_DHE_DSS_EXPORT1024_WITH_DES_CBC_SHA = "EXP1024-DHE-DSS-DES-CBC-SHA";
enum TLS1_TXT_RSA_EXPORT1024_WITH_RC4_56_SHA = "EXP1024-RC4-SHA";
enum TLS1_TXT_DHE_DSS_EXPORT1024_WITH_RC4_56_SHA = "EXP1024-DHE-DSS-RC4-SHA";
enum TLS1_TXT_DHE_DSS_WITH_RC4_128_SHA = "DHE-DSS-RC4-SHA";

/* AES ciphersuites from RFC3268 */
enum TLS1_TXT_RSA_WITH_AES_128_SHA = "AES128-SHA";
enum TLS1_TXT_DH_DSS_WITH_AES_128_SHA = "DH-DSS-AES128-SHA";
enum TLS1_TXT_DH_RSA_WITH_AES_128_SHA = "DH-RSA-AES128-SHA";
enum TLS1_TXT_DHE_DSS_WITH_AES_128_SHA = "DHE-DSS-AES128-SHA";
enum TLS1_TXT_DHE_RSA_WITH_AES_128_SHA = "DHE-RSA-AES128-SHA";
enum TLS1_TXT_ADH_WITH_AES_128_SHA = "ADH-AES128-SHA";

enum TLS1_TXT_RSA_WITH_AES_256_SHA = "AES256-SHA";
enum TLS1_TXT_DH_DSS_WITH_AES_256_SHA = "DH-DSS-AES256-SHA";
enum TLS1_TXT_DH_RSA_WITH_AES_256_SHA = "DH-RSA-AES256-SHA";
enum TLS1_TXT_DHE_DSS_WITH_AES_256_SHA = "DHE-DSS-AES256-SHA";
enum TLS1_TXT_DHE_RSA_WITH_AES_256_SHA = "DHE-RSA-AES256-SHA";
enum TLS1_TXT_ADH_WITH_AES_256_SHA = "ADH-AES256-SHA";

/* ECC ciphersuites from draft-ietf-tls-ecc-01.txt (Mar 15, 2001) */
enum TLS1_TXT_ECDH_ECDSA_WITH_NULL_SHA = "ECDH-ECDSA-NULL-SHA";
enum TLS1_TXT_ECDH_ECDSA_WITH_RC4_128_SHA = "ECDH-ECDSA-RC4-SHA";
enum TLS1_TXT_ECDH_ECDSA_WITH_DES_192_CBC3_SHA = "ECDH-ECDSA-DES-CBC3-SHA";
enum TLS1_TXT_ECDH_ECDSA_WITH_AES_128_CBC_SHA = "ECDH-ECDSA-AES128-SHA";
enum TLS1_TXT_ECDH_ECDSA_WITH_AES_256_CBC_SHA = "ECDH-ECDSA-AES256-SHA";

enum TLS1_TXT_ECDHE_ECDSA_WITH_NULL_SHA = "ECDHE-ECDSA-NULL-SHA";
enum TLS1_TXT_ECDHE_ECDSA_WITH_RC4_128_SHA = "ECDHE-ECDSA-RC4-SHA";
enum TLS1_TXT_ECDHE_ECDSA_WITH_DES_192_CBC3_SHA = "ECDHE-ECDSA-DES-CBC3-SHA";
enum TLS1_TXT_ECDHE_ECDSA_WITH_AES_128_CBC_SHA = "ECDHE-ECDSA-AES128-SHA";
enum TLS1_TXT_ECDHE_ECDSA_WITH_AES_256_CBC_SHA = "ECDHE-ECDSA-AES256-SHA";

enum TLS1_TXT_ECDH_RSA_WITH_NULL_SHA = "ECDH-RSA-NULL-SHA";
enum TLS1_TXT_ECDH_RSA_WITH_RC4_128_SHA = "ECDH-RSA-RC4-SHA";
enum TLS1_TXT_ECDH_RSA_WITH_DES_192_CBC3_SHA = "ECDH-RSA-DES-CBC3-SHA";
enum TLS1_TXT_ECDH_RSA_WITH_AES_128_CBC_SHA = "ECDH-RSA-AES128-SHA";
enum TLS1_TXT_ECDH_RSA_WITH_AES_256_CBC_SHA = "ECDH-RSA-AES256-SHA";

enum TLS1_TXT_ECDHE_RSA_WITH_NULL_SHA = "ECDHE-RSA-NULL-SHA";
enum TLS1_TXT_ECDHE_RSA_WITH_RC4_128_SHA = "ECDHE-RSA-RC4-SHA";
enum TLS1_TXT_ECDHE_RSA_WITH_DES_192_CBC3_SHA = "ECDHE-RSA-DES-CBC3-SHA";
enum TLS1_TXT_ECDHE_RSA_WITH_AES_128_CBC_SHA = "ECDHE-RSA-AES128-SHA";
enum TLS1_TXT_ECDHE_RSA_WITH_AES_256_CBC_SHA = "ECDHE-RSA-AES256-SHA";

enum TLS1_TXT_ECDH_anon_WITH_NULL_SHA = "AECDH-NULL-SHA";
enum TLS1_TXT_ECDH_anon_WITH_RC4_128_SHA = "AECDH-RC4-SHA";
enum TLS1_TXT_ECDH_anon_WITH_DES_192_CBC3_SHA = "AECDH-DES-CBC3-SHA";
enum TLS1_TXT_ECDH_anon_WITH_AES_128_CBC_SHA = "AECDH-AES128-SHA";
enum TLS1_TXT_ECDH_anon_WITH_AES_256_CBC_SHA = "AECDH-AES256-SHA";

/* PSK ciphersuites from RFC 4279 */
enum TLS1_TXT_PSK_WITH_RC4_128_SHA = "PSK-RC4-SHA";
enum TLS1_TXT_PSK_WITH_3DES_EDE_CBC_SHA = "PSK-3DES-EDE-CBC-SHA";
enum TLS1_TXT_PSK_WITH_AES_128_CBC_SHA = "PSK-AES128-CBC-SHA";
enum TLS1_TXT_PSK_WITH_AES_256_CBC_SHA = "PSK-AES256-CBC-SHA";

/* Camellia ciphersuites from RFC4132 */
enum TLS1_TXT_RSA_WITH_CAMELLIA_128_CBC_SHA = "CAMELLIA128-SHA";
enum TLS1_TXT_DH_DSS_WITH_CAMELLIA_128_CBC_SHA = "DH-DSS-CAMELLIA128-SHA";
enum TLS1_TXT_DH_RSA_WITH_CAMELLIA_128_CBC_SHA = "DH-RSA-CAMELLIA128-SHA";
enum TLS1_TXT_DHE_DSS_WITH_CAMELLIA_128_CBC_SHA = "DHE-DSS-CAMELLIA128-SHA";
enum TLS1_TXT_DHE_RSA_WITH_CAMELLIA_128_CBC_SHA = "DHE-RSA-CAMELLIA128-SHA";
enum TLS1_TXT_ADH_WITH_CAMELLIA_128_CBC_SHA = "ADH-CAMELLIA128-SHA";

enum TLS1_TXT_RSA_WITH_CAMELLIA_256_CBC_SHA = "CAMELLIA256-SHA";
enum TLS1_TXT_DH_DSS_WITH_CAMELLIA_256_CBC_SHA = "DH-DSS-CAMELLIA256-SHA";
enum TLS1_TXT_DH_RSA_WITH_CAMELLIA_256_CBC_SHA = "DH-RSA-CAMELLIA256-SHA";
enum TLS1_TXT_DHE_DSS_WITH_CAMELLIA_256_CBC_SHA = "DHE-DSS-CAMELLIA256-SHA";
enum TLS1_TXT_DHE_RSA_WITH_CAMELLIA_256_CBC_SHA = "DHE-RSA-CAMELLIA256-SHA";
enum TLS1_TXT_ADH_WITH_CAMELLIA_256_CBC_SHA = "ADH-CAMELLIA256-SHA";

/* SEED ciphersuites from RFC4162 */
enum TLS1_TXT_RSA_WITH_SEED_SHA = "SEED-SHA";
enum TLS1_TXT_DH_DSS_WITH_SEED_SHA = "DH-DSS-SEED-SHA";
enum TLS1_TXT_DH_RSA_WITH_SEED_SHA = "DH-RSA-SEED-SHA";
enum TLS1_TXT_DHE_DSS_WITH_SEED_SHA = "DHE-DSS-SEED-SHA";
enum TLS1_TXT_DHE_RSA_WITH_SEED_SHA = "DHE-RSA-SEED-SHA";
enum TLS1_TXT_ADH_WITH_SEED_SHA = "ADH-SEED-SHA";


enum TLS_CT_RSA_SIGN = 1;
enum TLS_CT_DSS_SIGN = 2;
enum TLS_CT_RSA_FIXED_DH = 3;
enum TLS_CT_DSS_FIXED_DH = 4;
enum TLS_CT_ECDSA_SIGN = 64;
enum TLS_CT_RSA_FIXED_ECDH = 65;
enum TLS_CT_ECDSA_FIXED_ECDH = 66;
enum TLS_CT_GOST94_SIGN = 21;
enum TLS_CT_GOST01_SIGN = 22;
/* when correcting this number, correct also SSL3_CT_NUMBER in ssl3.h (see
 * comment there) */
enum TLS_CT_NUMBER = 9;

enum TLS1_FINISH_MAC_LENGTH = 12;

enum TLS_MD_MAX_CONST_SIZE = 20;
enum TLS_MD_CLIENT_FINISH_CONST = "client finished";
enum TLS_MD_CLIENT_FINISH_CONST_SIZE = 15;
enum TLS_MD_SERVER_FINISH_CONST = "server finished";
enum TLS_MD_SERVER_FINISH_CONST_SIZE = 15;
enum TLS_MD_SERVER_WRITE_KEY_CONST = "server write key";
enum TLS_MD_SERVER_WRITE_KEY_CONST_SIZE = 16;
enum TLS_MD_KEY_EXPANSION_CONST = "key expansion";
enum TLS_MD_KEY_EXPANSION_CONST_SIZE = 13;
enum TLS_MD_CLIENT_WRITE_KEY_CONST = "client write key";
enum TLS_MD_CLIENT_WRITE_KEY_CONST_SIZE = 16;
// Oversight in original headers: Already defined above.
// enum TLS_MD_SERVER_WRITE_KEY_CONST = "server write key";
// enum TLS_MD_SERVER_WRITE_KEY_CONST_SIZE = 16;
enum TLS_MD_IV_BLOCK_CONST = "IV block";
enum TLS_MD_IV_BLOCK_CONST_SIZE = 8;
enum TLS_MD_MASTER_SECRET_CONST = "master secret";
enum TLS_MD_MASTER_SECRET_CONST_SIZE = 13;

/+#ifdef CHARSET_EBCDIC
#undef TLS_MD_CLIENT_FINISH_CONST
enum TLS_MD_CLIENT_FINISH_CONST = "\x63\x6c\x69\x65\x6e\x74\x20\x66\x69\x6e\x69\x73\x68\x65\x64";  /*client finished*/
#undef TLS_MD_SERVER_FINISH_CONST
enum TLS_MD_SERVER_FINISH_CONST = "\x73\x65\x72\x76\x65\x72\x20\x66\x69\x6e\x69\x73\x68\x65\x64";  /*server finished*/
#undef TLS_MD_SERVER_WRITE_KEY_CONST
enum TLS_MD_SERVER_WRITE_KEY_CONST = "\x73\x65\x72\x76\x65\x72\x20\x77\x72\x69\x74\x65\x20\x6b\x65\x79";  /*server write key*/
#undef TLS_MD_KEY_EXPANSION_CONST
enum TLS_MD_KEY_EXPANSION_CONST = "\x6b\x65\x79\x20\x65\x78\x70\x61\x6e\x73\x69\x6f\x6e";  /*key expansion*/
#undef TLS_MD_CLIENT_WRITE_KEY_CONST
enum TLS_MD_CLIENT_WRITE_KEY_CONST = "\x63\x6c\x69\x65\x6e\x74\x20\x77\x72\x69\x74\x65\x20\x6b\x65\x79";  /*client write key*/
#undef TLS_MD_SERVER_WRITE_KEY_CONST
enum TLS_MD_SERVER_WRITE_KEY_CONST = "\x73\x65\x72\x76\x65\x72\x20\x77\x72\x69\x74\x65\x20\x6b\x65\x79";  /*server write key*/
#undef TLS_MD_IV_BLOCK_CONST
enum TLS_MD_IV_BLOCK_CONST = "\x49\x56\x20\x62\x6c\x6f\x63\x6b";  /*IV block*/
#undef TLS_MD_MASTER_SECRET_CONST
enum TLS_MD_MASTER_SECRET_CONST = "\x6d\x61\x73\x74\x65\x72\x20\x73\x65\x63\x72\x65\x74";  /*master secret*/
#endif+/

/* TLS Session Ticket extension struct */
struct tls_session_ticket_ext_st
	{
	ushort length;
	void* data;
	};
