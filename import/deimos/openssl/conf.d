/* crypto/conf/conf.h */
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

module deimos.openssl.conf;

import deimos.openssl._d_util;

public import deimos.openssl.bio;
public import deimos.openssl.lhash;
public import deimos.openssl.stack;
public import deimos.openssl.safestack;
public import deimos.openssl.e_os2;

public import deimos.openssl.ossl_typ;

extern (C):
nothrow:

struct CONF_VALUE
	{
	char* section;
	char* name;
	char* value;
	}

/+mixin DECLARE_STACK_OF!(CONF_VALUE);+/
mixin DECLARE_LHASH_OF!(CONF_VALUE);

alias conf_method_st CONF_METHOD;

struct conf_method_st
	{
	const(char)* name;
	ExternC!(CONF* function(CONF_METHOD* meth)) create;
	ExternC!(int function(CONF* conf)) init_;
	ExternC!(int function(CONF* conf)) destroy;
	ExternC!(int function(CONF* conf)) destroy_data;
	ExternC!(int function(CONF* conf, BIO* bp, c_long* eline)) load_bio;
	ExternC!(int function(const(CONF)* conf, BIO* bp)) dump;
	ExternC!(int function(const(CONF)* conf, char c)) is_number;
	ExternC!(int function(const(CONF)* conf, char c)) to_int;
	ExternC!(int function(CONF* conf, const(char)* name, c_long* eline)) load;
	};

/* Module definitions */

struct conf_imodule_st;
alias conf_imodule_st CONF_IMODULE;
struct conf_module_st;
alias conf_module_st CONF_MODULE;

/+mixin DECLARE_STACK_OF!(CONF_MODULE);+/
/+mixin DECLARE_STACK_OF!(CONF_IMODULE);+/

/* DSO module function typedefs */
alias typeof(*(ExternC!(int function(CONF_IMODULE* md, const(CONF)* cnf))).init) conf_init_func;
alias typeof(*(ExternC!(void function(CONF_IMODULE* md))).init) conf_finish_func;

enum CONF_MFLAGS_IGNORE_ERRORS = 0x1;
enum CONF_MFLAGS_IGNORE_RETURN_CODES = 0x2;
enum CONF_MFLAGS_SILENT = 0x4;
enum CONF_MFLAGS_NO_DSO = 0x8;
enum CONF_MFLAGS_IGNORE_MISSING_FILE = 0x10;
enum CONF_MFLAGS_DEFAULT_SECTION = 0x20;

int CONF_set_default_method(CONF_METHOD* meth);
void CONF_set_nconf(CONF* conf,LHASH_OF!(CONF_VALUE) *hash);
LHASH_OF!(CONF_VALUE) *CONF_load(LHASH_OF!(CONF_VALUE) *conf,const(char)* file,
				c_long* eline);
version(OPENSSL_NO_FP_API) {} else {
LHASH_OF!(CONF_VALUE) *CONF_load_fp(LHASH_OF!(CONF_VALUE) *conf, FILE* fp,
				   c_long* eline);
}
LHASH_OF!(CONF_VALUE) *CONF_load_bio(LHASH_OF!(CONF_VALUE) *conf, BIO* bp,c_long* eline);
STACK_OF!(CONF_VALUE) *CONF_get_section(LHASH_OF!(CONF_VALUE) *conf,
				       const(char)* section);
char* CONF_get_string(LHASH_OF!(CONF_VALUE) *conf,const(char)* group,
		      const(char)* name);
c_long CONF_get_number(LHASH_OF!(CONF_VALUE) *conf,const(char)* group,
		     const(char)* name);
void CONF_free(LHASH_OF!(CONF_VALUE) *conf);
int CONF_dump_fp(LHASH_OF!(CONF_VALUE) *conf, FILE* out_);
int CONF_dump_bio(LHASH_OF!(CONF_VALUE) *conf, BIO* out_);

void OPENSSL_config(const(char)* config_name);
void OPENSSL_no_config();

/* New conf code.  The semantics are different from the functions above.
   If that wasn't the case, the above functions would have been replaced */

struct conf_st
	{
	CONF_METHOD* meth;
	void* meth_data;
	LHASH_OF!(CONF_VALUE) *data;
	};

CONF* NCONF_new(CONF_METHOD* meth);
CONF_METHOD* NCONF_default();
CONF_METHOD* NCONF_WIN32();
version (none) { /* Just to give you an idea of what I have in mind */
CONF_METHOD* NCONF_XML();
}
void NCONF_free(CONF* conf);
void NCONF_free_data(CONF* conf);

int NCONF_load(CONF* conf,const(char)* file,c_long* eline);
version(OPENSSL_NO_FP_API) {} else {
int NCONF_load_fp(CONF* conf, FILE* fp,c_long* eline);
}
int NCONF_load_bio(CONF* conf, BIO* bp,c_long* eline);
STACK_OF!(CONF_VALUE) *NCONF_get_section(const(CONF)* conf,const(char)* section);
char* NCONF_get_string(const(CONF)* conf,const(char)* group,const(char)* name);
int NCONF_get_number_e(const(CONF)* conf,const(char)* group,const(char)* name,
		       c_long* result);
int NCONF_dump_fp(const(CONF)* conf, FILE* out_);
int NCONF_dump_bio(const(CONF)* conf, BIO* out_);

version (none) { /* The following function has no error checking,
	 and should therefore be avoided */
c_long NCONF_get_number(CONF* conf,char* group,char* name);
} else {
alias NCONF_get_number_e NCONF_get_number;
}

/* Module functions */

int CONF_modules_load(const(CONF)* cnf, const(char)* appname,
		      c_ulong flags);
int CONF_modules_load_file(const(char)* filename, const(char)* appname,
			   c_ulong flags);
void CONF_modules_unload(int all);
void CONF_modules_finish();
void CONF_modules_free();
int CONF_module_add(const(char)* name, conf_init_func* ifunc,
		    conf_finish_func* ffunc);

const(char)* CONF_imodule_get_name(const(CONF_IMODULE)* md);
const(char)* CONF_imodule_get_value(const(CONF_IMODULE)* md);
void* CONF_imodule_get_usr_data(const(CONF_IMODULE)* md);
void CONF_imodule_set_usr_data(CONF_IMODULE* md, void* usr_data);
CONF_MODULE* CONF_imodule_get_module(const(CONF_IMODULE)* md);
c_ulong CONF_imodule_get_flags(const(CONF_IMODULE)* md);
void CONF_imodule_set_flags(CONF_IMODULE* md, c_ulong flags);
void* CONF_module_get_usr_data(CONF_MODULE* pmod);
void CONF_module_set_usr_data(CONF_MODULE* pmod, void* usr_data);

char* CONF_get1_default_config_file();

int CONF_parse_list(const(char)* list, int sep, int nospc,
	ExternC!(int function(const(char)* elem, int len, void* usr)) list_cb, void* arg);

void OPENSSL_load_builtin_modules();

/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
void ERR_load_CONF_strings();

/* Error codes for the CONF functions. */

/* Function codes. */
enum CONF_F_CONF_DUMP_FP = 104;
enum CONF_F_CONF_LOAD = 100;
enum CONF_F_CONF_LOAD_BIO = 102;
enum CONF_F_CONF_LOAD_FP = 103;
enum CONF_F_CONF_MODULES_LOAD = 116;
enum CONF_F_CONF_PARSE_LIST = 119;
enum CONF_F_DEF_LOAD = 120;
enum CONF_F_DEF_LOAD_BIO = 121;
enum CONF_F_MODULE_INIT = 115;
enum CONF_F_MODULE_LOAD_DSO = 117;
enum CONF_F_MODULE_RUN = 118;
enum CONF_F_NCONF_DUMP_BIO = 105;
enum CONF_F_NCONF_DUMP_FP = 106;
enum CONF_F_NCONF_GET_NUMBER = 107;
enum CONF_F_NCONF_GET_NUMBER_E = 112;
enum CONF_F_NCONF_GET_SECTION = 108;
enum CONF_F_NCONF_GET_STRING = 109;
enum CONF_F_NCONF_LOAD = 113;
enum CONF_F_NCONF_LOAD_BIO = 110;
enum CONF_F_NCONF_LOAD_FP = 114;
enum CONF_F_NCONF_NEW = 111;
enum CONF_F_STR_COPY = 101;

/* Reason codes. */
enum CONF_R_ERROR_LOADING_DSO = 110;
enum CONF_R_LIST_CANNOT_BE_NULL = 115;
enum CONF_R_MISSING_CLOSE_SQUARE_BRACKET = 100;
enum CONF_R_MISSING_EQUAL_SIGN = 101;
enum CONF_R_MISSING_FINISH_FUNCTION = 111;
enum CONF_R_MISSING_INIT_FUNCTION = 112;
enum CONF_R_MODULE_INITIALIZATION_ERROR = 109;
enum CONF_R_NO_CLOSE_BRACE = 102;
enum CONF_R_NO_CONF = 105;
enum CONF_R_NO_CONF_OR_ENVIRONMENT_VARIABLE = 106;
enum CONF_R_NO_SECTION = 107;
enum CONF_R_NO_SUCH_FILE = 114;
enum CONF_R_NO_VALUE = 108;
enum CONF_R_UNABLE_TO_CREATE_NEW_SECTION = 103;
enum CONF_R_UNKNOWN_MODULE_NAME = 113;
enum CONF_R_VARIABLE_HAS_NO_VALUE = 104;
