/* crypto/rsa/rsa.h */
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

module deimos.openssl.rsa;

import deimos.openssl._d_util;

import deimos.openssl.evp; // Needed for EVP_PKEY_ALG_CTRL.

public import deimos.openssl.asn1;

version(OPENSSL_NO_BIO) {} else {
public import deimos.openssl.bio;
}
public import deimos.openssl.crypto;
public import deimos.openssl.ossl_typ;
version(OPENSSL_NO_DEPRECATED) {} else {
public import deimos.openssl.bn;
}

version (OPENSSL_NO_RSA) {
  static assert(false, "RSA is disabled.");
}

extern (C):
nothrow:

/* Declared already in ossl_typ.h */
/* typedef rsa_st RSA; */
/* typedef rsa_meth_st RSA_METHOD; */

struct rsa_meth_st
	{
	const(char)* name;
	ExternC!(int function(int flen,const(ubyte)* from,
			   ubyte* to,
			   RSA* rsa,int padding)) rsa_pub_enc;
	ExternC!(int function(int flen,const(ubyte)* from,
			   ubyte* to,
			   RSA* rsa,int padding)) rsa_pub_dec;
	ExternC!(int function(int flen,const(ubyte)* from,
			    ubyte* to,
			    RSA* rsa,int padding)) rsa_priv_enc;
	ExternC!(int function(int flen,const(ubyte)* from,
			    ubyte* to,
			    RSA* rsa,int padding)) rsa_priv_dec;
	ExternC!(int function(BIGNUM* r0,const(BIGNUM)* I,RSA* rsa,BN_CTX* ctx)) rsa_mod_exp; /* Can be null */
	ExternC!(int function(BIGNUM* r, const(BIGNUM)* a, const(BIGNUM)* p,
			  const(BIGNUM)* m, BN_CTX* ctx,
			  BN_MONT_CTX* m_ctx)) bn_mod_exp; /* Can be null */
	ExternC!(int function(RSA* rsa)) init_;		/* called at new */
	ExternC!(int function(RSA* rsa)) finish;	/* called at free */
	int flags;			/* RSA_METHOD_FLAG_* things */
	char* app_data;			/* may be needed! */
/* New sign and verify functions: some libraries don't allow arbitrary data
 * to be signed/verified: this allows them to be used. Note: for this to work
 * the RSA_public_decrypt() and RSA_private_encrypt() should* NOT* be used
 * RSA_sign(), RSA_verify() should be used instead. Note: for backwards
 * compatibility this functionality is only enabled if the RSA_FLAG_SIGN_VER
 * option is set in 'flags'.
 */
	ExternC!(int function(int type,
		const(ubyte)* m, uint m_length,
		ubyte* sigret, uint* siglen, const(RSA)* rsa)) rsa_sign;
	ExternC!(int function(int dtype,
		const(ubyte)* m, uint m_length,
		const(ubyte)* sigbuf, uint siglen,
								const(RSA)* rsa)) rsa_verify;
/* If this callback is NULL, the builtin software RSA key-gen will be used. This
 * is for behavioural compatibility whilst the code gets rewired, but one day
 * it would be nice to assume there are no such things as "builtin software"
 * implementations. */
	ExternC!(int function(RSA* rsa, int bits, BIGNUM* e, BN_GENCB* cb)) rsa_keygen;
	};

struct rsa_st
	{
	/* The first parameter is used to pickup errors where
	 * this is passed instead of aEVP_PKEY, it is set to 0 */
	int pad;
	c_long version_;
	const(RSA_METHOD)* meth;
	/* functional reference if 'meth' is ENGINE-provided */
	ENGINE* engine;
	BIGNUM* n;
	BIGNUM* e;
	BIGNUM* d;
	BIGNUM* p;
	BIGNUM* q;
	BIGNUM* dmp1;
	BIGNUM* dmq1;
	BIGNUM* iqmp;
	/* be careful using this if the RSA structure is shared */
	CRYPTO_EX_DATA ex_data;
	int references;
	int flags;

	/* Used to cache montgomery values */
	BN_MONT_CTX* _method_mod_n;
	BN_MONT_CTX* _method_mod_p;
	BN_MONT_CTX* _method_mod_q;

	/* all BIGNUM values are actually in the following data, if it is not
	 * NULL */
	char* bignum_data;
	BN_BLINDING* blinding;
	BN_BLINDING* mt_blinding;
	};

// #ifndef OPENSSL_RSA_MAX_MODULUS_BITS
enum OPENSSL_RSA_MAX_MODULUS_BITS = 16384;
// #endif

// #ifndef OPENSSL_RSA_SMALL_MODULUS_BITS
enum OPENSSL_RSA_SMALL_MODULUS_BITS = 3072;
// #endif
// #ifndef OPENSSL_RSA_MAX_PUBEXP_BITS
enum OPENSSL_RSA_MAX_PUBEXP_BITS = 64; /* exponent limit enforced for "large" modulus only */
// #endif

enum RSA_3 = 0x3;
enum RSA_F4 = 0x10001;

enum RSA_METHOD_FLAG_NO_CHECK = 0x0001; /* don't check pub/private match */

enum RSA_FLAG_CACHE_PUBLIC = 0x0002;
enum RSA_FLAG_CACHE_PRIVATE = 0x0004;
enum RSA_FLAG_BLINDING = 0x0008;
enum RSA_FLAG_THREAD_SAFE = 0x0010;
/* This flag means the private key operations will be handled by rsa_mod_exp
 * and that they do not depend on the private key components being present:
 * for example a key stored in external hardware. Without this flag bn_mod_exp
 * gets called when private key components are absent.
 */
enum RSA_FLAG_EXT_PKEY = 0x0020;

/* This flag in the RSA_METHOD enables the new rsa_sign, rsa_verify functions.
 */
enum RSA_FLAG_SIGN_VER = 0x0040;

enum RSA_FLAG_NO_BLINDING = 0x0080; /* new with 0.9.6j and 0.9.7b; the built-in
                                                * RSA implementation now uses blinding by
                                                * default (ignoring RSA_FLAG_BLINDING),
                                                * but other engines might not need it
                                                */
enum RSA_FLAG_NO_CONSTTIME = 0x0100; /* new with 0.9.8f; the built-in RSA
						* implementation now uses constant time
						* operations by default in private key operations,
						* e.g., constant time modular exponentiation,
                                                * modular inverse without leaking branches,
                                                * division without leaking branches. This
                                                * flag disables these constant time
                                                * operations and results in faster RSA
                                                * private key operations.
                                                */
version(OPENSSL_NO_DEPRECATED) {} else {
alias RSA_FLAG_NO_CONSTTIME RSA_FLAG_NO_EXP_CONSTTIME; /* deprecated name for the flag*/
                                                /* new with 0.9.7h; the built-in RSA
                                                * implementation now uses constant time
                                                * modular exponentiation for secret exponents
                                                * by default. This flag causes the
                                                * faster variable sliding window method to
                                                * be used for all exponents.
                                                */
}


auto EVP_PKEY_CTX_set_rsa_padding()(EVP_PKEY_CTX* ctx, int pad) {
	return EVP_PKEY_CTX_ctrl(ctx, EVP_PKEY_RSA, -1, EVP_PKEY_CTRL_RSA_PADDING,
				pad, null);
}

auto EVP_PKEY_CTX_set_rsa_pss_saltlen()(EVP_PKEY_CTX* ctx, int len) {
	return EVP_PKEY_CTX_ctrl(ctx, EVP_PKEY_RSA,
				(EVP_PKEY_OP_SIGN|EVP_PKEY_OP_VERIFY),
				EVP_PKEY_CTRL_RSA_PSS_SALTLEN,
				len, null);
}

auto EVP_PKEY_CTX_set_rsa_keygen_bits()(EVP_PKEY_CTX* ctx, int bits) {
	return EVP_PKEY_CTX_ctrl(ctx, EVP_PKEY_RSA, EVP_PKEY_OP_KEYGEN,
				EVP_PKEY_CTRL_RSA_KEYGEN_BITS, bits, null);
}

auto EVP_PKEY_CTX_set_rsa_keygen_pubexp()(EVP_PKEY_CTX* ctx, void* pubexp) {
	return EVP_PKEY_CTX_ctrl(ctx, EVP_PKEY_RSA, EVP_PKEY_OP_KEYGEN,
				EVP_PKEY_CTRL_RSA_KEYGEN_PUBEXP, 0, pubexp);
}

enum EVP_PKEY_CTRL_RSA_PADDING = (EVP_PKEY_ALG_CTRL + 1);
enum EVP_PKEY_CTRL_RSA_PSS_SALTLEN = (EVP_PKEY_ALG_CTRL + 2);

enum EVP_PKEY_CTRL_RSA_KEYGEN_BITS = (EVP_PKEY_ALG_CTRL + 3);
enum EVP_PKEY_CTRL_RSA_KEYGEN_PUBEXP = (EVP_PKEY_ALG_CTRL + 4);

enum RSA_PKCS1_PADDING = 1;
enum RSA_SSLV23_PADDING = 2;
enum RSA_NO_PADDING = 3;
enum RSA_PKCS1_OAEP_PADDING = 4;
enum RSA_X931_PADDING = 5;
/* EVP_PKEY_ only */
enum RSA_PKCS1_PSS_PADDING = 6;

enum RSA_PKCS1_PADDING_SIZE = 11;

int RSA_set_app_data()(RSA* s, void* arg) { return RSA_set_ex_data(s,0,arg); }
void* RSA_get_app_data()(const(RSA)* s) { return RSA_get_ex_data(s,0); }

RSA* 	RSA_new();
RSA* 	RSA_new_method(ENGINE* engine);
int	RSA_size(const(RSA)*);

/* Deprecated version */
version(OPENSSL_NO_DEPRECATED) {} else {
RSA* 	RSA_generate_key(int bits, c_ulong e,ExternC!(void
	 function(int,int,void*)) callback,void* cb_arg);
} /* !defined(OPENSSL_NO_DEPRECATED) */

/* New version */
int	RSA_generate_key_ex(RSA* rsa, int bits, BIGNUM* e, BN_GENCB* cb);

int	RSA_check_key(const(RSA)*);
	/* next 4 return -1 on error */
int	RSA_public_encrypt(int flen, const(ubyte)* from,
		ubyte* to, RSA* rsa,int padding);
int	RSA_private_encrypt(int flen, const(ubyte)* from,
		ubyte* to, RSA* rsa,int padding);
int	RSA_public_decrypt(int flen, const(ubyte)* from,
		ubyte* to, RSA* rsa,int padding);
int	RSA_private_decrypt(int flen, const(ubyte)* from,
		ubyte* to, RSA* rsa,int padding);
void	RSA_free (RSA* r);
/* "up" the RSA object's reference count */
int	RSA_up_ref(RSA* r);

int	RSA_flags(const(RSA)* r);

void RSA_set_default_method(const(RSA_METHOD)* meth);
const(RSA_METHOD)* RSA_get_default_method();
const(RSA_METHOD)* RSA_get_method(const(RSA)* rsa);
int RSA_set_method(RSA* rsa, const(RSA_METHOD)* meth);

/* This function needs the memory locking malloc callbacks to be installed */
int RSA_memory_lock(RSA* r);

/* these are the actual SSLeay RSA functions */
const(RSA_METHOD)* RSA_PKCS1_SSLeay();

const(RSA_METHOD)* RSA_null_method();

mixin(DECLARE_ASN1_ENCODE_FUNCTIONS_const!("RSA", "RSAPublicKey"));
mixin(DECLARE_ASN1_ENCODE_FUNCTIONS_const!("RSA", "RSAPrivateKey"));

version(OPENSSL_NO_FP_API) {} else {
int	RSA_print_fp(FILE* fp, const(RSA)* r,int offset);
}

version(OPENSSL_NO_BIO) {} else {
int	RSA_print(BIO* bp, const(RSA)* r,int offset);
}

version(OPENSSL_NO_RC4) {} else {
int i2d_RSA_NET(const(RSA)* a, ubyte** pp,
		ExternC!(int function(char* buf, int len, const(char)* prompt, int verify)) cb,
		int sgckey);
RSA* d2i_RSA_NET(RSA** a, const(ubyte)** pp, c_long length,
		 ExternC!(int function(char* buf, int len, const(char)* prompt, int verify)) cb,
		 int sgckey);

int i2d_Netscape_RSA(const(RSA)* a, ubyte** pp,
		     ExternC!(int function(char* buf, int len, const(char)* prompt,
			       int verify)) cb);
RSA* d2i_Netscape_RSA(RSA** a, const(ubyte)** pp, c_long length,
		      ExternC!(int function(char* buf, int len, const(char)* prompt,
				int verify)) cb);
}

/* The following 2 functions sign and verify a X509_SIG ASN1 object
 * inside PKCS#1 padded RSA encryption */
int RSA_sign(int type, const(ubyte)* m, uint m_length,
	ubyte* sigret, uint* siglen, RSA* rsa);
int RSA_verify(int type, const(ubyte)* m, uint m_length,
	const(ubyte)* sigbuf, uint siglen, RSA* rsa);

/* The following 2 function sign and verify a ASN1_OCTET_STRING
 * object inside PKCS#1 padded RSA encryption */
int RSA_sign_ASN1_OCTET_STRING(int type,
	const(ubyte)* m, uint m_length,
	ubyte* sigret, uint* siglen, RSA* rsa);
int RSA_verify_ASN1_OCTET_STRING(int type,
	const(ubyte)* m, uint m_length,
	ubyte* sigbuf, uint siglen, RSA* rsa);

int RSA_blinding_on(RSA* rsa, BN_CTX* ctx);
void RSA_blinding_off(RSA* rsa);
BN_BLINDING* RSA_setup_blinding(RSA* rsa, BN_CTX* ctx);

int RSA_padding_add_PKCS1_type_1(ubyte* to,int tlen,
	const(ubyte)* f,int fl);
int RSA_padding_check_PKCS1_type_1(ubyte* to,int tlen,
	const(ubyte)* f,int fl,int rsa_len);
int RSA_padding_add_PKCS1_type_2(ubyte* to,int tlen,
	const(ubyte)* f,int fl);
int RSA_padding_check_PKCS1_type_2(ubyte* to,int tlen,
	const(ubyte)* f,int fl,int rsa_len);
int PKCS1_MGF1(ubyte* mask, c_long len,
	const(ubyte)* seed, c_long seedlen, const(EVP_MD)* dgst);
int RSA_padding_add_PKCS1_OAEP(ubyte* to,int tlen,
	const(ubyte)* f,int fl,
	const(ubyte)* p,int pl);
int RSA_padding_check_PKCS1_OAEP(ubyte* to,int tlen,
	const(ubyte)* f,int fl,int rsa_len,
	const(ubyte)* p,int pl);
int RSA_padding_add_SSLv23(ubyte* to,int tlen,
	const(ubyte)* f,int fl);
int RSA_padding_check_SSLv23(ubyte* to,int tlen,
	const(ubyte)* f,int fl,int rsa_len);
int RSA_padding_add_none(ubyte* to,int tlen,
	const(ubyte)* f,int fl);
int RSA_padding_check_none(ubyte* to,int tlen,
	const(ubyte)* f,int fl,int rsa_len);
int RSA_padding_add_X931(ubyte* to,int tlen,
	const(ubyte)* f,int fl);
int RSA_padding_check_X931(ubyte* to,int tlen,
	const(ubyte)* f,int fl,int rsa_len);
int RSA_X931_hash_id(int nid);

int RSA_verify_PKCS1_PSS(RSA* rsa, const(ubyte)* mHash,
			const(EVP_MD)* Hash, const(ubyte)* EM, int sLen);
int RSA_padding_add_PKCS1_PSS(RSA* rsa, ubyte* EM,
			const(ubyte)* mHash,
			const(EVP_MD)* Hash, int sLen);

int RSA_get_ex_new_index(c_long argl, void* argp, CRYPTO_EX_new* new_func,
	CRYPTO_EX_dup* dup_func, CRYPTO_EX_free* free_func);
int RSA_set_ex_data(RSA* r,int idx,void* arg);
void* RSA_get_ex_data(const(RSA)* r, int idx);

RSA* RSAPublicKey_dup(RSA* rsa);
RSA* RSAPrivateKey_dup(RSA* rsa);

/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
void ERR_load_RSA_strings();

/* Error codes for the RSA functions. */

/* Function codes. */
enum RSA_F_CHECK_PADDING_MD = 140;
enum RSA_F_DO_RSA_PRINT = 146;
enum RSA_F_INT_RSA_VERIFY = 145;
enum RSA_F_MEMORY_LOCK = 100;
enum RSA_F_OLD_RSA_PRIV_DECODE = 147;
enum RSA_F_PKEY_RSA_CTRL = 143;
enum RSA_F_PKEY_RSA_CTRL_STR = 144;
enum RSA_F_PKEY_RSA_SIGN = 142;
enum RSA_F_PKEY_RSA_VERIFYRECOVER = 141;
enum RSA_F_RSA_BUILTIN_KEYGEN = 129;
enum RSA_F_RSA_CHECK_KEY = 123;
enum RSA_F_RSA_EAY_PRIVATE_DECRYPT = 101;
enum RSA_F_RSA_EAY_PRIVATE_ENCRYPT = 102;
enum RSA_F_RSA_EAY_PUBLIC_DECRYPT = 103;
enum RSA_F_RSA_EAY_PUBLIC_ENCRYPT = 104;
enum RSA_F_RSA_GENERATE_KEY = 105;
enum RSA_F_RSA_MEMORY_LOCK = 130;
enum RSA_F_RSA_NEW_METHOD = 106;
enum RSA_F_RSA_NULL = 124;
enum RSA_F_RSA_NULL_MOD_EXP = 131;
enum RSA_F_RSA_NULL_PRIVATE_DECRYPT = 132;
enum RSA_F_RSA_NULL_PRIVATE_ENCRYPT = 133;
enum RSA_F_RSA_NULL_PUBLIC_DECRYPT = 134;
enum RSA_F_RSA_NULL_PUBLIC_ENCRYPT = 135;
enum RSA_F_RSA_PADDING_ADD_NONE = 107;
enum RSA_F_RSA_PADDING_ADD_PKCS1_OAEP = 121;
enum RSA_F_RSA_PADDING_ADD_PKCS1_PSS = 125;
enum RSA_F_RSA_PADDING_ADD_PKCS1_TYPE_1 = 108;
enum RSA_F_RSA_PADDING_ADD_PKCS1_TYPE_2 = 109;
enum RSA_F_RSA_PADDING_ADD_SSLV23 = 110;
enum RSA_F_RSA_PADDING_ADD_X931 = 127;
enum RSA_F_RSA_PADDING_CHECK_NONE = 111;
enum RSA_F_RSA_PADDING_CHECK_PKCS1_OAEP = 122;
enum RSA_F_RSA_PADDING_CHECK_PKCS1_TYPE_1 = 112;
enum RSA_F_RSA_PADDING_CHECK_PKCS1_TYPE_2 = 113;
enum RSA_F_RSA_PADDING_CHECK_SSLV23 = 114;
enum RSA_F_RSA_PADDING_CHECK_X931 = 128;
enum RSA_F_RSA_PRINT = 115;
enum RSA_F_RSA_PRINT_FP = 116;
enum RSA_F_RSA_PRIV_DECODE = 137;
enum RSA_F_RSA_PRIV_ENCODE = 138;
enum RSA_F_RSA_PUB_DECODE = 139;
enum RSA_F_RSA_SETUP_BLINDING = 136;
enum RSA_F_RSA_SIGN = 117;
enum RSA_F_RSA_SIGN_ASN1_OCTET_STRING = 118;
enum RSA_F_RSA_VERIFY = 119;
enum RSA_F_RSA_VERIFY_ASN1_OCTET_STRING = 120;
enum RSA_F_RSA_VERIFY_PKCS1_PSS = 126;

/* Reason codes. */
enum RSA_R_ALGORITHM_MISMATCH = 100;
enum RSA_R_BAD_E_VALUE = 101;
enum RSA_R_BAD_FIXED_HEADER_DECRYPT = 102;
enum RSA_R_BAD_PAD_BYTE_COUNT = 103;
enum RSA_R_BAD_SIGNATURE = 104;
enum RSA_R_BLOCK_TYPE_IS_NOT_01 = 106;
enum RSA_R_BLOCK_TYPE_IS_NOT_02 = 107;
enum RSA_R_DATA_GREATER_THAN_MOD_LEN = 108;
enum RSA_R_DATA_TOO_LARGE = 109;
enum RSA_R_DATA_TOO_LARGE_FOR_KEY_SIZE = 110;
enum RSA_R_DATA_TOO_LARGE_FOR_MODULUS = 132;
enum RSA_R_DATA_TOO_SMALL = 111;
enum RSA_R_DATA_TOO_SMALL_FOR_KEY_SIZE = 122;
enum RSA_R_DIGEST_TOO_BIG_FOR_RSA_KEY = 112;
enum RSA_R_DMP1_NOT_CONGRUENT_TO_D = 124;
enum RSA_R_DMQ1_NOT_CONGRUENT_TO_D = 125;
enum RSA_R_D_E_NOT_CONGRUENT_TO_1 = 123;
enum RSA_R_FIRST_OCTET_INVALID = 133;
enum RSA_R_ILLEGAL_OR_UNSUPPORTED_PADDING_MODE = 144;
enum RSA_R_INVALID_DIGEST_LENGTH = 143;
enum RSA_R_INVALID_HEADER = 137;
enum RSA_R_INVALID_KEYBITS = 145;
enum RSA_R_INVALID_MESSAGE_LENGTH = 131;
enum RSA_R_INVALID_PADDING = 138;
enum RSA_R_INVALID_PADDING_MODE = 141;
enum RSA_R_INVALID_PSS_SALTLEN = 146;
enum RSA_R_INVALID_TRAILER = 139;
enum RSA_R_INVALID_X931_DIGEST = 142;
enum RSA_R_IQMP_NOT_INVERSE_OF_Q = 126;
enum RSA_R_KEY_SIZE_TOO_SMALL = 120;
enum RSA_R_LAST_OCTET_INVALID = 134;
enum RSA_R_MODULUS_TOO_LARGE = 105;
enum RSA_R_NO_PUBLIC_EXPONENT = 140;
enum RSA_R_NULL_BEFORE_BLOCK_MISSING = 113;
enum RSA_R_N_DOES_NOT_EQUAL_P_Q = 127;
enum RSA_R_OAEP_DECODING_ERROR = 121;
enum RSA_R_OPERATION_NOT_SUPPORTED_FOR_THIS_KEYTYPE = 148;
enum RSA_R_PADDING_CHECK_FAILED = 114;
enum RSA_R_P_NOT_PRIME = 128;
enum RSA_R_Q_NOT_PRIME = 129;
enum RSA_R_RSA_OPERATIONS_NOT_SUPPORTED = 130;
enum RSA_R_SLEN_CHECK_FAILED = 136;
enum RSA_R_SLEN_RECOVERY_FAILED = 135;
enum RSA_R_SSLV3_ROLLBACK_ATTACK = 115;
enum RSA_R_THE_ASN1_OBJECT_IDENTIFIER_IS_NOT_KNOWN_FOR_THIS_MD = 116;
enum RSA_R_UNKNOWN_ALGORITHM_TYPE = 117;
enum RSA_R_UNKNOWN_PADDING_TYPE = 118;
enum RSA_R_VALUE_MISSING = 147;
enum RSA_R_WRONG_SIGNATURE_LENGTH = 119;
