/* ====================================================================
 * Copyright (c) 1998-2001 The OpenSSL Project.  All rights reserved.
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

module deimos.openssl.ossl_typ;

import deimos.openssl._d_util;

public import deimos.openssl.e_os2;

version (NO_ASN1_TYPEDEFS) {
alias ASN1_STRING ASN1_INTEGER;
alias ASN1_STRING ASN1_ENUMERATED;
alias ASN1_STRING ASN1_BIT_STRING;
alias ASN1_STRING ASN1_OCTET_STRING;
alias ASN1_STRING ASN1_PRINTABLESTRING;
alias ASN1_STRING ASN1_T61STRING;
alias ASN1_STRING ASN1_IA5STRING;
alias ASN1_STRING ASN1_UTCTIME;
alias ASN1_STRING ASN1_GENERALIZEDTIME;
alias ASN1_STRING ASN1_TIME;
alias ASN1_STRING ASN1_GENERALSTRING;
alias ASN1_STRING ASN1_UNIVERSALSTRING;
alias ASN1_STRING ASN1_BMPSTRING;
alias ASN1_STRING ASN1_VISIBLESTRING;
alias ASN1_STRING ASN1_UTF8STRING;
alias int ASN1_BOOLEAN;
alias int ASN1_NULL;
} else {
import deimos.openssl.asn1;
alias asn1_string_st ASN1_INTEGER;
alias asn1_string_st ASN1_ENUMERATED;
alias asn1_string_st ASN1_BIT_STRING;
alias asn1_string_st ASN1_OCTET_STRING;
alias asn1_string_st ASN1_PRINTABLESTRING;
alias asn1_string_st ASN1_T61STRING;
alias asn1_string_st ASN1_IA5STRING;
alias asn1_string_st ASN1_GENERALSTRING;
alias asn1_string_st ASN1_UNIVERSALSTRING;
alias asn1_string_st ASN1_BMPSTRING;
alias asn1_string_st ASN1_UTCTIME;
alias asn1_string_st ASN1_TIME;
alias asn1_string_st ASN1_GENERALIZEDTIME;
alias asn1_string_st ASN1_VISIBLESTRING;
alias asn1_string_st ASN1_UTF8STRING;
alias int ASN1_BOOLEAN;
alias int ASN1_NULL;
}

struct asn1_pctx_st;
alias asn1_pctx_st ASN1_PCTX;

//#ifdef OPENSSL_SYS_WIN32
//#undef X509_NAME
//#undef X509_EXTENSIONS
//#undef X509_CERT_PAIR
//#undef PKCS7_ISSUER_AND_SERIAL
//#undef OCSP_REQUEST
//#undef OCSP_RESPONSE
//#endif

//#ifdef BIGNUM
//#undef BIGNUM
//#endif
import deimos.openssl.bn;
alias bignum_st BIGNUM;
struct bignum_ctx;
alias bignum_ctx BN_CTX;
struct bn_blinding_st;
alias bn_blinding_st BN_BLINDING;
alias bn_mont_ctx_st BN_MONT_CTX;
alias bn_recp_ctx_st BN_RECP_CTX;
alias bn_gencb_st BN_GENCB;

import deimos.openssl.buffer;
alias buf_mem_st BUF_MEM;

import deimos.openssl.evp;
alias evp_cipher_st EVP_CIPHER;
alias evp_cipher_ctx_st EVP_CIPHER_CTX;
alias env_md_st EVP_MD;
alias env_md_ctx_st EVP_MD_CTX;
alias evp_pkey_st EVP_PKEY;

struct evp_pkey_asn1_method_st;
alias evp_pkey_asn1_method_st EVP_PKEY_ASN1_METHOD;
struct evp_pkey_method_st;
alias evp_pkey_method_st EVP_PKEY_METHOD;
struct evp_pkey_ctx_st;
alias evp_pkey_ctx_st EVP_PKEY_CTX;

import deimos.openssl.dh;
/*struct dh_st;*/
alias dh_st DH;
/*struct dh_method;*/
alias dh_method DH_METHOD;

import deimos.openssl.dsa;
/*struct dsa_st;*/
alias dsa_st DSA;
/*struct dsa_method;*/
alias dsa_method DSA_METHOD;

import deimos.openssl.rsa;
/*struct rsa_st;*/
alias rsa_st RSA;
/*struct rsa_meth_st;*/
alias rsa_meth_st RSA_METHOD;

import deimos.openssl.rand;
alias rand_meth_st RAND_METHOD;

struct ecdh_method;
alias ecdh_method ECDH_METHOD;
struct ecdsa_method;
alias ecdsa_method ECDSA_METHOD;

import deimos.openssl.x509;
import deimos.openssl.x509_vfy;
alias x509_st X509;
alias X509_algor_st X509_ALGOR;
alias X509_crl_st X509_CRL;
struct x509_crl_method_st;
alias x509_crl_method_st X509_CRL_METHOD;
alias x509_revoked_st X509_REVOKED;
alias X509_name_st X509_NAME;
alias X509_pubkey_st X509_PUBKEY;
alias x509_store_st X509_STORE;
/*struct x509_store_ctx_st;*/
alias x509_store_ctx_st X509_STORE_CTX;
alias pkcs8_priv_key_info_st PKCS8_PRIV_KEY_INFO;

import deimos.openssl.x509v3;
alias v3_ext_ctx X509V3_CTX;
import deimos.openssl.conf;
alias conf_st CONF;

struct store_st;
alias store_st STORE;
struct store_method_st;
alias store_method_st STORE_METHOD;

struct ui_st;
alias ui_st UI;
struct ui_method_st;
alias ui_method_st UI_METHOD;

struct st_ERR_FNS;
alias st_ERR_FNS ERR_FNS;

struct engine_st;
alias engine_st ENGINE;
import deimos.openssl.ssl;
alias ssl_st SSL;
alias ssl_ctx_st SSL_CTX;

struct X509_POLICY_NODE_st;
alias X509_POLICY_NODE_st X509_POLICY_NODE;
struct X509_POLICY_LEVEL_st;
alias X509_POLICY_LEVEL_st X509_POLICY_LEVEL;
struct X509_POLICY_TREE_st;
alias X509_POLICY_TREE_st X509_POLICY_TREE;
struct X509_POLICY_CACHE_st;
alias X509_POLICY_CACHE_st X509_POLICY_CACHE;

alias AUTHORITY_KEYID_st AUTHORITY_KEYID;
alias DIST_POINT_st DIST_POINT;
alias ISSUING_DIST_POINT_st ISSUING_DIST_POINT;
alias NAME_CONSTRAINTS_st NAME_CONSTRAINTS;

  /* If placed in pkcs12.h, we end up with a circular depency with pkcs7.h */
mixin template DECLARE_PKCS12_STACK_OF (type) { /* Nothing */ }
//#define IMPLEMENT_PKCS12_STACK_OF!(type) /* Nothing */

import deimos.openssl.crypto;
alias crypto_ex_data_st CRYPTO_EX_DATA;
/* Callback types for crypto.h */
alias typeof(*(ExternC!(int function(void* parent, void* ptr, CRYPTO_EX_DATA* ad,
					int idx, c_long argl, void* argp))).init) CRYPTO_EX_new;
alias typeof(*(ExternC!(void function(void* parent, void* ptr, CRYPTO_EX_DATA* ad,
					int idx, c_long argl, void* argp))).init) CRYPTO_EX_free;
alias typeof(*(ExternC!(int function(CRYPTO_EX_DATA* to, CRYPTO_EX_DATA* from, void* from_d,
					int idx, c_long argl, void* argp))).init) CRYPTO_EX_dup;

import deimos.openssl.ocsp;
struct ocsp_req_ctx_st;
alias ocsp_req_ctx_st OCSP_REQ_CTX;
/*struct ocsp_response_st;*/
alias ocsp_response_st OCSP_RESPONSE;
/*struct ocsp_responder_id_st;*/
alias ocsp_responder_id_st OCSP_RESPID;
