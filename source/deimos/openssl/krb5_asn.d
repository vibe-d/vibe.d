/* krb5_asn.h */
/* Written by Vern Staats <staatsvr@asc.hpc.mil> for the OpenSSL project,
** using ocsp/{*.h,*asn*.c} as a starting point
*/

/* ====================================================================
 * Copyright (c) 1998-2000 The OpenSSL Project.  All rights reserved.
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

module deimos.openssl.krb5_asn;

import deimos.openssl._d_util;

import deimos.openssl.asn1;

/*
#include <krb5.h>
*/
public import deimos.openssl.safestack;

extern (C):
nothrow:


/*	ASN.1 from Kerberos RFC 1510
*/

/*	EncryptedData ::=   SEQUENCE {
**		etype[0]                      INTEGER, -- EncryptionType
**		kvno[1]                       INTEGER OPTIONAL,
**		cipher[2]                     OCTET STRING -- ciphertext
**	}
*/
struct krb5_encdata_st {
	ASN1_INTEGER* etype;
	ASN1_INTEGER* kvno;
	ASN1_OCTET_STRING* cipher;
	}
alias krb5_encdata_st KRB5_ENCDATA;

/+mixin DECLARE_STACK_OF!(KRB5_ENCDATA);+/

/*	PrincipalName ::=   SEQUENCE {
**		name-type[0]                  INTEGER,
**		name-string[1]                SEQUENCE OF GeneralString
**	}
*/
struct krb5_princname_st {
	ASN1_INTEGER* nametype;
	STACK_OF!(ASN1_GENERALSTRING)	*namestring;
	}
alias krb5_princname_st KRB5_PRINCNAME;

/+mixin DECLARE_STACK_OF!(KRB5_PRINCNAME);+/


/*	Ticket ::=	[APPLICATION 1] SEQUENCE {
**		tkt-vno[0]                    INTEGER,
**		realm[1]                      Realm,
**		sname[2]                      PrincipalName,
**		enc-part[3]                   EncryptedData
**	}
*/
struct krb5_tktbody_st {
	ASN1_INTEGER* tktvno;
	ASN1_GENERALSTRING* realm;
	KRB5_PRINCNAME* sname;
	KRB5_ENCDATA* encdata;
	}
alias krb5_tktbody_st KRB5_TKTBODY;

alias STACK_OF!(KRB5_TKTBODY) KRB5_TICKET;
/+mixin DECLARE_STACK_OF!(KRB5_TKTBODY);+/


/*	AP-REQ ::=      [APPLICATION 14] SEQUENCE {
**		pvno[0]                       INTEGER,
**		msg-type[1]                   INTEGER,
**		ap-options[2]                 APOptions,
**		ticket[3]                     Ticket,
**		authenticator[4]              EncryptedData
**	}
**
**	APOptions ::=   BIT STRING {
**		reserved(0), use-session-key(1), mutual-required(2) }
*/
struct krb5_ap_req_st {
	ASN1_INTEGER* pvno;
	ASN1_INTEGER* msgtype;
	ASN1_BIT_STRING* apoptions;
	KRB5_TICKET* ticket;
	KRB5_ENCDATA* authenticator;
	}
alias krb5_ap_req_st KRB5_APREQBODY;

alias STACK_OF!(KRB5_APREQBODY) KRB5_APREQ;
/+mixin DECLARE_STACK_OF!(KRB5_APREQBODY);+/


/*	Authenticator Stuff	*/


/*	Checksum ::=   SEQUENCE {
**		cksumtype[0]                  INTEGER,
**		checksum[1]                   OCTET STRING
**	}
*/
struct krb5_checksum_st {
	ASN1_INTEGER* ctype;
	ASN1_OCTET_STRING* checksum;
	}
alias krb5_checksum_st KRB5_CHECKSUM;

/+mixin DECLARE_STACK_OF!(KRB5_CHECKSUM);+/


/*	EncryptionKey ::=   SEQUENCE {
**		keytype[0]                    INTEGER,
**		keyvalue[1]                   OCTET STRING
**	}
*/
struct krb5_encryptionkey_st {
	ASN1_INTEGER* ktype;
	ASN1_OCTET_STRING* keyvalue;
	}
alias krb5_encryptionkey_st KRB5_ENCKEY;

/+mixin DECLARE_STACK_OF!(KRB5_ENCKEY);+/


/*	AuthorizationData ::=   SEQUENCE OF SEQUENCE {
**		ad-type[0]                    INTEGER,
**             ad-data[1]                    OCTET STRING
**	}
*/
struct krb5_authorization_st {
	ASN1_INTEGER* adtype;
	ASN1_OCTET_STRING* addata;
	}
alias krb5_authorization_st KRB5_AUTHDATA;

/+mixin DECLARE_STACK_OF!(KRB5_AUTHDATA);+/


/*	-- Unencrypted authenticator
**	Authenticator ::=    [APPLICATION 2] SEQUENCE    {
**		authenticator-vno[0]          INTEGER,
**		crealm[1]                     Realm,
**		cname[2]                      PrincipalName,
**		cksum[3]                      Checksum OPTIONAL,
**		cusec[4]                      INTEGER,
**		ctime[5]                      KerberosTime,
**		subkey[6]                     EncryptionKey OPTIONAL,
**		seq-number[7]                 INTEGER OPTIONAL,
**		authorization-data[8]         AuthorizationData OPTIONAL
**	}
*/
struct krb5_authenticator_st {
	ASN1_INTEGER* avno;
	ASN1_GENERALSTRING* crealm;
	KRB5_PRINCNAME* cname;
	KRB5_CHECKSUM* cksum;
	ASN1_INTEGER* cusec;
	ASN1_GENERALIZEDTIME* ctime;
	KRB5_ENCKEY* subkey;
	ASN1_INTEGER* seqnum;
	KRB5_AUTHDATA* authorization;
	}
alias krb5_authenticator_st KRB5_AUTHENTBODY;

alias STACK_OF!(KRB5_AUTHENTBODY) KRB5_AUTHENT;
/+mixin DECLARE_STACK_OF!(KRB5_AUTHENTBODY);+/


/* DECLARE_ASN1_FUNCTIONS(type) = DECLARE_ASN1_FUNCTIONS_name(type, type) =
**	type* name##_new();
**	void name##_free(type* a);
**	DECLARE_ASN1_ENCODE_FUNCTIONS(type, name, name) =
**	 DECLARE_ASN1_ENCODE_FUNCTIONS(type, itname, name) =
**	  type* d2i_##name(type** a, const(ubyte)** in_, c_long len);
**	  int i2d_##name(type* a, ubyte** out_);
**	  DECLARE_ASN1_ITEM(itname) = OPENSSL_EXTERN const ASN1_ITEM itname##_it
*/

mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_ENCDATA");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_PRINCNAME");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_TKTBODY");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_APREQBODY");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_TICKET");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_APREQ");

mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_CHECKSUM");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_ENCKEY");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_AUTHDATA");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_AUTHENTBODY");
mixin(DECLARE_ASN1_FUNCTIONS!"KRB5_AUTHENT");


/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
