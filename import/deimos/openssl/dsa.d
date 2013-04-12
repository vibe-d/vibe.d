/* crypto/dsa/dsa.h */
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

/*
 * The DSS routines are based on patches supplied by
 * Steven Schoch <schoch@sheba.arc.nasa.gov>.  He basically did the
 * work and I have just tweaked them a little to fit into my
 * stylistic vision for SSLeay :-) */

module deimos.openssl.dsa;

import deimos.openssl._d_util;

import deimos.openssl.evp; // Needed for EVP_PKEY_ALG_CTRL.

public import deimos.openssl.e_os2;

version (OPENSSL_NO_DSA) {
  static assert(false, "DSA is disabled.");
}

version(OPENSSL_NO_BIO) {} else {
public import deimos.openssl.bio;
}
public import deimos.openssl.crypto;
public import deimos.openssl.ossl_typ;

version(OPENSSL_NO_DEPRECATED) {} else {
public import deimos.openssl.bn;
version(OPENSSL_NO_DH) {} else {
public import deimos.openssl.dh;
}
}

// #ifndef OPENSSL_DSA_MAX_MODULUS_BITS
enum OPENSSL_DSA_MAX_MODULUS_BITS = 10000;
// #endif

enum DSA_FLAG_CACHE_MONT_P = 0x01;
enum DSA_FLAG_NO_EXP_CONSTTIME = 0x02; /* new with 0.9.7h; the built-in DSA
                                              * implementation now uses constant time
                                              * modular exponentiation for secret exponents
                                              * by default. This flag causes the
                                              * faster variable sliding window method to
                                              * be used for all exponents.
                                              */

extern (C):
nothrow:

/* Already defined in ossl_typ.h */
/* typedef dsa_st DSA; */
/* typedef dsa_method DSA_METHOD; */

struct DSA_SIG_st {
	BIGNUM* r;
	BIGNUM* s;
	}
alias DSA_SIG_st DSA_SIG;

struct dsa_method
	{
	const(char)* name;
	ExternC!(DSA_SIG* function(const(ubyte)* dgst, int dlen, DSA* dsa)) dsa_do_sign;
	ExternC!(int function(DSA* dsa, BN_CTX* ctx_in, BIGNUM** kinvp,
								BIGNUM** rp)) dsa_sign_setup;
	ExternC!(int function(const(ubyte)* dgst, int dgst_len,
			     DSA_SIG* sig, DSA* dsa)) dsa_do_verify;
	ExternC!(int function(DSA* dsa, BIGNUM* rr, BIGNUM* a1, BIGNUM* p1,
			BIGNUM* a2, BIGNUM* p2, BIGNUM* m, BN_CTX* ctx,
			BN_MONT_CTX* in_mont)) dsa_mod_exp;
	ExternC!(int function(DSA* dsa, BIGNUM* r, BIGNUM* a, const(BIGNUM)* p,
				const(BIGNUM)* m, BN_CTX* ctx,
				BN_MONT_CTX* m_ctx)) bn_mod_exp; /* Can be null */
	ExternC!(int function(DSA* dsa)) init_;
	ExternC!(int function(DSA* dsa)) finish;
	int flags;
	char* app_data;
	/* If this is non-NULL, it is used to generate DSA parameters */
	ExternC!(int function(DSA* dsa, int bits,
			const(ubyte)* seed, int seed_len,
			int* counter_ret, c_ulong* h_ret,
			BN_GENCB* cb)) dsa_paramgen;
	/* If this is non-NULL, it is used to generate DSA keys */
	ExternC!(int function(DSA* dsa)) dsa_keygen;
	};

struct dsa_st
	{
	/* This first variable is used to pick up errors where
	 * a DSA is passed instead of of a EVP_PKEY */
	int pad;
	c_long version_;
	int write_params;
	BIGNUM* p;
	BIGNUM* q;	/* == 20 */
	BIGNUM* g;

	BIGNUM* pub_key;  /* y public key */
	BIGNUM* priv_key; /* x private key */

	BIGNUM* kinv;	/* Signing pre-calc */
	BIGNUM* r;	/* Signing pre-calc */

	int flags;
	/* Normally used to cache montgomery values */
	BN_MONT_CTX* method_mont_p;
	int references;
	CRYPTO_EX_DATA ex_data;
	const(DSA_METHOD)* meth;
	/* functional reference if 'meth' is ENGINE-provided */
	ENGINE* engine;
	};

auto d2i_DSAparams_fp()(FILE* fp, void** x) {
	return cast(DSA*)ASN1_d2i_fp(cast(ExternC!(void* function()))&DSA_new,
		cast(d2i_of_void*)&d2i_DSAparams,fp,x);
}
auto i2d_DSAparams_fp()(FILE* fp, void* x) { return ASN1_i2d_fp(cast(d2i_of_void*)&i2d_DSAparams,fp, x); }
auto d2i_DSAparams_bio()(BIO* bp, void** x) { return ASN1_d2i_bio_of!DSA(&DSA_new,&d2i_DSAparams,bp,x); }
auto i2d_DSAparams_bio()(BIO* bp, void** x) { return ASN1_i2d_bio_of_const!DSA(&i2d_DSAparams,bp,x); }

DSA* DSAparams_dup(DSA* x);
DSA_SIG* DSA_SIG_new();
void	DSA_SIG_free(DSA_SIG* a);
int	i2d_DSA_SIG(const(DSA_SIG)* a, ubyte** pp);
DSA_SIG* d2i_DSA_SIG(DSA_SIG** v, const(ubyte)** pp, c_long length);

DSA_SIG* DSA_do_sign(const(ubyte)* dgst,int dlen,DSA* dsa);
int	DSA_do_verify(const(ubyte)* dgst,int dgst_len,
		      DSA_SIG* sig,DSA* dsa);

const(DSA_METHOD)* DSA_OpenSSL();

void	DSA_set_default_method(const(DSA_METHOD)*);
const(DSA_METHOD)* DSA_get_default_method();
int	DSA_set_method(DSA* dsa, const(DSA_METHOD)*);

DSA* 	DSA_new();
DSA* 	DSA_new_method(ENGINE* engine);
void	DSA_free (DSA* r);
/* "up" the DSA object's reference count */
int	DSA_up_ref(DSA* r);
int	DSA_size(const(DSA)*);
	/* next 4 return -1 on error */
int	DSA_sign_setup( DSA* dsa,BN_CTX* ctx_in,BIGNUM** kinvp,BIGNUM** rp);
int	DSA_sign(int type,const(ubyte)* dgst,int dlen,
		ubyte* sig, uint* siglen, DSA* dsa);
int	DSA_verify(int type,const(ubyte)* dgst,int dgst_len,
		const(ubyte)* sigbuf, int siglen, DSA* dsa);
int DSA_get_ex_new_index(c_long argl, void* argp, CRYPTO_EX_new* new_func,
	     CRYPTO_EX_dup* dup_func, CRYPTO_EX_free* free_func);
int DSA_set_ex_data(DSA* d, int idx, void* arg);
void* DSA_get_ex_data(DSA* d, int idx);

DSA* 	d2i_DSAPublicKey(DSA** a, const(ubyte)** pp, c_long length);
DSA* 	d2i_DSAPrivateKey(DSA** a, const(ubyte)** pp, c_long length);
DSA* 	d2i_DSAparams(DSA** a, const(ubyte)** pp, c_long length);

/* Deprecated version */
version(OPENSSL_NO_DEPRECATED) {} else {
DSA* 	DSA_generate_parameters(int bits,
		ubyte* seed,int seed_len,
		int* counter_ret, c_ulong* h_ret,ExternC!(void
	 function(int, int, void*)) callback,void* cb_arg);
} /* !defined(OPENSSL_NO_DEPRECATED) */

/* New version */
int	DSA_generate_parameters_ex(DSA* dsa, int bits,
		const(ubyte)* seed,int seed_len,
		int* counter_ret, c_ulong* h_ret, BN_GENCB* cb);

int	DSA_generate_key(DSA* a);
int	i2d_DSAPublicKey(const(DSA)* a, ubyte** pp);
int 	i2d_DSAPrivateKey(const(DSA)* a, ubyte** pp);
int	i2d_DSAparams(const(DSA)* a,ubyte** pp);

version(OPENSSL_NO_BIO) {} else {
int	DSAparams_print(BIO* bp, const(DSA)* x);
int	DSA_print(BIO* bp, const(DSA)* x, int off);
}
version(OPENSSL_NO_FP_API) {} else {
int	DSAparams_print_fp(FILE* fp, const(DSA)* x);
int	DSA_print_fp(FILE* bp, const(DSA)* x, int off);
}

enum DSS_prime_checks = 50;
/* Primality test according to FIPS PUB 186[-1], Appendix 2.1:
 * 50 rounds of Rabin-Miller */
int	DSA_is_prime()(const(BIGNUM)* n, ExternC!(void function(int,int,void*)) callback, void* cb_arg) {
	return BN_is_prime(n, DSS_prime_checks, callback, null, cb_arg);
}


version(OPENSSL_NO_DH) {} else {
/* Convert DSA structure (key or just parameters) into DH structure
 * (be careful to avoid small subgroup attacks when using this!) */
DH* DSA_dup_DH(const(DSA)* r);
}

auto EVP_PKEY_CTX_set_dsa_paramgen_bits()(EVP_PKEY_CTX* ctx, int nbits) {
	return EVP_PKEY_CTX_ctrl(ctx, EVP_PKEY_DSA, EVP_PKEY_OP_PARAMGEN,
				EVP_PKEY_CTRL_DSA_PARAMGEN_BITS, nbits, null);
}

enum EVP_PKEY_CTRL_DSA_PARAMGEN_BITS = (EVP_PKEY_ALG_CTRL + 1);
enum EVP_PKEY_CTRL_DSA_PARAMGEN_Q_BITS = (EVP_PKEY_ALG_CTRL + 2);
enum EVP_PKEY_CTRL_DSA_PARAMGEN_MD = (EVP_PKEY_ALG_CTRL + 3);

/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
void ERR_load_DSA_strings();

/* Error codes for the DSA functions. */

/* Function codes. */
enum DSA_F_D2I_DSA_SIG = 110;
enum DSA_F_DO_DSA_PRINT = 104;
enum DSA_F_DSAPARAMS_PRINT = 100;
enum DSA_F_DSAPARAMS_PRINT_FP = 101;
enum DSA_F_DSA_DO_SIGN = 112;
enum DSA_F_DSA_DO_VERIFY = 113;
enum DSA_F_DSA_NEW_METHOD = 103;
enum DSA_F_DSA_PARAM_DECODE = 119;
enum DSA_F_DSA_PRINT_FP = 105;
enum DSA_F_DSA_PRIV_DECODE = 115;
enum DSA_F_DSA_PRIV_ENCODE = 116;
enum DSA_F_DSA_PUB_DECODE = 117;
enum DSA_F_DSA_PUB_ENCODE = 118;
enum DSA_F_DSA_SIGN = 106;
enum DSA_F_DSA_SIGN_SETUP = 107;
enum DSA_F_DSA_SIG_NEW = 109;
enum DSA_F_DSA_VERIFY = 108;
enum DSA_F_I2D_DSA_SIG = 111;
enum DSA_F_OLD_DSA_PRIV_DECODE = 122;
enum DSA_F_PKEY_DSA_CTRL = 120;
enum DSA_F_PKEY_DSA_KEYGEN = 121;
enum DSA_F_SIG_CB = 114;

/* Reason codes. */
enum DSA_R_BAD_Q_VALUE = 102;
enum DSA_R_BN_DECODE_ERROR = 108;
enum DSA_R_BN_ERROR = 109;
enum DSA_R_DATA_TOO_LARGE_FOR_KEY_SIZE = 100;
enum DSA_R_DECODE_ERROR = 104;
enum DSA_R_INVALID_DIGEST_TYPE = 106;
enum DSA_R_MISSING_PARAMETERS = 101;
enum DSA_R_MODULUS_TOO_LARGE = 103;
enum DSA_R_NO_PARAMETERS_SET = 107;
enum DSA_R_PARAMETER_ENCODING_ERROR = 105;
