/* x509v3.h */
/* Written by Dr Stephen N Henson (steve@openssl.org) for the OpenSSL
 * project 1999.
 */
/* ====================================================================
 * Copyright (c) 1999-2004 The OpenSSL Project.  All rights reserved.
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
module deimos.openssl.x509v3;

import deimos.openssl._d_util;

public import deimos.openssl.bio;
public import deimos.openssl.x509;
public import deimos.openssl.conf;

extern (C):
nothrow:

/* Forward reference */
// struct v3_ext_method;
// struct v3_ext_ctx;

/* Useful typedefs */

alias ExternC!(void*function()) X509V3_EXT_NEW;
alias ExternC!(void function(void*)) X509V3_EXT_FREE;
alias ExternC!(void*function(void*, const(ubyte)** , c_long)) X509V3_EXT_D2I;
alias ExternC!(int function(void*, ubyte**)) X509V3_EXT_I2D;
alias ExternC!(STACK_OF!(CONF_VALUE)* function(const(v3_ext_method)* method, void* ext,
		    STACK_OF!(CONF_VALUE) *extlist)) X509V3_EXT_I2V;
alias ExternC!(void*function(const(v3_ext_method)* method,
				 v3_ext_ctx* ctx,
				 STACK_OF!(CONF_VALUE) *values)) X509V3_EXT_V2I;
alias ExternC!(char*function(const(v3_ext_method)* method, void* ext)) X509V3_EXT_I2S;
alias ExternC!(void*function(const(v3_ext_method)* method,
				 v3_ext_ctx* ctx, const(char)* str)) X509V3_EXT_S2I;
alias ExternC!(int function(const(v3_ext_method)* method, void* ext,
			      BIO* out_, int indent)) X509V3_EXT_I2R;
alias ExternC!(void*function(const(v3_ext_method)* method,
				 v3_ext_ctx* ctx, const(char)* str)) X509V3_EXT_R2I;

/* V3 extension structure */

struct v3_ext_method {
int ext_nid;
int ext_flags;
/* If this is set the following four fields are ignored */
ASN1_ITEM_EXP* it;
/* Old style ASN1 calls */
X509V3_EXT_NEW ext_new;
X509V3_EXT_FREE ext_free;
X509V3_EXT_D2I d2i;
X509V3_EXT_I2D i2d;

/* The following pair is used for string extensions */
X509V3_EXT_I2S i2s;
X509V3_EXT_S2I s2i;

/* The following pair is used for multi-valued extensions */
X509V3_EXT_I2V i2v;
X509V3_EXT_V2I v2i;

/* The following are used for raw extensions */
X509V3_EXT_I2R i2r;
X509V3_EXT_R2I r2i;

void* usr_data;	/* Any extension specific data */
};

struct X509V3_CONF_METHOD_st {
ExternC!(char* function(void* db, char* section, char* value)) get_string;
ExternC!(STACK_OF!(CONF_VALUE)* function(void* db, char* section)) get_section;
ExternC!(void function(void* db, char* string)) free_string;
ExternC!(void function(void* db, STACK_OF!(CONF_VALUE) *section)) free_section;
}
alias X509V3_CONF_METHOD_st X509V3_CONF_METHOD;

/* Context specific info */
struct v3_ext_ctx {
enum CTX_TEST = 0x1;
int flags;
X509* issuer_cert;
X509* subject_cert;
X509_REQ* subject_req;
X509_CRL* crl;
X509V3_CONF_METHOD* db_meth;
void* db;
/* Maybe more here */
};

alias v3_ext_method X509V3_EXT_METHOD;

/+mixin DECLARE_STACK_OF!(X509V3_EXT_METHOD);+/

/* ext_flags values */
enum X509V3_EXT_DYNAMIC = 0x1;
enum X509V3_EXT_CTX_DEP = 0x2;
enum X509V3_EXT_MULTILINE = 0x4;

alias BIT_STRING_BITNAME ENUMERATED_NAMES;

struct BASIC_CONSTRAINTS_st {
int ca;
ASN1_INTEGER* pathlen;
}
alias BASIC_CONSTRAINTS_st BASIC_CONSTRAINTS;


struct PKEY_USAGE_PERIOD_st {
ASN1_GENERALIZEDTIME* notBefore;
ASN1_GENERALIZEDTIME* notAfter;
}
alias PKEY_USAGE_PERIOD_st PKEY_USAGE_PERIOD;

struct otherName_st {
ASN1_OBJECT* type_id;
ASN1_TYPE* value;
}
alias otherName_st OTHERNAME;

struct EDIPartyName_st {
	ASN1_STRING* nameAssigner;
	ASN1_STRING* partyName;
}
alias EDIPartyName_st EDIPARTYNAME;

struct GENERAL_NAME_st {

enum GEN_OTHERNAME = 0;
enum GEN_EMAIL = 1;
enum GEN_DNS = 2;
enum GEN_X400 = 3;
enum GEN_DIRNAME = 4;
enum GEN_EDIPARTY = 5;
enum GEN_URI = 6;
enum GEN_IPADD = 7;
enum GEN_RID = 8;

int type;
union d_ {
	char* ptr;
	OTHERNAME* otherName; /* otherName */
	ASN1_IA5STRING* rfc822Name;
	ASN1_IA5STRING* dNSName;
	ASN1_TYPE* x400Address;
	X509_NAME* directoryName;
	EDIPARTYNAME* ediPartyName;
	ASN1_IA5STRING* uniformResourceIdentifier;
	ASN1_OCTET_STRING* iPAddress;
	ASN1_OBJECT* registeredID;

	/* Old names */
	ASN1_OCTET_STRING* ip; /* iPAddress */
	X509_NAME* dirn;		/* dirn */
	ASN1_IA5STRING* ia5;/* rfc822Name, dNSName, uniformResourceIdentifier */
	ASN1_OBJECT* rid; /* registeredID */
	ASN1_TYPE* other; /* x400Address */
}
d_ d;
}
alias GENERAL_NAME_st GENERAL_NAME;

alias STACK_OF!(GENERAL_NAME) GENERAL_NAMES;

struct ACCESS_DESCRIPTION_st {
	ASN1_OBJECT* method;
	GENERAL_NAME* location;
}
alias ACCESS_DESCRIPTION_st ACCESS_DESCRIPTION;

alias STACK_OF!(ACCESS_DESCRIPTION) AUTHORITY_INFO_ACCESS;

alias STACK_OF!(ASN1_OBJECT) EXTENDED_KEY_USAGE;

/+mixin DECLARE_STACK_OF!(GENERAL_NAME);+/
mixin DECLARE_ASN1_SET_OF!(GENERAL_NAME);

/+mixin DECLARE_STACK_OF!(ACCESS_DESCRIPTION);+/
mixin DECLARE_ASN1_SET_OF!(ACCESS_DESCRIPTION);

struct DIST_POINT_NAME_st {
int type;
union name_ {
	GENERAL_NAMES* fullname;
	STACK_OF!(X509_NAME_ENTRY) *relativename;
}
name_ name;
/* If relativename then this contains the full distribution point name */
X509_NAME* dpname;
}
alias DIST_POINT_NAME_st DIST_POINT_NAME;
/* All existing reasons */
enum CRLDP_ALL_REASONS = 0x807f;

enum CRL_REASON_NONE = -1;
enum CRL_REASON_UNSPECIFIED = 0;
enum CRL_REASON_KEY_COMPROMISE = 1;
enum CRL_REASON_CA_COMPROMISE = 2;
enum CRL_REASON_AFFILIATION_CHANGED = 3;
enum CRL_REASON_SUPERSEDED = 4;
enum CRL_REASON_CESSATION_OF_OPERATION = 5;
enum CRL_REASON_CERTIFICATE_HOLD = 6;
enum CRL_REASON_REMOVE_FROM_CRL = 8;
enum CRL_REASON_PRIVILEGE_WITHDRAWN = 9;
enum CRL_REASON_AA_COMPROMISE = 10;

struct DIST_POINT_st {
DIST_POINT_NAME* distpoint;
ASN1_BIT_STRING* reasons;
GENERAL_NAMES* CRLissuer;
int dp_reasons;
};

alias STACK_OF!(DIST_POINT) CRL_DIST_POINTS;

/+mixin DECLARE_STACK_OF!(DIST_POINT);+/
mixin DECLARE_ASN1_SET_OF!(DIST_POINT);

struct AUTHORITY_KEYID_st {
ASN1_OCTET_STRING* keyid;
GENERAL_NAMES* issuer;
ASN1_INTEGER* serial;
};

/* Strong extranet structures */

struct SXNET_ID_st {
	ASN1_INTEGER* zone;
	ASN1_OCTET_STRING* user;
}
alias SXNET_ID_st SXNETID;

/+mixin DECLARE_STACK_OF!(SXNETID);+/
mixin DECLARE_ASN1_SET_OF!(SXNETID);

struct SXNET_st {
	ASN1_INTEGER* version_;
	STACK_OF!(SXNETID) *ids;
}
alias SXNET_st SXNET;

struct NOTICEREF_st {
	ASN1_STRING* organization;
	STACK_OF!(ASN1_INTEGER) *noticenos;
}
alias NOTICEREF_st NOTICEREF;

struct USERNOTICE_st {
	NOTICEREF* noticeref;
	ASN1_STRING* exptext;
}
alias USERNOTICE_st USERNOTICE;

struct POLICYQUALINFO_st {
	ASN1_OBJECT* pqualid;
	union d_ {
		ASN1_IA5STRING* cpsuri;
		USERNOTICE* usernotice;
		ASN1_TYPE* other;
	}
	d_ d;
}
alias POLICYQUALINFO_st POLICYQUALINFO;

/+mixin DECLARE_STACK_OF!(POLICYQUALINFO);+/
mixin DECLARE_ASN1_SET_OF!(POLICYQUALINFO);

struct POLICYINFO_st {
	ASN1_OBJECT* policyid;
	STACK_OF!(POLICYQUALINFO) *qualifiers;
}
alias POLICYINFO_st POLICYINFO;

alias STACK_OF!(POLICYINFO) CERTIFICATEPOLICIES;

/+mixin DECLARE_STACK_OF!(POLICYINFO);+/
mixin DECLARE_ASN1_SET_OF!(POLICYINFO);

struct POLICY_MAPPING_st {
	ASN1_OBJECT* issuerDomainPolicy;
	ASN1_OBJECT* subjectDomainPolicy;
}
alias POLICY_MAPPING_st POLICY_MAPPING;

/+mixin DECLARE_STACK_OF!(POLICY_MAPPING);+/

alias STACK_OF!(POLICY_MAPPING) POLICY_MAPPINGS;

struct GENERAL_SUBTREE_st {
	GENERAL_NAME* base;
	ASN1_INTEGER* minimum;
	ASN1_INTEGER* maximum;
}
alias GENERAL_SUBTREE_st GENERAL_SUBTREE;

/+mixin DECLARE_STACK_OF!(GENERAL_SUBTREE);+/

struct NAME_CONSTRAINTS_st {
	STACK_OF!(GENERAL_SUBTREE) *permittedSubtrees;
	STACK_OF!(GENERAL_SUBTREE) *excludedSubtrees;
};

struct POLICY_CONSTRAINTS_st {
	ASN1_INTEGER* requireExplicitPolicy;
	ASN1_INTEGER* inhibitPolicyMapping;
}
alias POLICY_CONSTRAINTS_st POLICY_CONSTRAINTS;

/* Proxy certificate structures, see RFC 3820 */
struct PROXY_POLICY_st {
	ASN1_OBJECT* policyLanguage;
	ASN1_OCTET_STRING* policy;
	}
alias PROXY_POLICY_st PROXY_POLICY;

struct PROXY_CERT_INFO_EXTENSION_st {
	ASN1_INTEGER* pcPathLengthConstraint;
	PROXY_POLICY* proxyPolicy;
	}
alias PROXY_CERT_INFO_EXTENSION_st PROXY_CERT_INFO_EXTENSION;

mixin(DECLARE_ASN1_FUNCTIONS!"PROXY_POLICY");
mixin(DECLARE_ASN1_FUNCTIONS!"PROXY_CERT_INFO_EXTENSION");

struct ISSUING_DIST_POINT_st
	{
	DIST_POINT_NAME* distpoint;
	int onlyuser;
	int onlyCA;
	ASN1_BIT_STRING* onlysomereasons;
	int indirectCRL;
	int onlyattr;
	};

/* Values in idp_flags field */
/* IDP present */
enum IDP_PRESENT = 0x1;
/* IDP values inconsistent */
enum IDP_INVALID = 0x2;
/* onlyuser true */
enum IDP_ONLYUSER = 0x4;
/* onlyCA true */
enum IDP_ONLYCA = 0x8;
/* onlyattr true */
enum IDP_ONLYATTR = 0x10;
/* indirectCRL true */
enum IDP_INDIRECT = 0x20;
/* onlysomereasons present */
enum IDP_REASONS = 0x40;

auto X509V3_conf_err()(CONF_VALUE* val) {
	return ERR_add_error_data(6, "section:", val.section,
		",name:", val.name, ",value:", val.value);
}

auto X509V3_set_ctx_test()(X509V3_CTX* ctx) {
	return X509V3_set_ctx(ctx, null, null, null, null, CTX_TEST);
}

void X509V3_set_ctx_nodb()(X509V3_CTX* ctx) { ctx.db = null; }

/+ FIXME: Not yet ported.
#define EXT_BITSTRING(nid, table) { nid, 0, ASN1_ITEM_ref(ASN1_BIT_STRING), \
			0,0,0,0, \
			0,0, \
			(X509V3_EXT_I2V)i2v_ASN1_BIT_STRING, \
			(X509V3_EXT_V2I)v2i_ASN1_BIT_STRING, \
			NULL, NULL, \
			table}

#define EXT_IA5STRING(nid) { nid, 0, ASN1_ITEM_ref(ASN1_IA5STRING), \
			0,0,0,0, \
			(X509V3_EXT_I2S)i2s_ASN1_IA5STRING, \
			(X509V3_EXT_S2I)s2i_ASN1_IA5STRING, \
			0,0,0,0, \
			NULL}

#define EXT_END { -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
+/


/* X509_PURPOSE stuff */

enum EXFLAG_BCONS = 0x1;
enum EXFLAG_KUSAGE = 0x2;
enum EXFLAG_XKUSAGE = 0x4;
enum EXFLAG_NSCERT = 0x8;

enum EXFLAG_CA = 0x10;
/* Really self issued not necessarily self signed */
enum EXFLAG_SI = 0x20;
enum EXFLAG_SS = 0x20;
enum EXFLAG_V1 = 0x40;
enum EXFLAG_INVALID = 0x80;
enum EXFLAG_SET = 0x100;
enum EXFLAG_CRITICAL = 0x200;
enum EXFLAG_PROXY = 0x400;

enum EXFLAG_INVALID_POLICY = 0x800;
enum EXFLAG_FRESHEST = 0x1000;

enum KU_DIGITAL_SIGNATURE = 0x0080;
enum KU_NON_REPUDIATION = 0x0040;
enum KU_KEY_ENCIPHERMENT = 0x0020;
enum KU_DATA_ENCIPHERMENT = 0x0010;
enum KU_KEY_AGREEMENT = 0x0008;
enum KU_KEY_CERT_SIGN = 0x0004;
enum KU_CRL_SIGN = 0x0002;
enum KU_ENCIPHER_ONLY = 0x0001;
enum KU_DECIPHER_ONLY = 0x8000;

enum NS_SSL_CLIENT = 0x80;
enum NS_SSL_SERVER = 0x40;
enum NS_SMIME = 0x20;
enum NS_OBJSIGN = 0x10;
enum NS_SSL_CA = 0x04;
enum NS_SMIME_CA = 0x02;
enum NS_OBJSIGN_CA = 0x01;
enum NS_ANY_CA = (NS_SSL_CA|NS_SMIME_CA|NS_OBJSIGN_CA);

enum XKU_SSL_SERVER = 0x1;
enum XKU_SSL_CLIENT = 0x2;
enum XKU_SMIME = 0x4;
enum XKU_CODE_SIGN = 0x8;
enum XKU_SGC = 0x10;
enum XKU_OCSP_SIGN = 0x20;
enum XKU_TIMESTAMP = 0x40;
enum XKU_DVCS = 0x80;

enum X509_PURPOSE_DYNAMIC = 0x1;
enum X509_PURPOSE_DYNAMIC_NAME = 0x2;

struct x509_purpose_st {
	int purpose;
	int trust;		/* Default trust ID */
	int flags;
	ExternC!(int function(const(x509_purpose_st)*,
				const(X509)*, int)) check_purpose;
	char* name;
	char* sname;
	void* usr_data;
}
alias x509_purpose_st X509_PURPOSE;

enum X509_PURPOSE_SSL_CLIENT = 1;
enum X509_PURPOSE_SSL_SERVER = 2;
enum X509_PURPOSE_NS_SSL_SERVER = 3;
enum X509_PURPOSE_SMIME_SIGN = 4;
enum X509_PURPOSE_SMIME_ENCRYPT = 5;
enum X509_PURPOSE_CRL_SIGN = 6;
enum X509_PURPOSE_ANY = 7;
enum X509_PURPOSE_OCSP_HELPER = 8;
enum X509_PURPOSE_TIMESTAMP_SIGN = 9;

enum X509_PURPOSE_MIN = 1;
enum X509_PURPOSE_MAX = 9;

/* Flags for X509V3_EXT_print() */

enum X509V3_EXT_UNKNOWN_MASK = (0xfL << 16);
/* Return error for unknown extensions */
enum X509V3_EXT_DEFAULT = 0;
/* Print error for unknown extensions */
enum X509V3_EXT_ERROR_UNKNOWN = (1L << 16);
/* ASN1 parse unknown extensions */
enum X509V3_EXT_PARSE_UNKNOWN = (2L << 16);
/* BIO_dump unknown extensions */
enum X509V3_EXT_DUMP_UNKNOWN = (3L << 16);

/* Flags for X509V3_add1_i2d */

enum X509V3_ADD_OP_MASK = 0xf;
enum X509V3_ADD_DEFAULT = 0;
enum X509V3_ADD_APPEND = 1;
enum X509V3_ADD_REPLACE = 2;
enum X509V3_ADD_REPLACE_EXISTING = 3;
enum X509V3_ADD_KEEP_EXISTING = 4;
enum X509V3_ADD_DELETE = 5;
enum X509V3_ADD_SILENT = 0x10;

/+mixin DECLARE_STACK_OF!(X509_PURPOSE);+/

mixin(DECLARE_ASN1_FUNCTIONS!"BASIC_CONSTRAINTS");

mixin(DECLARE_ASN1_FUNCTIONS!"SXNET");
mixin(DECLARE_ASN1_FUNCTIONS!"SXNETID");

int SXNET_add_id_asc(SXNET** psx, char* zone, char* user, int userlen);
int SXNET_add_id_ulong(SXNET** psx, c_ulong lzone, char* user, int userlen);
int SXNET_add_id_INTEGER(SXNET** psx, ASN1_INTEGER* izone, char* user, int userlen);

ASN1_OCTET_STRING* SXNET_get_id_asc(SXNET* sx, char* zone);
ASN1_OCTET_STRING* SXNET_get_id_ulong(SXNET* sx, c_ulong lzone);
ASN1_OCTET_STRING* SXNET_get_id_INTEGER(SXNET* sx, ASN1_INTEGER* zone);

mixin(DECLARE_ASN1_FUNCTIONS!"AUTHORITY_KEYID");

mixin(DECLARE_ASN1_FUNCTIONS!"PKEY_USAGE_PERIOD");

mixin(DECLARE_ASN1_FUNCTIONS!"GENERAL_NAME");
GENERAL_NAME* GENERAL_NAME_dup(GENERAL_NAME* a);
int GENERAL_NAME_cmp(GENERAL_NAME* a, GENERAL_NAME* b);



ASN1_BIT_STRING* v2i_ASN1_BIT_STRING(X509V3_EXT_METHOD* method,
				X509V3_CTX* ctx, STACK_OF!(CONF_VALUE) *nval);
STACK_OF!(CONF_VALUE) *i2v_ASN1_BIT_STRING(X509V3_EXT_METHOD* method,
				ASN1_BIT_STRING* bits,
				STACK_OF!(CONF_VALUE) *extlist);

STACK_OF!(CONF_VALUE) *i2v_GENERAL_NAME(X509V3_EXT_METHOD* method, GENERAL_NAME* gen, STACK_OF!(CONF_VALUE) *ret);
int GENERAL_NAME_print(BIO* out_, GENERAL_NAME* gen);

mixin(DECLARE_ASN1_FUNCTIONS!"GENERAL_NAMES");

STACK_OF!(CONF_VALUE) *i2v_GENERAL_NAMES(X509V3_EXT_METHOD* method,
		GENERAL_NAMES* gen, STACK_OF!(CONF_VALUE) *extlist);
GENERAL_NAMES* v2i_GENERAL_NAMES(const(X509V3_EXT_METHOD)* method,
				 X509V3_CTX* ctx, STACK_OF!(CONF_VALUE) *nval);

mixin(DECLARE_ASN1_FUNCTIONS!"OTHERNAME");
mixin(DECLARE_ASN1_FUNCTIONS!"EDIPARTYNAME");
int OTHERNAME_cmp(OTHERNAME* a, OTHERNAME* b);
void GENERAL_NAME_set0_value(GENERAL_NAME* a, int type, void* value);
void* GENERAL_NAME_get0_value(GENERAL_NAME* a, int* ptype);
int GENERAL_NAME_set0_othername(GENERAL_NAME* gen,
				ASN1_OBJECT* oid, ASN1_TYPE* value);
int GENERAL_NAME_get0_otherName(GENERAL_NAME* gen,
				ASN1_OBJECT** poid, ASN1_TYPE** pvalue);

char* i2s_ASN1_OCTET_STRING(X509V3_EXT_METHOD* method, ASN1_OCTET_STRING* ia5);
ASN1_OCTET_STRING* s2i_ASN1_OCTET_STRING(X509V3_EXT_METHOD* method, X509V3_CTX* ctx, char* str);

mixin(DECLARE_ASN1_FUNCTIONS!"EXTENDED_KEY_USAGE");
int i2a_ACCESS_DESCRIPTION(BIO* bp, ACCESS_DESCRIPTION* a);

mixin(DECLARE_ASN1_FUNCTIONS!"CERTIFICATEPOLICIES");
mixin(DECLARE_ASN1_FUNCTIONS!"POLICYINFO");
mixin(DECLARE_ASN1_FUNCTIONS!"POLICYQUALINFO");
mixin(DECLARE_ASN1_FUNCTIONS!"USERNOTICE");
mixin(DECLARE_ASN1_FUNCTIONS!"NOTICEREF");

mixin(DECLARE_ASN1_FUNCTIONS!"CRL_DIST_POINTS");
mixin(DECLARE_ASN1_FUNCTIONS!"DIST_POINT");
mixin(DECLARE_ASN1_FUNCTIONS!"DIST_POINT_NAME");
mixin(DECLARE_ASN1_FUNCTIONS!"ISSUING_DIST_POINT");

int DIST_POINT_set_dpname(DIST_POINT_NAME* dpn, X509_NAME* iname);

int NAME_CONSTRAINTS_check(X509* x, NAME_CONSTRAINTS* nc);

mixin(DECLARE_ASN1_FUNCTIONS!"ACCESS_DESCRIPTION");
mixin(DECLARE_ASN1_FUNCTIONS!"AUTHORITY_INFO_ACCESS");

mixin(DECLARE_ASN1_ITEM!"POLICY_MAPPING");
mixin(DECLARE_ASN1_ALLOC_FUNCTIONS_name!("POLICY_MAPPING", "POLICY_MAPPING"));
mixin(DECLARE_ASN1_ITEM!"POLICY_MAPPINGS");

mixin(DECLARE_ASN1_ITEM!"GENERAL_SUBTREE");
mixin(DECLARE_ASN1_ALLOC_FUNCTIONS_name!("GENERAL_SUBTREE", "GENERAL_SUBTREE"));

mixin(DECLARE_ASN1_ITEM!"NAME_CONSTRAINTS");
mixin(DECLARE_ASN1_ALLOC_FUNCTIONS_name!("NAME_CONSTRAINTS", "NAME_CONSTRAINTS"));

mixin(DECLARE_ASN1_ALLOC_FUNCTIONS_name!("POLICY_CONSTRAINTS", "POLICY_CONSTRAINTS"));
mixin(DECLARE_ASN1_ITEM!"POLICY_CONSTRAINTS");

GENERAL_NAME* a2i_GENERAL_NAME(GENERAL_NAME* out_,
			       const(X509V3_EXT_METHOD)* method, X509V3_CTX* ctx,
			       int gen_type, char* value, int is_nc);

// #ifdef HEADER_CONF_H
GENERAL_NAME* v2i_GENERAL_NAME(const(X509V3_EXT_METHOD)* method, X509V3_CTX* ctx,
			       CONF_VALUE* cnf);
GENERAL_NAME* v2i_GENERAL_NAME_ex(GENERAL_NAME* out_,
				  const(X509V3_EXT_METHOD)* method,
				  X509V3_CTX* ctx, CONF_VALUE* cnf, int is_nc);
void X509V3_conf_free(CONF_VALUE* val);

X509_EXTENSION* X509V3_EXT_nconf_nid(CONF* conf, X509V3_CTX* ctx, int ext_nid, char* value);
X509_EXTENSION* X509V3_EXT_nconf(CONF* conf, X509V3_CTX* ctx, char* name, char* value);
int X509V3_EXT_add_nconf_sk(CONF* conf, X509V3_CTX* ctx, char* section, STACK_OF!(X509_EXTENSION) **sk);
int X509V3_EXT_add_nconf(CONF* conf, X509V3_CTX* ctx, char* section, X509* cert);
int X509V3_EXT_REQ_add_nconf(CONF* conf, X509V3_CTX* ctx, char* section, X509_REQ* req);
int X509V3_EXT_CRL_add_nconf(CONF* conf, X509V3_CTX* ctx, char* section, X509_CRL* crl);

X509_EXTENSION* X509V3_EXT_conf_nid(LHASH_OF!(CONF_VALUE) *conf, X509V3_CTX* ctx,
				    int ext_nid, char* value);
X509_EXTENSION* X509V3_EXT_conf(LHASH_OF!(CONF_VALUE) *conf, X509V3_CTX* ctx,
				char* name, char* value);
int X509V3_EXT_add_conf(LHASH_OF!(CONF_VALUE) *conf, X509V3_CTX* ctx,
			char* section, X509* cert);
int X509V3_EXT_REQ_add_conf(LHASH_OF!(CONF_VALUE) *conf, X509V3_CTX* ctx,
			    char* section, X509_REQ* req);
int X509V3_EXT_CRL_add_conf(LHASH_OF!(CONF_VALUE) *conf, X509V3_CTX* ctx,
			    char* section, X509_CRL* crl);

int X509V3_add_value_bool_nf(char* name, int asn1_bool,
			     STACK_OF!(CONF_VALUE) **extlist);
int X509V3_get_value_bool(CONF_VALUE* value, int* asn1_bool);
int X509V3_get_value_int(CONF_VALUE* value, ASN1_INTEGER** aint);
void X509V3_set_nconf(X509V3_CTX* ctx, CONF* conf);
void X509V3_set_conf_lhash(X509V3_CTX* ctx, LHASH_OF!(CONF_VALUE) *lhash);
// #endif

char* X509V3_get_string(X509V3_CTX* ctx, char* name, char* section);
STACK_OF!(CONF_VALUE) * X509V3_get_section(X509V3_CTX* ctx, char* section);
void X509V3_string_free(X509V3_CTX* ctx, char* str);
void X509V3_section_free( X509V3_CTX* ctx, STACK_OF!(CONF_VALUE) *section);
void X509V3_set_ctx(X509V3_CTX* ctx, X509* issuer, X509* subject,
				 X509_REQ* req, X509_CRL* crl, int flags);

int X509V3_add_value(const(char)* name, const(char)* value,
						STACK_OF!(CONF_VALUE) **extlist);
int X509V3_add_value_uchar(const(char)* name, const(ubyte)* value,
						STACK_OF!(CONF_VALUE) **extlist);
int X509V3_add_value_bool(const(char)* name, int asn1_bool,
						STACK_OF!(CONF_VALUE) **extlist);
int X509V3_add_value_int(const(char)* name, ASN1_INTEGER* aint,
						STACK_OF!(CONF_VALUE) **extlist);
char* i2s_ASN1_INTEGER(X509V3_EXT_METHOD* meth, ASN1_INTEGER* aint);
ASN1_INTEGER* s2i_ASN1_INTEGER(X509V3_EXT_METHOD* meth, char* value);
char* i2s_ASN1_ENUMERATED(X509V3_EXT_METHOD* meth, ASN1_ENUMERATED* aint);
char* i2s_ASN1_ENUMERATED_TABLE(X509V3_EXT_METHOD* meth, ASN1_ENUMERATED* aint);
int X509V3_EXT_add(X509V3_EXT_METHOD* ext);
int X509V3_EXT_add_list(X509V3_EXT_METHOD* extlist);
int X509V3_EXT_add_alias(int nid_to, int nid_from);
void X509V3_EXT_cleanup();

const(X509V3_EXT_METHOD)* X509V3_EXT_get(X509_EXTENSION* ext);
const(X509V3_EXT_METHOD)* X509V3_EXT_get_nid(int nid);
int X509V3_add_standard_extensions();
STACK_OF!(CONF_VALUE) *X509V3_parse_list(const(char)* line);
void* X509V3_EXT_d2i(X509_EXTENSION* ext);
void* X509V3_get_d2i(STACK_OF!(X509_EXTENSION) *x, int nid, int* crit, int* idx);


X509_EXTENSION* X509V3_EXT_i2d(int ext_nid, int crit, void* ext_struc);
int X509V3_add1_i2d(STACK_OF!(X509_EXTENSION) **x, int nid, void* value, int crit, c_ulong flags);

char* hex_to_string(const(ubyte)* buffer, c_long len);
ubyte* string_to_hex(const(char)* str, c_long* len);
int name_cmp(const(char)* name, const(char)* cmp);

void X509V3_EXT_val_prn(BIO* out_, STACK_OF!(CONF_VALUE) *val, int indent,
								 int ml);
int X509V3_EXT_print(BIO* out_, X509_EXTENSION* ext, c_ulong flag, int indent);
int X509V3_EXT_print_fp(FILE* out_, X509_EXTENSION* ext, int flag, int indent);

int X509V3_extensions_print(BIO* out_, char* title, STACK_OF!(X509_EXTENSION) *exts, c_ulong flag, int indent);

int X509_check_ca(X509* x);
int X509_check_purpose(X509* x, int id, int ca);
int X509_supported_extension(X509_EXTENSION* ex);
int X509_PURPOSE_set(int* p, int purpose);
int X509_check_issued(X509* issuer, X509* subject);
int X509_check_akid(X509* issuer, AUTHORITY_KEYID* akid);
int X509_PURPOSE_get_count();
X509_PURPOSE* X509_PURPOSE_get0(int idx);
int X509_PURPOSE_get_by_sname(char* sname);
int X509_PURPOSE_get_by_id(int id);
int X509_PURPOSE_add(int id, int trust, int flags,
			ExternC!(int function(const(X509_PURPOSE)*, const(X509)*, int)) ck,
				char* name, char* sname, void* arg);
char* X509_PURPOSE_get0_name(X509_PURPOSE* xp);
char* X509_PURPOSE_get0_sname(X509_PURPOSE* xp);
int X509_PURPOSE_get_trust(X509_PURPOSE* xp);
void X509_PURPOSE_cleanup();
int X509_PURPOSE_get_id(X509_PURPOSE*);

STACK_OF!(OPENSSL_STRING) *X509_get1_email(X509* x);
STACK_OF!(OPENSSL_STRING) *X509_REQ_get1_email(X509_REQ* x);
void X509_email_free(STACK_OF!(OPENSSL_STRING) *sk);
STACK_OF!(OPENSSL_STRING) *X509_get1_ocsp(X509* x);

ASN1_OCTET_STRING* a2i_IPADDRESS(const(char)* ipasc);
ASN1_OCTET_STRING* a2i_IPADDRESS_NC(const(char)* ipasc);
int a2i_ipadd(ubyte* ipout, const(char)* ipasc);
int X509V3_NAME_from_section(X509_NAME* nm, STACK_OF!(CONF_VALUE)*dn_sk,
						c_ulong chtype);

void X509_POLICY_NODE_print(BIO* out_, X509_POLICY_NODE* node, int indent);
/+mixin DECLARE_STACK_OF!(X509_POLICY_NODE);+/

version(OPENSSL_NO_RFC3779) {} else {
struct ASRange_st {
  ASN1_INTEGER* min, max;
}
alias ASRange_st ASRange;

enum ASIdOrRange_id = 0;
enum ASIdOrRange_range = 1;

struct ASIdOrRange_st {
  int type;
  union u_ {
    ASN1_INTEGER* id;
    ASRange* range;
  }
  u_ u;
}
alias ASIdOrRange_st ASIdOrRange;

alias STACK_OF!(ASIdOrRange) ASIdOrRanges;
/+mixin DECLARE_STACK_OF!(ASIdOrRange);+/

enum ASIdentifierChoice_inherit = 0;
enum ASIdentifierChoice_asIdsOrRanges = 1;

struct ASIdentifierChoice_st {
  int type;
  union u_ {
    ASN1_NULL* inherit;
    ASIdOrRanges* asIdsOrRanges;
  }
  u_ u;
}
alias ASIdOrRange_st ASIdentifierChoice;

struct ASIdentifiers_st {
  ASIdentifierChoice* asnum, rdi;
}
alias ASIdentifiers_st ASIdentifiers;

mixin(DECLARE_ASN1_FUNCTIONS!"ASRange");
mixin(DECLARE_ASN1_FUNCTIONS!"ASIdOrRange");
mixin(DECLARE_ASN1_FUNCTIONS!"ASIdentifierChoice");
mixin(DECLARE_ASN1_FUNCTIONS!"ASIdentifiers");


struct IPAddressRange_st {
  ASN1_BIT_STRING* min, max;
}
alias IPAddressRange_st IPAddressRange;

enum IPAddressOrRange_addressPrefix = 0;
enum IPAddressOrRange_addressRange = 1;

struct IPAddressOrRange_st {
  int type;
  union u_ {
    ASN1_BIT_STRING* addressPrefix;
    IPAddressRange* addressRange;
  }
  u_ u;
}
alias IPAddressOrRange_st IPAddressOrRange;

alias STACK_OF!(IPAddressOrRange) IPAddressOrRanges;
/+mixin DECLARE_STACK_OF!(IPAddressOrRange);+/

enum IPAddressChoice_inherit = 0;
enum IPAddressChoice_addressesOrRanges = 1;

struct IPAddressChoice_st {
  int type;
  union u_ {
    ASN1_NULL* inherit;
    IPAddressOrRanges* addressesOrRanges;
  }
  u_ u;
}
alias IPAddressChoice_st IPAddressChoice;

struct IPAddressFamily_st {
  ASN1_OCTET_STRING* addressFamily;
  IPAddressChoice* ipAddressChoice;
}
alias IPAddressFamily_st IPAddressFamily;

alias STACK_OF!(IPAddressFamily) IPAddrBlocks;
/+mixin DECLARE_STACK_OF!(IPAddressFamily);+/

mixin(DECLARE_ASN1_FUNCTIONS!"IPAddressRange");
mixin(DECLARE_ASN1_FUNCTIONS!"IPAddressOrRange");
mixin(DECLARE_ASN1_FUNCTIONS!"IPAddressChoice");
mixin(DECLARE_ASN1_FUNCTIONS!"IPAddressFamily");

/*
 * API tag for elements of the ASIdentifer SEQUENCE.
 */
enum V3_ASID_ASNUM = 0;
enum V3_ASID_RDI = 1;

/*
 * AFI values, assigned by IANA.  It'd be nice to make the AFI
 * handling code totally generic, but there are too many little things
 * that would need to be defined for other address families for it to
 * be worth the trouble.
 */
enum IANA_AFI_IPV4 = 1;
enum IANA_AFI_IPV6 = 2;

/*
 * Utilities to conand extract values from RFC3779 extensions,
 * since some of the encodings (particularly for IP address prefixes
 * and ranges) are a bit tedious to work with directly.
 */
int v3_asid_add_inherit(ASIdentifiers* asid, int which);
int v3_asid_add_id_or_range(ASIdentifiers* asid, int which,
			    ASN1_INTEGER* min, ASN1_INTEGER* max);
int v3_addr_add_inherit(IPAddrBlocks* addr,
			const uint afi, const(uint)* safi);
int v3_addr_add_prefix(IPAddrBlocks* addr,
		       const uint afi, const(uint)* safi,
		       ubyte* a, const int prefixlen);
int v3_addr_add_range(IPAddrBlocks* addr,
		      const uint afi, const(uint)* safi,
		      ubyte* min, ubyte* max);
uint v3_addr_get_afi(const(IPAddressFamily)* f);
int v3_addr_get_range(IPAddressOrRange* aor, const uint afi,
		      ubyte* min, ubyte* max,
		      const int length);

/*
 * Canonical forms.
 */
int v3_asid_is_canonical(ASIdentifiers* asid);
int v3_addr_is_canonical(IPAddrBlocks* addr);
int v3_asid_canonize(ASIdentifiers* asid);
int v3_addr_canonize(IPAddrBlocks* addr);

/*
 * Tests for inheritance and containment.
 */
int v3_asid_inherits(ASIdentifiers* asid);
int v3_addr_inherits(IPAddrBlocks* addr);
int v3_asid_subset(ASIdentifiers* a, ASIdentifiers* b);
int v3_addr_subset(IPAddrBlocks* a, IPAddrBlocks* b);

/*
 * Check whether RFC 3779 extensions nest properly in chains.
 */
int v3_asid_validate_path(X509_STORE_CTX*);
int v3_addr_validate_path(X509_STORE_CTX*);
int v3_asid_validate_resource_set(STACK_OF!(X509) *chain,
				  ASIdentifiers* ext,
				  int allow_inheritance);
int v3_addr_validate_resource_set(STACK_OF!(X509) *chain,
				  IPAddrBlocks* ext,
				  int allow_inheritance);

} /* OPENSSL_NO_RFC3779 */

/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
void ERR_load_X509V3_strings();

/* Error codes for the X509V3 functions. */

/* Function codes. */
enum X509V3_F_A2I_GENERAL_NAME = 164;
enum X509V3_F_ASIDENTIFIERCHOICE_CANONIZE = 161;
enum X509V3_F_ASIDENTIFIERCHOICE_IS_CANONICAL = 162;
enum X509V3_F_COPY_EMAIL = 122;
enum X509V3_F_COPY_ISSUER = 123;
enum X509V3_F_DO_DIRNAME = 144;
enum X509V3_F_DO_EXT_CONF = 124;
enum X509V3_F_DO_EXT_I2D = 135;
enum X509V3_F_DO_EXT_NCONF = 151;
enum X509V3_F_DO_I2V_NAME_CONSTRAINTS = 148;
enum X509V3_F_GNAMES_FROM_SECTNAME = 156;
enum X509V3_F_HEX_TO_STRING = 111;
enum X509V3_F_I2S_ASN1_ENUMERATED = 121;
enum X509V3_F_I2S_ASN1_IA5STRING = 149;
enum X509V3_F_I2S_ASN1_INTEGER = 120;
enum X509V3_F_I2V_AUTHORITY_INFO_ACCESS = 138;
enum X509V3_F_NOTICE_SECTION = 132;
enum X509V3_F_NREF_NOS = 133;
enum X509V3_F_POLICY_SECTION = 131;
enum X509V3_F_PROCESS_PCI_VALUE = 150;
enum X509V3_F_R2I_CERTPOL = 130;
enum X509V3_F_R2I_PCI = 155;
enum X509V3_F_S2I_ASN1_IA5STRING = 100;
enum X509V3_F_S2I_ASN1_INTEGER = 108;
enum X509V3_F_S2I_ASN1_OCTET_STRING = 112;
enum X509V3_F_S2I_ASN1_SKEY_ID = 114;
enum X509V3_F_S2I_SKEY_ID = 115;
enum X509V3_F_SET_DIST_POINT_NAME = 158;
enum X509V3_F_STRING_TO_HEX = 113;
enum X509V3_F_SXNET_ADD_ID_ASC = 125;
enum X509V3_F_SXNET_ADD_ID_INTEGER = 126;
enum X509V3_F_SXNET_ADD_ID_ULONG = 127;
enum X509V3_F_SXNET_GET_ID_ASC = 128;
enum X509V3_F_SXNET_GET_ID_ULONG = 129;
enum X509V3_F_V2I_ASIDENTIFIERS = 163;
enum X509V3_F_V2I_ASN1_BIT_STRING = 101;
enum X509V3_F_V2I_AUTHORITY_INFO_ACCESS = 139;
enum X509V3_F_V2I_AUTHORITY_KEYID = 119;
enum X509V3_F_V2I_BASIC_CONSTRAINTS = 102;
enum X509V3_F_V2I_CRLD = 134;
enum X509V3_F_V2I_EXTENDED_KEY_USAGE = 103;
enum X509V3_F_V2I_GENERAL_NAMES = 118;
enum X509V3_F_V2I_GENERAL_NAME_EX = 117;
enum X509V3_F_V2I_IDP = 157;
enum X509V3_F_V2I_IPADDRBLOCKS = 159;
enum X509V3_F_V2I_ISSUER_ALT = 153;
enum X509V3_F_V2I_NAME_CONSTRAINTS = 147;
enum X509V3_F_V2I_POLICY_CONSTRAINTS = 146;
enum X509V3_F_V2I_POLICY_MAPPINGS = 145;
enum X509V3_F_V2I_SUBJECT_ALT = 154;
enum X509V3_F_V3_ADDR_VALIDATE_PATH_INTERNAL = 160;
enum X509V3_F_V3_GENERIC_EXTENSION = 116;
enum X509V3_F_X509V3_ADD1_I2D = 140;
enum X509V3_F_X509V3_ADD_VALUE = 105;
enum X509V3_F_X509V3_EXT_ADD = 104;
enum X509V3_F_X509V3_EXT_ADD_ALIAS = 106;
enum X509V3_F_X509V3_EXT_CONF = 107;
enum X509V3_F_X509V3_EXT_I2D = 136;
enum X509V3_F_X509V3_EXT_NCONF = 152;
enum X509V3_F_X509V3_GET_SECTION = 142;
enum X509V3_F_X509V3_GET_STRING = 143;
enum X509V3_F_X509V3_GET_VALUE_BOOL = 110;
enum X509V3_F_X509V3_PARSE_LIST = 109;
enum X509V3_F_X509_PURPOSE_ADD = 137;
enum X509V3_F_X509_PURPOSE_SET = 141;

/* Reason codes. */
enum X509V3_R_BAD_IP_ADDRESS = 118;
enum X509V3_R_BAD_OBJECT = 119;
enum X509V3_R_BN_DEC2BN_ERROR = 100;
enum X509V3_R_BN_TO_ASN1_INTEGER_ERROR = 101;
enum X509V3_R_DIRNAME_ERROR = 149;
enum X509V3_R_DISTPOINT_ALREADY_SET = 160;
enum X509V3_R_DUPLICATE_ZONE_ID = 133;
enum X509V3_R_ERROR_CONVERTING_ZONE = 131;
enum X509V3_R_ERROR_CREATING_EXTENSION = 144;
enum X509V3_R_ERROR_IN_EXTENSION = 128;
enum X509V3_R_EXPECTED_A_SECTION_NAME = 137;
enum X509V3_R_EXTENSION_EXISTS = 145;
enum X509V3_R_EXTENSION_NAME_ERROR = 115;
enum X509V3_R_EXTENSION_NOT_FOUND = 102;
enum X509V3_R_EXTENSION_SETTING_NOT_SUPPORTED = 103;
enum X509V3_R_EXTENSION_VALUE_ERROR = 116;
enum X509V3_R_ILLEGAL_EMPTY_EXTENSION = 151;
enum X509V3_R_ILLEGAL_HEX_DIGIT = 113;
enum X509V3_R_INCORRECT_POLICY_SYNTAX_TAG = 152;
enum X509V3_R_INVALID_MULTIPLE_RDNS = 161;
enum X509V3_R_INVALID_ASNUMBER = 162;
enum X509V3_R_INVALID_ASRANGE = 163;
enum X509V3_R_INVALID_BOOLEAN_STRING = 104;
enum X509V3_R_INVALID_EXTENSION_STRING = 105;
enum X509V3_R_INVALID_INHERITANCE = 165;
enum X509V3_R_INVALID_IPADDRESS = 166;
enum X509V3_R_INVALID_NAME = 106;
enum X509V3_R_INVALID_NULL_ARGUMENT = 107;
enum X509V3_R_INVALID_NULL_NAME = 108;
enum X509V3_R_INVALID_NULL_VALUE = 109;
enum X509V3_R_INVALID_NUMBER = 140;
enum X509V3_R_INVALID_NUMBERS = 141;
enum X509V3_R_INVALID_OBJECT_IDENTIFIER = 110;
enum X509V3_R_INVALID_OPTION = 138;
enum X509V3_R_INVALID_POLICY_IDENTIFIER = 134;
enum X509V3_R_INVALID_PROXY_POLICY_SETTING = 153;
enum X509V3_R_INVALID_PURPOSE = 146;
enum X509V3_R_INVALID_SAFI = 164;
enum X509V3_R_INVALID_SECTION = 135;
enum X509V3_R_INVALID_SYNTAX = 143;
enum X509V3_R_ISSUER_DECODE_ERROR = 126;
enum X509V3_R_MISSING_VALUE = 124;
enum X509V3_R_NEED_ORGANIZATION_AND_NUMBERS = 142;
enum X509V3_R_NO_CONFIG_DATABASE = 136;
enum X509V3_R_NO_ISSUER_CERTIFICATE = 121;
enum X509V3_R_NO_ISSUER_DETAILS = 127;
enum X509V3_R_NO_POLICY_IDENTIFIER = 139;
enum X509V3_R_NO_PROXY_CERT_POLICY_LANGUAGE_DEFINED = 154;
enum X509V3_R_NO_PUBLIC_KEY = 114;
enum X509V3_R_NO_SUBJECT_DETAILS = 125;
enum X509V3_R_ODD_NUMBER_OF_DIGITS = 112;
enum X509V3_R_OPERATION_NOT_DEFINED = 148;
enum X509V3_R_OTHERNAME_ERROR = 147;
enum X509V3_R_POLICY_LANGUAGE_ALREADY_DEFINED = 155;
enum X509V3_R_POLICY_PATH_LENGTH = 156;
enum X509V3_R_POLICY_PATH_LENGTH_ALREADY_DEFINED = 157;
enum X509V3_R_POLICY_SYNTAX_NOT_CURRENTLY_SUPPORTED = 158;
enum X509V3_R_POLICY_WHEN_PROXY_LANGUAGE_REQUIRES_NO_POLICY = 159;
enum X509V3_R_SECTION_NOT_FOUND = 150;
enum X509V3_R_UNABLE_TO_GET_ISSUER_DETAILS = 122;
enum X509V3_R_UNABLE_TO_GET_ISSUER_KEYID = 123;
enum X509V3_R_UNKNOWN_BIT_STRING_ARGUMENT = 111;
enum X509V3_R_UNKNOWN_EXTENSION = 129;
enum X509V3_R_UNKNOWN_EXTENSION_NAME = 130;
enum X509V3_R_UNKNOWN_OPTION = 120;
enum X509V3_R_UNSUPPORTED_OPTION = 117;
enum X509V3_R_UNSUPPORTED_TYPE = 167;
enum X509V3_R_USER_TOO_LONG = 132;
