/* crypto/camellia/camellia.h -*- mode:C; c-file-style: "eay" -*- */
/* ====================================================================
 * Copyright (c) 2006 The OpenSSL Project.  All rights reserved.
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
 */

module deimos.openssl.camellia;

import deimos.openssl._d_util;

public import deimos.openssl.opensslconf;

version (OPENSSL_NO_CAMELLIA) {
  static assert(false, "CAMELLIA is disabled.");
}

import core.stdc.config;

enum CAMELLIA_ENCRYPT = 1;
enum CAMELLIA_DECRYPT = 0;

/* Because array size can't be a const in C, the following two are macros.
   Both sizes are in bytes. */

extern (C):
nothrow:

/* This should be a hidden type, but EVP requires that the size be known */

enum CAMELLIA_BLOCK_SIZE = 16;
enum CAMELLIA_TABLE_BYTE_LEN = 272;
enum CAMELLIA_TABLE_WORD_LEN = (CAMELLIA_TABLE_BYTE_LEN / 4);

alias uint[CAMELLIA_TABLE_WORD_LEN] KEY_TABLE_TYPE; /* to match with WORD */

struct camellia_key_st
	{
	union u_ {
		double d;	/* ensures 64-bit align */
		KEY_TABLE_TYPE rd_key;
		}
	u_ u;
	int grand_rounds;
	};
alias camellia_key_st CAMELLIA_KEY;

int Camellia_set_key(const(ubyte)* userKey, const int bits,
	CAMELLIA_KEY* key);

void Camellia_encrypt(const(ubyte)* in_, ubyte* out_,
	const(CAMELLIA_KEY)* key);
void Camellia_decrypt(const(ubyte)* in_, ubyte* out_,
	const(CAMELLIA_KEY)* key);

void Camellia_ecb_encrypt(const(ubyte)* in_, ubyte* out_,
	const(CAMELLIA_KEY)* key, const int enc);
void Camellia_cbc_encrypt(const(ubyte)* in_, ubyte* out_,
	size_t length, const(CAMELLIA_KEY)* key,
	ubyte* ivec, const int enc);
void Camellia_cfb128_encrypt(const(ubyte)* in_, ubyte* out_,
	size_t length, const(CAMELLIA_KEY)* key,
	ubyte* ivec, int* num, const int enc);
void Camellia_cfb1_encrypt(const(ubyte)* in_, ubyte* out_,
	size_t length, const(CAMELLIA_KEY)* key,
	ubyte* ivec, int* num, const int enc);
void Camellia_cfb8_encrypt(const(ubyte)* in_, ubyte* out_,
	size_t length, const(CAMELLIA_KEY)* key,
	ubyte* ivec, int* num, const int enc);
void Camellia_ofb128_encrypt(const(ubyte)* in_, ubyte* out_,
	size_t length, const(CAMELLIA_KEY)* key,
	ubyte* ivec, int* num);
void Camellia_ctr128_encrypt(const(ubyte)* in_, ubyte* out_,
	size_t length, const(CAMELLIA_KEY)* key,
	ubyte ivec[CAMELLIA_BLOCK_SIZE],
	ubyte ecount_buf[CAMELLIA_BLOCK_SIZE],
	uint* num);
