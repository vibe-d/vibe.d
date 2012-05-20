/* crypto/err/err.h */
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

module deimos.openssl.err;

import deimos.openssl._d_util;

public import deimos.openssl.e_os2;

version(OPENSSL_NO_FP_API) {} else {
import core.stdc.stdio;
import core.stdc.stdlib;
}

public import deimos.openssl.ossl_typ;
version(OPENSSL_NO_BIO) {} else {
public import deimos.openssl.bio;
}
version(OPENSSL_NO_LHASH) {} else {
public import deimos.openssl.lhash;
}

extern (C):
nothrow:

// #ifndef OPENSSL_NO_ERR
// #define ERR_PUT_error(a,b,c,d,e)	ERR_put_error(a,b,c,d,e)
// #else
// #define ERR_PUT_error(a,b,c,d,e)	ERR_put_error(a,b,c,NULL,0)
// #endif
version (OPENSSL_NO_ERR) {
	void ERR_PUT_error()(int a, int b,int c,const(char)* d,int e) {
		ERR_put_error(a,b,c,null,0);
	}
} else {
	alias ERR_put_error ERR_PUT_error;
}

// #include <errno.h>

enum ERR_TXT_MALLOCED = 0x01;
enum ERR_TXT_STRING = 0x02;

enum ERR_FLAG_MARK = 0x01;

enum ERR_NUM_ERRORS = 16;
struct err_state_st {
	CRYPTO_THREADID tid;
	int err_flags[ERR_NUM_ERRORS];
	c_ulong err_buffer[ERR_NUM_ERRORS];
	char* err_data[ERR_NUM_ERRORS];
	int err_data_flags[ERR_NUM_ERRORS];
	const(char)* err_file[ERR_NUM_ERRORS];
	int err_line[ERR_NUM_ERRORS];
	int top,bottom;
	}
alias err_state_st ERR_STATE;

/* library */
enum ERR_LIB_NONE = 1;
enum ERR_LIB_SYS = 2;
enum ERR_LIB_BN = 3;
enum ERR_LIB_RSA = 4;
enum ERR_LIB_DH = 5;
enum ERR_LIB_EVP = 6;
enum ERR_LIB_BUF = 7;
enum ERR_LIB_OBJ = 8;
enum ERR_LIB_PEM = 9;
enum ERR_LIB_DSA = 10;
enum ERR_LIB_X509 = 11;
/* enum ERR_LIB_METH = 12; */
enum ERR_LIB_ASN1 = 13;
enum ERR_LIB_CONF = 14;
enum ERR_LIB_CRYPTO = 15;
enum ERR_LIB_EC = 16;
enum ERR_LIB_SSL = 20;
/* enum ERR_LIB_SSL23 = 21; */
/* enum ERR_LIB_SSL2 = 22; */
/* enum ERR_LIB_SSL3 = 23; */
/* enum ERR_LIB_RSAREF = 30; */
/* enum ERR_LIB_PROXY = 31; */
enum ERR_LIB_BIO = 32;
enum ERR_LIB_PKCS7 = 33;
enum ERR_LIB_X509V3 = 34;
enum ERR_LIB_PKCS12 = 35;
enum ERR_LIB_RAND = 36;
enum ERR_LIB_DSO = 37;
enum ERR_LIB_ENGINE = 38;
enum ERR_LIB_OCSP = 39;
enum ERR_LIB_UI = 40;
enum ERR_LIB_COMP = 41;
enum ERR_LIB_ECDSA = 42;
enum ERR_LIB_ECDH = 43;
enum ERR_LIB_STORE = 44;
enum ERR_LIB_FIPS = 45;
enum ERR_LIB_CMS = 46;
enum ERR_LIB_TS = 47;
enum ERR_LIB_HMAC = 48;
enum ERR_LIB_JPAKE = 49;

enum ERR_LIB_USER = 128;

void SYSerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_SYS,f,r,file,line); }
void BNerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_BN,f,r,file,line); }
void RSAerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_RSA,f,r,file,line); }
void DHerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_DH,f,r,file,line); }
void EVPerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_EVP,f,r,file,line); }
void BUFerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_BUF,f,r,file,line); }
void OBJerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_OBJ,f,r,file,line); }
void PEMerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_PEM,f,r,file,line); }
void DSAerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_DSA,f,r,file,line); }
void X509err_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_X509,f,r,file,line); }
void ASN1err_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_ASN1,f,r,file,line); }
void CONFerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_CONF,f,r,file,line); }
void CRYPTOerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_CRYPTO,f,r,file,line); }
void ECerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_EC,f,r,file,line); }
void SSLerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_SSL,f,r,file,line); }
void BIOerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_BIO,f,r,file,line); }
void PKCS7err_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_PKCS7,f,r,file,line); }
void X509V3err_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_X509V3,f,r,file,line); }
void PKCS12err_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_PKCS12,f,r,file,line); }
void RANDerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_RAND,f,r,file,line); }
void DSOerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_DSO,f,r,file,line); }
void ENGINEerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_ENGINE,f,r,file,line); }
void OCSPerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_OCSP,f,r,file,line); }
void UIerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_UI,f,r,file,line); }
void COMPerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_COMP,f,r,file,line); }
void ECDSAerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_ECDSA,f,r,file,line); }
void ECDHerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_ECDH,f,r,file,line); }
void STOREerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_STORE,f,r,file,line); }
void FIPSerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_FIPS,f,r,file,line); }
void CMSerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_CMS,f,r,file,line); }
void TSerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_TS,f,r,file,line); }
void HMACerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_HMAC,f,r,file,line); }
void JPAKEerr_err(string file = __FILE__, size_t line = __LINE__)(int f, int r){ ERR_PUT_error(ERR_LIB_JPAKE,f,r,file,line); }

/* Borland C seems too stupid to be able to shift and do longs in
 * the pre-processor :-( */
auto ERR_PACK()(c_ulong l, c_ulong f, c_ulong r) {
	return ((((l)&0xffL)*0x1000000)|
					(((f)&0xfffL)*0x1000)|
					(((r)&0xfffL)));
}
auto ERR_GET_LIB()(c_ulong l) { return cast(int)(((l)>>24L)&0xffL); }
auto ERR_GET_FUNC()(c_ulong l) { return cast(int)(((l)>>12L)&0xfffL); }
auto ERR_GET_REASON()(c_ulong l) { return cast(int)((l)&0xfffL); }
auto ERR_FATAL_ERROR()(c_ulong l) { return cast(int)((l)&ERR_R_FATAL); }


/* OS functions */
enum SYS_F_FOPEN = 1;
enum SYS_F_CONNECT = 2;
enum SYS_F_GETSERVBYNAME = 3;
enum SYS_F_SOCKET = 4;
enum SYS_F_IOCTLSOCKET = 5;
enum SYS_F_BIND = 6;
enum SYS_F_LISTEN = 7;
enum SYS_F_ACCEPT = 8;
enum SYS_F_WSASTARTUP = 9; /* Winsock stuff */
enum SYS_F_OPENDIR = 10;
enum SYS_F_FREAD = 11;


/* reasons */
alias ERR_LIB_SYS ERR_R_SYS_LIB ; /* 2 */
alias ERR_LIB_BN ERR_R_BN_LIB ; /* 3 */
alias ERR_LIB_RSA ERR_R_RSA_LIB ; /* 4 */
alias ERR_LIB_DH ERR_R_DH_LIB ; /* 5 */
alias ERR_LIB_EVP ERR_R_EVP_LIB ; /* 6 */
alias ERR_LIB_BUF ERR_R_BUF_LIB ; /* 7 */
alias ERR_LIB_OBJ ERR_R_OBJ_LIB ; /* 8 */
alias ERR_LIB_PEM ERR_R_PEM_LIB ; /* 9 */
alias ERR_LIB_DSA ERR_R_DSA_LIB ; /* 10 */
alias ERR_LIB_X509 ERR_R_X509_LIB ; /* 11 */
alias ERR_LIB_ASN1 ERR_R_ASN1_LIB ; /* 13 */
alias ERR_LIB_CONF ERR_R_CONF_LIB ; /* 14 */
alias ERR_LIB_CRYPTO ERR_R_CRYPTO_LIB ; /* 15 */
alias ERR_LIB_EC ERR_R_EC_LIB ; /* 16 */
alias ERR_LIB_SSL ERR_R_SSL_LIB ; /* 20 */
alias ERR_LIB_BIO ERR_R_BIO_LIB ; /* 32 */
alias ERR_LIB_PKCS7 ERR_R_PKCS7_LIB ; /* 33 */
alias ERR_LIB_X509V3 ERR_R_X509V3_LIB ; /* 34 */
alias ERR_LIB_PKCS12 ERR_R_PKCS12_LIB ; /* 35 */
alias ERR_LIB_RAND ERR_R_RAND_LIB ; /* 36 */
alias ERR_LIB_DSO ERR_R_DSO_LIB ; /* 37 */
alias ERR_LIB_ENGINE ERR_R_ENGINE_LIB ; /* 38 */
alias ERR_LIB_OCSP ERR_R_OCSP_LIB ; /* 39 */
alias ERR_LIB_UI ERR_R_UI_LIB ; /* 40 */
alias ERR_LIB_COMP ERR_R_COMP_LIB ; /* 41 */
alias ERR_LIB_ECDSA ERR_R_ECDSA_LIB ; /* 42 */
alias ERR_LIB_ECDH ERR_R_ECDH_LIB ; /* 43 */
alias ERR_LIB_STORE ERR_R_STORE_LIB ; /* 44 */
alias ERR_LIB_TS ERR_R_TS_LIB ; /* 45 */

enum ERR_R_NESTED_ASN1_ERROR = 58;
enum ERR_R_BAD_ASN1_OBJECT_HEADER = 59;
enum ERR_R_BAD_GET_ASN1_OBJECT_CALL = 60;
enum ERR_R_EXPECTING_AN_ASN1_SEQUENCE = 61;
enum ERR_R_ASN1_LENGTH_MISMATCH = 62;
enum ERR_R_MISSING_ASN1_EOS = 63;

/* fatal error */
enum ERR_R_FATAL = 64;
enum ERR_R_MALLOC_FAILURE = (1|ERR_R_FATAL);
enum ERR_R_SHOULD_NOT_HAVE_BEEN_CALLED = (2|ERR_R_FATAL);
enum ERR_R_PASSED_NULL_PARAMETER = (3|ERR_R_FATAL);
enum ERR_R_INTERNAL_ERROR = (4|ERR_R_FATAL);
enum ERR_R_DISABLED = (5|ERR_R_FATAL);

/* 99 is the maximum possible ERR_R_... code, higher values
 * are reserved for the individual libraries */


struct ERR_string_data_st {
	c_ulong error;
	const(char)* string;
	}
alias ERR_string_data_st ERR_STRING_DATA;

void ERR_put_error(int lib, int func,int reason,const(char)* file,int line);
void ERR_set_error_data(char* data,int flags);

c_ulong ERR_get_error();
c_ulong ERR_get_error_line(const(char)** file,int* line);
c_ulong ERR_get_error_line_data(const(char)** file,int* line,
				      const(char)** data, int* flags);
c_ulong ERR_peek_error();
c_ulong ERR_peek_error_line(const(char)** file,int* line);
c_ulong ERR_peek_error_line_data(const(char)** file,int* line,
				       const(char)** data,int* flags);
c_ulong ERR_peek_last_error();
c_ulong ERR_peek_last_error_line(const(char)** file,int* line);
c_ulong ERR_peek_last_error_line_data(const(char)** file,int* line,
				       const(char)** data,int* flags);
void ERR_clear_error();
char* ERR_error_string(c_ulong e,char* buf);
void ERR_error_string_n(c_ulong e, char* buf, size_t len);
const(char)* ERR_lib_error_string(c_ulong e);
const(char)* ERR_func_error_string(c_ulong e);
const(char)* ERR_reason_error_string(c_ulong e);
void ERR_print_errors_cb(ExternC!(int function(const(char)* str, size_t len, void* u)) cb,
			 void* u);
version(OPENSSL_NO_FP_API) {} else {
void ERR_print_errors_fp(FILE* fp);
}
version(OPENSSL_NO_BIO) {} else {
void ERR_print_errors(BIO* bp);
void ERR_add_error_data(int num, ...);
}
void ERR_load_strings(int lib,ERR_STRING_DATA str[]);
void ERR_unload_strings(int lib,ERR_STRING_DATA str[]);
void ERR_load_ERR_strings();
void ERR_load_crypto_strings();
void ERR_free_strings();

void ERR_remove_thread_state(const(CRYPTO_THREADID)* tid);
version(OPENSSL_NO_DEPRECATED) {} else {
void ERR_remove_state(c_ulong pid); /* if zero we look it up */
}
ERR_STATE* ERR_get_state();

version(OPENSSL_NO_LHASH) {} else {
LHASH_OF!(ERR_STRING_DATA) *ERR_get_string_table();
LHASH_OF!(ERR_STATE) *ERR_get_err_state_table();
void ERR_release_err_state_table(LHASH_OF!(ERR_STATE) **hash);
}

int ERR_get_next_error_library();

int ERR_set_mark();
int ERR_pop_to_mark();

/* Already defined in ossl_typ.h */
/* typedef st_ERR_FNS ERR_FNS; */
/* An application can use this function and provide the return value to loaded
 * modules that should use the application's ERR state/functionality */
const(ERR_FNS)* ERR_get_implementation();
/* A loaded module should call this function prior to any ERR operations using
 * the application's "ERR_FNS". */
int ERR_set_implementation(const(ERR_FNS)* fns);
