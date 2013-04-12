/* crypto/pem/pem.h */
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

module deimos.openssl.pem;

import deimos.openssl._d_util;

import deimos.openssl.pkcs7; // Needed for PKCS7.

public import deimos.openssl.e_os2;
version(OPENSSL_NO_BIO) {} else {
public import deimos.openssl.bio;
}
version(OPENSSL_NO_STACK) {} else {
public import deimos.openssl.stack;
}
public import deimos.openssl.evp;
public import deimos.openssl.x509;
public import deimos.openssl.pem2;

extern (C):
nothrow:

enum PEM_BUFSIZE = 1024;

enum PEM_OBJ_UNDEF = 0;
enum PEM_OBJ_X509 = 1;
enum PEM_OBJ_X509_REQ = 2;
enum PEM_OBJ_CRL = 3;
enum PEM_OBJ_SSL_SESSION = 4;
enum PEM_OBJ_PRIV_KEY = 10;
enum PEM_OBJ_PRIV_RSA = 11;
enum PEM_OBJ_PRIV_DSA = 12;
enum PEM_OBJ_PRIV_DH = 13;
enum PEM_OBJ_PUB_RSA = 14;
enum PEM_OBJ_PUB_DSA = 15;
enum PEM_OBJ_PUB_DH = 16;
enum PEM_OBJ_DHPARAMS = 17;
enum PEM_OBJ_DSAPARAMS = 18;
enum PEM_OBJ_PRIV_RSA_PUBLIC = 19;
enum PEM_OBJ_PRIV_ECDSA = 20;
enum PEM_OBJ_PUB_ECDSA = 21;
enum PEM_OBJ_ECPARAMETERS = 22;

enum PEM_ERROR = 30;
enum PEM_DEK_DES_CBC = 40;
enum PEM_DEK_IDEA_CBC = 45;
enum PEM_DEK_DES_EDE = 50;
enum PEM_DEK_DES_ECB = 60;
enum PEM_DEK_RSA = 70;
enum PEM_DEK_RSA_MD2 = 80;
enum PEM_DEK_RSA_MD5 = 90;

alias NID_md2 PEM_MD_MD2;
alias NID_md5 PEM_MD_MD5;
alias NID_sha PEM_MD_SHA;
alias NID_md2WithRSAEncryption PEM_MD_MD2_RSA;
alias NID_md5WithRSAEncryption PEM_MD_MD5_RSA;
alias NID_sha1WithRSAEncryption PEM_MD_SHA_RSA;

enum PEM_STRING_X509_OLD = "X509 CERTIFICATE";
enum PEM_STRING_X509 = "CERTIFICATE";
enum PEM_STRING_X509_PAIR = "CERTIFICATE PAIR";
enum PEM_STRING_X509_TRUSTED = "TRUSTED CERTIFICATE";
enum PEM_STRING_X509_REQ_OLD = "NEW CERTIFICATE REQUEST";
enum PEM_STRING_X509_REQ = "CERTIFICATE REQUEST";
enum PEM_STRING_X509_CRL = "X509 CRL";
enum PEM_STRING_EVP_PKEY = "ANY PRIVATE KEY";
enum PEM_STRING_PUBLIC = "PUBLIC KEY";
enum PEM_STRING_RSA = "RSA PRIVATE KEY";
enum PEM_STRING_RSA_PUBLIC = "RSA PUBLIC KEY";
enum PEM_STRING_DSA = "DSA PRIVATE KEY";
enum PEM_STRING_DSA_PUBLIC = "DSA PUBLIC KEY";
enum PEM_STRING_PKCS7 = "PKCS7";
enum PEM_STRING_PKCS7_SIGNED = "PKCS #7 SIGNED DATA";
enum PEM_STRING_PKCS8 = "ENCRYPTED PRIVATE KEY";
enum PEM_STRING_PKCS8INF = "PRIVATE KEY";
enum PEM_STRING_DHPARAMS = "DH PARAMETERS";
enum PEM_STRING_SSL_SESSION = "SSL SESSION PARAMETERS";
enum PEM_STRING_DSAPARAMS = "DSA PARAMETERS";
enum PEM_STRING_ECDSA_PUBLIC = "ECDSA PUBLIC KEY";
enum PEM_STRING_ECPARAMETERS = "EC PARAMETERS";
enum PEM_STRING_ECPRIVATEKEY = "EC PRIVATE KEY";
enum PEM_STRING_PARAMETERS = "PARAMETERS";
enum PEM_STRING_CMS = "CMS";

  /* Note that this structure is initialised by PEM_SealInit and cleaned up
     by PEM_SealFinal (at least for now) */
struct PEM_Encode_Seal_st {
	EVP_ENCODE_CTX encode;
	EVP_MD_CTX md;
	EVP_CIPHER_CTX cipher;
	}
alias PEM_Encode_Seal_st PEM_ENCODE_SEAL_CTX;

/* enc_type is one off */
enum PEM_TYPE_ENCRYPTED = 10;
enum PEM_TYPE_MIC_ONLY = 20;
enum PEM_TYPE_MIC_CLEAR = 30;
enum PEM_TYPE_CLEAR = 40;

struct pem_recip_st {
	char* name;
	X509_NAME* dn;

	int cipher;
	int key_enc;
	/*	char iv[8]; unused and wrong size */
	}
alias pem_recip_st PEM_USER;

struct pem_ctx_st
	{
	int type;		/* what type of object */

	struct proc_type_ {
		int version_;
		int mode;
	}
	proc_type_ proc_type;

	char* domain;

	struct DEK_info_{
		int cipher;
	/* unused, and wrong size
	   ubyte iv[8]; */
		}
	DEK_info_ DEK_info;

	PEM_USER* originator;

	int num_recipient;
	PEM_USER** recipient;

	/* XXX(ben): don#t think this is used!
		STACK* x509_chain;	/ * certificate chain */
	EVP_MD* md;		/* signature type */

	int md_enc;		/* is the md encrypted or not? */
	int md_len;		/* length of md_data */
	char* md_data;		/* message digest, could be pkey encrypted */

	EVP_CIPHER* dec;	/* date encryption cipher */
	int key_len;		/* key length */
	ubyte* key;	/* key */
	/* unused, and wrong size
	   ubyte iv[8]; */


	int  data_enc;		/* is the data encrypted */
	int data_len;
	ubyte* data;
	}
alias pem_ctx_st PEM_CTX;

/* These macros make the PEM_read/PEM_write functions easier to maintain and
 * write. Now they are all implemented with either:
 * IMPLEMENT_PEM_rw(...) or IMPLEMENT_PEM_rw_cb(...)
 */

/+#ifdef OPENSSL_NO_FP_API

#define IMPLEMENT_PEM_read_fp(name, type, str, asn1) /**/
#define IMPLEMENT_PEM_write_fp(name, type, str, asn1) /**/
#define IMPLEMENT_PEM_write_fp_const(name, type, str, asn1) /**/
#define IMPLEMENT_PEM_write_cb_fp(name, type, str, asn1) /**/
#define IMPLEMENT_PEM_write_cb_fp_const(name, type, str, asn1) /**/

#else

#define IMPLEMENT_PEM_read_fp(name, type, str, asn1) \
type* PEM_read_##name(FILE* fp, type** x, pem_password_cb* cb, void* u)\
{ \
return PEM_ASN1_read((d2i_of_void*)d2i_##asn1, str,fp,(void**)x,cb,u); \
}

#define IMPLEMENT_PEM_write_fp(name, type, str, asn1) \
int PEM_write_##name(FILE* fp, type* x) \
{ \
return PEM_ASN1_write((i2d_of_void*)i2d_##asn1,str,fp,x,NULL,NULL,0,NULL,NULL); \
}

#define IMPLEMENT_PEM_write_fp_const(name, type, str, asn1) \
int PEM_write_##name(FILE* fp, const(type)* x) \
{ \
return PEM_ASN1_write((i2d_of_void*)i2d_##asn1,str,fp,(void*)x,NULL,NULL,0,NULL,NULL); \
}

#define IMPLEMENT_PEM_write_cb_fp(name, type, str, asn1) \
int PEM_write_##name(FILE* fp, type* x, const(EVP_CIPHER)* enc, \
	     ubyte* kstr, int klen, pem_password_cb* cb, \
		  void* u) \
	{ \
	return PEM_ASN1_write((i2d_of_void*)i2d_##asn1,str,fp,x,enc,kstr,klen,cb,u); \
	}

#define IMPLEMENT_PEM_write_cb_fp_const(name, type, str, asn1) \
int PEM_write_##name(FILE* fp, type* x, const(EVP_CIPHER)* enc, \
	     ubyte* kstr, int klen, pem_password_cb* cb, \
		  void* u) \
	{ \
	return PEM_ASN1_write((i2d_of_void*)i2d_##asn1,str,fp,x,enc,kstr,klen,cb,u); \
	}

#endif

#define IMPLEMENT_PEM_read_bio(name, type, str, asn1) \
type* PEM_read_bio_##name(BIO* bp, type** x, pem_password_cb* cb, void* u)\
{ \
return PEM_ASN1_read_bio((d2i_of_void*)d2i_##asn1, str,bp,(void**)x,cb,u); \
}

#define IMPLEMENT_PEM_write_bio(name, type, str, asn1) \
int PEM_write_bio_##name(BIO* bp, type* x) \
{ \
return PEM_ASN1_write_bio((i2d_of_void*)i2d_##asn1,str,bp,x,NULL,NULL,0,NULL,NULL); \
}

#define IMPLEMENT_PEM_write_bio_const(name, type, str, asn1) \
int PEM_write_bio_##name(BIO* bp, const(type)* x) \
{ \
return PEM_ASN1_write_bio((i2d_of_void*)i2d_##asn1,str,bp,(void*)x,NULL,NULL,0,NULL,NULL); \
}

#define IMPLEMENT_PEM_write_cb_bio(name, type, str, asn1) \
int PEM_write_bio_##name(BIO* bp, type* x, const(EVP_CIPHER)* enc, \
	     ubyte* kstr, int klen, pem_password_cb* cb, void* u) \
	{ \
	return PEM_ASN1_write_bio((i2d_of_void*)i2d_##asn1,str,bp,x,enc,kstr,klen,cb,u); \
	}

#define IMPLEMENT_PEM_write_cb_bio_const(name, type, str, asn1) \
int PEM_write_bio_##name(BIO* bp, type* x, const(EVP_CIPHER)* enc, \
	     ubyte* kstr, int klen, pem_password_cb* cb, void* u) \
	{ \
	return PEM_ASN1_write_bio((i2d_of_void*)i2d_##asn1,str,bp,(void*)x,enc,kstr,klen,cb,u); \
	}

#define IMPLEMENT_PEM_write(name, type, str, asn1) \
	IMPLEMENT_PEM_write_bio(name, type, str, asn1) \
	IMPLEMENT_PEM_write_fp(name, type, str, asn1)

#define IMPLEMENT_PEM_write_const(name, type, str, asn1) \
	IMPLEMENT_PEM_write_bio_const(name, type, str, asn1) \
	IMPLEMENT_PEM_write_fp_const(name, type, str, asn1)

#define IMPLEMENT_PEM_write_cb(name, type, str, asn1) \
	IMPLEMENT_PEM_write_cb_bio(name, type, str, asn1) \
	IMPLEMENT_PEM_write_cb_fp(name, type, str, asn1)

#define IMPLEMENT_PEM_write_cb_const(name, type, str, asn1) \
	IMPLEMENT_PEM_write_cb_bio_const(name, type, str, asn1) \
	IMPLEMENT_PEM_write_cb_fp_const(name, type, str, asn1)

#define IMPLEMENT_PEM_read(name, type, str, asn1) \
	IMPLEMENT_PEM_read_bio(name, type, str, asn1) \
	IMPLEMENT_PEM_read_fp(name, type, str, asn1)

#define IMPLEMENT_PEM_rw(name, type, str, asn1) \
	IMPLEMENT_PEM_read(name, type, str, asn1) \
	IMPLEMENT_PEM_write(name, type, str, asn1)

#define IMPLEMENT_PEM_rw_const(name, type, str, asn1) \
	IMPLEMENT_PEM_read(name, type, str, asn1) \
	IMPLEMENT_PEM_write_const(name, type, str, asn1)

#define IMPLEMENT_PEM_rw_cb(name, type, str, asn1) \
	IMPLEMENT_PEM_read(name, type, str, asn1) \
	IMPLEMENT_PEM_write_cb(name, type, str, asn1)
+/

/* These are the same except they are for the declarations */

version (OPENSSL_NO_FP_API) {
	mixin template DECLARE_PEM_read_fp(string name, type) {}
	mixin template DECLARE_PEM_write_fp(string name, type) {}
	mixin template DECLARE_PEM_write_fp_const(string name, type) {}
	mixin template DECLARE_PEM_write_cb_fp(string name, type) {}
} else {
	mixin template DECLARE_PEM_read_fp(string name, type) {
		mixin("type* PEM_read_" ~ name ~ "(FILE* fp, type** x, pem_password_cb* cb, void* u);");
	}

	mixin template DECLARE_PEM_write_fp(string name, type) {
		mixin("int PEM_write_" ~ name ~ "(FILE* fp, type* x);");
	}

	mixin template DECLARE_PEM_write_fp_const(string name, type) {
		mixin("int PEM_write_" ~ name ~ "(FILE* fp, const(type)* x);");
	}

	mixin template DECLARE_PEM_write_cb_fp(string name, type) {
		mixin("int PEM_write_" ~ name ~ "(FILE* fp, type* x, const(EVP_CIPHER)* enc,
		     ubyte* kstr, int klen, pem_password_cb* cb, void* u);");
	}

}

version (OPENSSL_NO_BIO) {
	mixin template DECLARE_PEM_read_bio(string name, type) {}
	mixin template DECLARE_PEM_write_bio(string name, type) {}
	mixin template DECLARE_PEM_write_bio_const(string name, type) {}
	mixin template DECLARE_PEM_write_cb_bio(string name, type) {}
} else {
	mixin template DECLARE_PEM_read_bio(string name, type) {
		mixin("type* PEM_read_bio_" ~ name ~ "(BIO* bp, type** x, pem_password_cb* cb, void* u);");
	}

	mixin template DECLARE_PEM_write_bio(string name, type) {
		mixin("int PEM_write_bio_" ~ name ~ "(BIO* bp, type* x);");
	}

	mixin template DECLARE_PEM_write_bio_const(string name, type) {
		mixin("int PEM_write_bio_" ~ name ~ "(BIO* bp, const(type)* x);");
	}

	mixin template DECLARE_PEM_write_cb_bio(string name, type) {
		mixin("int PEM_write_bio_" ~ name ~ "(BIO* bp, type* x, const(EVP_CIPHER)* enc,
		     ubyte* kstr, int klen, pem_password_cb* cb, void* u);");
	}
}

mixin template DECLARE_PEM_write(string name, type) {
	mixin DECLARE_PEM_write_bio!(name, type);
	mixin DECLARE_PEM_write_fp!(name, type);
}

mixin template DECLARE_PEM_write_const(string name, type) {
	mixin DECLARE_PEM_write_bio_const!(name, type);
	mixin DECLARE_PEM_write_fp_const!(name, type);
}

mixin template DECLARE_PEM_write_cb(string name, type) {
	mixin DECLARE_PEM_write_cb_bio!(name, type);
	mixin DECLARE_PEM_write_cb_fp!(name, type);
}

mixin template DECLARE_PEM_read(string name, type) {
	mixin DECLARE_PEM_read_bio!(name, type);
	mixin DECLARE_PEM_read_fp!(name, type);
}

mixin template DECLARE_PEM_rw(string name, type) {
	mixin DECLARE_PEM_read!(name, type);
	mixin DECLARE_PEM_write!(name, type);
}

mixin template DECLARE_PEM_rw_const(string name, type) {
	mixin DECLARE_PEM_read!(name, type);
	mixin DECLARE_PEM_write_const!(name, type);
}

mixin template DECLARE_PEM_rw_cb(string name, type) {
	mixin DECLARE_PEM_read!(name, type);
	mixin DECLARE_PEM_write_cb!(name, type);
}

version (all) {
/* "userdata": new with OpenSSL 0.9.4 */
alias typeof(*(ExternC!(int function(char* buf, int size, int rwflag, void* userdata))).init) pem_password_cb;
} else {
/* OpenSSL 0.9.3, 0.9.3a */
alias typeof(*(ExternC!(int function(char* buf, int size, int rwflag))).init) pem_password_cb;
}

int	PEM_get_EVP_CIPHER_INFO(char* header, EVP_CIPHER_INFO* cipher);
int	PEM_do_header (EVP_CIPHER_INFO* cipher, ubyte* data,c_long* len,
	pem_password_cb* callback,void* u);

version(OPENSSL_NO_BIO) {} else {
int	PEM_read_bio(BIO* bp, char** name, char** header,
		ubyte** data,c_long* len);
int	PEM_write_bio(BIO* bp,const(char)* name,char* hdr,ubyte* data,
		c_long len);
int PEM_bytes_read_bio(ubyte** pdata, c_long* plen, char** pnm, const(char)* name, BIO* bp,
	     pem_password_cb* cb, void* u);
void* 	PEM_ASN1_read_bio(d2i_of_void* d2i, const(char)* name, BIO* bp,
			  void** x, pem_password_cb* cb, void* u);
int	PEM_ASN1_write_bio(i2d_of_void* i2d, const(char)* name,BIO* bp, void* x,
			   const(EVP_CIPHER)* enc,ubyte* kstr,int klen,
			   pem_password_cb* cb, void* u);

STACK_OF!(X509_INFO) *	PEM_X509_INFO_read_bio(BIO* bp, STACK_OF!(X509_INFO) *sk, pem_password_cb* cb, void* u);
int	PEM_X509_INFO_write_bio(BIO* bp,X509_INFO* xi, EVP_CIPHER* enc,
		ubyte* kstr, int klen, pem_password_cb* cd, void* u);
}

int	PEM_read(FILE* fp, char** name, char** header,
		ubyte** data,c_long* len);
int	PEM_write(FILE* fp,char* name,char* hdr,ubyte* data,c_long len);
void*  PEM_ASN1_read(d2i_of_void* d2i, const(char)* name, FILE* fp, void** x,
		      pem_password_cb* cb, void* u);
int	PEM_ASN1_write(i2d_of_void* i2d,const(char)* name,FILE* fp,
		       void* x,const(EVP_CIPHER)* enc,ubyte* kstr,
		       int klen,pem_password_cb* callback, void* u);
STACK_OF!(X509_INFO) *	PEM_X509_INFO_read(FILE* fp, STACK_OF!(X509_INFO) *sk,
	pem_password_cb* cb, void* u);

int	PEM_SealInit(PEM_ENCODE_SEAL_CTX* ctx, EVP_CIPHER* type,
		EVP_MD* md_type, ubyte** ek, int* ekl,
		ubyte* iv, EVP_PKEY** pubk, int npubk);
void	PEM_SealUpdate(PEM_ENCODE_SEAL_CTX* ctx, ubyte* out_, int* outl,
		ubyte* in_, int inl);
int	PEM_SealFinal(PEM_ENCODE_SEAL_CTX* ctx, ubyte* sig,int* sigl,
		ubyte* out_, int* outl, EVP_PKEY* priv);

void    PEM_SignInit(EVP_MD_CTX* ctx, EVP_MD* type);
void    PEM_SignUpdate(EVP_MD_CTX* ctx,ubyte* d,uint cnt);
int	PEM_SignFinal(EVP_MD_CTX* ctx, ubyte* sigret,
		uint* siglen, EVP_PKEY* pkey);

int	PEM_def_callback(char* buf, int num, int w, void* key);
void	PEM_proc_type(char* buf, int type);
void	PEM_dek_info(char* buf, const(char)* type, int len, char* str);


public import deimos.openssl.symhacks;

mixin DECLARE_PEM_rw!("X509", X509);

mixin DECLARE_PEM_rw!("X509_AUX", X509);

mixin DECLARE_PEM_rw!("X509_CERT_PAIR", X509_CERT_PAIR);

mixin DECLARE_PEM_rw!("X509_REQ", X509_REQ);
mixin DECLARE_PEM_write!("X509_REQ_NEW", X509_REQ);

mixin DECLARE_PEM_rw!("X509_CRL", X509_CRL);

mixin DECLARE_PEM_rw!("PKCS7", PKCS7);

mixin DECLARE_PEM_rw!("NETSCAPE_CERT_SEQUENCE", NETSCAPE_CERT_SEQUENCE);

mixin DECLARE_PEM_rw!("PKCS8", X509_SIG);

mixin DECLARE_PEM_rw!("PKCS8_PRIV_KEY_INFO", PKCS8_PRIV_KEY_INFO);

version(OPENSSL_NO_RSA) {} else {
mixin DECLARE_PEM_rw_cb!("RSAPrivateKey", RSA);

mixin DECLARE_PEM_rw_const!("RSAPublicKey", RSA);
mixin DECLARE_PEM_rw!("RSA_PUBKEY", RSA);

}

version(OPENSSL_NO_DSA) {} else {
mixin DECLARE_PEM_rw_cb!("DSAPrivateKey", DSA);

mixin DECLARE_PEM_rw!("DSA_PUBKEY", DSA);

mixin DECLARE_PEM_rw_const!("DSAparams", DSA);

}

version(OPENSSL_NO_EC) {} else {
mixin DECLARE_PEM_rw_const!("ECPKParameters", EC_GROUP);
mixin DECLARE_PEM_rw_cb!("ECPrivateKey", EC_KEY);
mixin DECLARE_PEM_rw!("EC_PUBKEY", EC_KEY);
}

version(OPENSSL_NO_DH) {} else {
mixin DECLARE_PEM_rw_const!("DHparams", DH);

}

mixin DECLARE_PEM_rw_cb!("PrivateKey", EVP_PKEY);

mixin DECLARE_PEM_rw!("PUBKEY", EVP_PKEY);

int PEM_write_bio_PKCS8PrivateKey_nid(BIO* bp, EVP_PKEY* x, int nid,
				  char* kstr, int klen,
				  pem_password_cb* cb, void* u);
int PEM_write_bio_PKCS8PrivateKey(BIO*, EVP_PKEY*, const(EVP_CIPHER)*,
                                  char*, int, pem_password_cb*, void*);
int i2d_PKCS8PrivateKey_bio(BIO* bp, EVP_PKEY* x, const(EVP_CIPHER)* enc,
				  char* kstr, int klen,
				  pem_password_cb* cb, void* u);
int i2d_PKCS8PrivateKey_nid_bio(BIO* bp, EVP_PKEY* x, int nid,
				  char* kstr, int klen,
				  pem_password_cb* cb, void* u);
EVP_PKEY* d2i_PKCS8PrivateKey_bio(BIO* bp, EVP_PKEY** x, pem_password_cb* cb, void* u);

int i2d_PKCS8PrivateKey_fp(FILE* fp, EVP_PKEY* x, const(EVP_CIPHER)* enc,
				  char* kstr, int klen,
				  pem_password_cb* cb, void* u);
int i2d_PKCS8PrivateKey_nid_fp(FILE* fp, EVP_PKEY* x, int nid,
				  char* kstr, int klen,
				  pem_password_cb* cb, void* u);
int PEM_write_PKCS8PrivateKey_nid(FILE* fp, EVP_PKEY* x, int nid,
				  char* kstr, int klen,
				  pem_password_cb* cb, void* u);

EVP_PKEY* d2i_PKCS8PrivateKey_fp(FILE* fp, EVP_PKEY** x, pem_password_cb* cb, void* u);

int PEM_write_PKCS8PrivateKey(FILE* fp,EVP_PKEY* x,const(EVP_CIPHER)* enc,
			      char* kstr,int klen, pem_password_cb* cd, void* u);

EVP_PKEY* PEM_read_bio_Parameters(BIO* bp, EVP_PKEY** x);
int PEM_write_bio_Parameters(BIO* bp, EVP_PKEY* x);


EVP_PKEY* b2i_PrivateKey(const(ubyte)** in_, c_long length);
EVP_PKEY* b2i_PublicKey(const(ubyte)** in_, c_long length);
EVP_PKEY* b2i_PrivateKey_bio(BIO* in_);
EVP_PKEY* b2i_PublicKey_bio(BIO* in_);
int i2b_PrivateKey_bio(BIO* out_, EVP_PKEY* pk);
int i2b_PublicKey_bio(BIO* out_, EVP_PKEY* pk);
version(OPENSSL_NO_RC4) {} else {
EVP_PKEY* b2i_PVK_bio(BIO* in_, pem_password_cb* cb, void* u);
int i2b_PVK_bio(BIO* out_, EVP_PKEY* pk, int enclevel,
		pem_password_cb* cb, void* u);
}


/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
void ERR_load_PEM_strings();

/* Error codes for the PEM functions. */

/* Function codes. */
enum PEM_F_B2I_DSS = 127;
enum PEM_F_B2I_PVK_BIO = 128;
enum PEM_F_B2I_RSA = 129;
enum PEM_F_CHECK_BITLEN_DSA = 130;
enum PEM_F_CHECK_BITLEN_RSA = 131;
enum PEM_F_D2I_PKCS8PRIVATEKEY_BIO = 120;
enum PEM_F_D2I_PKCS8PRIVATEKEY_FP = 121;
enum PEM_F_DO_B2I = 132;
enum PEM_F_DO_B2I_BIO = 133;
enum PEM_F_DO_BLOB_HEADER = 134;
enum PEM_F_DO_PK8PKEY = 126;
enum PEM_F_DO_PK8PKEY_FP = 125;
enum PEM_F_DO_PVK_BODY = 135;
enum PEM_F_DO_PVK_HEADER = 136;
enum PEM_F_I2B_PVK = 137;
enum PEM_F_I2B_PVK_BIO = 138;
enum PEM_F_LOAD_IV = 101;
enum PEM_F_PEM_ASN1_READ = 102;
enum PEM_F_PEM_ASN1_READ_BIO = 103;
enum PEM_F_PEM_ASN1_WRITE = 104;
enum PEM_F_PEM_ASN1_WRITE_BIO = 105;
enum PEM_F_PEM_DEF_CALLBACK = 100;
enum PEM_F_PEM_DO_HEADER = 106;
enum PEM_F_PEM_F_PEM_WRITE_PKCS8PRIVATEKEY = 118;
enum PEM_F_PEM_GET_EVP_CIPHER_INFO = 107;
enum PEM_F_PEM_PK8PKEY = 119;
enum PEM_F_PEM_READ = 108;
enum PEM_F_PEM_READ_BIO = 109;
enum PEM_F_PEM_READ_BIO_PARAMETERS = 140;
enum PEM_F_PEM_READ_BIO_PRIVATEKEY = 123;
enum PEM_F_PEM_READ_PRIVATEKEY = 124;
enum PEM_F_PEM_SEALFINAL = 110;
enum PEM_F_PEM_SEALINIT = 111;
enum PEM_F_PEM_SIGNFINAL = 112;
enum PEM_F_PEM_WRITE = 113;
enum PEM_F_PEM_WRITE_BIO = 114;
enum PEM_F_PEM_WRITE_PRIVATEKEY = 139;
enum PEM_F_PEM_X509_INFO_READ = 115;
enum PEM_F_PEM_X509_INFO_READ_BIO = 116;
enum PEM_F_PEM_X509_INFO_WRITE_BIO = 117;

/* Reason codes. */
enum PEM_R_BAD_BASE64_DECODE = 100;
enum PEM_R_BAD_DECRYPT = 101;
enum PEM_R_BAD_END_LINE = 102;
enum PEM_R_BAD_IV_CHARS = 103;
enum PEM_R_BAD_MAGIC_NUMBER = 116;
enum PEM_R_BAD_PASSWORD_READ = 104;
enum PEM_R_BAD_VERSION_NUMBER = 117;
enum PEM_R_BIO_WRITE_FAILURE = 118;
enum PEM_R_CIPHER_IS_NULL = 127;
enum PEM_R_ERROR_CONVERTING_PRIVATE_KEY = 115;
enum PEM_R_EXPECTING_PRIVATE_KEY_BLOB = 119;
enum PEM_R_EXPECTING_PUBLIC_KEY_BLOB = 120;
enum PEM_R_INCONSISTENT_HEADER = 121;
enum PEM_R_KEYBLOB_HEADER_PARSE_ERROR = 122;
enum PEM_R_KEYBLOB_TOO_SHORT = 123;
enum PEM_R_NOT_DEK_INFO = 105;
enum PEM_R_NOT_ENCRYPTED = 106;
enum PEM_R_NOT_PROC_TYPE = 107;
enum PEM_R_NO_START_LINE = 108;
enum PEM_R_PROBLEMS_GETTING_PASSWORD = 109;
enum PEM_R_PUBLIC_KEY_NO_RSA = 110;
enum PEM_R_PVK_DATA_TOO_SHORT = 124;
enum PEM_R_PVK_TOO_SHORT = 125;
enum PEM_R_READ_KEY = 111;
enum PEM_R_SHORT_HEADER = 112;
enum PEM_R_UNSUPPORTED_CIPHER = 113;
enum PEM_R_UNSUPPORTED_ENCRYPTION = 114;
enum PEM_R_UNSUPPORTED_KEY_COMPONENTS = 126;
