/* crypto/des/des.h */
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

module deimos.openssl.des;

import deimos.openssl._d_util;

public import deimos.openssl.e_os2;	/* OPENSSL_EXTERN, OPENSSL_NO_DES,
				   DES_LONG (via openssl/opensslconf.h */

version (OPENSSL_NO_DES) {
  static assert(false, "DES is disabled.");
}


extern (C):
nothrow:

alias ubyte[8] DES_cblock;
alias ubyte[8] const_DES_cblock;
/* With "const", gcc 2.8.1 on Solaris thinks that DES_cblock* 
 * and const_DES_cblock* are incompatible pointer types. */

struct DES_ks
    {
    union ks_
	{
	DES_cblock cblock;
	/* make sure things are correct size on machines with
	 * 8 byte longs */
	DES_LONG deslong[2];
	}
	ks_[16] ks;
    }
alias DES_ks DES_key_schedule;

// #ifndef OPENSSL_DISABLE_OLD_DES_SUPPORT
// # ifndef OPENSSL_ENABLE_OLD_DES_SUPPORT
// #  define OPENSSL_ENABLE_OLD_DES_SUPPORT
// # endif
// #endif

version (OPENSSL_ENABLE_OLD_DES_SUPPORT) {
public import deimos.openssl.des_old;
}

enum DES_KEY_SZ = DES_cblock.sizeof;
enum DES_SCHEDULE_SZ = DES_key_schedule.sizeof;

enum DES_ENCRYPT = 1;
enum DES_DECRYPT = 0;

enum DES_CBC_MODE = 0;
enum DES_PCBC_MODE = 1;

alias DES_ecb3_encrypt DES_ecb2_encrypt;

alias DES_ede3_cbc_encrypt DES_ede2_cbc_encrypt;

alias DES_ede3_cfb64_encrypt DES_ede2_cfb64_encrypt;

alias DES_ede3_ofb64_encrypt DES_ede2_ofb64_encrypt;

extern int _shadow_DES_check_key;	/* defaults to false */
alias _shadow_DES_check_key DES_check_key;
extern int _shadow_DES_rw_mode;	/* defaults to DES_PCBC_MODE */
alias _shadow_DES_rw_mode DES_rw_mode;

const(char)* DES_options();
void DES_ecb3_encrypt(const_DES_cblock* input, DES_cblock* output,
		      DES_key_schedule* ks1,DES_key_schedule* ks2,
		      DES_key_schedule* ks3, int enc);
DES_LONG DES_cbc_cksum(const(ubyte)* input,DES_cblock* output,
		       c_long length,DES_key_schedule* schedule,
		       const_DES_cblock* ivec);
/* DES_cbc_encrypt does not update the IV!  Use DES_ncbc_encrypt instead. */
void DES_cbc_encrypt(const(ubyte)* input,ubyte* output,
		     c_long length,DES_key_schedule* schedule,DES_cblock* ivec,
		     int enc);
void DES_ncbc_encrypt(const(ubyte)* input,ubyte* output,
		      c_long length,DES_key_schedule* schedule,DES_cblock* ivec,
		      int enc);
void DES_xcbc_encrypt(const(ubyte)* input,ubyte* output,
		      c_long length,DES_key_schedule* schedule,DES_cblock* ivec,
		      const_DES_cblock* inw,const_DES_cblock* outw,int enc);
void DES_cfb_encrypt(const(ubyte)* in_,ubyte* out_,int numbits,
		     c_long length,DES_key_schedule* schedule,DES_cblock* ivec,
		     int enc);
void DES_ecb_encrypt(const_DES_cblock* input,DES_cblock* output,
		     DES_key_schedule* ks,int enc);

/* 	This is the DES encryption function that gets called by just about
	every other DES routine in the library.  You should not use this
	function except to implement 'modes' of DES.  I say this because the
	functions that call this routine do the conversion from 'char* ' to
	c_long, and this needs to be done to make sure 'non-aligned' memory
	access do not occur.  The characters are loaded 'little endian'.
	Data is a pointer to 2 c_ulong's and ks is the
	DES_key_schedule to use.  enc, is non zero specifies encryption,
	zero if decryption. */
void DES_encrypt1(DES_LONG* data,DES_key_schedule* ks, int enc);

/* 	This functions is the same as DES_encrypt1() except that the DES
	initial permutation (IP) and final permutation (FP) have been left
	out.  As for DES_encrypt1(), you should not use this function.
	It is used by the routines in the library that implement triple DES.
	IP() DES_encrypt2() DES_encrypt2() DES_encrypt2() FP() is the same
	as DES_encrypt1() DES_encrypt1() DES_encrypt1() except faster :-). */
void DES_encrypt2(DES_LONG* data,DES_key_schedule* ks, int enc);

void DES_encrypt3(DES_LONG* data, DES_key_schedule* ks1,
		  DES_key_schedule* ks2, DES_key_schedule* ks3);
void DES_decrypt3(DES_LONG* data, DES_key_schedule* ks1,
		  DES_key_schedule* ks2, DES_key_schedule* ks3);
void DES_ede3_cbc_encrypt(const(ubyte)* input,ubyte* output,
			  c_long length,
			  DES_key_schedule* ks1,DES_key_schedule* ks2,
			  DES_key_schedule* ks3,DES_cblock* ivec,int enc);
void DES_ede3_cbcm_encrypt(const(ubyte)* in_,ubyte* out_,
			   c_long length,
			   DES_key_schedule* ks1,DES_key_schedule* ks2,
			   DES_key_schedule* ks3,
			   DES_cblock* ivec1,DES_cblock* ivec2,
			   int enc);
void DES_ede3_cfb64_encrypt(const(ubyte)* in_,ubyte* out_,
			    c_long length,DES_key_schedule* ks1,
			    DES_key_schedule* ks2,DES_key_schedule* ks3,
			    DES_cblock* ivec,int* num,int enc);
void DES_ede3_cfb_encrypt(const(ubyte)* in_,ubyte* out_,
			  int numbits,c_long length,DES_key_schedule* ks1,
			  DES_key_schedule* ks2,DES_key_schedule* ks3,
			  DES_cblock* ivec,int enc);
void DES_ede3_ofb64_encrypt(const(ubyte)* in_,ubyte* out_,
			    c_long length,DES_key_schedule* ks1,
			    DES_key_schedule* ks2,DES_key_schedule* ks3,
			    DES_cblock* ivec,int* num);
version (none) {
void DES_xwhite_in2out(const_DES_cblock* DES_key,const_DES_cblock* in_white,
		       DES_cblock* out_white);
}

int DES_enc_read(int fd,void* buf,int len,DES_key_schedule* sched,
		 DES_cblock* iv);
int DES_enc_write(int fd,const(void)* buf,int len,DES_key_schedule* sched,
		  DES_cblock* iv);
char* DES_fcrypt(const(char)* buf,const(char)* salt, char* ret);
char* DES_crypt(const(char)* buf,const(char)* salt);
void DES_ofb_encrypt(const(ubyte)* in_,ubyte* out_,int numbits,
		     c_long length,DES_key_schedule* schedule,DES_cblock* ivec);
void DES_pcbc_encrypt(const(ubyte)* input,ubyte* output,
		      c_long length,DES_key_schedule* schedule,DES_cblock* ivec,
		      int enc);
DES_LONG DES_quad_cksum(const(ubyte)* input,DES_cblock output[],
			c_long length,int out_count,DES_cblock* seed);
int DES_random_key(DES_cblock* ret);
void DES_set_odd_parity(DES_cblock* key);
int DES_check_key_parity(const_DES_cblock* key);
int DES_is_weak_key(const_DES_cblock* key);
/* DES_set_key (= set_key = DES_key_sched = key_sched) calls
 * DES_set_key_checked if global variable DES_check_key is set,
 * DES_set_key_unchecked otherwise. */
int DES_set_key(const_DES_cblock* key,DES_key_schedule* schedule);
int DES_key_sched(const_DES_cblock* key,DES_key_schedule* schedule);
int DES_set_key_checked(const_DES_cblock* key,DES_key_schedule* schedule);
void DES_set_key_unchecked(const_DES_cblock* key,DES_key_schedule* schedule);
void DES_string_to_key(const(char)* str,DES_cblock* key);
void DES_string_to_2keys(const(char)* str,DES_cblock* key1,DES_cblock* key2);
void DES_cfb64_encrypt(const(ubyte)* in_,ubyte* out_,c_long length,
		       DES_key_schedule* schedule,DES_cblock* ivec,int* num,
		       int enc);
void DES_ofb64_encrypt(const(ubyte)* in_,ubyte* out_,c_long length,
		       DES_key_schedule* schedule,DES_cblock* ivec,int* num);

int DES_read_password(DES_cblock* key, const(char)* prompt, int verify);
int DES_read_2passwords(DES_cblock* key1, DES_cblock* key2, const(char)* prompt,
	int verify);

alias DES_set_odd_parity DES_fixup_key_parity;
