/* crypto/rc2/rc2.h */
/* Copyright (C) 1995-1997 Eric Young (eay@cryptsoft.com)
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

module deimos.openssl.rc2;

import deimos.openssl._d_util;

public import deimos.openssl.opensslconf; /* OPENSSL_NO_RC2, RC2_INT */
version (OPENSSL_NO_RC2) {
  static assert(false, "RC2 is disabled.");
}

enum RC2_ENCRYPT = 1;
enum RC2_DECRYPT = 0;

enum RC2_BLOCK = 8;
enum RC2_KEY_LENGTH = 16;

extern (C):
nothrow:

struct rc2_key_st {
	RC2_INT data[64];
	}
alias rc2_key_st RC2_KEY;

 
void RC2_set_key(RC2_KEY* key, int len, const(ubyte)* data,int bits);
void RC2_ecb_encrypt(const(ubyte)* in_,ubyte* out_,RC2_KEY* key,
		     int enc);
void RC2_encrypt(c_ulong* data,RC2_KEY* key);
void RC2_decrypt(c_ulong* data,RC2_KEY* key);
void RC2_cbc_encrypt(const(ubyte)* in_, ubyte* out_, c_long length,
	RC2_KEY* ks, ubyte* iv, int enc);
void RC2_cfb64_encrypt(const(ubyte)* in_, ubyte* out_,
		       c_long length, RC2_KEY* schedule, ubyte* ivec,
		       int* num, int enc);
void RC2_ofb64_encrypt(const(ubyte)* in_, ubyte* out_,
		       c_long length, RC2_KEY* schedule, ubyte* ivec,
		       int* num);
