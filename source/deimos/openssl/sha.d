/* crypto/sha/sha.h */
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

module deimos.openssl.sha;

import deimos.openssl._d_util;

public import deimos.openssl.e_os2;
import core.stdc.config;

extern (C):
nothrow:

version (OPENSSL_NO_SHA) {
	static assert(false, "SHA is disabled.");
}

version (OPENSSL_NO_SHA0) {
	version (OPENSSL_NO_SHA1) {
		static assert(false, "SHA is disabled.");
	}
}

version (OPENSSL_FIPS) {
	alias size_t FIPS_SHA_SIZE_T;
}

/*
 * !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 * ! SHA_LONG has to be at least 32 bits wide. If it's wider, then !
 * ! SHA_LONG_LOG2 has to be defined along.                        !
 * !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 */

//#if defined(__LP32__)
//alias c_ulong SHA_LONG;
//#elif defined(OPENSSL_SYS_CRAY) || defined(__ILP64__)
//alias c_ulong SHA_LONG;
//enum SHA_LONG_LOG2 = 3;
//#else
//alias uint SHA_LONG;
//#endif
alias uint SHA_LONG;

enum SHA_LBLOCK = 16;
enum SHA_CBLOCK = (SHA_LBLOCK*4);	/* SHA treats input data as a
					 * contiguous array of 32 bit
					 * wide big-endian values. */
enum SHA_LAST_BLOCK = (SHA_CBLOCK-8);
enum SHA_DIGEST_LENGTH = 20;

struct SHAstate_st
	{
	SHA_LONG h0,h1,h2,h3,h4;
	SHA_LONG Nl,Nh;
	SHA_LONG data[SHA_LBLOCK];
	uint num;
	}
alias SHAstate_st  SHA_CTX;

version(OPENSSL_NO_SHA0) {} else {
int SHA_Init(SHA_CTX* c);
int SHA_Update(SHA_CTX* c, const(void)* data, size_t len);
int SHA_Final(ubyte* md, SHA_CTX* c);
ubyte* SHA(const(ubyte)* d, size_t n, ubyte* md);
void SHA_Transform(SHA_CTX* c, const(ubyte)* data);
}
version(OPENSSL_NO_SHA1) {} else {
int SHA1_Init(SHA_CTX* c);
int SHA1_Update(SHA_CTX* c, const(void)* data, size_t len);
int SHA1_Final(ubyte* md, SHA_CTX* c);
ubyte* SHA1(const(ubyte)* d, size_t n, ubyte* md);
void SHA1_Transform(SHA_CTX* c, const(ubyte)* data);
}

enum SHA256_CBLOCK = (SHA_LBLOCK*4);	/* SHA-256 treats input data as a
					 * contiguous array of 32 bit
					 * wide big-endian values. */
enum SHA224_DIGEST_LENGTH = 28;
enum SHA256_DIGEST_LENGTH = 32;

struct SHA256state_st {
	SHA_LONG h[8];
	SHA_LONG Nl,Nh;
	SHA_LONG data[SHA_LBLOCK];
	uint num,md_len;
	}
alias SHA256state_st SHA256_CTX;

version(OPENSSL_NO_SHA256) {} else {
int SHA224_Init(SHA256_CTX* c);
int SHA224_Update(SHA256_CTX* c, const(void)* data, size_t len);
int SHA224_Final(ubyte* md, SHA256_CTX* c);
ubyte* SHA224(const(ubyte)* d, size_t n,ubyte* md);
int SHA256_Init(SHA256_CTX* c);
int SHA256_Update(SHA256_CTX* c, const(void)* data, size_t len);
int SHA256_Final(ubyte* md, SHA256_CTX* c);
ubyte* SHA256(const(ubyte)* d, size_t n,ubyte* md);
void SHA256_Transform(SHA256_CTX* c, const(ubyte)* data);
}

enum SHA384_DIGEST_LENGTH = 48;
enum SHA512_DIGEST_LENGTH = 64;

version (OPENSSL_NO_SHA512) {} else {
/*
 * Unlike 32-bit digest algorithms, SHA-512* relies* on SHA_LONG64
 * being exactly 64-bit wide. See Implementation Notes in sha512.c
 * for further details.
 */
enum SHA512_CBLOCK = (SHA_LBLOCK*8);	/* SHA-512 treats input data as a
					 * contiguous array of 64 bit
					 * wide big-endian values. */
//#if (defined(_WIN32) || defined(_WIN64)) && !defined(__MINGW32__)
//alias unsigned SHA_LONG64; __int64
//#define U64(C)     C##UI64
//#elif defined(__arch64__)
//alias c_ulong SHA_LONG64;
//#define U64(C)     C##UL
//#else
//alias c_ulong SHA_LONG64; c_long
//#define U64(C)     C##ULL
//#endif
alias ulong SHA_LONG64;

struct SHA512state_st
	{
	SHA_LONG64 h[8];
	SHA_LONG64 Nl,Nh;
	union u_ {
		SHA_LONG64	d[SHA_LBLOCK];
		ubyte	p[SHA512_CBLOCK];
	}
	u_ u;
	uint num,md_len;
	}
alias SHA512state_st SHA512_CTX;
}

version(OPENSSL_NO_SHA512) {} else {
int SHA384_Init(SHA512_CTX* c);
int SHA384_Update(SHA512_CTX* c, const(void)* data, size_t len);
int SHA384_Final(ubyte* md, SHA512_CTX* c);
ubyte* SHA384(const(ubyte)* d, size_t n,ubyte* md);
int SHA512_Init(SHA512_CTX* c);
int SHA512_Update(SHA512_CTX* c, const(void)* data, size_t len);
int SHA512_Final(ubyte* md, SHA512_CTX* c);
ubyte* SHA512(const(ubyte)* d, size_t n,ubyte* md);
void SHA512_Transform(SHA512_CTX* c, const(ubyte)* data);
}
