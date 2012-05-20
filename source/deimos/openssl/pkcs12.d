/* pkcs12.h */
/* Written by Dr Stephen N Henson (steve@openssl.org) for the OpenSSL
 * project 1999.
 */
/* ====================================================================
 * Copyright (c) 1999 The OpenSSL Project.  All rights reserved.
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
 *   for use in the OpenSSL Toolkit. (http://www.OpenSSL.org/)"
 *
 * 4. The names "OpenSSL Toolkit" and "OpenSSL Project" must not be used to
 *   endorse or promote products derived from this software without
 *   prior written permission. For written permission, please contact
 *   licensing@OpenSSL.org.
 *
 * 5. Products derived from this software may not be called "OpenSSL"
 *   nor may "OpenSSL" appear in their names without prior written
 *   permission of the OpenSSL Project.
 *
 * 6. Redistributions of any form whatsoever must retain the following
 *   acknowledgment:
 *   "This product includes software developed by the OpenSSL Project
 *   for use in the OpenSSL Toolkit (http://www.OpenSSL.org/)"
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

module deimos.openssl.pkcs12;

import deimos.openssl._d_util;

public import deimos.openssl.bio;
public import deimos.openssl.x509;
public import deimos.openssl.pkcs7;

extern (C):
nothrow:

enum PKCS12_KEY_ID = 1;
enum PKCS12_IV_ID = 2;
enum PKCS12_MAC_ID = 3;

/* Default iteration count */
// #ifndef PKCS12_DEFAULT_ITER
alias PKCS5_DEFAULT_ITER PKCS12_DEFAULT_ITER;
// #endif

enum PKCS12_MAC_KEY_LENGTH = 20;

enum PKCS12_SALT_LEN = 8;

/* Uncomment out next line for unicode password and names, otherwise ASCII */

/*#define PBE_UNICODE*/

version (PBE_UNICODE) {
alias PKCS12_key_gen_uni PKCS12_key_gen;
alias PKCS12_add_friendlyname_uni PKCS12_add_friendlyname;
} else {
alias PKCS12_key_gen_asc PKCS12_key_gen;
alias PKCS12_add_friendlyname_asc PKCS12_add_friendlyname;
}

/* MS key usage constants */

enum KEY_EX = 0x10;
enum KEY_SIG = 0x80;

struct PKCS12_MAC_DATA {
X509_SIG* dinfo;
ASN1_OCTET_STRING* salt;
ASN1_INTEGER* iter;	/* defaults to 1 */
}

struct PKCS12 {
ASN1_INTEGER* version_;
PKCS12_MAC_DATA* mac;
PKCS7* authsafes;
}

struct PKCS12_SAFEBAG {
ASN1_OBJECT* type;
union value_ {
	pkcs12_bag_st* bag; /* secret, crl and certbag */
	pkcs8_priv_key_info_st* keybag; /* keybag */
	X509_SIG* shkeybag; /* shrouded key bag */
	STACK_OF!(PKCS12_SAFEBAG) *safes;
	ASN1_TYPE* other;
}
value_ value;
STACK_OF!(X509_ATTRIBUTE) *attrib;
}

/+mixin DECLARE_STACK_OF!(PKCS12_SAFEBAG);+/
mixin DECLARE_ASN1_SET_OF!(PKCS12_SAFEBAG);
mixin DECLARE_PKCS12_STACK_OF!(PKCS12_SAFEBAG);

struct pkcs12_bag_st {
ASN1_OBJECT* type;
union value_ {
	ASN1_OCTET_STRING* x509cert;
	ASN1_OCTET_STRING* x509crl;
	ASN1_OCTET_STRING* octet;
	ASN1_IA5STRING* sdsicert;
	ASN1_TYPE* other; /* Secret or other bag */
}
value_ value;
}
alias pkcs12_bag_st PKCS12_BAGS;

enum PKCS12_ERROR = 0;
enum PKCS12_OK = 1;

/* Compatibility macros */

alias PKCS12_x5092certbag M_PKCS12_x5092certbag;
alias PKCS12_x509crl2certbag M_PKCS12_x509crl2certbag;

alias PKCS12_certbag2x509 M_PKCS12_certbag2x509;
alias PKCS12_certbag2x509crl M_PKCS12_certbag2x509crl;

alias PKCS12_unpack_p7data M_PKCS12_unpack_p7data;
alias PKCS12_pack_authsafes M_PKCS12_pack_authsafes;
alias PKCS12_unpack_authsafes M_PKCS12_unpack_authsafes;
alias PKCS12_unpack_p7encdata M_PKCS12_unpack_p7encdata;

alias PKCS12_decrypt_skey M_PKCS12_decrypt_skey;
alias PKCS8_decrypt M_PKCS8_decrypt;

auto M_PKCS12_bag_type(B)(B bg) {return OBJ_obj2nid(bg.type); }
auto M_PKCS12_cert_bag_type(B)(B bg) {return OBJ_obj2nid(bg.value.bag.type); }
alias M_PKCS12_cert_bag_type M_PKCS12_crl_bag_type;

auto PKCS12_get_attr()(PKCS12_SAFEBAG* bag, int attr_nid) {
			 return PKCS12_get_attr_gen(bag.attrib, attr_nid); }

auto PKCS8_get_attr(P)(P p8, int attr_nid) {
		return PKCS12_get_attr_gen(p8.attributes, attr_nid);}

auto PKCS12_mac_present()(PKCS12* p12) { return p12.mac ? 1 : 0; }


PKCS12_SAFEBAG* PKCS12_x5092certbag(X509* x509);
PKCS12_SAFEBAG* PKCS12_x509crl2certbag(X509_CRL* crl);
X509* PKCS12_certbag2x509(PKCS12_SAFEBAG* bag);
X509_CRL* PKCS12_certbag2x509crl(PKCS12_SAFEBAG* bag);

PKCS12_SAFEBAG* PKCS12_item_pack_safebag(void* obj, const(ASN1_ITEM)* it, int nid1,
	     int nid2);
PKCS12_SAFEBAG* PKCS12_MAKE_KEYBAG(PKCS8_PRIV_KEY_INFO* p8);
PKCS8_PRIV_KEY_INFO* PKCS8_decrypt(X509_SIG* p8, const(char)* pass, int passlen);
PKCS8_PRIV_KEY_INFO* PKCS12_decrypt_skey(PKCS12_SAFEBAG* bag, const(char)* pass,
								int passlen);
X509_SIG* PKCS8_encrypt(int pbe_nid, const(EVP_CIPHER)* cipher,
			const(char)* pass, int passlen,
			ubyte* salt, int saltlen, int iter,
			PKCS8_PRIV_KEY_INFO* p8);
PKCS12_SAFEBAG* PKCS12_MAKE_SHKEYBAG(int pbe_nid, const(char)* pass,
				     int passlen, ubyte* salt,
				     int saltlen, int iter,
				     PKCS8_PRIV_KEY_INFO* p8);
PKCS7* PKCS12_pack_p7data(STACK_OF!(PKCS12_SAFEBAG) *sk);
STACK_OF!(PKCS12_SAFEBAG) *PKCS12_unpack_p7data(PKCS7* p7);
PKCS7* PKCS12_pack_p7encdata(int pbe_nid, const(char)* pass, int passlen,
			     ubyte* salt, int saltlen, int iter,
			     STACK_OF!(PKCS12_SAFEBAG) *bags);
STACK_OF!(PKCS12_SAFEBAG) *PKCS12_unpack_p7encdata(PKCS7* p7, const(char)* pass, int passlen);

int PKCS12_pack_authsafes(PKCS12* p12, STACK_OF!(PKCS7) *safes);
STACK_OF!(PKCS7) *PKCS12_unpack_authsafes(PKCS12* p12);

int PKCS12_add_localkeyid(PKCS12_SAFEBAG* bag, ubyte* name, int namelen);
int PKCS12_add_friendlyname_asc(PKCS12_SAFEBAG* bag, const(char)* name,
				int namelen);
int PKCS12_add_CSPName_asc(PKCS12_SAFEBAG* bag, const(char)* name,
				int namelen);
int PKCS12_add_friendlyname_uni(PKCS12_SAFEBAG* bag, const(ubyte)* name,
				int namelen);
int PKCS8_add_keyusage(PKCS8_PRIV_KEY_INFO* p8, int usage);
ASN1_TYPE* PKCS12_get_attr_gen(STACK_OF!(X509_ATTRIBUTE) *attrs, int attr_nid);
char* PKCS12_get_friendlyname(PKCS12_SAFEBAG* bag);
ubyte* PKCS12_pbe_crypt(X509_ALGOR* algor, const(char)* pass,
				int passlen, ubyte* in_, int inlen,
				ubyte** data, int* datalen, int en_de);
void* PKCS12_item_decrypt_d2i(X509_ALGOR* algor, const(ASN1_ITEM)* it,
	     const(char)* pass, int passlen, ASN1_OCTET_STRING* oct, int zbuf);
ASN1_OCTET_STRING* PKCS12_item_i2d_encrypt(X509_ALGOR* algor, const(ASN1_ITEM)* it,
				       const(char)* pass, int passlen,
				       void* obj, int zbuf);
PKCS12* PKCS12_init(int mode);
int PKCS12_key_gen_asc(const(char)* pass, int passlen, ubyte* salt,
		       int saltlen, int id, int iter, int n,
		       ubyte* out_, const(EVP_MD)* md_type);
int PKCS12_key_gen_uni(ubyte* pass, int passlen, ubyte* salt, int saltlen, int id, int iter, int n, ubyte* out_, const(EVP_MD)* md_type);
int PKCS12_PBE_keyivgen(EVP_CIPHER_CTX* ctx, const(char)* pass, int passlen,
			 ASN1_TYPE* param, const(EVP_CIPHER)* cipher, const(EVP_MD)* md_type,
			 int en_de);
int PKCS12_gen_mac(PKCS12* p12, const(char)* pass, int passlen,
			 ubyte* mac, uint* maclen);
int PKCS12_verify_mac(PKCS12* p12, const(char)* pass, int passlen);
int PKCS12_set_mac(PKCS12* p12, const(char)* pass, int passlen,
		   ubyte* salt, int saltlen, int iter,
		   const(EVP_MD)* md_type);
int PKCS12_setup_mac(PKCS12* p12, int iter, ubyte* salt,
					 int saltlen, const(EVP_MD)* md_type);
ubyte* OPENSSL_asc2uni(const(char)* asc, int asclen, ubyte** uni, int* unilen);
char* OPENSSL_uni2asc(ubyte* uni, int unilen);

mixin(DECLARE_ASN1_FUNCTIONS!"PKCS12");
mixin(DECLARE_ASN1_FUNCTIONS!"PKCS12_MAC_DATA");
mixin(DECLARE_ASN1_FUNCTIONS!"PKCS12_SAFEBAG");
mixin(DECLARE_ASN1_FUNCTIONS!"PKCS12_BAGS");

mixin(DECLARE_ASN1_ITEM!"PKCS12_SAFEBAGS");
mixin(DECLARE_ASN1_ITEM!"PKCS12_AUTHSAFES");

void PKCS12_PBE_add();
int PKCS12_parse(PKCS12* p12, const(char)* pass, EVP_PKEY** pkey, X509** cert,
		 STACK_OF!(X509) **ca);
PKCS12* PKCS12_create(char* pass, char* name, EVP_PKEY* pkey, X509* cert,
			 STACK_OF!(X509) *ca, int nid_key, int nid_cert, int iter,
						 int mac_iter, int keytype);

PKCS12_SAFEBAG* PKCS12_add_cert(STACK_OF!(PKCS12_SAFEBAG) **pbags, X509* cert);
PKCS12_SAFEBAG* PKCS12_add_key(STACK_OF!(PKCS12_SAFEBAG) **pbags, EVP_PKEY* key,
						int key_usage, int iter,
						int key_nid, char* pass);
int PKCS12_add_safe(STACK_OF!(PKCS7) **psafes, STACK_OF!(PKCS12_SAFEBAG) *bags,
					int safe_nid, int iter, char* pass);
PKCS12* PKCS12_add_safes(STACK_OF!(PKCS7) *safes, int p7_nid);

int i2d_PKCS12_bio(BIO* bp, PKCS12* p12);
int i2d_PKCS12_fp(FILE* fp, PKCS12* p12);
PKCS12* d2i_PKCS12_bio(BIO* bp, PKCS12** p12);
PKCS12* d2i_PKCS12_fp(FILE* fp, PKCS12** p12);
int PKCS12_newpass(PKCS12* p12, char* oldpass, char* newpass);

/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
void ERR_load_PKCS12_strings();

/* Error codes for the PKCS12 functions. */

/* Function codes. */
enum PKCS12_F_PARSE_BAG = 129;
enum PKCS12_F_PARSE_BAGS = 103;
enum PKCS12_F_PKCS12_ADD_FRIENDLYNAME = 100;
enum PKCS12_F_PKCS12_ADD_FRIENDLYNAME_ASC = 127;
enum PKCS12_F_PKCS12_ADD_FRIENDLYNAME_UNI = 102;
enum PKCS12_F_PKCS12_ADD_LOCALKEYID = 104;
enum PKCS12_F_PKCS12_CREATE = 105;
enum PKCS12_F_PKCS12_GEN_MAC = 107;
enum PKCS12_F_PKCS12_INIT = 109;
enum PKCS12_F_PKCS12_ITEM_DECRYPT_D2I = 106;
enum PKCS12_F_PKCS12_ITEM_I2D_ENCRYPT = 108;
enum PKCS12_F_PKCS12_ITEM_PACK_SAFEBAG = 117;
enum PKCS12_F_PKCS12_KEY_GEN_ASC = 110;
enum PKCS12_F_PKCS12_KEY_GEN_UNI = 111;
enum PKCS12_F_PKCS12_MAKE_KEYBAG = 112;
enum PKCS12_F_PKCS12_MAKE_SHKEYBAG = 113;
enum PKCS12_F_PKCS12_NEWPASS = 128;
enum PKCS12_F_PKCS12_PACK_P7DATA = 114;
enum PKCS12_F_PKCS12_PACK_P7ENCDATA = 115;
enum PKCS12_F_PKCS12_PARSE = 118;
enum PKCS12_F_PKCS12_PBE_CRYPT = 119;
enum PKCS12_F_PKCS12_PBE_KEYIVGEN = 120;
enum PKCS12_F_PKCS12_SETUP_MAC = 122;
enum PKCS12_F_PKCS12_SET_MAC = 123;
enum PKCS12_F_PKCS12_UNPACK_AUTHSAFES = 130;
enum PKCS12_F_PKCS12_UNPACK_P7DATA = 131;
enum PKCS12_F_PKCS12_VERIFY_MAC = 126;
enum PKCS12_F_PKCS8_ADD_KEYUSAGE = 124;
enum PKCS12_F_PKCS8_ENCRYPT = 125;

/* Reason codes. */
enum PKCS12_R_CANT_PACK_STRUCTURE = 100;
enum PKCS12_R_CONTENT_TYPE_NOT_DATA = 121;
enum PKCS12_R_DECODE_ERROR = 101;
enum PKCS12_R_ENCODE_ERROR = 102;
enum PKCS12_R_ENCRYPT_ERROR = 103;
enum PKCS12_R_ERROR_SETTING_ENCRYPTED_DATA_TYPE = 120;
enum PKCS12_R_INVALID_NULL_ARGUMENT = 104;
enum PKCS12_R_INVALID_NULL_PKCS12_POINTER = 105;
enum PKCS12_R_IV_GEN_ERROR = 106;
enum PKCS12_R_KEY_GEN_ERROR = 107;
enum PKCS12_R_MAC_ABSENT = 108;
enum PKCS12_R_MAC_GENERATION_ERROR = 109;
enum PKCS12_R_MAC_SETUP_ERROR = 110;
enum PKCS12_R_MAC_STRING_SET_ERROR = 111;
enum PKCS12_R_MAC_VERIFY_ERROR = 112;
enum PKCS12_R_MAC_VERIFY_FAILURE = 113;
enum PKCS12_R_PARSE_ERROR = 114;
enum PKCS12_R_PKCS12_ALGOR_CIPHERINIT_ERROR = 115;
enum PKCS12_R_PKCS12_CIPHERFINAL_ERROR = 116;
enum PKCS12_R_PKCS12_PBE_CRYPT_ERROR = 117;
enum PKCS12_R_UNKNOWN_DIGEST_ALGORITHM = 118;
enum PKCS12_R_UNSUPPORTED_PKCS12_MODE = 119;
