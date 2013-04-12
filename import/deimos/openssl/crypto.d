/* crypto/crypto.h */
/* ====================================================================
 * Copyright (c) 1998-2006 The OpenSSL Project.  All rights reserved.
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
/* ====================================================================
 * Copyright 2002 Sun Microsystems, Inc. ALL RIGHTS RESERVED.
 * ECDH support in OpenSSL originally developed by
 * SUN MICROSYSTEMS, INC., and contributed to the OpenSSL project.
 */

module deimos.openssl.crypto;

import deimos.openssl._d_util;

import core.stdc.stdlib;

public import deimos.openssl.e_os2;

version(OPENSSL_NO_FP_API) {} else {
import core.stdc.stdio;
}

public import deimos.openssl.stack;
public import deimos.openssl.safestack;
public import deimos.openssl.opensslv;
public import deimos.openssl.ossl_typ;

version (CHARSET_EBCDIC) {
public import deimos.openssl.ebcdic;
}

/* Resolve problems on some operating systems with symbol names that clash
   one way or another */
public import deimos.openssl.symhacks;

extern (C):
nothrow:

/* Backward compatibility to SSLeay */
/* This is more to be used to check the correct DLL is being used
 * in the MS world. */
alias OPENSSL_VERSION_NUMBER SSLEAY_VERSION_NUMBER;
enum SSLEAY_VERSION = 0;
/* enum SSLEAY_OPTIONS = 1; no longer supported */
enum SSLEAY_CFLAGS = 2;
enum SSLEAY_BUILT_ON = 3;
enum SSLEAY_PLATFORM = 4;
enum SSLEAY_DIR = 5;

/* Already declared in ossl_typ.h */
/+#if 0
alias crypto_ex_data_st CRYPTO_EX_DATA;
/* Called when a new object is created */
typedef int CRYPTO_EX_new(void* parent, void* ptr, CRYPTO_EX_DATA* ad,
					int idx, c_long argl, void* argp);
/* Called when an object is free()ed */
typedef void CRYPTO_EX_free(void* parent, void* ptr, CRYPTO_EX_DATA* ad,
					int idx, c_long argl, void* argp);
/* Called when we need to dup an object */
typedef int CRYPTO_EX_dup(CRYPTO_EX_DATA* to, CRYPTO_EX_DATA* from, void* from_d,
					int idx, c_long argl, void* argp);
#endif+/

/* A generic structure to pass assorted data in a expandable way */
struct openssl_item_st {
	int code;
	void* value;		/* Not used for flag attributes */
	size_t value_size;	/* Max size of value for output, length for input */
	size_t* value_length;	/* Returned length of value for output */
	}
alias openssl_item_st OPENSSL_ITEM;


/* When changing the CRYPTO_LOCK_* list, be sure to maintin the text lock
 * names in cryptlib.c
 */

enum CRYPTO_LOCK_ERR = 1;
enum CRYPTO_LOCK_EX_DATA = 2;
enum CRYPTO_LOCK_X509 = 3;
enum CRYPTO_LOCK_X509_INFO = 4;
enum CRYPTO_LOCK_X509_PKEY = 5;
enum CRYPTO_LOCK_X509_CRL = 6;
enum CRYPTO_LOCK_X509_REQ = 7;
enum CRYPTO_LOCK_DSA = 8;
enum CRYPTO_LOCK_RSA = 9;
enum CRYPTO_LOCK_EVP_PKEY = 10;
enum CRYPTO_LOCK_X509_STORE = 11;
enum CRYPTO_LOCK_SSL_CTX = 12;
enum CRYPTO_LOCK_SSL_CERT = 13;
enum CRYPTO_LOCK_SSL_SESSION = 14;
enum CRYPTO_LOCK_SSL_SESS_CERT = 15;
enum CRYPTO_LOCK_SSL = 16;
enum CRYPTO_LOCK_SSL_METHOD = 17;
enum CRYPTO_LOCK_RAND = 18;
enum CRYPTO_LOCK_RAND2 = 19;
enum CRYPTO_LOCK_MALLOC = 20;
enum CRYPTO_LOCK_BIO = 21;
enum CRYPTO_LOCK_GETHOSTBYNAME = 22;
enum CRYPTO_LOCK_GETSERVBYNAME = 23;
enum CRYPTO_LOCK_READDIR = 24;
enum CRYPTO_LOCK_RSA_BLINDING = 25;
enum CRYPTO_LOCK_DH = 26;
enum CRYPTO_LOCK_MALLOC2 = 27;
enum CRYPTO_LOCK_DSO = 28;
enum CRYPTO_LOCK_DYNLOCK = 29;
enum CRYPTO_LOCK_ENGINE = 30;
enum CRYPTO_LOCK_UI = 31;
enum CRYPTO_LOCK_ECDSA = 32;
enum CRYPTO_LOCK_EC = 33;
enum CRYPTO_LOCK_ECDH = 34;
enum CRYPTO_LOCK_BN = 35;
enum CRYPTO_LOCK_EC_PRE_COMP = 36;
enum CRYPTO_LOCK_STORE = 37;
enum CRYPTO_LOCK_COMP = 38;
enum CRYPTO_LOCK_FIPS = 39;
enum CRYPTO_LOCK_FIPS2 = 40;
enum CRYPTO_NUM_LOCKS = 41;

enum CRYPTO_LOCK = 1;
enum CRYPTO_UNLOCK = 2;
enum CRYPTO_READ = 4;
enum CRYPTO_WRITE = 8;

version (OPENSSL_NO_LOCKING) {
	void CRYPTO_w_lock()(int type) {}
	void CRYPTO_w_unlock()(int type) {}
	void CRYPTO_r_lock()(int type) {}
	void CRYPTO_r_unlock()(int type) {}
	void CRYPTO_add()(int* addr, int amount, int type) { *addr += amount; }
} else {
	void CRYPTO_w_lock(string file = __FILE__, size_t line = __LINE__)(int type) {
		CRYPTO_lock(CRYPTO_LOCK|CRYPTO_WRITE,type,file,line);
	}
	void CRYPTO_w_unlock(string file = __FILE__, size_t line = __LINE__)(int type) {
		CRYPTO_lock(CRYPTO_UNLOCK|CRYPTO_WRITE,type,file,line);
	}
	void CRYPTO_r_lock(string file = __FILE__, size_t line = __LINE__)(int type) {
		CRYPTO_lock(CRYPTO_LOCK|CRYPTO_READ,type,file,line);
	}
	void CRYPTO_r_unlock(string file = __FILE__, size_t line = __LINE__)(int type) {
		CRYPTO_lock(CRYPTO_UNLOCK|CRYPTO_READ,type,file,line);
	}
	void CRYPTO_add(string file = __FILE__, size_t line = __LINE__)(int* addr, int amount, int type) {
		CRYPTO_add_lock(addr,amount,type,file,line);
	}
}

/* Some applications as well as some parts of OpenSSL need to allocate
   and deallocate locks in a dynamic fashion.  The following typedef
   makes this possible in a type-safe manner.  */
/* CRYPTO_dynlock_value has to be defined by the application. */
// FIXME: struct CRYPTO_dynlock_value;
struct CRYPTO_dynlock
	{
	int references;
	CRYPTO_dynlock_value* data;
	}


/* The following can be used to detect memory leaks in the SSLeay library.
 * It used, it turns on malloc checking */

enum CRYPTO_MEM_CHECK_OFF = 0x0;	/* an enume */
enum CRYPTO_MEM_CHECK_ON = 0x1;	/* a bit */
enum CRYPTO_MEM_CHECK_ENABLE = 0x2;	/* a bit */
enum CRYPTO_MEM_CHECK_DISABLE = 0x3;	/* an enume */

/* The following are bit values to turn on or off options connected to the
 * malloc checking functionality */

/* Adds time to the memory checking information */
enum V_CRYPTO_MDEBUG_TIME = 0x1; /* a bit */
/* Adds thread number to the memory checking information */
enum V_CRYPTO_MDEBUG_THREAD = 0x2; /* a bit */

enum V_CRYPTO_MDEBUG_ALL = (V_CRYPTO_MDEBUG_TIME | V_CRYPTO_MDEBUG_THREAD);


/* predec of the BIO type */
import deimos.openssl.bio; /*struct bio_st;*/
alias bio_st BIO_dummy;

struct crypto_ex_data_st
	{
	STACK_OF!() *sk;
	int dummy; /* gcc is screwing up this data structure :-( */
	};
/+mixin DECLARE_STACK_OF!();+/

/* This stuff is basically class callback functions
 * The current classes are SSL_CTX, SSL, SSL_SESSION, and a few more */

struct crypto_ex_data_func_st {
	c_long argl;	/* Arbitary c_long */
	void* argp;	/* Arbitary void* */
	CRYPTO_EX_new* new_func;
	CRYPTO_EX_free* free_func;
	CRYPTO_EX_dup* dup_func;
	}
alias crypto_ex_data_func_st CRYPTO_EX_DATA_FUNCS;

/+mixin DECLARE_STACK_OF!(CRYPTO_EX_DATA_FUNCS);+/

/* Per class, we have a STACK of CRYPTO_EX_DATA_FUNCS for each CRYPTO_EX_DATA
 * entry.
 */

enum CRYPTO_EX_INDEX_BIO = 0;
enum CRYPTO_EX_INDEX_SSL = 1;
enum CRYPTO_EX_INDEX_SSL_CTX = 2;
enum CRYPTO_EX_INDEX_SSL_SESSION = 3;
enum CRYPTO_EX_INDEX_X509_STORE = 4;
enum CRYPTO_EX_INDEX_X509_STORE_CTX = 5;
enum CRYPTO_EX_INDEX_RSA = 6;
enum CRYPTO_EX_INDEX_DSA = 7;
enum CRYPTO_EX_INDEX_DH = 8;
enum CRYPTO_EX_INDEX_ENGINE = 9;
enum CRYPTO_EX_INDEX_X509 = 10;
enum CRYPTO_EX_INDEX_UI = 11;
enum CRYPTO_EX_INDEX_ECDSA = 12;
enum CRYPTO_EX_INDEX_ECDH = 13;
enum CRYPTO_EX_INDEX_COMP = 14;
enum CRYPTO_EX_INDEX_STORE = 15;

/* Dynamically assigned indexes start from this value (don't use directly, use
 * via CRYPTO_ex_data_new_class). */
enum CRYPTO_EX_INDEX_USER = 100;


/* This is the default callbacks, but we can have others as well:
 * this is needed in Win32 where the application malloc and the
 * library malloc may not be the same.
 */
void CRYPTO_malloc_init()() {
	CRYPTO_set_mem_functions(&malloc, &realloc, &free);
}

/+#if defined CRYPTO_MDEBUG_ALL || defined CRYPTO_MDEBUG_TIME || defined CRYPTO_MDEBUG_THREAD
# ifndef CRYPTO_MDEBUG /* avoid duplicate #define */
#  define CRYPTO_MDEBUG
# endif
#endif+/

/* Set standard debugging functions (not done by default
 * unless CRYPTO_MDEBUG is defined) */
void CRYPTO_malloc_debug_init()() {
	CRYPTO_set_mem_debug_functions(&CRYPTO_dbg_malloc, &CRYPTO_dbg_realloc,
		&CRYPTO_dbg_free, &CRYPTO_dbg_set_options, &CRYPTO_dbg_get_options);
}

int CRYPTO_mem_ctrl(int mode);
int CRYPTO_is_mem_check_on();

/* for applications */
int MemCheck_start()() { return CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON); }
int MemCheck_stop()(){ return CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_OFF); }

/* for library-internal use */
int MemCheck_on()() { return CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ENABLE); }
int MemCheck_off()() { return CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_DISABLE); }
alias CRYPTO_is_mem_check_on is_MemCheck_on;

auto OPENSSL_malloc(string file = __FILE__, size_t line = __LINE__)(int num) {
	return CRYPTO_malloc(num,file,line);
}
auto OPENSSL_strdup(string file = __FILE__, size_t line = __LINE__)(const(char)* str) {
	return CRYPTO_strdup(str,file,line);
}
auto OPENSSL_realloc(string file = __FILE__, size_t line = __LINE__)(void* addr, int num) {
	return CRYPTO_realloc(addr,num,file,line);
}
auto OPENSSL_realloc_clean(string file = __FILE__, size_t line = __LINE__)(void* addr,int old_num,int num) {
	CRYPTO_realloc_clean(addr,old_num,num,file,line);
}
auto OPENSSL_remalloc(string file = __FILE__, size_t line = __LINE__)(void** addr, int num) {
	return CRYPTO_remalloc(cast(char**)addr,num,file,line);
}
alias CRYPTO_free OPENSSL_freeFunc;
alias CRYPTO_free OPENSSL_free;

auto OPENSSL_malloc_locked(string file = __FILE__, size_t line = __LINE__)(int num) {
	return CRYPTO_malloc_locked(num, file, line);
}
alias CRYPTO_free_locked OPENSSL_free_locked;


const(char)* SSLeay_version(int type);
c_ulong SSLeay();

int OPENSSL_issetugid();

/* An opaque type representing an implementation of "ex_data" support */
struct st_CRYPTO_EX_DATA_IMPL;
alias st_CRYPTO_EX_DATA_IMPL CRYPTO_EX_DATA_IMPL;
/* Return an opaque pointer to the current "ex_data" implementation */
const(CRYPTO_EX_DATA_IMPL)* CRYPTO_get_ex_data_implementation();
/* Sets the "ex_data" implementation to be used (if it's not too late) */
int CRYPTO_set_ex_data_implementation(const(CRYPTO_EX_DATA_IMPL)* i);
/* Get a new "ex_data" class, and return the corresponding "class_index" */
int CRYPTO_ex_data_new_class();
/* Within a given class, get/register a new index */
int CRYPTO_get_ex_new_index(int class_index, c_long argl, void* argp,
		CRYPTO_EX_new* new_func, CRYPTO_EX_dup* dup_func,
		CRYPTO_EX_free* free_func);
/* Initialise/duplicate/free CRYPTO_EX_DATA variables corresponding to a given
 * class (invokes whatever per-class callbacks are applicable) */
int CRYPTO_new_ex_data(int class_index, void* obj, CRYPTO_EX_DATA* ad);
int CRYPTO_dup_ex_data(int class_index, CRYPTO_EX_DATA* to,
		CRYPTO_EX_DATA* from);
void CRYPTO_free_ex_data(int class_index, void* obj, CRYPTO_EX_DATA* ad);
/* Get/set data in a CRYPTO_EX_DATA variable corresponding to a particular index
 * (relative to the class type involved) */
int CRYPTO_set_ex_data(CRYPTO_EX_DATA* ad, int idx, void* val);
void* CRYPTO_get_ex_data(const(CRYPTO_EX_DATA)* ad,int idx);
/* This function cleans up all "ex_data" state. It mustn't be called under
 * potential race-conditions. */
void CRYPTO_cleanup_all_ex_data();

int CRYPTO_get_new_lockid(char* name);

int CRYPTO_num_locks(); /* return CRYPTO_NUM_LOCKS (shared libs!) */
void CRYPTO_lock(int mode, int type,const(char)* file,int line);
void CRYPTO_set_locking_callback(ExternC!(void function(int mode,int type,
					      const(char)* file,int line)) func);
ExternC!(void function(int mode,int type,const(char)* file,int line)) CRYPTO_get_locking_callback();
void CRYPTO_set_add_lock_callback(ExternC!(int function(int* num,int mount,int type,
					      const(char)* file, int line)) func);
ExternC!(void function(int* num,int mount,int type,const(char)* file, int line)) CRYPTO_get_add_lock_callback();

/* Don't use this structure directly. */
struct crypto_threadid_st {
	void* ptr;
	c_ulong val;
	}
alias crypto_threadid_st CRYPTO_THREADID;
/* Only use CRYPTO_THREADID_set_[numeric|pointer]() within callbacks */
void CRYPTO_THREADID_set_numeric(CRYPTO_THREADID* id, c_ulong val);
void CRYPTO_THREADID_set_pointer(CRYPTO_THREADID* id, void* ptr);
int CRYPTO_THREADID_set_callback(ExternC!(void function(CRYPTO_THREADID*)) threadid_func);
ExternC!(void function(CRYPTO_THREADID*)) CRYPTO_THREADID_get_callback();
void CRYPTO_THREADID_current(CRYPTO_THREADID* id);
int CRYPTO_THREADID_cmp(const(CRYPTO_THREADID)* a, const(CRYPTO_THREADID)* b);
void CRYPTO_THREADID_cpy(CRYPTO_THREADID* dest, const(CRYPTO_THREADID)* src);
c_ulong CRYPTO_THREADID_hash(const(CRYPTO_THREADID)* id);
version(OPENSSL_NO_DEPRECATED) {} else {
void CRYPTO_set_id_callback(ExternC!(c_ulong function()) func);
ExternC!(c_ulong function()) CRYPTO_get_id_callback();
c_ulong CRYPTO_thread_id();
}

const(char)* CRYPTO_get_lock_name(int type);
int CRYPTO_add_lock(int* pointer,int amount,int type, const(char)* file,
		    int line);

int CRYPTO_get_new_dynlockid();
void CRYPTO_destroy_dynlockid(int i);
struct CRYPTO_dynlock_value;
CRYPTO_dynlock_value* CRYPTO_get_dynlock_value(int i);
void CRYPTO_set_dynlock_create_callback(ExternC!(CRYPTO_dynlock_value* function(const(char)* file, int line)) dyn_create_function);
void CRYPTO_set_dynlock_lock_callback(ExternC!(void function(int mode, CRYPTO_dynlock_value* l, const(char)* file, int line)) dyn_lock_function);
void CRYPTO_set_dynlock_destroy_callback(ExternC!(void function(CRYPTO_dynlock_value* l, const(char)* file, int line)) dyn_destroy_function);
ExternC!(CRYPTO_dynlock_value* function(const(char)* file,int line)) CRYPTO_get_dynlock_create_callback();
ExternC!(void function(int mode, CRYPTO_dynlock_value* l, const(char)* file,int line)) CRYPTO_get_dynlock_lock_callback();
ExternC!(void function(CRYPTO_dynlock_value* l, const(char)* file,int line)) CRYPTO_get_dynlock_destroy_callback();

/* CRYPTO_set_mem_functions includes CRYPTO_set_locked_mem_functions --
 * call the latter last if you need different functions */
int CRYPTO_set_mem_functions(ExternC!(void* function(size_t)) m,ExternC!(void* function(void*,size_t)) r, ExternC!(void function(void*)) f);
int CRYPTO_set_locked_mem_functions(ExternC!(void* function(size_t)) m, ExternC!(void function(void*)) free_func);
int CRYPTO_set_mem_ex_functions(ExternC!(void* function(size_t,const(char)*,int)) m,
                                ExternC!(void* function(void*,size_t,const(char)*,int)) r,
                                ExternC!(void function(void*)) f);
int CRYPTO_set_locked_mem_ex_functions(ExternC!(void* function(size_t,const(char)*,int)) m,
                                       ExternC!(void function(void*)) free_func);
int CRYPTO_set_mem_debug_functions(ExternC!(void function(void*,int,const(char)*,int,int)) m,
				   ExternC!(void function(void*,void*,int,const(char)*,int,int)) r,
				   ExternC!(void function(void*,int)) f,
				   ExternC!(void function(c_long)) so,
				   ExternC!(c_long function()) go);
void CRYPTO_get_mem_functions(ExternC!(void* function(size_t))* m,ExternC!(void* function(void*, size_t))* r, ExternC!(void function(void*))* f);
void CRYPTO_get_locked_mem_functions(ExternC!(void* function(size_t))* m, ExternC!(void function(void*))* f);
void CRYPTO_get_mem_ex_functions(ExternC!(void* function(size_t,const(char)*,int))* m,
                                 ExternC!(void* function(void*, size_t,const(char)*,int))* r,
                                 ExternC!(void function(void*))* f);
void CRYPTO_get_locked_mem_ex_functions(ExternC!(void* function(size_t,const(char)*,int))* m,
                                        ExternC!(void function(void*))* f);
void CRYPTO_get_mem_debug_functions(ExternC!(void function(void*,int,const(char)*,int,int))* m,
				    ExternC!(void function(void*,void*,int,const(char)*,int,int))* r,
				    ExternC!(void function(void*,int))* f,
				    ExternC!(void function(c_long))* so,
				    ExternC!(c_long function())* go);

void* CRYPTO_malloc_locked(int num, const(char)* file, int line);
void CRYPTO_free_locked(void*);
void* CRYPTO_malloc(int num, const(char)* file, int line);
char* CRYPTO_strdup(const(char)* str, const(char)* file, int line);
void CRYPTO_free(void*);
void* CRYPTO_realloc(void* addr,int num, const(char)* file, int line);
void* CRYPTO_realloc_clean(void* addr,int old_num,int num,const(char)* file,
			   int line);
void* CRYPTO_remalloc(void* addr,int num, const(char)* file, int line);

void OPENSSL_cleanse(void* ptr, size_t len);

void CRYPTO_set_mem_debug_options(c_long bits);
c_long CRYPTO_get_mem_debug_options();

auto CRYPTO_push_info(string file = __FILE__, size_t line = __LINE__)(info) {
	return CRYPTO_push_info_(info, file, line);
}
int CRYPTO_push_info_(const(char)* info, const(char)* file, int line);
int CRYPTO_pop_info();
int CRYPTO_remove_all_info();


/* Default debugging functions (enabled by CRYPTO_malloc_debug_init() macro;
 * used as default in CRYPTO_MDEBUG compilations): */
/* The last argument has the following significance:
 *
 * 0:	called before the actual memory allocation has taken place
 * 1:	called after the actual memory allocation has taken place
 */
void CRYPTO_dbg_malloc(void* addr,int num,const(char)* file,int line,int before_p);
void CRYPTO_dbg_realloc(void* addr1,void* addr2,int num,const(char)* file,int line,int before_p);
void CRYPTO_dbg_free(void* addr,int before_p);
/* Tell the debugging code about options.  By default, the following values
 * apply:
 *
 * 0:                           Clear all options.
 * V_CRYPTO_MDEBUG_TIME (1):    Set the "Show Time" option.
 * V_CRYPTO_MDEBUG_THREAD (2):  Set the "Show Thread Number" option.
 * V_CRYPTO_MDEBUG_ALL (3):     1 + 2
 */
void CRYPTO_dbg_set_options(c_long bits);
c_long CRYPTO_dbg_get_options();


version(OPENSSL_NO_FP_API) {} else {
void CRYPTO_mem_leaks_fp(FILE*);
}
void CRYPTO_mem_leaks(bio_st* bio);
/* c_ulong order, char* file, int line, int num_bytes, char* addr */
alias typeof(*(void* function (c_ulong, const(char)*, int, int, void*)).init) CRYPTO_MEM_LEAK_CB;
void CRYPTO_mem_leaks_cb(CRYPTO_MEM_LEAK_CB* cb);

/* die if we have to */
void OpenSSLDie(const(char)* file,int line,const(char)* assertion);
void OPENSSL_assert(string file = __FILE__, size_t line = __LINE__)(int e) {
	if (!e) OpenSSLDie(file, line, "assertion failed"); // No good way to translate.
}

c_ulong* OPENSSL_ia32cap_loc();
auto OPENSSL_ia32cap()(){ return* OPENSSL_ia32cap_loc(); }
int OPENSSL_isservice();

/* BEGIN ERROR CODES */
/* The following lines are auto generated by the script mkerr.pl. Any changes
 * made after this point may be overwritten when the script is next run.
 */
void ERR_load_CRYPTO_strings();

/* Error codes for the CRYPTO functions. */

/* Function codes. */
enum CRYPTO_F_CRYPTO_GET_EX_NEW_INDEX = 100;
enum CRYPTO_F_CRYPTO_GET_NEW_DYNLOCKID = 103;
enum CRYPTO_F_CRYPTO_GET_NEW_LOCKID = 101;
enum CRYPTO_F_CRYPTO_SET_EX_DATA = 102;
enum CRYPTO_F_DEF_ADD_INDEX = 104;
enum CRYPTO_F_DEF_GET_CLASS = 105;
enum CRYPTO_F_INT_DUP_EX_DATA = 106;
enum CRYPTO_F_INT_FREE_EX_DATA = 107;
enum CRYPTO_F_INT_NEW_EX_DATA = 108;

/* Reason codes. */
enum CRYPTO_R_NO_DYNLOCK_CREATE_CALLBACK = 100;
